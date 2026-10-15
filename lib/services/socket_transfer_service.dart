import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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

typedef FilePermissionCheckCallback = Future<bool> Function(
  IncomingFileRequest request,
);

/// Lettore asincrono bufferizzato su singolo listener per leggere header, ACK e frammenti
/// dallo stesso Socket TCP senza causare eccezioni di stream multi-subscription.
class _BufferedSocketReader {
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  StreamSubscription<Uint8List>? _sub;
  bool _isClosed = false;
  Object? _error;

  _BufferedSocketReader(Socket socket) {
    _sub = socket.listen(
      (Uint8List data) {
        if (data.isEmpty) return;
        _buffer.add(data);
        _notifyWaiters();
      },
      onError: (Object err) {
        _error = err;
        _isClosed = true;
        _notifyWaiters();
      },
      onDone: () {
        _isClosed = true;
        _notifyWaiters();
      },
      cancelOnError: false,
    );
  }

  void _notifyWaiters() {
    while (_waiters.isNotEmpty) {
      final Completer<void> c = _waiters.removeFirst();
      if (!c.isCompleted) c.complete();
    }
  }

  Future<Uint8List> readExact(
    int count, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (count == 0) return Uint8List(0);

    final DateTime deadline = DateTime.now().add(timeout);
    while (_buffer.length < count) {
      if (_error != null) {
        throw SocketException('Errore lettura socket: $_error');
      }
      if (_isClosed) {
        throw const SocketException('Connessione chiusa dal peer remoto.');
      }
      final Duration remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw TimeoutException('Timeout in attesa di $count byte dal peer.');
      }
      final Completer<void> waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future.timeout(remaining);
    }

    final Uint8List all = _buffer.takeBytes();
    final Uint8List result = Uint8List.sublistView(all, 0, count);
    if (all.length > count) {
      _buffer.add(Uint8List.sublistView(all, count));
    }
    return Uint8List.fromList(result);
  }

  Future<int> readByte({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final Uint8List b = await readExact(1, timeout: timeout);
    return b[0];
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _notifyWaiters();
  }
}

class SocketTransferService {
  final String localNodeId;
  String localAlias;
  final int listenPort;
  final String? Function() getLocalIp;
  final void Function(String targetIp)? onRequestReverseConnect;
  final FilePermissionCheckCallback? onIncomingFilePermissionCheck;

  ServerSocket? _serverSocket;
  final Uuid _uuid = const Uuid();
  ProgressCallback? _onIncomingProgress;

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
    this.onIncomingFilePermissionCheck,
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
          isOnline: true,
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
    final String remoteIp = remoteIpOverride ?? socket.remoteAddress.address;
    _BufferedSocketReader? reader;
    IOSink? outputFileSink;
    String? savedFilePath;

    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      reader = _BufferedSocketReader(socket);

      // 1. Legge i 4 byte di lunghezza dell'Header JSON
      final Uint8List lengthBytes =
          await reader.readExact(4, timeout: const Duration(seconds: 15));
      final int headerLength =
          ByteData.sublistView(lengthBytes).getUint32(0, Endian.big);

      // 2. Legge l'Header JSON completo
      final Uint8List headerJsonBytes = await reader.readExact(
        headerLength,
        timeout: const Duration(seconds: 15),
      );
      final Map<String, dynamic> headerMap =
          jsonDecode(utf8.decode(headerJsonBytes)) as Map<String, dynamic>;
      final TcpTransferHeader parsedHeader =
          TcpTransferHeader.fromMap(headerMap);

      final String peerRealIp = (parsedHeader.senderIp != null &&
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
            tcpPort:
                parsedHeader.senderPort ?? NetworkConstants.tcpTransferPort,
            platform: _parsePlatform(parsedHeader.senderPlatform),
            lastSeen: DateTime.now(),
            isOnline: true,
          ),
        );
      }

      // Caso 1: Handshake
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
        return;
      }

      // Caso 2: Reverse Connect (pullPending)
      if (parsedHeader.type == TransferPayloadType.pullPending) {
        final List<Completer<Socket>>? waiters =
            _pendingReverseSocketsByIp[peerRealIp] ??
                _pendingReverseSocketsByIp[remoteIp];
        if (waiters != null && waiters.isNotEmpty) {
          final Completer<Socket> completer = waiters.removeAt(0);
          if (!completer.isCompleted) {
            await reader.dispose();
            reader = null;
            completer.complete(socket);
            return;
          }
        }
        return;
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
        socket.add(const [NetworkConstants.ctrlAccepted]);
        await socket.flush();
        return;
      }

      // Caso 4: File binario in arrivo (con richiesta mandatoria se non fidato)
      final IncomingFileRequest fileReq = IncomingFileRequest(
        transferId: parsedHeader.transferId,
        senderId: parsedHeader.senderId,
        senderAlias: parsedHeader.senderAlias,
        senderIp: peerRealIp,
        fileName: parsedHeader.fileName ?? 'file_ricevuto.bin',
        fileSizeBytes: parsedHeader.payloadSizeBytes,
        timestamp: DateTime.now(),
      );

      bool isAllowed = true;
      if (onIncomingFilePermissionCheck != null) {
        isAllowed = await onIncomingFilePermissionCheck!(fileReq);
      }

      if (!isAllowed) {
        socket.add(const [NetworkConstants.ctrlRejected]);
        await socket.flush();
        return;
      }

      // Invia conferma di accettazione al mittente
      socket.add(const [NetworkConstants.ctrlAccepted]);
      await socket.flush();

      final Directory targetDir = await _resolveDownloadDirectory();
      final String safeName = (parsedHeader.fileName ?? 'file_ricevuto.bin')
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      savedFilePath = _resolveUniqueFilePath(targetDir.path, safeName);
      outputFileSink = File(savedFilePath).openWrite();

      int receivedPayloadBytes = 0;
      int lastProgressReportMs = 0;

      if (parsedHeader.chunkedProtocol) {
        // Ricezione a pacchetti frammentati con controllo di flusso
        int chunksSinceLastAck = 0;
        while (receivedPayloadBytes < parsedHeader.payloadSizeBytes) {
          final Uint8List chunkHeaderBytes = await reader.readExact(
            8,
            timeout: const Duration(seconds: 45),
          );
          final ByteData chunkHeader = ByteData.sublistView(chunkHeaderBytes);
          final int chunkIndex = chunkHeader.getUint32(0, Endian.big);
          final int chunkLength = chunkHeader.getUint32(4, Endian.big);

          if (chunkLength == 0 && chunkIndex == 0xFFFFFFFF) {
            break; // Marker EOF
          }

          final Uint8List fragmentData = await reader.readExact(
            chunkLength,
            timeout: const Duration(seconds: 45),
          );

          outputFileSink.add(fragmentData);
          receivedPayloadBytes += fragmentData.length;
          chunksSinceLastAck++;

          final int nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - lastProgressReportMs > 80 ||
              receivedPayloadBytes >= parsedHeader.payloadSizeBytes) {
            lastProgressReportMs = nowMs;
            _onIncomingProgress?.call(
              parsedHeader.transferId,
              receivedPayloadBytes,
              parsedHeader.payloadSizeBytes,
            );
          }

          // Ogni N frammenti (o a fine file), scarica su disco e invia ACK di finestra
          if (chunksSinceLastAck >= NetworkConstants.ackWindowChunks ||
              receivedPayloadBytes >= parsedHeader.payloadSizeBytes) {
            await outputFileSink.flush();
            socket.add(const [NetworkConstants.ctrlChunkWindowAck]);
            await socket.flush();
            chunksSinceLastAck = 0;
          }
        }
      } else {
        // Retrocompatibilità con nodi non frammentati
        while (receivedPayloadBytes < parsedHeader.payloadSizeBytes) {
          final int remaining =
              parsedHeader.payloadSizeBytes - receivedPayloadBytes;
          final int toRead =
              math.min(remaining, NetworkConstants.fileChunkSizeBytes);
          final Uint8List data = await reader.readExact(
            toRead,
            timeout: const Duration(seconds: 45),
          );
          outputFileSink.add(data);
          receivedPayloadBytes += data.length;
          _onIncomingProgress?.call(
            parsedHeader.transferId,
            receivedPayloadBytes,
            parsedHeader.payloadSizeBytes,
          );
        }
      }

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

      socket.add(const [NetworkConstants.ctrlTransferCompleteAck]);
      await socket.flush();
    } catch (_) {
      // Se il trasferimento si interrompe a metà, rimuove il file parziale
      if (outputFileSink != null) {
        try {
          await outputFileSink.close();
          outputFileSink = null;
          if (savedFilePath != null) {
            final File incomplete = File(savedFilePath);
            if (await incomplete.exists()) {
              await incomplete.delete();
            }
          }
        } catch (_) {}
      }
    } finally {
      try {
        await reader?.dispose();
      } catch (_) {}
      try {
        await outputFileSink?.close();
      } catch (_) {}
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  String _resolveUniqueFilePath(String dirPath, String fileName) {
    String candidate = '$dirPath${Platform.pathSeparator}$fileName';
    if (!File(candidate).existsSync()) return candidate;

    final int dotIndex = fileName.lastIndexOf('.');
    final String baseName =
        dotIndex != -1 ? fileName.substring(0, dotIndex) : fileName;
    final String ext = dotIndex != -1 ? fileName.substring(dotIndex) : '';
    int counter = 1;
    while (File(candidate).existsSync()) {
      candidate = '$dirPath${Platform.pathSeparator}${baseName}_($counter)$ext';
      counter++;
    }
    return candidate;
  }

  Future<Socket> _openSocketWithReverseFallback(PeerNode targetPeer) async {
    try {
      final Socket directSocket = await Socket.connect(
        targetPeer.ipAddress,
        targetPeer.tcpPort,
        timeout: const Duration(seconds: 3),
      );
      directSocket.setOption(SocketOption.tcpNoDelay, true);
      return directSocket;
    } catch (_) {
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
    final _BufferedSocketReader reader = _BufferedSocketReader(socket);

    try {
      socket.add(header.toFramedHeaderBytes());
      await socket.flush();
      await reader.readByte(timeout: const Duration(seconds: 3));
    } catch (_) {
    } finally {
      await reader.dispose();
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

  /// Invia un file suddividendolo in frammenti da 64 KB con attesa di autorizzazione
  /// (per gli host non fidati) e controllo di flusso a finestra (per file di grandi dimensioni).
  Future<P2PChatMessage> sendFileFragmented({
    required PeerNode targetPeer,
    required String fileName,
    required int totalBytes,
    String? localFilePath,
    Stream<List<int>>? fallbackStream,
    ProgressCallback? onProgress,
  }) async {
    final String transferId = _uuid.v4();
    const int chunkSize = NetworkConstants.fileChunkSizeBytes;
    final int totalChunks =
        totalBytes == 0 ? 1 : ((totalBytes + chunkSize - 1) ~/ chunkSize);

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
      chunkedProtocol: true,
      chunkSize: chunkSize,
      totalChunks: totalChunks,
    );

    final Socket socket = await _openSocketWithReverseFallback(targetPeer);
    final _BufferedSocketReader reader = _BufferedSocketReader(socket);
    RandomAccessFile? raf;

    try {
      // 1. Invia l'Header del file e attende l'accettazione (fino a 90s se il destinatario deve cliccare Accetta)
      socket.add(header.toFramedHeaderBytes());
      await socket.flush();

      final int permissionByte = await reader.readByte(
        timeout: const Duration(seconds: 90),
      );

      if (permissionByte != NetworkConstants.ctrlAccepted) {
        throw Exception(
          'Richiesta di invio file rifiutata da ${targetPeer.alias}.',
        );
      }

      int sentBytes = 0;
      int chunkIndex = 0;
      int chunksInWindow = 0;
      int lastProgressMs = 0;

      Future<void> sendSingleFragment(Uint8List payloadSlice) async {
        final ByteData fHeader = ByteData(8)
          ..setUint32(0, chunkIndex, Endian.big)
          ..setUint32(4, payloadSlice.length, Endian.big);

        socket.add(fHeader.buffer.asUint8List());
        socket.add(payloadSlice);

        sentBytes += payloadSlice.length;
        chunkIndex++;
        chunksInWindow++;

        final int nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - lastProgressMs > 80 || sentBytes >= totalBytes) {
          lastProgressMs = nowMs;
          onProgress?.call(transferId, sentBytes, totalBytes);
        }

        if (chunksInWindow >= NetworkConstants.ackWindowChunks ||
            sentBytes >= totalBytes) {
          await socket.flush();
          final int ack = await reader.readByte(
            timeout: const Duration(seconds: 45),
          );
          if (ack != NetworkConstants.ctrlChunkWindowAck) {
            throw const SocketException(
              'Errore di sincronizzazione pacchetto durante il trasferimento.',
            );
          }
          chunksInWindow = 0;
        }
      }

      // 2. Lettura deterministica a blocchi da 64 KB tramite RandomAccessFile (ottimale per file enormi)
      if (localFilePath != null && File(localFilePath).existsSync()) {
        raf = await File(localFilePath).open(mode: FileMode.read);
        final Uint8List reusableBuffer = Uint8List(chunkSize);

        while (sentBytes < totalBytes) {
          final int bytesRead = await raf.readInto(reusableBuffer);
          if (bytesRead <= 0) break;
          final Uint8List slice = bytesRead == chunkSize
              ? Uint8List.fromList(reusableBuffer)
              : Uint8List.fromList(reusableBuffer.sublist(0, bytesRead));
          await sendSingleFragment(slice);
        }
      } else if (fallbackStream != null) {
        // Fallback con risegmentazione esatta in blocchi da 64 KB
        final BytesBuilder accumulator = BytesBuilder(copy: false);
        await for (final List<int> rawChunk in fallbackStream) {
          accumulator.add(rawChunk);
          while (accumulator.length >= chunkSize) {
            final Uint8List all = accumulator.takeBytes();
            final Uint8List slice =
                Uint8List.fromList(Uint8List.sublistView(all, 0, chunkSize));
            if (all.length > chunkSize) {
              accumulator.add(Uint8List.sublistView(all, chunkSize));
            }
            await sendSingleFragment(slice);
          }
        }
        if (accumulator.isNotEmpty) {
          await sendSingleFragment(accumulator.takeBytes());
        }
      } else {
        throw Exception('Sorgente file non disponibile.');
      }

      // 3. Attende la conferma finale di salvataggio completato su disco
      final int finalAck = await reader.readByte(
        timeout: const Duration(seconds: 30),
      );
      if (finalAck != NetworkConstants.ctrlTransferCompleteAck) {
        throw const SocketException(
            'Mancata conferma finale di salvataggio dal destinatario.');
      }
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
      await reader.dispose();
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
