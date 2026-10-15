import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/p2p_packet.dart';
import '../models/peer_node.dart';
import '../services/discovery_service.dart';
import '../services/socket_transfer_service.dart';

class P2PController extends ChangeNotifier {
  late final String localNodeId;
  late final String localAlias;
  late final DiscoveryService _discoveryService;
  late final SocketTransferService _transferService;

  List<PeerNode> _peers = [];
  PeerNode? _selectedPeer;
  final List<P2PChatMessage> _messages = [];
  double _activeTransferProgress = 0.0;
  bool _isTransferring = false;
  String? _errorBanner;

  List<PeerNode> get peers => _peers;
  PeerNode? get selectedPeer => _selectedPeer;
  String? get localIp => _discoveryService.localIp;
  bool get isTransferring => _isTransferring;
  double get activeTransferProgress => _activeTransferProgress;
  String? get errorBanner => _errorBanner;

  List<P2PChatMessage> get messagesForSelectedPeer {
    if (_selectedPeer == null) return [];
    return _messages
        .where((m) => m.peerId == _selectedPeer!.nodeId)
        .toList();
  }

  P2PController() {
    localNodeId = const Uuid().v4().substring(0, 8);
    localAlias = Platform.isWindows
        ? 'Win-${Platform.localHostname}'
        : 'Android-Node-$localNodeId';

    _discoveryService = DiscoveryService(
      localNodeId: localNodeId,
      localAlias: localAlias,
    );

    _transferService = SocketTransferService(
      localNodeId: localNodeId,
      localAlias: localAlias,
    );

    _initializeNetworking();
  }

  Future<void> _initializeNetworking() async {
    _discoveryService.peersStream.listen((updatedPeers) {
      _peers = updatedPeers;
      if (_selectedPeer == null && _peers.isNotEmpty) {
        _selectedPeer = _peers.first;
      }
      notifyListeners();
    });

    _transferService.incomingMessages.listen((msg) {
      _messages.add(msg);
      _isTransferring = false;
      _activeTransferProgress = 0.0;
      notifyListeners();
    });

    try {
      await _transferService.startServer(
        onIncomingProgress: (_, transferred, total) {
          _isTransferring = true;
          _activeTransferProgress = total > 0 ? transferred / total : 0.0;
          notifyListeners();
        },
      );
      await _discoveryService.startDiscovery();
    } catch (e) {
      _errorBanner = 'Errore avvio socket di rete: $e';
      notifyListeners();
    }
  }

  void selectPeer(PeerNode peer) {
    _selectedPeer = peer;
    _errorBanner = null;
    notifyListeners();
  }

  Future<void> sendText(String text) async {
    final PeerNode? target = _selectedPeer;
    if (target == null || text.trim().isEmpty) return;

    try {
      final P2PChatMessage sent = await _transferService.sendTextMessage(
        targetPeer: target,
        messageText: text.trim(),
      );
      _messages.add(sent);
      notifyListeners();
    } catch (e) {
      _errorBanner = 'Invio messaggio fallito verso ${target.alias}: $e';
      notifyListeners();
    }
  }

  Future<void> pickAndSendFile() async {
    final PeerNode? target = _selectedPeer;
    if (target == null) return;

    final FilePickerResult? result = await FilePicker.platform.pickFiles();
    final String? path = result?.files.single.path;
    if (path == null) return;

    _isTransferring = true;
    _activeTransferProgress = 0.0;
    notifyListeners();

    try {
      final P2PChatMessage sentFileMsg = await _transferService.sendFileStream(
        targetPeer: target,
        file: File(path),
        onProgress: (_, sent, total) {
          _activeTransferProgress = total > 0 ? sent / total : 0.0;
          notifyListeners();
        },
      );
      _messages.add(sentFileMsg);
    } catch (e) {
      _errorBanner = 'Trasferimento file interrotto: $e';
    } finally {
      _isTransferring = false;
      _activeTransferProgress = 0.0;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _discoveryService.dispose();
    _transferService.dispose();
    super.dispose();
  }
}