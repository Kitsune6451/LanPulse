import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import '../core/constants/network_constants.dart';
import '../models/peer_node.dart';

class DiscoveryService {
  String localNodeId;
  String localAlias;
  final int localTcpPort;
  final void Function(String ip, int port)? onTcpPeerCandidateFound;
  final void Function(String ip, int port)? onReverseConnectRequested;

  RawDatagramSocket? _udpSocket;
  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;
  Timer? _networkWatchTimer;

  String? _cachedLocalIp;
  List<String> _allLocalIps = [];
  bool _isScanningSubnet = false;
  bool _isInitialized = false;

  final Map<String, PeerNode> _activePeers = {};
  final Set<String> _pinnedPeerIds = {};

  final StreamController<List<PeerNode>> _peersController =
      StreamController<List<PeerNode>>.broadcast();
  final StreamController<String?> _networkChangeController =
      StreamController<String?>.broadcast();

  Stream<List<PeerNode>> get peersStream => _peersController.stream;
  Stream<String?> get networkChangeStream => _networkChangeController.stream;
  List<PeerNode> get currentPeers => _activePeers.values.toList();
  String? get localIp => _cachedLocalIp;
  List<String> get allLocalIps => _allLocalIps;
  bool get isScanningSubnet => _isScanningSubnet;

  DiscoveryService({
    required this.localNodeId,
    required this.localAlias,
    this.localTcpPort = NetworkConstants.tcpTransferPort,
    this.onTcpPeerCandidateFound,
    this.onReverseConnectRequested,
  });

  PeerPlatform get _currentPlatform {
    if (Platform.isAndroid) return PeerPlatform.android;
    if (Platform.isWindows) return PeerPlatform.windows;
    return PeerPlatform.unknown;
  }

  void updateIdentity({String? newNodeId, String? newAlias}) {
    if (newNodeId != null && newNodeId.isNotEmpty) {
      localNodeId = newNodeId;
    }
    if (newAlias != null && newAlias.isNotEmpty) {
      localAlias = newAlias;
    }
    _sendAnnouncementBeacon();
  }

  void updateAlias(String newAlias) {
    localAlias = newAlias;
    _sendAnnouncementBeacon();
  }

  PeerNode registerVerifiedPeer(PeerNode peer, {bool pin = false}) {
    final List<String> duplicateIds = _activePeers.entries
        .where(
            (e) => e.value.ipAddress == peer.ipAddress && e.key != peer.nodeId)
        .map((e) => e.key)
        .toList();

    for (final oldId in duplicateIds) {
      _activePeers.remove(oldId);
      _pinnedPeerIds.remove(oldId);
    }

    if (pin) {
      _pinnedPeerIds.add(peer.nodeId);
    }
    _activePeers[peer.nodeId] =
        peer.copyWith(lastSeen: DateTime.now(), isOnline: true);
    _emitSortedPeers();
    return _activePeers[peer.nodeId]!;
  }

  void removePeer(String nodeId) {
    _activePeers.remove(nodeId);
    _pinnedPeerIds.remove(nodeId);
    _emitSortedPeers();
  }

  Future<void> startDiscovery() async {
    await _stopSocketsAndTimers();
    _cachedLocalIp = await _resolveLocalWifiIp();
    _isInitialized = true;

    await _bindUdpSocket();

    _networkWatchTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => checkNetworkChange(),
    );

    unawaited(scanWifiSubnet());
  }

  Future<void> _bindUdpSocket() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        NetworkConstants.udpDiscoveryPort,
        reuseAddress: true,
        reusePort: false,
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
    } catch (_) {}
  }

  Future<bool> checkNetworkChange() async {
    final String? newIp = await _resolveLocalWifiIp();
    if (!_isInitialized) return false;

    if (newIp != _cachedLocalIp) {
      _cachedLocalIp = newIp;
      _activePeers.clear();
      _pinnedPeerIds.clear();
      _emitSortedPeers();
      _networkChangeController.add(newIp);

      _heartbeatTimer?.cancel();
      _cleanupTimer?.cancel();
      _udpSocket?.close();
      _udpSocket = null;

      if (newIp != null) {
        await _bindUdpSocket();
        unawaited(scanWifiSubnet());
      }
      return true;
    }
    return false;
  }

  Future<void> scanWifiSubnet() async {
    if (_isScanningSubnet) return;
    final String? ip = _cachedLocalIp ?? await _resolveLocalWifiIp();
    if (ip == null || ip == '0.0.0.0') return;

    final List<String> parts = ip.split('.');
    if (parts.length != 4) return;
    final String prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    final int selfLastOctet = int.tryParse(parts[3]) ?? -1;

    _isScanningSubnet = true;
    try {
      const int batchSize = 30;
      for (int start = 1; start <= 254; start += batchSize) {
        if (_cachedLocalIp != ip) break;

        final List<Future<void>> batch = [];
        final int end = (start + batchSize - 1).clamp(1, 254);

        for (int i = start; i <= end; i++) {
          if (i == selfLastOctet) continue;
          final String targetIp = '$prefix.$i';
          batch.add(_probeTcpHost(targetIp, localTcpPort));
        }
        await Future.wait(batch);
      }
    } finally {
      _isScanningSubnet = false;
    }
  }

  Future<void> _probeTcpHost(String ip, int port) async {
    try {
      final Socket s = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 350),
      );
      await s.close();
      onTcpPeerCandidateFound?.call(ip, port);
    } catch (_) {}
  }

  void sendReverseConnectRequest(String targetIp) {
    final RawDatagramSocket? socket = _udpSocket;
    final String? myIp = _cachedLocalIp;
    if (socket == null || myIp == null) return;

    final String payload = jsonEncode({
      'magic': NetworkConstants.protocolMagic,
      'type': 'REVERSE_CONNECT',
      'nodeId': localNodeId,
      'alias': localAlias,
      'ip': myIp,
      'tcpPort': localTcpPort,
    });
    final List<int> bytes = utf8.encode(payload);

    try {
      socket.send(
        bytes,
        InternetAddress(targetIp),
        NetworkConstants.udpDiscoveryPort,
      );
    } catch (_) {}

    final String? broadcast = _computeSubnetBroadcast(myIp);
    if (broadcast != null) {
      try {
        socket.send(
          bytes,
          InternetAddress(broadcast),
          NetworkConstants.udpDiscoveryPort,
        );
      } catch (_) {}
    }
  }

  void _onDatagramReceived(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _udpSocket == null) return;
    final Datagram? datagram = _udpSocket!.receive();
    if (datagram == null) return;

    final String senderIp = datagram.address.address;
    final String rawPayload = utf8.decode(datagram.data, allowMalformed: true);

    try {
      final Map<String, dynamic> map =
          jsonDecode(rawPayload) as Map<String, dynamic>;
      if (map['magic'] != NetworkConstants.protocolMagic) return;
      if (map['nodeId'] == localNodeId) return;

      if (map['type'] == 'REVERSE_CONNECT') {
        final int port = (map['tcpPort'] as num?)?.toInt() ??
            NetworkConstants.tcpTransferPort;
        onReverseConnectRequested?.call(senderIp, port);
        return;
      }
    } catch (_) {
      return;
    }

    final PeerNode? discovered = PeerNode.fromBeaconJson(
      rawPayload,
      NetworkConstants.protocolMagic,
      fallbackSenderIp: senderIp,
    );

    if (discovered == null || discovered.nodeId == localNodeId) {
      return;
    }

    final String effectiveIp =
        (discovered.ipAddress == '0.0.0.0' || discovered.ipAddress.isEmpty)
            ? senderIp
            : discovered.ipAddress;

    registerVerifiedPeer(
      discovered.copyWith(ipAddress: effectiveIp, isOnline: true),
    );
  }

  Future<void> _sendAnnouncementBeacon() async {
    final RawDatagramSocket? socket = _udpSocket;
    if (socket == null) return;

    final String ip = _cachedLocalIp ?? '0.0.0.0';
    if (ip == '0.0.0.0') return;

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

    for (final localAddr in _allLocalIps) {
      final String? subnetBroadcast = _computeSubnetBroadcast(localAddr);
      if (subnetBroadcast != null) {
        try {
          socket.send(
            payloadBytes,
            InternetAddress(subnetBroadcast),
            NetworkConstants.udpDiscoveryPort,
          );
        } catch (_) {}
      }
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

  Future<String?> _resolveLocalWifiIp() async {
    final List<String> priorityWifiIps = [];
    final List<String> fallbackLanIps = [];

    try {
      final String? pluginWifiIp = await NetworkInfo().getWifiIP();
      if (pluginWifiIp != null &&
          pluginWifiIp.isNotEmpty &&
          pluginWifiIp != '127.0.0.1' &&
          pluginWifiIp != '0.0.0.0' &&
          !pluginWifiIp.startsWith('192.168.56.')) {
        priorityWifiIps.add(pluginWifiIp);
      }
    } catch (_) {}

    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final NetworkInterface iface in interfaces) {
        final String name = iface.name.toLowerCase();
        if (name.contains('vethernet') ||
            name.contains('wsl') ||
            name.contains('docker') ||
            name.contains('vmware') ||
            name.contains('vbox') ||
            name.contains('virtual') ||
            name.contains('rmnet') ||
            name.contains('ccmni') ||
            name.contains('tun') ||
            name.contains('tap') ||
            name.contains('tailscale') ||
            name.contains('zerotier')) {
          continue;
        }

        final bool isWifiOrHotspot = name.contains('wlan') ||
            name.contains('wi-fi') ||
            name.contains('wifi') ||
            name.contains('swlan') ||
            name.contains('ap') ||
            name.contains('hotspot');

        for (final InternetAddress addr in iface.addresses) {
          final String ip = addr.address;
          if (ip.startsWith('169.254.') || ip.startsWith('192.168.56.')) {
            continue;
          }
          if (isWifiOrHotspot) {
            if (!priorityWifiIps.contains(ip)) priorityWifiIps.add(ip);
          } else {
            if (!fallbackLanIps.contains(ip)) fallbackLanIps.add(ip);
          }
        }
      }
    } catch (_) {}

    _allLocalIps = [...priorityWifiIps, ...fallbackLanIps];

    for (final ip in priorityWifiIps) {
      if (ip.startsWith('192.168.') ||
          ip.startsWith('172.') ||
          ip.startsWith('10.')) {
        return ip;
      }
    }
    for (final ip in fallbackLanIps) {
      if (ip.startsWith('192.168.')) return ip;
    }
    for (final ip in fallbackLanIps) {
      if (ip.startsWith('172.') || ip.startsWith('10.')) return ip;
    }
    return _allLocalIps.isNotEmpty ? _allLocalIps.first : null;
  }

  void _pruneStalePeers() {
    final DateTime now = DateTime.now();
    bool removedAny = false;
    _activePeers.removeWhere((id, peer) {
      if (_pinnedPeerIds.contains(id)) return false;
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

  Future<void> _stopSocketsAndTimers() async {
    _heartbeatTimer?.cancel();
    _cleanupTimer?.cancel();
    _networkWatchTimer?.cancel();
    _udpSocket?.close();
    _udpSocket = null;
  }

  Future<void> stopDiscovery() async {
    _isInitialized = false;
    await _stopSocketsAndTimers();
  }

  void dispose() {
    stopDiscovery();
    _peersController.close();
    _networkChangeController.close();
  }
}
