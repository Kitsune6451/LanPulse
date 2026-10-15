import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import '../core/constants/network_constants.dart';
import '../models/peer_node.dart';

class DiscoveryService {
  final String localNodeId;
  String localAlias;
  final int localTcpPort;

  RawDatagramSocket? _udpSocket;
  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;
  String? _cachedLocalIp;
  List<String> _allLocalIps = [];

  final Map<String, PeerNode> _activePeers = {};
  final Set<String> _manualPeerIds = {};
  final StreamController<List<PeerNode>> _peersController =
      StreamController<List<PeerNode>>.broadcast();

  Stream<List<PeerNode>> get peersStream => _peersController.stream;
  List<PeerNode> get currentPeers => _activePeers.values.toList();
  String? get localIp => _cachedLocalIp;
  List<String> get allLocalIps => _allLocalIps;

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

  void updateAlias(String newAlias) {
    localAlias = newAlias;
    _sendAnnouncementBeacon();
  }

  /// Aggiunge o aggiorna un nodo manualmente tramite IP (Wi-Fi diretto, Hotspot, VPN)
  PeerNode addManualPeer({
    required String ipAddress,
    String? customAlias,
    int tcpPort = NetworkConstants.tcpTransferPort,
  }) {
    final String cleanIp = ipAddress.trim();
    final String nodeId = 'manual-$cleanIp:$tcpPort';
    final PeerNode node = PeerNode(
      nodeId: nodeId,
      alias: (customAlias != null && customAlias.trim().isNotEmpty)
          ? customAlias.trim()
          : 'Nodo Wi-Fi ($cleanIp)',
      ipAddress: cleanIp,
      tcpPort: tcpPort,
      platform: PeerPlatform.unknown,
      lastSeen: DateTime.now(),
    );

    _manualPeerIds.add(nodeId);
    _activePeers[nodeId] = node;
    _emitSortedPeers();
    return node;
  }

  Future<void> refreshNetworkAddresses() async {
    _cachedLocalIp = await _resolveLocalWifiIp();
  }

  /// Avvia il socket UDP su 0.0.0.0:45454 in modo sicuro per Android 14/15/16 e Windows
  Future<void> startDiscovery() async {
    await stopDiscovery();
    _cachedLocalIp = await _resolveLocalWifiIp();

    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        NetworkConstants.udpDiscoveryPort,
        reuseAddress: true,
        reusePort: false, // CRITICO: reusePort=true causa crash SocketException su Android
      );

      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.multicastLoopback = false;

      try {
        _udpSocket!.joinMulticast(
          InternetAddress(NetworkConstants.multicastGroupIp),
        );
      } catch (_) {}

      _udpSocket!.listen(_onDatagramReceived, onError: (_) {});

      _sendAnnouncementBeacon();
      _heartbeatTimer = Timer.periodic(
        NetworkConstants.heartbeatInterval,
        (_) => _sendAnnouncementBeacon(),
      );

      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _pruneStalePeers(),
      );
    } catch (_) {
      // Anche se l'UDP è bloccato dalla rete, il trasferimento diretto via IP TCP resta attivo
    }
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
      return;
    }

    // Rimuove eventuale duplicato manuale se lo stesso IP viene rilevato automaticamente
    _activePeers.removeWhere(
      (key, value) =>
          _manualPeerIds.contains(key) &&
          value.ipAddress == discovered.ipAddress,
    );

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

    final String? subnetBroadcast = _computeSubnetBroadcast(ip);
    if (subnetBroadcast != null) {
      try {
        socket.send(
          payloadBytes,
          InternetAddress(subnetBroadcast),
          NetworkConstants.udpDiscoveryPort,
        );
      } catch (_) {}
    }

    try {
      socket.send(
        payloadBytes,
        InternetAddress('255.255.255.255'),
        NetworkConstants.udpDiscoveryPort,
      );
    } catch (_) {}

    try {
      socket.send(
        payloadBytes,
        InternetAddress(NetworkConstants.multicastGroupIp),
        NetworkConstants.udpDiscoveryPort,
      );
    } catch (_) {}
  }

  String? _computeSubnetBroadcast(String ip) {
    final List<String> octets = ip.split('.');
    if (octets.length != 4 || ip == '0.0.0.0') return null;
    return '${octets[0]}.${octets[1]}.${octets[2]}.255';
  }

  /// Risolve l'IP Wi-Fi / Hotspot / LAN su Android e Windows
  Future<String?> _resolveLocalWifiIp() async {
    final List<String> detectedIps = [];

    try {
      final String? wifiIp = await NetworkInfo().getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '127.0.0.1') {
        detectedIps.add(wifiIp);
      }
    } catch (_) {}

    try {
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
          if (!detectedIps.contains(addr.address)) {
            detectedIps.add(addr.address);
          }
        }
      }
    } catch (_) {}

    _allLocalIps = detectedIps;

    // Priorità a 192.168.x.x (Wi-Fi domestico / Hotspot Android)
    for (final ip in detectedIps) {
      if (ip.startsWith('192.168.')) return ip;
    }
    for (final ip in detectedIps) {
      if (ip.startsWith('10.') || ip.startsWith('172.')) return ip;
    }
    return detectedIps.isNotEmpty ? detectedIps.first : null;
  }

  void _pruneStalePeers() {
    final DateTime now = DateTime.now();
    bool removedAny = false;
    _activePeers.removeWhere((id, peer) {
      if (_manualPeerIds.contains(id)) return false; // Non rimuovere i nodi aggiunti via IP
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
