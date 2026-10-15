import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/network_constants.dart';
import '../models/p2p_packet.dart';
import '../models/peer_node.dart';

typedef ProgressCallback = void Function(
  String transferId,
  int transferredBytes,
  int totalBytes,
);

class SocketTransferService {
  final String localNodeId;
  final String localAlias;
  final int listenPort;

  ServerSocket? _serverSocket;
  final Uuid _uuid = const Uuid();

  final StreamController<P2PChatMessage> _incomingMessagesController =
      StreamController<P2PChatMessage>.broadcast();

  Stream<P2PChatMessage> get incomingMessages =>
      _incomingMessagesController.stream;

  SocketTransferService({
    required this.localNodeId,
    required this.localAlias,
    this.listenPort = NetworkConstants.tcpTransferPort,
  });

  /// Avvia il ServerSocket TCP in ascolto su tutte le interfacce IPv4
  Future<void> startServer({ProgressCallback? onIncomingProgress}) async {
    await stopServer();
    _serverSocket = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      listenPort,
      shared: true,
    );

    _serverSocket!.listen(
      (Socket clientSocket) =>
          _handleClientConnection(clientSocket, onIncomingProgress),
      onError: (_) {},
    );
  }

  /// Gestisce una connessione TCP in ingresso con parser a macchina a stati:
  /// Stato 1: Lettura dei 4 byte di lunghezza dell'Header
  /// Stato 2: Lettura dell'Header JSON UTF-8
  /// Stato 3: Scrittura diretta su disco dello stream di byte del file
  Future<void> _handleClientConnection(
    Socket socket,
    ProgressCallback? onIncomingProgress,
  ) async {
    final List<int> headerAccumulator = [];
    int? expectedHeaderLength;
    TcpTransferHeader? parsedHeader;
    IOSink? outputFileSink;
    String? savedFilePath;
    int receivedPayloadBytes = 0;

    try {
      await for (final Uint8List chunk in socket) {
        int offset = 0;

        // Fase 1: Leggi i 4 byte che indicano la dimensione dell'Header JSON
        if (expectedHeaderLength == null) {
          headerAccumulator.addAll(chunk);
          if (headerAccumulator.length < 4) continue;

          final Uint8List prefixBytes =
              Uint8List.fromList(headerAccumulator.sublist(0, 4));
          expectedHeaderLength =
              ByteData.sublistView(prefixBytes).getUint32(0, Endian.big);
          headerAccumulator.removeRange(0, 4);
        }

        // Fase 2: Accumula i byte dell'Header JSON finché non è completo
        if (parsedHeader == null) {
          if (offset == 0 && headerAccumulator.isNotEmpty) {
            // I byte residui dopo i primi 4 byte sono già in headerAccumulator
          } else {
            headerAccumulator.addAll(chunk);
          }

          if (headerAccumulator.length < expectedHeaderLength) {
            continue;
          }

          final List<int> jsonBytes =
              headerAccumulator.sublist(0, expectedHeaderLength);
          final List<int> leftoverPayload =
              headerAccumulator.sublist(expectedHeaderLength);
          headerAccumulator.clear();

          final Map<String, dynamic> headerMap =
              jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
          parsedHeader = TcpTransferHeader.fromMap(headerMap);

          if (parsedHeader.type == TransferPayloadType.textMessage) {
            _incomingMessagesController.add(
              P2PChatMessage(
                id: parsedHeader.transferId,
                peerId: parsedHeader.senderId,
                peerAlias: parsedHeader.senderAlias,
                isOutgoing: false,
                type: TransferPayloadType.textMessage,
                content: parsedHeader.textContent ?? '',
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  parsedHeader.timestampMs,
                ),
              ),
            );
            break;
          } else {
            // Prepariamo il file di destinazione nella cartella Download/Documenti
            final Directory targetDir = await _resolveDownloadDirectory();
            final String safeName =
                (parsedHeader.fileName ?? 'file_ricevuto.bin')
                    .replaceAll(RegExp(r'[<>:"/\|?*]'), '_');
            savedFilePath = '${targetDir.path}${Platform.pathSeparator}$safeName';
            outputFileSink = File(savedFilePath).openWrite();

            if (leftoverPayload.isNotEmpty) {
              outputFileSink.add(leftoverPayload);
              receivedPayloadBytes += leftoverPayload.length;
              onIncomingProgress?.call(
                parsedHeader.transferId,
                receivedPayloadBytes,
                parsedHeader.payloadSizeBytes,
              );
            }

            if (receivedPayloadBytes >= parsedHeader.payloadSizeBytes) {
              break;
            }
            continue;
          }
        }

        // Fase 3: Scrittura diretta su disco dei chunk successivi del file
        if (outputFileSink != null) {
          outputFileSink.add(chunk);
          receivedPayloadBytes += chunk.length;
          onIncomingProgress?.call(
            parsedHeader.transferId,
            receivedPayloadBytes,
            parsedHeader.payloadSizeBytes,
          );

          if (receivedPayloadBytes >= parsedHeader.payloadSizeBytes) {
            break;
          }
        }
      }

      if (outputFileSink != null && parsedHeader != null) {
        await outputFileSink.flush();
        await outputFileSink.close();
        outputFileSink = null;

        _incomingMessagesController.add(
          P2PChatMessage(
            id: parsedHeader.transferId,
            peerId: parsedHeader.senderId,
            peerAlias: parsedHeader.senderAlias,
            isOutgoing: false,
            type: TransferPayloadType.binaryFile,
            content: parsedHeader.fileName ?? 'File ricevuto',
            filePath: savedFilePath,
            fileSize: parsedHeader.payloadSizeBytes,
            progress: 1.0,
            timestamp: DateTime.now(),
          ),
        );
      }
    } finally {
      await outputFileSink?.close();
      socket.destroy();
    }
  }

  /// Invia una stringa di testo asincrona al nodo selezionato tramite TCP
  Future<P2PChatMessage> sendTextMessage({
    required PeerNode targetPeer,
    required String messageText,
  }) async {
    final String transferId = _uuid.v4();
    final TcpTransferHeader header = TcpTransferHeader(
      transferId: transferId,
      type: TransferPayloadType.textMessage,
      senderId: localNodeId,
      senderAlias: localAlias,
      textContent: messageText,
      payloadSizeBytes: 0,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    final Socket socket = await Socket.connect(
      targetPeer.ipAddress,
      targetPeer.tcpPort,
      timeout: const Duration(seconds: 5),
    );

    try {
      socket.add(header.toFramedHeaderBytes());
      await socket.flush();
    } finally {
      await socket.close();
    }

    return P2PChatMessage(
      id: transferId,
      peerId: targetPeer.nodeId,
      peerAlias: targetPeer.alias,
      isOutgoing: true,
      type: TransferPayloadType.textMessage,
      content: messageText,
      timestamp: DateTime.now(),
    );
  }

  /// Invia un file arbitrario tramite stream di byte (chunk da 64 KB) con backpressure TCP
  Future<P2PChatMessage> sendFileStream({
    required PeerNode targetPeer,
    required File file,
    ProgressCallback? onProgress,
  }) async {
    final String transferId = _uuid.v4();
    final int totalBytes = await file.length();
    final String fileName = file.uri.pathSegments.last;

    final TcpTransferHeader header = TcpTransferHeader(
      transferId: transferId,
      type: TransferPayloadType.binaryFile,
      senderId: localNodeId,
      senderAlias: localAlias,
      fileName: fileName,
      payloadSizeBytes: totalBytes,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    final Socket socket = await Socket.connect(
      targetPeer.ipAddress,
      targetPeer.tcpPort,
      timeout: const Duration(seconds: 8),
    );

    socket.setOption(SocketOption.tcpNoDelay, true);

    try {
      // 1. Invia i 4 byte di lunghezza + Header JSON
      socket.add(header.toFramedHeaderBytes());

      // 2. Invia il file come Stream di blocchi gestendo la backpressure con socket.flush()
      int sentBytes = 0;
      final Stream<List<int>> fileStream = file.openRead();

      await for (final List<int> chunk in fileStream) {
        socket.add(chunk);
        sentBytes += chunk.length;
        onProgress?.call(transferId, sentBytes, totalBytes);

        // Ogni 512 KB attendiamo il flush del buffer di rete del kernel OS
        if (sentBytes % (512 * 1024) < chunk.length) {
          await socket.flush();
        }
      }

      await socket.flush();
    } finally {
      await socket.close();
    }

    return P2PChatMessage(
      id: transferId,
      peerId: targetPeer.nodeId,
      peerAlias: targetPeer.alias,
      isOutgoing: true,
      type: TransferPayloadType.binaryFile,
      content: fileName,
      filePath: file.path,
      fileSize: totalBytes,
      progress: 1.0,
      timestamp: DateTime.now(),
    );
  }

  Future<Directory> _resolveDownloadDirectory() async {
    if (Platform.isWindows) {
      final Directory? downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<void> stopServer() async {
    await _serverSocket?.close();
    _serverSocket = null;
  }

  void dispose() {
    stopServer();
    _incomingMessagesController.close();
  }
}
