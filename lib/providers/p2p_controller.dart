import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/network_constants.dart';
import '../models/p2p_packet.dart';
import '../models/peer_node.dart';
import '../services/discovery_service.dart';
import '../services/notification_service.dart';
import '../services/socket_transfer_service.dart';
import '../services/sound_service.dart';

enum AppThemePreset {
  cyberPulse('Cyber Cyan', Color(0xFF0284C7), Color(0xFF38BDF8)),
  emeraldMatrix('Emerald Mint', Color(0xFF059669), Color(0xFF10B981)),
  royalAmethyst('Linear Violet', Color(0xFF6D28D9), Color(0xFFA78BFA)),
  sunsetCrimson('Pulse Rose', Color(0xFFE11D48), Color(0xFFFB7185)),
  nordicFrost('Arctic Blue', Color(0xFF2563EB), Color(0xFF60A5FA)),
  amberGold('Fintech Gold', Color(0xFFD97706), Color(0xFFFBBF24));

  final String label;
  final Color lightSeed;
  final Color darkSeed;
  const AppThemePreset(this.label, this.lightSeed, this.darkSeed);
}

class PendingRequestItem {
  final IncomingFileRequest request;
  final Completer<bool> completer;

  PendingRequestItem({
    required this.request,
    required this.completer,
  });
}

class P2PController extends ChangeNotifier with WidgetsBindingObserver {
  // Versione corrente dell'app
  static const String appVersion = 'v1.4.0 (0.3.5)';

  late String localNodeId;
  late String _localAlias;
  late final DiscoveryService _discoveryService;
  late final SocketTransferService _transferService;
  final SoundService _soundService = SoundService();
  final NotificationAndBackgroundService _notifService =
      NotificationAndBackgroundService.instance;

  List<PeerNode> _onlinePeers = [];
  final Map<String, PeerNode> _knownPeers = {};
  PeerNode? _selectedPeer;

  final List<P2PChatMessage> _messages = [];
  final List<FileHistoryEntry> _fileHistory = [];
  final Map<String, int> _unreadCounts = {};
  final List<PendingRequestItem> _pendingFileRequests = [];

  ActiveTransferTask? _activeTransferTask;
  int _lastNotifiedProgressPct = -1;
  bool _isScanningWifi = false;
  String? _statusBanner;
  bool _isBannerError = false;

  bool _isDarkMode = true;
  bool _useAmoledBlack = false;
  AppThemePreset _themePreset = AppThemePreset.cyberPulse;
  bool _sfxEnabled = true;

  PeerNode? get selectedPeer => _selectedPeer;
  String get localAlias => _localAlias;
  String? get localIp => _discoveryService.localIp;
  List<String> get allLocalIps => _discoveryService.allLocalIps;
  int get tcpPort => NetworkConstants.tcpTransferPort;
  ActiveTransferTask? get activeTransferTask => _activeTransferTask;
  bool get isTransferring => _activeTransferTask != null;
  double get activeTransferProgress => _activeTransferTask?.progress ?? 0.0;
  bool get isScanningWifi => _isScanningWifi;
  String? get errorBanner => _statusBanner;
  bool get isBannerError => _isBannerError;

  bool get isDarkMode => _isDarkMode;
  bool get useAmoledBlack => _useAmoledBlack;
  AppThemePreset get themePreset => _themePreset;
  bool get sfxEnabled => _sfxEnabled;

  List<FileHistoryEntry> get fileHistory => List.unmodifiable(_fileHistory);
  List<FileHistoryEntry> get sentFileHistory =>
      _fileHistory.where((f) => f.isOutgoing).toList();
  List<FileHistoryEntry> get receivedFileHistory =>
      _fileHistory.where((f) => !f.isOutgoing).toList();

  List<PendingRequestItem> get pendingFileRequests =>
      List.unmodifiable(_pendingFileRequests);

  int get totalUnreadCount =>
      _unreadCounts.values.fold(0, (prev, count) => prev + count);

  List<PeerNode> get peers {
    final Map<String, PeerNode> merged = {};

    for (final saved in _knownPeers.values) {
      merged[saved.nodeId] = saved.copyWith(isOnline: false);
    }

    for (final online in _onlinePeers) {
      PeerNode? matchedKnown = _knownPeers[online.nodeId];
      if (matchedKnown == null) {
        for (final k in _knownPeers.values) {
          if (k.ipAddress == online.ipAddress ||
              (k.alias.toLowerCase() == online.alias.toLowerCase() &&
                  k.platform == online.platform)) {
            matchedKnown = k;
            break;
          }
        }
      }

      final bool trusted = matchedKnown?.isTrusted ?? false;
      merged[online.nodeId] = online.copyWith(
        alias: matchedKnown?.alias ?? online.alias,
        isTrusted: trusted,
        isOnline: true,
      );
    }

    final List<PeerNode> result = merged.values.toList()
      ..sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        if (a.isTrusted != b.isTrusted) return a.isTrusted ? -1 : 1;
        return a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
      });
    return result;
  }

  List<PeerNode> get savedContactsList =>
      peers.where((p) => p.isTrusted).toList();

  List<PeerNode> get activeChatPeers {
    final Set<String> peerIdsWithMessages =
        _messages.map((m) => m.peerId).toSet();
    final List<PeerNode> allKnown = peers;
    final Map<String, PeerNode> chatMap = {};

    for (final p in allKnown) {
      if (p.isTrusted || peerIdsWithMessages.contains(p.nodeId)) {
        chatMap[p.nodeId] = p;
      }
    }

    for (final msg in _messages) {
      if (!chatMap.containsKey(msg.peerId)) {
        chatMap[msg.peerId] = PeerNode(
          nodeId: msg.peerId,
          alias: msg.peerAlias,
          ipAddress: 'Offline',
          tcpPort: NetworkConstants.tcpTransferPort,
          platform: PeerPlatform.unknown,
          lastSeen: msg.timestamp,
          isTrusted: false,
          isOnline: false,
        );
      }
    }

    final List<PeerNode> list = chatMap.values.toList();
    list.sort((a, b) {
      final DateTime aTime =
          lastMessageForPeer(a.nodeId)?.timestamp ?? a.lastSeen;
      final DateTime bTime =
          lastMessageForPeer(b.nodeId)?.timestamp ?? b.lastSeen;
      return bTime.compareTo(aTime);
    });
    return list;
  }

  int unreadCountForPeer(String peerId) => _unreadCounts[peerId] ?? 0;

  P2PChatMessage? lastMessageForPeer(String peerId) {
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].peerId == peerId) return _messages[i];
    }
    return null;
  }

  List<P2PChatMessage> messagesForPeer(String peerId) {
    return _messages.where((m) => m.peerId == peerId).toList();
  }

  List<P2PChatMessage> get messagesForSelectedPeer {
    if (_selectedPeer == null) return [];
    return messagesForPeer(_selectedPeer!.nodeId);
  }

  P2PController() {
    WidgetsBinding.instance.addObserver(this);
    localNodeId = const Uuid().v4().substring(0, 8);
    _localAlias = Platform.isWindows
        ? 'PC-${Platform.localHostname}'
        : 'Android-$localNodeId';

    _discoveryService = DiscoveryService(
      localNodeId: localNodeId,
      localAlias: _localAlias,
      onTcpPeerCandidateFound: (ip, port) {
        _transferService.performHandshake(targetIp: ip, targetPort: port);
      },
      onReverseConnectRequested: (ip, port) {
        _transferService.fulfillReverseConnect(targetIp: ip, targetPort: port);
      },
    );

    _transferService = SocketTransferService(
      localNodeId: localNodeId,
      localAlias: _localAlias,
      getLocalIp: () => _discoveryService.localIp,
      onRequestReverseConnect: (targetIp) {
        _discoveryService.sendReverseConnectRequest(targetIp);
      },
      onIncomingFilePermissionCheck: _handleIncomingFilePermission,
      onTransferTaskUpdated: _handleTransferTaskUpdated,
    );

    _initializeApp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _discoveryService.checkNetworkChange();
    }
  }

  Future<void> _initializeApp() async {
    await _loadSavedSettingsAndData();

    _discoveryService.updateIdentity(
      newNodeId: localNodeId,
      newAlias: _localAlias,
    );
    _transferService.localNodeId = localNodeId;
    _transferService.localAlias = _localAlias;

    if (Platform.isAndroid) {
      try {
        await [
          Permission.nearbyWifiDevices,
          Permission.locationWhenInUse,
          Permission.notification,
          Permission.ignoreBatteryOptimizations,
        ].request();
      } catch (_) {}
    }

    await _notifService.initialize(
      onDecision: (transferId, accepted) {
        PendingRequestItem? match;
        for (final item in _pendingFileRequests) {
          if (item.request.transferId == transferId) {
            match = item;
            break;
          }
        }
        if (match != null) {
          respondToFileRequest(match, accept: accepted);
        }
      },
      onStopApp: () async {
        _transferService.cancelActiveTransfer();
        await _transferService.stopServer();
        await _discoveryService.stopDiscovery();
        await _notifService.stopAndroidForegroundServiceAndExit();
      },
    );
    
    await _initializeNetworking();
  }

  Future<void> _loadSavedSettingsAndData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final String? savedNodeId = prefs.getString('local_node_id');
      if (savedNodeId != null && savedNodeId.isNotEmpty) {
        localNodeId = savedNodeId;
      } else {
        await prefs.setString('local_node_id', localNodeId);
        if (!Platform.isWindows && !prefs.containsKey('local_alias')) {
          _localAlias = 'Android-$localNodeId';
        }
      }

      final String? savedAlias = prefs.getString('local_alias');
      if (savedAlias != null && savedAlias.isNotEmpty) {
        _localAlias = savedAlias;
      }

      _isDarkMode = prefs.getBool('dark_mode') ?? true;
      _useAmoledBlack = prefs.getBool('amoled_black') ?? false;
      _sfxEnabled = prefs.getBool('sfx_enabled') ?? true;

      final String? presetName = prefs.getString('theme_preset');
      if (presetName != null) {
        _themePreset = AppThemePreset.values.firstWhere(
          (e) => e.name == presetName,
          orElse: () => AppThemePreset.cyberPulse,
        );
      }

      final String? contactsJson =
          prefs.getString('saved_known_peers_v3') ??
              prefs.getString('saved_contacts_v2');
      if (contactsJson != null && contactsJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(contactsJson) as List<dynamic>;
        for (final item in decoded) {
          final PeerNode peer =
              PeerNode.fromStorageMap(item as Map<String, dynamic>);
          if (peer.nodeId.isNotEmpty) {
            _knownPeers[peer.nodeId] = peer;
          }
        }
      }

      final String? messagesJson =
          prefs.getString('saved_messages_v3') ??
              prefs.getString('saved_messages_v2');
      if (messagesJson != null && messagesJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(messagesJson) as List<dynamic>;
        _messages.clear();
        for (final item in decoded) {
          _messages.add(
            P2PChatMessage.fromMap(item as Map<String, dynamic>),
          );
        }
      }

      final String? historyJson = prefs.getString('file_history_v2');
      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(historyJson) as List<dynamic>;
        _fileHistory.clear();
        for (final item in decoded) {
          _fileHistory.add(
            FileHistoryEntry.fromMap(item as Map<String, dynamic>),
          );
        }
      }

      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistContactsAndMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> peersList =
          _knownPeers.values.map((c) => c.toStorageMap()).toList();
      await prefs.setString('saved_known_peers_v3', jsonEncode(peersList));

      final List<Map<String, dynamic>> allMessages =
          _messages.map((m) => m.toMap()).toList();
      await prefs.setString('saved_messages_v3', jsonEncode(allMessages));
    } catch (_) {}
  }

  Future<void> _persistFileHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> list =
          _fileHistory.map((h) => h.toMap()).toList();
      await prefs.setString('file_history_v2', jsonEncode(list));
    } catch (_) {}
  }

  PeerNode _unifyAndRememberPeer(PeerNode incomingPeer, {bool? forceTrusted}) {
    String? oldDuplicateId;
    for (final entry in _knownPeers.entries) {
      if (entry.key != incomingPeer.nodeId &&
          (entry.value.ipAddress == incomingPeer.ipAddress ||
              (entry.value.alias.toLowerCase() ==
                      incomingPeer.alias.toLowerCase() &&
                  entry.value.platform == incomingPeer.platform))) {
        oldDuplicateId = entry.key;
        break;
      }
    }

    bool wasTrusted = _knownPeers[incomingPeer.nodeId]?.isTrusted ?? false;
    if (oldDuplicateId != null) {
      wasTrusted =
          wasTrusted || (_knownPeers[oldDuplicateId]?.isTrusted ?? false);
      _knownPeers.remove(oldDuplicateId);
      for (int i = 0; i < _messages.length; i++) {
        if (_messages[i].peerId == oldDuplicateId) {
          _messages[i] = _messages[i].copyWith(
            peerId: incomingPeer.nodeId,
            peerAlias: incomingPeer.alias,
          );
        }
      }
    }

    final PeerNode unified = incomingPeer.copyWith(
      isTrusted: forceTrusted ?? wasTrusted,
      lastSeen: DateTime.now(),
    );
    _knownPeers[unified.nodeId] = unified;
    return unified;
  }

  bool isPeerTrusted(String nodeId, [String? ipAddress]) {
    if (_knownPeers[nodeId]?.isTrusted == true) return true;
    if (ipAddress != null && ipAddress.isNotEmpty) {
      return _knownPeers.values
          .any((c) => c.isTrusted && c.ipAddress == ipAddress);
    }
    return false;
  }

  Future<void> toggleSaveContact(PeerNode peer, {String? customAlias}) async {
    final bool currentlyTrusted = _knownPeers[peer.nodeId]?.isTrusted ?? false;
    final PeerNode updated = peer.copyWith(
      alias: (customAlias != null && customAlias.trim().isNotEmpty)
          ? customAlias.trim()
          : peer.alias,
      isTrusted: !currentlyTrusted,
    );
    _knownPeers[peer.nodeId] = updated;

    if (_selectedPeer?.nodeId == peer.nodeId) {
      _selectedPeer = updated.copyWith(isOnline: peer.isOnline);
    }
    _setBanner(
      updated.isTrusted
          ? '${updated.alias} aggiunto ai Contatti Fidati.'
          : '${updated.alias} rimosso dai Contatti Fidati.',
    );
    await _persistContactsAndMessages();
    notifyListeners();
  }

  Future<void> deleteChat(
    String peerId, {
    bool alsoRemoveTrusted = false,
  }) async {
    _messages.removeWhere((m) => m.peerId == peerId);
    _unreadCounts.remove(peerId);

    if (alsoRemoveTrusted || (_knownPeers[peerId]?.isTrusted == false)) {
      _knownPeers.remove(peerId);
    }

    if (_selectedPeer?.nodeId == peerId) {
      _selectedPeer = null;
    }

    await _persistContactsAndMessages();
    _setBanner('Chat eliminata.');
    notifyListeners();
  }

  String _formatBytesCompact(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<bool> _handleIncomingFilePermission(
    IncomingFileRequest request,
  ) async {
    if (isPeerTrusted(request.senderId, request.senderIp)) {
      return true;
    }

    if (_sfxEnabled) {
      unawaited(_soundService.playIncomingRequestSfx());
    }

    unawaited(
      _notifService.showIncomingFileRequestNotification(
        transferId: request.transferId,
        senderAlias: request.senderAlias,
        fileName: request.fileName,
        formattedSize: _formatBytesCompact(request.fileSizeBytes),
      ),
    );

    final Completer<bool> completer = Completer<bool>();
    final PendingRequestItem item = PendingRequestItem(
      request: request,
      completer: completer,
    );
    _pendingFileRequests.add(item);
    notifyListeners();

    try {
      return await completer.future.timeout(
        const Duration(seconds: 85),
        onTimeout: () => false,
      );
    } finally {
      _pendingFileRequests.remove(item);
      unawaited(_notifService.cancelRequestNotification(request.transferId));
      notifyListeners();
    }
  }

  Future<void> respondToFileRequest(
    PendingRequestItem item, {
    required bool accept,
    bool trustSender = false,
  }) async {
    unawaited(_notifService.cancelRequestNotification(item.request.transferId));

    if (accept) {
      final PeerNode senderNode = PeerNode(
        nodeId: item.request.senderId,
        alias: item.request.senderAlias,
        ipAddress: item.request.senderIp,
        tcpPort: NetworkConstants.tcpTransferPort,
        platform: PeerPlatform.unknown,
        lastSeen: DateTime.now(),
        isTrusted: trustSender ||
            isPeerTrusted(item.request.senderId, item.request.senderIp),
        isOnline: true,
      );
      _unifyAndRememberPeer(
        senderNode,
        forceTrusted: trustSender ? true : null,
      );
      await _persistContactsAndMessages();
    }

    if (!item.completer.isCompleted) {
      item.completer.complete(accept);
    }
    _pendingFileRequests.remove(item);
    notifyListeners();
  }

  void _handleTransferTaskUpdated(ActiveTransferTask? task) {
    final ActiveTransferTask? previous = _activeTransferTask;
    _activeTransferTask = task;

    if (task != null) {
      final int pct = (task.progress * 100).round();
      if (pct != _lastNotifiedProgressPct ||
          task.state != previous?.state) {
        _lastNotifiedProgressPct = pct;
        unawaited(
          _notifService.showTransferProgressNotification(
            fileName: task.fileName,
            peerAlias: task.peerAlias,
            isOutgoing: task.isOutgoing,
            progressPercent: pct,
            isPaused: task.state == TransferTaskState.paused,
          ),
        );
      }
    } else if (previous != null) {
      _lastNotifiedProgressPct = -1;
    }

    notifyListeners();
  }

  void pauseTransfer() => _transferService.pauseActiveTransfer();
  void resumeTransfer() => _transferService.resumeActiveTransfer();
  void cancelTransfer() => _transferService.cancelActiveTransfer();

  Future<void> _initializeNetworking() async {
    _discoveryService.networkChangeStream.listen((newIp) async {
      if (newIp == null) {
        _setBanner(
          'Rete Wi-Fi disconnessa. Le chat salvate restano disponibili.',
          isError: true,
        );
      } else {
        await _transferService.startServer();
      }
      notifyListeners();
    });

    _discoveryService.peersStream.listen((updatedPeers) {
      _onlinePeers = updatedPeers;

      bool knownUpdated = false;
      for (final online in _onlinePeers) {
        if (_knownPeers.containsKey(online.nodeId)) {
          _unifyAndRememberPeer(online);
          knownUpdated = true;
        } else {
          final bool matchesExisting = _knownPeers.values.any(
            (k) =>
                k.ipAddress == online.ipAddress ||
                (k.alias.toLowerCase() == online.alias.toLowerCase() &&
                    k.platform == online.platform),
          );
          if (matchesExisting) {
            _unifyAndRememberPeer(online);
            knownUpdated = true;
          }
        }
      }
      if (knownUpdated) {
        unawaited(_persistContactsAndMessages());
      }

      if (_selectedPeer != null) {
        final PeerNode? refreshed = peers.cast<PeerNode?>().firstWhere(
              (p) =>
                  p?.nodeId == _selectedPeer!.nodeId ||
                  p?.ipAddress == _selectedPeer!.ipAddress,
              orElse: () => null,
            );
        if (refreshed != null) {
          _selectedPeer = refreshed;
        } else {
          _selectedPeer = _selectedPeer!.copyWith(isOnline: false);
        }
      }
      notifyListeners();
    });

    _transferService.discoveredPeerStream.listen((peer) {
      final PeerNode verified =
          _discoveryService.registerVerifiedPeer(peer, pin: true);
      final PeerNode unified = _unifyAndRememberPeer(verified);
      unawaited(_persistContactsAndMessages());

      if (_selectedPeer != null &&
          (_selectedPeer!.ipAddress == unified.ipAddress ||
              _selectedPeer!.nodeId == unified.nodeId)) {
        _selectedPeer = unified.copyWith(isOnline: true);
      }
      notifyListeners();
    });

    _transferService.incomingMessages.listen((msg) {
      final PeerNode? existingPeer = peers.cast<PeerNode?>().firstWhere(
            (p) => p?.nodeId == msg.peerId,
            orElse: () => null,
          );
      if (existingPeer != null) {
        _unifyAndRememberPeer(existingPeer);
      } else {
        _knownPeers[msg.peerId] = PeerNode(
          nodeId: msg.peerId,
          alias: msg.peerAlias,
          ipAddress: '',
          tcpPort: NetworkConstants.tcpTransferPort,
          platform: PeerPlatform.unknown,
          lastSeen: DateTime.now(),
          isTrusted: false,
          isOnline: true,
        );
      }

      _messages.add(msg);

      if (_selectedPeer == null || _selectedPeer!.nodeId != msg.peerId) {
        _unreadCounts[msg.peerId] = (_unreadCounts[msg.peerId] ?? 0) + 1;
      }

      if (msg.type == TransferPayloadType.binaryFile) {
        _fileHistory.insert(
          0,
          FileHistoryEntry(
            id: msg.id,
            fileName: msg.content,
            filePath: msg.filePath,
            fileSizeBytes: msg.fileSize ?? 0,
            peerId: msg.peerId,
            peerAlias: msg.peerAlias,
            peerIp: existingPeer?.ipAddress ?? '',
            isOutgoing: false,
            timestamp: msg.timestamp,
          ),
        );
        unawaited(_persistFileHistory());
        unawaited(
          _notifService.showTransferCompletedNotification(
            fileName: msg.content,
            peerAlias: msg.peerAlias,
            isOutgoing: false,
            success: true,
          ),
        );
      }

      unawaited(_persistContactsAndMessages());
      notifyListeners();
    });

    await _startServers();
  }

  Future<void> _startServers() async {
    try {
      await _transferService.startServer();
      await _discoveryService.startDiscovery();
      notifyListeners();
    } catch (e) {
      _setBanner('Errore avvio socket di rete: $e', isError: true);
    }
  }

  void _setBanner(String? message, {bool isError = false}) {
    _statusBanner = message;
    _isBannerError = isError;
    notifyListeners();
  }

  void clearError() {
    _statusBanner = null;
    notifyListeners();
  }

  Future<void> refreshNetwork() async {
    _isScanningWifi = true;
    notifyListeners();

    await _discoveryService.startDiscovery();
    await _discoveryService.scanWifiSubnet();

    _isScanningWifi = false;
    notifyListeners();
  }

  void selectPeer(PeerNode? peer) {
    _selectedPeer = peer;
    if (peer != null) {
      _unreadCounts.remove(peer.nodeId);
    }
    _statusBanner = null;
    notifyListeners();
  }

  void cycleActiveChat(int delta) {
    final List<PeerNode> chats = activeChatPeers;
    if (chats.isEmpty) return;
    if (_selectedPeer == null) {
      selectPeer(chats.first);
      return;
    }
    final int currentIndex =
        chats.indexWhere((c) => c.nodeId == _selectedPeer!.nodeId);
    if (currentIndex == -1) {
      selectPeer(chats.first);
      return;
    }
    final int nextIndex = (currentIndex + delta) % chats.length;
    selectPeer(chats[nextIndex < 0 ? chats.length - 1 : nextIndex]);
  }

  Future<void> clearFileHistory() async {
    _fileHistory.clear();
    await _persistFileHistory();
    notifyListeners();
  }

  Future<bool> connectByIp({
    required String ipAddress,
    String? customAlias,
    int port = NetworkConstants.tcpTransferPort,
    bool saveAsTrusted = false,
  }) async {
    String cleanIp = ipAddress.trim();
    int resolvedPort = port;

    if (cleanIp.contains(':')) {
      final parts = cleanIp.split(':');
      cleanIp = parts[0].trim();
      resolvedPort = int.tryParse(parts[1].trim()) ?? port;
    }

    if (cleanIp.isEmpty) return false;

    final PeerNode? verifiedPeer = await _transferService.performHandshake(
      targetIp: cleanIp,
      targetPort: resolvedPort,
    );

    if (verifiedPeer != null) {
      final PeerNode finalPeer = _unifyAndRememberPeer(
        (customAlias != null && customAlias.trim().isNotEmpty)
            ? verifiedPeer.copyWith(alias: customAlias.trim())
            : verifiedPeer,
        forceTrusted: saveAsTrusted ? true : null,
      );
      _discoveryService.registerVerifiedPeer(finalPeer, pin: true);
      await _persistContactsAndMessages();
      selectPeer(finalPeer.copyWith(isOnline: true));
      return true;
    } else {
      final PeerNode fallbackNode = _unifyAndRememberPeer(
        PeerNode(
          nodeId: 'manual-$cleanIp:$resolvedPort',
          alias: (customAlias != null && customAlias.trim().isNotEmpty)
              ? customAlias.trim()
              : 'Host ($cleanIp)',
          ipAddress: cleanIp,
          tcpPort: resolvedPort,
          platform: PeerPlatform.unknown,
          lastSeen: DateTime.now(),
          isTrusted: saveAsTrusted,
          isOnline: true,
        ),
        forceTrusted: saveAsTrusted ? true : null,
      );
      _discoveryService.registerVerifiedPeer(fallbackNode, pin: true);
      await _persistContactsAndMessages();
      selectPeer(fallbackNode);
      _discoveryService.sendReverseConnectRequest(cleanIp);
      return true;
    }
  }

  Future<void> updateLocalAlias(String newAlias) async {
    if (newAlias.trim().isEmpty) return;
    _localAlias = newAlias.trim();
    _discoveryService.updateAlias(_localAlias);
    _transferService.localAlias = _localAlias;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_alias', _localAlias);
    notifyListeners();
  }

  Future<void> toggleDarkMode(bool value) async {
    _isDarkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
    notifyListeners();
  }

  Future<void> toggleAmoledBlack(bool value) async {
    _useAmoledBlack = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('amoled_black', value);
    notifyListeners();
  }

  Future<void> setThemePreset(AppThemePreset preset) async {
    _themePreset = preset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_preset', preset.name);
    notifyListeners();
  }

  Future<void> toggleSfx(bool value) async {
    _sfxEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sfx_enabled', value);
    if (value) {
      unawaited(_soundService.playIncomingRequestSfx());
    }
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
      _unifyAndRememberPeer(target);
      _messages.add(sent);
      _statusBanner = null;
      await _persistContactsAndMessages();
      notifyListeners();
    } catch (e) {
      _setBanner(
        'Host ${target.alias} non raggiungibile.',
        isError: true,
      );
    }
  }

  Future<void> sendDroppedFiles(List<String> filePaths) async {
    final PeerNode? target = _selectedPeer;
    if (target == null || filePaths.isEmpty) return;

    for (final path in filePaths) {
      final File file = File(path);
      if (!file.existsSync()) continue;
      if (FileSystemEntity.isDirectorySync(path)) continue;

      final String fileName = path.split(Platform.pathSeparator).last;
      final int totalBytes = await file.length();
      await _executeFileTransfer(
        target: target,
        fileName: fileName,
        totalBytes: totalBytes,
        localFilePath: path,
      );
    }
  }

  Future<void> pickAndSendFile({PeerNode? targetOverride}) async {
    if (isTransferring) return;
    final PeerNode? target = targetOverride ?? _selectedPeer;
    if (target == null) return;

    selectPeer(target);

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
        withReadStream: true,
      );
    } catch (e) {
      _setBanner('Impossibile aprire il selettore file: $e', isError: true);
      return;
    }

    if (result == null || result.files.isEmpty) return;
    final PlatformFile picked = result.files.single;

    final String fileName = picked.name;
    final int totalBytes =
        picked.path != null && File(picked.path!).existsSync()
            ? await File(picked.path!).length()
            : picked.size;

    await _executeFileTransfer(
      target: target,
      fileName: fileName,
      totalBytes: totalBytes,
      localFilePath: picked.path,
      fallbackStream: picked.readStream,
    );
  }

  Future<void> _executeFileTransfer({
    required PeerNode target,
    required String fileName,
    required int totalBytes,
    String? localFilePath,
    Stream<List<int>>? fallbackStream,
  }) async {
    _statusBanner = null;
    notifyListeners();

    try {
      final P2PChatMessage sentFileMsg =
          await _transferService.sendFileFragmented(
        targetPeer: target,
        fileName: fileName,
        totalBytes: totalBytes,
        localFilePath: localFilePath,
        fallbackStream: fallbackStream,
      );

      _unifyAndRememberPeer(target);
      _messages.add(sentFileMsg);
      _fileHistory.insert(
        0,
        FileHistoryEntry(
          id: sentFileMsg.id,
          fileName: fileName,
          filePath: localFilePath,
          fileSizeBytes: totalBytes,
          peerId: target.nodeId,
          peerAlias: target.alias,
          peerIp: target.ipAddress,
          isOutgoing: true,
          timestamp: sentFileMsg.timestamp,
        ),
      );

      await _persistFileHistory();
      await _persistContactsAndMessages();
      unawaited(
        _notifService.showTransferCompletedNotification(
          fileName: fileName,
          peerAlias: target.alias,
          isOutgoing: true,
          success: true,
        ),
      );
    } catch (e) {
      unawaited(
        _notifService.showTransferCompletedNotification(
          fileName: fileName,
          peerAlias: target.alias,
          isOutgoing: true,
          success: false,
        ),
      );
      _setBanner('Trasferimento interrotto: $e', isError: true);
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _soundService.dispose();
    _discoveryService.dispose();
    _transferService.dispose();
    super.dispose();
  }
}
