import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import '../core/constants/network_constants.dart';
import '../models/peer_node.dart';

class DiscoveryService {
  final String localNodeId;
  final String localAlias;
  final int localTcpPort;

  RawDatagramSocket? _udpSocket;
  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;
  String? _cachedLocalIp;

  final Map<String, PeerNode> _activePeers = {};
  final StreamController<List<PeerNode>> _peersController =
      StreamController<List<PeerNode>>.broadcast();

  Stream<List<PeerNode>> get peersStream => _peersController.stream;
  List<PeerNode> get currentPeers => _activePeers.values.toList();
  String? get localIp => _cachedLocalIp;

  DiscoveryService({
    required this.localNodeId,
    required this.localAlias,
    this.localTcpPort = NetworkConstants.tcpTransferPort,
  });

  PeerPlatform get _currentPlatform {
    if (Platform.isAndroid) return PeerPlatform.android;
    if (Platform.isWindows) return PeerPlatform.windows;
    return PeerPlatform.unknown;
  }

  /// Avvia il socket UDP su 0.0.0.0:45454 abilitando Broadcast e Multicast
  Future<void> startDiscovery() async {
    await stopDiscovery();
    _cachedLocalIp = await _resolveLocalWifiIp();

    _udpSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      NetworkConstants.udpDiscoveryPort,
      reuseAddress: true,
      reusePort: !Platform.isWindows, // Windows gestisce reuseAddress nativamente
    );

    _udpSocket!.broadcastEnabled = true;
    _udpSocket!.multicastLoopback = false;

    // Registrazione al gruppo Multicast per router che filtrano 255.255.255.255
    try {
      _udpSocket!.joinMulticast(InternetAddress(NetworkConstants.multicastGroupIp));
    } catch (_) {
      // Alcune interfacce virtuali Windows (Hyper-V/WSL) non supportano joinMulticast:
      // il broadcast di sottorete continuerà comunque a funzionare.
    }

    _udpSocket!.listen(_onDatagramReceived, onError: (_) {});

    // Primo annuncio immediato + Heartbeat periodico
    _sendAnnouncementBeacon();
    _heartbeatTimer = Timer.periodic(
      NetworkConstants.heartbeatInterval,
      (_) => _sendAnnouncementBeacon(),
    );

    // Rimozione automatica dei nodi disconnessi
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pruneStalePeers(),
    );
  }

  void _onDatagramReceived(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _udpSocket == null) return;
    final Datagram? datagram = _udpSocket!.receive();
    if (datagram == null) return;

    final String rawPayload = utf8.decode(datagram.data, allowMalformed: true);
    final PeerNode? discovered = PeerNode.fromBeaconJson(
      rawPayload,
      NetworkConstants.protocolMagic,
      fallbackSenderIp: datagram.address.address,
    );

    if (discovered == null || discovered.nodeId == localNodeId) {
      return; // Ignora i propri pacchetti o i pacchetti non validi
    }

    _activePeers[discovered.nodeId] = discovered;
    _emitSortedPeers();
  }

  Future<void> _sendAnnouncementBeacon() async {
    final RawDatagramSocket? socket = _udpSocket;
    if (socket == null) return;

    _cachedLocalIp ??= await _resolveLocalWifiIp();
    final String ip = _cachedLocalIp ?? '0.0.0.0';

    final PeerNode selfNode = PeerNode(
      nodeId: localNodeId,
      alias: localAlias,
      ipAddress: ip,
      tcpPort: localTcpPort,
      platform: _currentPlatform,
      lastSeen: DateTime.now(),
    );

    final List<int> payloadBytes =
        utf8.encode(selfNode.toBeaconJson(NetworkConstants.protocolMagic));

    // 1. Invio sul broadcast diretto della sottorete (es. 192.168.1.255)
    final String? subnetBroadcast = _computeSubnetBroadcast(ip);
    if (subnetBroadcast != null) {
      socket.send(
        payloadBytes,
        InternetAddress(subnetBroadcast),
        NetworkConstants.udpDiscoveryPort,
      );
    }

    // 2. Invio su Global Broadcast 255.255.255.255
    socket.send(
      payloadBytes,
      InternetAddress('255.255.255.255'),
      NetworkConstants.udpDiscoveryPort,
    );

    // 3. Invio sul gruppo Multicast 239.255.45.45
    socket.send(
      payloadBytes,
      InternetAddress(NetworkConstants.multicastGroupIp),
      NetworkConstants.udpDiscoveryPort,
    );
  }

  String? _computeSubnetBroadcast(String ip) {
    final List<String> octets = ip.split('.');
    if (octets.length != 4 || ip == '0.0.0.0') return null;
    return '${octets[0]}.${octets[1]}.${octets[2]}.255';
  }

  /// Risolve l'IP della scheda Wi-Fi/LAN evitando gli adattatori virtuali (WSL, Docker, VPN)
  Future<String?> _resolveLocalWifiIp() async {
    try {
      final String? wifiIp = await NetworkInfo().getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '127.0.0.1') {
        return wifiIp;
      }
    } catch (_) {}

    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    for (final NetworkInterface iface in interfaces) {
      final String lowerName = iface.name.toLowerCase();
      if (lowerName.contains('vethernet') ||
          lowerName.contains('wsl') ||
          lowerName.contains('docker') ||
          lowerName.contains('vmware') ||
          lowerName.contains('vbox')) {
        continue;
      }
      for (final InternetAddress addr in iface.addresses) {
        if (addr.address.startsWith('192.168.') ||
            addr.address.startsWith('10.') ||
            addr.address.startsWith('172.')) {
          return addr.address;
        }
      }
    }
    return null;
  }

  void _pruneStalePeers() {
    final DateTime now = DateTime.now();
    bool removedAny = false;
    _activePeers.removeWhere((_, peer) {
      final bool isStale =
          now.difference(peer.lastSeen) > NetworkConstants.peerStaleTimeout;
      if (isStale) removedAny = true;
      return isStale;
    });
    if (removedAny) {
      _emitSortedPeers();
    }
  }

  void _emitSortedPeers() {
    final List<PeerNode> list = _activePeers.values.toList()
      ..sort((a, b) => a.alias.compareTo(b.alias));
    _peersController.add(list);
  }

  Future<void> stopDiscovery() async {
    _heartbeatTimer?.cancel();
    _cleanupTimer?.cancel();
    _udpSocket?.close();
    _udpSocket = null;
  }

  void dispose() {
    stopDiscovery();
    _peersController.close();
  }
}
