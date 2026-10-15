import 'dart:convert';

enum PeerPlatform { android, windows, unknown }

class PeerNode {
  final String nodeId;
  final String alias;
  final String ipAddress;
  final int tcpPort;
  final PeerPlatform platform;
  final DateTime lastSeen;
  final bool isTrusted;
  final bool isOnline;

  const PeerNode({
    required this.nodeId,
    required this.alias,
    required this.ipAddress,
    required this.tcpPort,
    required this.platform,
    required this.lastSeen,
    this.isTrusted = false,
    this.isOnline = true,
  });

  PeerNode copyWith({
    String? nodeId,
    String? alias,
    String? ipAddress,
    int? tcpPort,
    PeerPlatform? platform,
    DateTime? lastSeen,
    bool? isTrusted,
    bool? isOnline,
  }) {
    return PeerNode(
      nodeId: nodeId ?? this.nodeId,
      alias: alias ?? this.alias,
      ipAddress: ipAddress ?? this.ipAddress,
      tcpPort: tcpPort ?? this.tcpPort,
      platform: platform ?? this.platform,
      lastSeen: lastSeen ?? this.lastSeen,
      isTrusted: isTrusted ?? this.isTrusted,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  Map<String, dynamic> toBeaconMap(String protocolMagic) {
    return {
      'magic': protocolMagic,
      'nodeId': nodeId,
      'alias': alias,
      'ip': ipAddress,
      'tcpPort': tcpPort,
      'platform': platform.name.toUpperCase(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  String toBeaconJson(String protocolMagic) =>
      jsonEncode(toBeaconMap(protocolMagic));

  Map<String, dynamic> toStorageMap() => {
        'nodeId': nodeId,
        'alias': alias,
        'ipAddress': ipAddress,
        'tcpPort': tcpPort,
        'platform': platform.name,
        'lastSeen': lastSeen.millisecondsSinceEpoch,
        'isTrusted': isTrusted,
      };

  factory PeerNode.fromStorageMap(Map<String, dynamic> map) {
    final String rawPlatform = (map['platform'] as String? ?? '').toLowerCase();
    final PeerPlatform parsedPlatform = switch (rawPlatform) {
      'android' => PeerPlatform.android,
      'windows' => PeerPlatform.windows,
      _ => PeerPlatform.unknown,
    };

    return PeerNode(
      nodeId: map['nodeId'] as String? ?? '',
      alias: map['alias'] as String? ?? 'Contatto Salvato',
      ipAddress: map['ipAddress'] as String? ?? '',
      tcpPort: (map['tcpPort'] as num?)?.toInt() ?? 45455,
      platform: parsedPlatform,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(
        (map['lastSeen'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      isTrusted: map['isTrusted'] as bool? ?? true,
      isOnline: false,
    );
  }

  static PeerNode? fromBeaconJson(
    String rawJson,
    String expectedMagic, {
    String? fallbackSenderIp,
  }) {
    try {
      final Map<String, dynamic> data =
          jsonDecode(rawJson) as Map<String, dynamic>;
      if (data['magic'] != expectedMagic) return null;

      final String rawPlatform =
          (data['platform'] as String? ?? '').toUpperCase();
      final PeerPlatform parsedPlatform = switch (rawPlatform) {
        'ANDROID' => PeerPlatform.android,
        'WINDOWS' => PeerPlatform.windows,
        _ => PeerPlatform.unknown,
      };

      final String resolvedIp = (data['ip'] as String?)?.isNotEmpty == true
          ? data['ip'] as String
          : (fallbackSenderIp ?? '');

      if (resolvedIp.isEmpty) return null;

      return PeerNode(
        nodeId: data['nodeId'] as String,
        alias: data['alias'] as String,
        ipAddress: resolvedIp,
        tcpPort: (data['tcpPort'] as num).toInt(),
        platform: parsedPlatform,
        lastSeen: DateTime.now(),
        isOnline: true,
      );
    } catch (_) {
      return null;
    }
  }
}
