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
  String localAlias;
  final int listenPort;
  final String? Function() getLocalIp;
  final void Function(String targetIp)? onRequestReverseConnect;

  ServerSocket? _serverSocket;
  final Uuid _uuid = const Uuid();
  ProgressCallback? _onIncomingProgress;

  /// Coda di socket inversi richiesti quando il destinatario (es. PC Windows) ha il firewall attivo
  final Map<String, List<Completer<Socket>>> _pendingReverseSocketsByIp = {};

  final StreamController<P2PChatMessage> _incomingMessagesController =
      StreamController<P2PChatMessage>.broadcast();
  final StreamController<PeerNode> _discoveredPeerController =
      StreamController<PeerNode>.broadcast();

  Stream<P2PChatMessage> get incomingMessages =>
      _incomingMessagesController.stream;
  Stream<PeerNode> get discoveredPeerStream => _discoveredPeerController.stream;

  SocketTransferService({
    required this.localNodeId,
    required this.localAlias,
    required this.getLocalIp,
    this.onRequestReverseConnect,
    this.listenPort = NetworkConstants.tcpTransferPort,
  });

  String get _platformName {
    if (Platform.isAndroid) return 'ANDROID';
    if (Platform.isWindows) return 'WINDOWS';
    return 'UNKNOWN';
  }

  PeerPlatform _parsePlatform(String? raw) {
    return switch ((raw ?? '').toUpperCase()) {
      'ANDROID' => PeerPlatform.android,
      'WINDOWS' => PeerPlatform.windows,
      _ => PeerPlatform.unknown,
    };
  }

  Future<void> startServer({ProgressCallback? onIncomingProgress}) async {
    await stopServer();
    _onIncomingProgress = onIncomingProgress;

    if (Platform.isWindows) {
      _tryConfigureWindowsFirewall();
    }

    _serverSocket = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      listenPort,
      shared: true,
    );

    _serverSocket!.listen(
      (Socket clientSocket) => _handleIncomingSocket(clientSocket),
      onError: (_) {},
    );
  }

  void _tryConfigureWindowsFirewall() {
    try {
      Process.run('netsh', [
        'advfirewall',
        'firewall',
        'add',
        'rule',
        'name=LanPulse P2P TCP',
        'dir=in',
        'action=allow',
        'protocol=TCP',
        'localport=$listenPort',
      ]);
      Process.run('netsh', [
        'advfirewall',
        'firewall',
        'add',
        'rule',
        'name=LanPulse P2P UDP',
        'dir=in',
        'action=allow',
        'protocol=UDP',
        'localport=${NetworkConstants.udpDiscoveryPort}',
      ]);
    } catch (_) {}
  }

  /// Esegue un Handshake TCP bidirezionale con un IP e restituisce il PeerNode reale
  Future<PeerNode?> performHandshake({
    required String targetIp,
    int targetPort = NetworkConstants.tcpTransferPort,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        targetIp,
        targetPort,
        timeout: const Duration(seconds: 3),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);

      final TcpTransferHeader header = TcpTransferHeader(
        transferId: _uuid.v4(),
        type: TransferPayloadType.handshake,
        senderId: localNodeId,
        senderAlias: localAlias,
        senderIp: getLocalIp(),
        senderPort: listenPort,
        senderPlatform: _platformName,
        payloadSizeBytes: 0,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

      socket.add(header.toFramedHeaderBytes());
      await socket.flush();

      final List<int> responseBytes = await socket
          .fold<List<int>>(<int>[], (prev, element) => prev..addAll(element))
          .timeout(const Duration(seconds: 3), onTimeout: () => <int>[]);

      if (responseBytes.isNotEmpty) {
        final Map<String, dynamic> map =
            jsonDecode(utf8.decode(responseBytes)) as Map<String, dynamic>;
        final PeerNode remotePeer = PeerNode(
          nodeId: map['nodeId'] as String? ?? 'peer-$targetIp',
          alias: map['alias'] as String? ?? 'Dispositivo ($targetIp)',
          ipAddress: targetIp,
          tcpPort: (map['tcpPort'] as num?)?.toInt() ?? targetPort,
          platform: _parsePlatform(map['platform'] as String?),
          lastSeen: DateTime.now(),
        );
        _discoveredPeerController.add(remotePeer);
        return remotePeer;
      }
    } catch (_) {
      return null;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
    return null;
  }

  /// Chiamato dal PC/dispositivo quando riceve una richiesta di connessione inversa
  /// (per ricevere file o messaggi da un telefono bloccato dal firewall in ingresso).
  Future<void> fulfillReverseConnect({
    required String targetIp,
    int targetPort = NetworkConstants.tcpTransferPort,
  }) async {
    try {
      final Socket socket = await Socket.connect(
        targetIp,
        targetPort,
        timeout: const Duration(seconds: 4),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);

      final TcpTransferHeader pullHeader = TcpTransferHeader(
        transferId: _uuid.v4(),
        type: TransferPayloadType.pullPending,
        senderId: localNodeId,
        senderAlias: localAlias,
        senderIp: getLocalIp(),
        senderPort: listenPort,
        senderPlatform: _platformName,
        payloadSizeBytes: 0,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

      socket.add(pullHeader.toFramedHeaderBytes());
      await socket.flush();

      // Ora legge il messaggio o file che il telefono invia su questo stesso socket!
      await _processIncomingStream(socket, remoteIpOverride: targetIp);
    } catch (_) {}
  }

  Future<void> _handleIncomingSocket(Socket socket) async {
    await _processIncomingStream(socket);
  }

  Future<void> _processIncomingStream(
    Socket socket, {
    String? remoteIpOverride,
  }) async {
    final String remoteIp =
        remoteIpOverride ?? socket.remoteAddress.address;
    final List<int> headerBuffer = [];
    int? expectedHeaderLength;
    TcpTransferHeader? parsedHeader;
    IOSink? outputFileSink;
    String? savedFilePath;
    int receivedPayloadBytes = 0;
    int lastProgressReportMs = 0;

    try {
      await for (final Uint8List chunk in socket) {
        if (parsedHeader == null) {
          headerBuffer.addAll(chunk);

          if (expectedHeaderLength == null) {
            if (headerBuffer.length < 4) continue;
            final Uint8List prefix =
                Uint8List.fromList(headerBuffer.sublist(0, 4));
            expectedHeaderLength =
                ByteData.sublistView(prefix).getUint32(0, Endian.big);
            headerBuffer.removeRange(0, 4);
          }

          if (headerBuffer.length < expectedHeaderLength!) {
            continue;
          }

          final List<int> jsonBytes =
              headerBuffer.sublist(0, expectedHeaderLength!);
          final List<int> leftoverPayload =
              headerBuffer.sublist(expectedHeaderLength!);
          headerBuffer.clear();

          final Map<String, dynamic> headerMap =
              jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
          parsedHeader = TcpTransferHeader.fromMap(headerMap);

          // Registra sempre il nodo mittente con il suo vero indirizzo IP!
          final String peerRealIp =
              (parsedHeader.senderIp != null &&
                      parsedHeader.senderIp!.isNotEmpty &&
                      parsedHeader.senderIp != '0.0.0.0')
                  ? parsedHeader.senderIp!
                  : remoteIp;

          if (parsedHeader.senderId.isNotEmpty &&
              parsedHeader.senderId != localNodeId) {
            _discoveredPeerController.add(
              PeerNode(
                nodeId: parsedHeader.senderId,
                alias: parsedHeader.senderAlias,
                ipAddress: peerRealIp,
                tcpPort: parsedHeader.senderPort ??
                    NetworkConstants.tcpTransferPort,
                platform: _parsePlatform(parsedHeader.senderPlatform),
                lastSeen: DateTime.now(),
              ),
            );
          }

          // Caso 1: Handshake di scoperta/connessione
          if (parsedHeader.type == TransferPayloadType.handshake) {
            final String replyJson = jsonEncode({
              'nodeId': localNodeId,
              'alias': localAlias,
              'ip': getLocalIp() ?? '',
              'tcpPort': listenPort,
              'platform': _platformName,
            });
            socket.add(utf8.encode(replyJson));
            await socket.flush();
            break;
          }

          // Caso 2: Il PC si è connesso al telefono per prelevare un file/messaggio in coda
          if (parsedHeader.type == TransferPayloadType.pullPending) {
            final List<Completer<Socket>>? waiters =
                _pendingReverseSocketsByIp[peerRealIp] ??
                _pendingReverseSocketsByIp[remoteIp];
            if (waiters != null && waiters.isNotEmpty) {
              final Completer<Socket> completer = waiters.removeAt(0);
              if (!completer.isCompleted) {
                completer.complete(socket);
                // Non chiudere il socket qui: verrà gestito e chiuso da chi invia il file!
                return;
              }
            }
            break;
          }

          // Caso 3: Messaggio di testo
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
            socket.add(const [1]); // Invia ACK
            await socket.flush();
            break;
          }

          // Caso 4: File binario in arrivo
          final Directory targetDir = await _resolveDownloadDirectory();
          final String safeName =
              (parsedHeader.fileName ?? 'file_ricevuto.bin')
                  .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
          savedFilePath =
              '${targetDir.path}${Platform.pathSeparator}$safeName';
          outputFileSink = File(savedFilePath).openWrite();

          if (leftoverPayload.isNotEmpty) {
            outputFileSink.add(leftoverPayload);
            receivedPayloadBytes += leftoverPayload.length;
            _onIncomingProgress?.call(
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

        // Scrittura su disco dei chunk successivi del file
        if (outputFileSink != null && parsedHeader != null) {
          outputFileSink.add(chunk);
          receivedPayloadBytes += chunk.length;

          final int nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - lastProgressReportMs > 90 ||
              receivedPayloadBytes >= parsedHeader.payloadSizeBytes) {
            lastProgressReportMs = nowMs;
            _onIncomingProgress?.call(
              parsedHeader.transferId,
              receivedPayloadBytes,
              parsedHeader.payloadSizeBytes,
            );
          }

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

        socket.add(const [1]); // Invia ACK di conferma salvataggio file
        await socket.flush();
      }
    } catch (_) {
      // Gestione silenziosa disconnessioni socket
    } finally {
      try {
        await outputFileSink?.close();
      } catch (_) {}
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  /// Apre un socket TCP verso il destinatario; se bloccato da Windows Firewall,
  /// attiva automaticamente il Reverse-Connect e usa il socket aperto dal destinatario.
  Future<Socket> _openSocketWithReverseFallback(PeerNode targetPeer) async {
    try {
      final Socket directSocket = await Socket.connect(
        targetPeer.ipAddress,
        targetPeer.tcpPort,
        timeout: const Duration(seconds: 2, milliseconds: 500),
      );
      directSocket.setOption(SocketOption.tcpNoDelay, true);
      return directSocket;
    } catch (_) {
      // Fallback: richiedi al destinatario di connettersi a noi
      final Completer<Socket> reverseCompleter = Completer<Socket>();
      _pendingReverseSocketsByIp
          .putIfAbsent(targetPeer.ipAddress, () => [])
          .add(reverseCompleter);

      onRequestReverseConnect?.call(targetPeer.ipAddress);

      try {
        return await reverseCompleter.future.timeout(
          const Duration(seconds: 6),
        );
      } finally {
        _pendingReverseSocketsByIp[targetPeer.ipAddress]
            ?.remove(reverseCompleter);
      }
    }
  }

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
      senderIp: getLocalIp(),
      senderPort: listenPort,
      senderPlatform: _platformName,
      textContent: messageText,
      payloadSizeBytes: 0,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    final Socket socket = await _openSocketWithReverseFallback(targetPeer);

    try {
      socket.add(header.toFramedHeaderBytes());
      await socket.flush();
      // Attendi ACK o chiusura dal destinatario (max 2s)
      await socket.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => Uint8List(0),
      );
    } catch (_) {
    } finally {
      try {
        await socket.close();
      } catch (_) {}
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

  Future<P2PChatMessage> sendFileStream({
    required PeerNode targetPeer,
    required String fileName,
    required int totalBytes,
    required Stream<List<int>> fileStream,
    String? localFilePath,
    ProgressCallback? onProgress,
  }) async {
    final String transferId = _uuid.v4();

    final TcpTransferHeader header = TcpTransferHeader(
      transferId: transferId,
      type: TransferPayloadType.binaryFile,
      senderId: localNodeId,
      senderAlias: localAlias,
      senderIp: getLocalIp(),
      senderPort: listenPort,
      senderPlatform: _platformName,
      fileName: fileName,
      payloadSizeBytes: totalBytes,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    final Socket socket = await _openSocketWithReverseFallback(targetPeer);

    try {
      socket.add(header.toFramedHeaderBytes());

      int sentBytes = 0;
      int lastProgressMs = 0;

      await for (final List<int> chunk in fileStream) {
        socket.add(chunk);
        sentBytes += chunk.length;

        final int nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - lastProgressMs > 90 || sentBytes >= totalBytes) {
          lastProgressMs = nowMs;
          onProgress?.call(transferId, sentBytes, totalBytes);
        }

        if (sentBytes % (512 * 1024) < chunk.length) {
          await socket.flush();
        }
      }

      await socket.flush();
      // Attendi che il destinatario confermi il salvataggio su disco
      await socket.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => Uint8List(0),
      );
    } finally {
      try {
        await socket.close();
      } catch (_) {}
    }

    return P2PChatMessage(
      id: transferId,
      peerId: targetPeer.nodeId,
      peerAlias: targetPeer.alias,
      isOutgoing: true,
      type: TransferPayloadType.binaryFile,
      content: fileName,
      filePath: localFilePath,
      fileSize: totalBytes,
      progress: 1.0,
      timestamp: DateTime.now(),
    );
  }

  Future<Directory> _resolveDownloadDirectory() async {
    if (Platform.isWindows) {
      final Directory? downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } else if (Platform.isAndroid) {
      final Directory publicDownload = Directory('/storage/emulated/0/Download');
      if (await publicDownload.exists()) {
        return publicDownload;
      }
      final Directory? extDir = await getExternalStorageDirectory();
      if (extDir != null) return extDir;
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
    _discoveredPeerController.close();
  }
}
