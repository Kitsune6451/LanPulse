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

enum AppUiStyle {
  modernGlass('Soft Rounded', 16.0),
  compactSharp('Tech Sharp', 8.0),
  minimalistFlat('Ultra Pill', 22.0);

  final String label;
  final double borderRadius;
  const AppUiStyle(this.label, this.borderRadius);
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
  late String localNodeId;
  late String _localAlias;
  late final DiscoveryService _discoveryService;
  late final SocketTransferService _transferService;
  final SoundService _soundService = SoundService();

  List<PeerNode> _onlinePeers = [];
  final Map<String, PeerNode> _savedContacts = {};
  PeerNode? _selectedPeer;

  final List<P2PChatMessage> _messages = [];
  final List<FileHistoryEntry> _fileHistory = [];
  final Map<String, int> _unreadCounts = {};
  final List<PendingRequestItem> _pendingFileRequests = [];

  double _activeTransferProgress = 0.0;
  bool _isTransferring = false;
  bool _isScanningWifi = false;
  String? _statusBanner;
  bool _isBannerError = false;

  bool _isDarkMode = true;
  bool _useAmoledBlack = false;
  AppThemePreset _themePreset = AppThemePreset.cyberPulse;
  AppUiStyle _uiStyle = AppUiStyle.modernGlass;
  bool _sfxEnabled = true;

  PeerNode? get selectedPeer => _selectedPeer;
  String get localAlias => _localAlias;
  String? get localIp => _discoveryService.localIp;
  List<String> get allLocalIps => _discoveryService.allLocalIps;
  int get tcpPort => NetworkConstants.tcpTransferPort;
  bool get isTransferring => _isTransferring;
  bool get isScanningWifi => _isScanningWifi;
  double get activeTransferProgress => _activeTransferProgress;
  String? get errorBanner => _statusBanner;
  bool get isBannerError => _isBannerError;

  bool get isDarkMode => _isDarkMode;
  bool get useAmoledBlack => _useAmoledBlack;
  AppThemePreset get themePreset => _themePreset;
  AppUiStyle get uiStyle => _uiStyle;
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

    for (final saved in _savedContacts.values) {
      merged[saved.nodeId] = saved.copyWith(isTrusted: true, isOnline: false);
    }

    for (final online in _onlinePeers) {
      PeerNode? matchedContact = _savedContacts[online.nodeId];
      if (matchedContact == null) {
        for (final c in _savedContacts.values) {
          if (c.ipAddress == online.ipAddress) {
            matchedContact = c;
            break;
          }
        }
      }

      final bool trusted = matchedContact != null;
      merged[online.nodeId] = online.copyWith(
        alias: matchedContact?.alias ?? online.alias,
        isTrusted: trusted,
        isOnline: true,
      );
    }

    final List<PeerNode> result = merged.values.toList()
      ..sort((a, b) {
        if (a.isTrusted != b.isTrusted) return a.isTrusted ? -1 : 1;
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
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

    if (Platform.isAndroid) {
      try {
        await [
          Permission.nearbyWifiDevices,
          Permission.locationWhenInUse,
        ].request();
      } catch (_) {}
    }

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
      }

      final String? savedAlias = prefs.getString('local_alias');
      if (savedAlias != null && savedAlias.isNotEmpty) {
        _localAlias = savedAlias;
        _discoveryService.updateAlias(_localAlias);
        _transferService.localAlias = _localAlias;
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

      final String? styleName = prefs.getString('ui_style');
      if (styleName != null) {
        _uiStyle = AppUiStyle.values.firstWhere(
          (e) => e.name == styleName,
          orElse: () => AppUiStyle.modernGlass,
        );
      }

      final String? contactsJson = prefs.getString('saved_contacts_v2');
      if (contactsJson != null && contactsJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(contactsJson) as List<dynamic>;
        for (final item in decoded) {
          final PeerNode contact =
              PeerNode.fromStorageMap(item as Map<String, dynamic>);
          if (contact.nodeId.isNotEmpty) {
            _savedContacts[contact.nodeId] = contact;
          }
        }
      }

      final String? messagesJson = prefs.getString('saved_messages_v2');
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
      final List<Map<String, dynamic>> contactsList =
          _savedContacts.values.map((c) => c.toStorageMap()).toList();
      await prefs.setString('saved_contacts_v2', jsonEncode(contactsList));

      final Set<String> trustedIds = _savedContacts.keys.toSet();
      final List<Map<String, dynamic>> persistentMessages = _messages
          .where((m) => trustedIds.contains(m.peerId))
          .map((m) => m.toMap())
          .toList();
      await prefs.setString(
        'saved_messages_v2',
        jsonEncode(persistentMessages),
      );
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

  bool isPeerTrusted(String nodeId, [String? ipAddress]) {
    if (_savedContacts.containsKey(nodeId)) return true;
    if (ipAddress != null && ipAddress.isNotEmpty) {
      return _savedContacts.values.any((c) => c.ipAddress == ipAddress);
    }
    return false;
  }

  Future<void> toggleSaveContact(PeerNode peer, {String? customAlias}) async {
    if (_savedContacts.containsKey(peer.nodeId)) {
      _savedContacts.remove(peer.nodeId);
      if (_selectedPeer?.nodeId == peer.nodeId) {
        _selectedPeer = _selectedPeer!.copyWith(isTrusted: false);
      }
      _setBanner('${peer.alias} rimosso dai Contatti Fidati.');
    } else {
      final PeerNode saved = peer.copyWith(
        alias: (customAlias != null && customAlias.trim().isNotEmpty)
            ? customAlias.trim()
            : peer.alias,
        isTrusted: true,
      );
      _savedContacts[peer.nodeId] = saved;
      if (_selectedPeer?.nodeId == peer.nodeId) {
        _selectedPeer = saved.copyWith(isOnline: peer.isOnline);
      }
      _setBanner('${saved.alias} salvato nei Contatti Fidati.');
    }
    await _persistContactsAndMessages();
    notifyListeners();
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
      notifyListeners();
    }
  }

  Future<void> respondToFileRequest(
    PendingRequestItem item, {
    required bool accept,
    bool trustSender = false,
  }) async {
    if (trustSender && accept) {
      final PeerNode newTrusted = PeerNode(
        nodeId: item.request.senderId,
        alias: item.request.senderAlias,
        ipAddress: item.request.senderIp,
        tcpPort: NetworkConstants.tcpTransferPort,
        platform: PeerPlatform.unknown,
        lastSeen: DateTime.now(),
        isTrusted: true,
        isOnline: true,
      );
      _savedContacts[newTrusted.nodeId] = newTrusted;
      await _persistContactsAndMessages();
    }

    if (!item.completer.isCompleted) {
      item.completer.complete(accept);
    }
    _pendingFileRequests.remove(item);
    notifyListeners();
  }

  Future<void> _initializeNetworking() async {
    _discoveryService.networkChangeStream.listen((newIp) async {
      _isTransferring = false;
      _activeTransferProgress = 0.0;

      if (newIp == null) {
        _setBanner(
          'Rete Wi-Fi disconnessa. Le chat salvate restano consultabili.',
          isError: true,
        );
      } else {
        await _transferService.startServer(
          onIncomingProgress: _handleTransferProgress,
        );
      }
      notifyListeners();
    });

    _discoveryService.peersStream.listen((updatedPeers) {
      _onlinePeers = updatedPeers;

      bool contactsUpdated = false;
      for (final online in _onlinePeers) {
        if (_savedContacts.containsKey(online.nodeId)) {
          final PeerNode existing = _savedContacts[online.nodeId]!;
          if (existing.ipAddress != online.ipAddress) {
            _savedContacts[online.nodeId] = existing.copyWith(
              ipAddress: online.ipAddress,
              lastSeen: DateTime.now(),
            );
            contactsUpdated = true;
          }
        }
      }
      if (contactsUpdated) {
        unawaited(_persistContactsAndMessages());
      }

      if (_selectedPeer != null) {
        final PeerNode? refreshed = peers.cast<PeerNode?>().firstWhere(
              (p) => p?.nodeId == _selectedPeer!.nodeId,
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
      for (int i = 0; i < _messages.length; i++) {
        if (_messages[i].peerId == 'manual-${peer.ipAddress}:${peer.tcpPort}') {
          _messages[i] = _messages[i].copyWith(
            peerId: peer.nodeId,
            peerAlias: peer.alias,
          );
        }
      }

      final PeerNode verified =
          _discoveryService.registerVerifiedPeer(peer, pin: true);
      final bool trusted = isPeerTrusted(verified.nodeId, verified.ipAddress);
      if (trusted && !_savedContacts.containsKey(verified.nodeId)) {
        _savedContacts[verified.nodeId] = verified.copyWith(isTrusted: true);
        unawaited(_persistContactsAndMessages());
      }

      if (_selectedPeer != null &&
          _selectedPeer!.ipAddress == verified.ipAddress) {
        _selectedPeer = verified.copyWith(isTrusted: trusted, isOnline: true);
      }
      notifyListeners();
    });

    _transferService.incomingMessages.listen((msg) {
      _messages.add(msg);
      _isTransferring = false;
      _activeTransferProgress = 0.0;

      if (_selectedPeer == null || _selectedPeer!.nodeId != msg.peerId) {
        _unreadCounts[msg.peerId] = (_unreadCounts[msg.peerId] ?? 0) + 1;
      }

      if (msg.type == TransferPayloadType.binaryFile) {
        final PeerNode? senderNode = peers.cast<PeerNode?>().firstWhere(
              (p) => p?.nodeId == msg.peerId,
              orElse: () => null,
            );
        _fileHistory.insert(
          0,
          FileHistoryEntry(
            id: msg.id,
            fileName: msg.content,
            filePath: msg.filePath,
            fileSizeBytes: msg.fileSize ?? 0,
            peerId: msg.peerId,
            peerAlias: msg.peerAlias,
            peerIp: senderNode?.ipAddress ?? '',
            isOutgoing: false,
            timestamp: msg.timestamp,
          ),
        );
        unawaited(_persistFileHistory());
      }

      unawaited(_persistContactsAndMessages());
      notifyListeners();
    });

    await _startServers();
  }

  void _handleTransferProgress(String _, int transferred, int total) {
    _isTransferring = true;
    _activeTransferProgress = total > 0 ? transferred / total : 0.0;
    notifyListeners();
  }

  Future<void> _startServers() async {
    try {
      await _transferService.startServer(
        onIncomingProgress: _handleTransferProgress,
      );
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
      final PeerNode finalPeer =
          (customAlias != null && customAlias.trim().isNotEmpty)
              ? verifiedPeer.copyWith(
                  alias: customAlias.trim(),
                  isTrusted: saveAsTrusted ||
                      isPeerTrusted(verifiedPeer.nodeId, cleanIp),
                )
              : verifiedPeer.copyWith(
                  isTrusted: saveAsTrusted ||
                      isPeerTrusted(verifiedPeer.nodeId, cleanIp),
                );
      _discoveryService.registerVerifiedPeer(finalPeer, pin: true);
      if (finalPeer.isTrusted) {
        _savedContacts[finalPeer.nodeId] = finalPeer;
        await _persistContactsAndMessages();
      }
      selectPeer(finalPeer);
      return true;
    } else {
      final PeerNode fallbackNode = PeerNode(
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
      );
      _discoveryService.registerVerifiedPeer(fallbackNode, pin: true);
      if (saveAsTrusted) {
        _savedContacts[fallbackNode.nodeId] = fallbackNode;
        await _persistContactsAndMessages();
      }
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

  Future<void> setUiStyle(AppUiStyle style) async {
    _uiStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ui_style', style.name);
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
      _messages.add(sent);
      _statusBanner = null;
      await _persistContactsAndMessages();
      notifyListeners();
    } catch (e) {
      _setBanner(
        'Host ${target.alias} non raggiungibile sulla rete locale.',
        isError: true,
      );
    }
  }

  Future<void> pickAndSendFile({PeerNode? targetOverride}) async {
    if (_isTransferring) return;
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

    _isTransferring = true;
    _activeTransferProgress = 0.0;
    _statusBanner = !target.isTrusted
        ? 'In attesa che ${target.alias} accetti il trasferimento...'
        : null;
    _isBannerError = false;
    notifyListeners();

    try {
      final P2PChatMessage sentFileMsg =
          await _transferService.sendFileFragmented(
        targetPeer: target,
        fileName: fileName,
        totalBytes: totalBytes,
        localFilePath: picked.path,
        fallbackStream: picked.readStream,
        onProgress: (_, sent, total) {
          _activeTransferProgress = total > 0 ? sent / total : 0.0;
          notifyListeners();
        },
      );

      _messages.add(sentFileMsg);
      _fileHistory.insert(
        0,
        FileHistoryEntry(
          id: sentFileMsg.id,
          fileName: fileName,
          filePath: picked.path,
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
      _statusBanner = null;
    } catch (e) {
      _setBanner('Trasferimento annullato o fallito: $e', isError: true);
    } finally {
      _isTransferring = false;
      _activeTransferProgress = 0.0;
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
