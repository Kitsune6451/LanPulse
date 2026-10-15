import 'dart:convert';

enum PeerPlatform { android, windows, unknown }

class PeerNode {
  final String nodeId;
  final String alias;
  final String ipAddress;
  final int tcpPort;
  final PeerPlatform platform;
  final DateTime lastSeen;

  const PeerNode({
    required this.nodeId,
    required this.alias,
    required this.ipAddress,
    required this.tcpPort,
    required this.platform,
    required this.lastSeen,
  });

  PeerNode copyWith({
    String? alias,
    String? ipAddress,
    int? tcpPort,
    DateTime? lastSeen,
  }) {
    return PeerNode(
      nodeId: nodeId,
      alias: alias ?? this.alias,
      ipAddress: ipAddress ?? this.ipAddress,
      tcpPort: tcpPort ?? this.tcpPort,
      platform: platform,
      lastSeen: lastSeen ?? this.lastSeen,
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

  String toBeaconJson(String protocolMagic) => jsonEncode(toBeaconMap(protocolMagic));

  static PeerNode? fromBeaconJson(String rawJson, String expectedMagic, {String? fallbackSenderIp}) {
    try {
      final Map<String, dynamic> data = jsonDecode(rawJson) as Map<String, dynamic>;
      if (data['magic'] != expectedMagic) return null;

      final String rawPlatform = (data['platform'] as String? ?? '').toUpperCase();
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
      );
    } catch (_) {
      return null;
    }
  }
}
