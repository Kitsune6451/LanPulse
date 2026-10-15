import 'dart:convert';
import 'dart:typed_data';

enum TransferPayloadType {
  textMessage,
  binaryFile,
  handshake,
  pullPending,
}

class TcpTransferHeader {
  final String transferId;
  final TransferPayloadType type;
  final String senderId;
  final String senderAlias;
  final String? senderIp;
  final int? senderPort;
  final String? senderPlatform;
  final String? textContent;
  final String? fileName;
  final int payloadSizeBytes;
  final String? sha256Checksum;
  final int timestampMs;

  const TcpTransferHeader({
    required this.transferId,
    required this.type,
    required this.senderId,
    required this.senderAlias,
    required this.payloadSizeBytes,
    required this.timestampMs,
    this.senderIp,
    this.senderPort,
    this.senderPlatform,
    this.textContent,
    this.fileName,
    this.sha256Checksum,
  });

  Map<String, dynamic> toMap() => {
        'transferId': transferId,
        'type': type.name,
        'senderId': senderId,
        'senderAlias': senderAlias,
        'senderIp': senderIp,
        'senderPort': senderPort,
        'senderPlatform': senderPlatform,
        'textContent': textContent,
        'fileName': fileName,
        'payloadSizeBytes': payloadSizeBytes,
        'sha256Checksum': sha256Checksum,
        'timestampMs': timestampMs,
      };

  factory TcpTransferHeader.fromMap(Map<String, dynamic> map) {
    final String rawType = map['type'] as String? ?? 'textMessage';
    final TransferPayloadType parsedType = switch (rawType) {
      'binaryFile' => TransferPayloadType.binaryFile,
      'handshake' => TransferPayloadType.handshake,
      'pullPending' => TransferPayloadType.pullPending,
      _ => TransferPayloadType.textMessage,
    };

    return TcpTransferHeader(
      transferId: map['transferId'] as String? ?? '',
      type: parsedType,
      senderId: map['senderId'] as String? ?? '',
      senderAlias: map['senderAlias'] as String? ?? 'Nodo Wi-Fi',
      senderIp: map['senderIp'] as String?,
      senderPort: (map['senderPort'] as num?)?.toInt(),
      senderPlatform: map['senderPlatform'] as String?,
      textContent: map['textContent'] as String?,
      fileName: map['fileName'] as String?,
      payloadSizeBytes: (map['payloadSizeBytes'] as num?)?.toInt() ?? 0,
      sha256Checksum: map['sha256Checksum'] as String?,
      timestampMs: (map['timestampMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Uint8List toFramedHeaderBytes() {
    final Uint8List headerJsonBytes = utf8.encode(jsonEncode(toMap()));
    final ByteData lengthPrefix = ByteData(4)
      ..setUint32(0, headerJsonBytes.length, Endian.big);

    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(lengthPrefix.buffer.asUint8List())
      ..add(headerJsonBytes);

    return builder.toBytes();
  }
}

class P2PChatMessage {
  final String id;
  final String peerId;
  final String peerAlias;
  final bool isOutgoing;
  final TransferPayloadType type;
  final String content;
  final String? filePath;
  final int? fileSize;
  final double progress;
  final DateTime timestamp;

  const P2PChatMessage({
    required this.id,
    required this.peerId,
    required this.peerAlias,
    required this.isOutgoing,
    required this.type,
    required this.content,
    required this.timestamp,
    this.filePath,
    this.fileSize,
    this.progress = 1.0,
  });

  P2PChatMessage copyWith({
    String? peerId,
    String? peerAlias,
    double? progress,
    String? filePath,
  }) {
    return P2PChatMessage(
      id: id,
      peerId: peerId ?? this.peerId,
      peerAlias: peerAlias ?? this.peerAlias,
      isOutgoing: isOutgoing,
      type: type,
      content: content,
      timestamp: timestamp,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize,
      progress: progress ?? this.progress,
    );
  }
}
