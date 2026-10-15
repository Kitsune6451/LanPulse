import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  cyberPulse('Cyber Pulse (Ciano)', Color(0xFF0284C7), Color(0xFF38BDF8)),
  emeraldMatrix('Emerald Matrix (Verde)', Color(0xFF059669), Color(0xFF34D399)),
  royalAmethyst('Royal Amethyst (Viola)', Color(0xFF7C3AED), Color(0xFFA78BFA)),
  sunsetCrimson('Sunset Crimson (Rosso)', Color(0xFFE11D48), Color(0xFFFB7185)),
  nordicFrost('Nordic Frost (Ghiaccio)', Color(0xFF0369A1), Color(0xFF7DD3FC)),
  amberGold('Amber Gold (Ambra)', Color(0xFFD97706), Color(0xFFFBBF24));

  final String label;
  final Color lightSeed;
  final Color darkSeed;
  const AppThemePreset(this.label, this.lightSeed, this.darkSeed);
}

enum AppUiStyle {
  modernGlass('Modern Glass (Morbido)', 18.0),
  compactSharp('Compact Sharp (Tecnico)', 6.0),
  minimalistFlat('Minimalist Flat (Piatto)', 12.0);

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

  // Temi e Stili
  bool _isDarkMode = true;
  bool _useAmoledBlack = false;
  AppThemePreset _themePreset = AppThemePreset.cyberPulse;
  AppUiStyle _uiStyle = AppUiStyle.modernGlass;
  bool _sfxEnabled = true;

  // Google OAuth 2.0 Desktop & Mobile
  String? _googleDisplayName;
  String? _googleEmail;
  String? _googlePhotoUrl;
  bool _isAuthenticatingGoogle = false;
  HttpServer? _localAuthServer;
  String _googleDesktopClientId = const String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
    defaultValue: '',
  );
  String _googleDesktopClientSecret = const String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
    defaultValue: '',
  );

  // Getters
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

  bool get isGoogleSignedIn => _googleEmail != null;
  bool get isAuthenticatingGoogle => _isAuthenticatingGoogle;
  String? get googleDisplayName => _googleDisplayName;
  String? get googleEmail => _googleEmail;
  String? get googlePhotoUrl => _googlePhotoUrl;
  String get googleDesktopClientId => _googleDesktopClientId;
  String get googleDesktopClientSecret => _googleDesktopClientSecret;

  List<FileHistoryEntry> get fileHistory => List.unmodifiable(_fileHistory);
  List<FileHistoryEntry> get sentFileHistory =>
      _fileHistory.where((f) => f.isOutgoing).toList();
  List<FileHistoryEntry> get receivedFileHistory =>
      _fileHistory.where((f) => !f.isOutgoing).toList();

  List<PendingRequestItem> get pendingFileRequests =>
      List.unmodifiable(_pendingFileRequests);

  /// Unisce i nodi online sulla LAN e i contatti salvati (anche se offline)
  List<PeerNode> get peers {
    final Map<String, PeerNode> merged = {};

    for (final saved in _savedContacts.values) {
      merged[saved.nodeId] = saved.copyWith(isTrusted: true, isOnline: false);
    }

    for (final online in _onlinePeers) {
      // Verifica se il nodo online corrisponde a un contatto salvato per ID o per IP
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

  /// Restituisce tutte le chat attive o permanenti per poter scorrere tra le diverse conversazioni
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

    // Aggiungi eventuali peer con cui abbiamo messaggi ma che si sono disconnessi e non sono salvati
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
      final DateTime aTime = lastMessageForPeer(a.nodeId)?.timestamp ?? a.lastSeen;
      final DateTime bTime = lastMessageForPeer(b.nodeId)?.timestamp ?? b.lastSeen;
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
        : 'S25-Ultra-$localNodeId';

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

      // Mantieni un localNodeId persistente così gli altri contatti ci riconoscono sempre
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

      _googleDisplayName = prefs.getString('google_name');
      _googleEmail = prefs.getString('google_email');
      _googlePhotoUrl = prefs.getString('google_photo');
      _googleDesktopClientId =
          prefs.getString('google_client_id') ?? _googleDesktopClientId;
      _googleDesktopClientSecret =
          prefs.getString('google_client_secret') ?? _googleDesktopClientSecret;

      // Carica i contatti salvati
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

      // Carica i messaggi permanenti dei contatti salvati
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

      // Carica la cronologia file inviati e ricevuti
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

      // Salva permanentemente i messaggi appartenenti ai contatti salvati
      final Set<String> trustedIds = _savedContacts.keys.toSet();
      final List<Map<String, dynamic>> persistentMessages = _messages
          .where((m) => trustedIds.contains(m.peerId))
          .map((m) => m.toMap())
          .toList();
      await prefs.setString('saved_messages_v2', jsonEncode(persistentMessages));
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

  /// Verifica se un nodo è salvato come contatto fidato (per nodeId o per IP)
  bool isPeerTrusted(String nodeId, [String? ipAddress]) {
    if (_savedContacts.containsKey(nodeId)) return true;
    if (ipAddress != null && ipAddress.isNotEmpty) {
      return _savedContacts.values.any((c) => c.ipAddress == ipAddress);
    }
    return false;
  }

  /// Salva o rimuove un Host dai Contatti Fidati e rende la sua chat permanente
  Future<void> toggleSaveContact(PeerNode peer, {String? customAlias}) async {
    if (_savedContacts.containsKey(peer.nodeId)) {
      _savedContacts.remove(peer.nodeId);
      if (_selectedPeer?.nodeId == peer.nodeId) {
        _selectedPeer = _selectedPeer!.copyWith(isTrusted: false);
      }
      _setBanner('${peer.alias} rimosso dai contatti fidati.');
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
      _setBanner(
        '${saved.alias} salvato nei Contatti Fidati! Chat permanente e ricezione file diretta attive.',
      );
    }
    await _persistContactsAndMessages();
    notifyListeners();
  }

  /// Gestisce la richiesta di autorizzazione quando arriva un file:
  /// - Se l'host è un Contatto Fidato salvato -> Accetta automaticamente!
  /// - Altrimenti -> Riproduce l'SFX e mostra la richiesta mandatoria all'utente.
  Future<bool> _handleIncomingFilePermission(
    IncomingFileRequest request,
  ) async {
    if (isPeerTrusted(request.senderId, request.senderIp)) {
      return true; // Bypass automatico per gli host fidati salvati!
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

  /// Risponde a una richiesta di invio file in entrata (Accetta / Accetta e Salva / Rifiuta)
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
          'Disconnesso dalla rete Wi-Fi. Le chat dei contatti salvati restano consultabili.',
          isError: true,
        );
      } else {
        _setBanner(
          'Cambio rete rilevato! Nuovo IP Wi-Fi: $newIp',
          isError: false,
        );
        await _transferService.startServer(
          onIncomingProgress: _handleTransferProgress,
        );
      }
      notifyListeners();
    });

    _discoveryService.peersStream.listen((updatedPeers) {
      _onlinePeers = updatedPeers;

      // Sincronizza automaticamente l'IP dei contatti salvati quando tornano online
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
        final PeerNode? refreshed = peers
            .cast<PeerNode?>()
            .firstWhere((p) => p?.nodeId == _selectedPeer!.nodeId, orElse: () => null);
        if (refreshed != null) {
          _selectedPeer = refreshed;
        } else {
          // Non chiudere la chat! Segna solo il nodo come offline
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

      if (_selectedPeer == null ||
          _selectedPeer!.ipAddress == verified.ipAddress) {
        _selectedPeer = verified.copyWith(isTrusted: trusted, isOnline: true);
      }
      notifyListeners();
    });

    _transferService.incomingMessages.listen((msg) {
      _messages.add(msg);
      _isTransferring = false;
      _activeTransferProgress = 0.0;

      if (_selectedPeer == null) {
        final PeerNode? sender = peers
            .cast<PeerNode?>()
            .firstWhere((p) => p?.nodeId == msg.peerId, orElse: () => null);
        if (sender != null) {
          _selectedPeer = sender;
        }
      } else if (_selectedPeer!.nodeId != msg.peerId) {
        _unreadCounts[msg.peerId] = (_unreadCounts[msg.peerId] ?? 0) + 1;
      }

      if (msg.type == TransferPayloadType.binaryFile) {
        final PeerNode? senderNode = peers
            .cast<PeerNode?>()
            .firstWhere((p) => p?.nodeId == msg.peerId, orElse: () => null);
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
    _setBanner('Scansione della rete Wi-Fi e aggiornamento IP in corso...');
    notifyListeners();

    await _discoveryService.startDiscovery();
    await _discoveryService.scanWifiSubnet();

    _isScanningWifi = false;
    _statusBanner = null;
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

  /// Scorre rapidamente alla chat successiva o precedente nella lista delle chat
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

    _setBanner('Connessione a $cleanIp:$resolvedPort in corso...');

    final PeerNode? verifiedPeer = await _transferService.performHandshake(
      targetIp: cleanIp,
      targetPort: resolvedPort,
    );

    if (verifiedPeer != null) {
      final PeerNode finalPeer =
          (customAlias != null && customAlias.trim().isNotEmpty)
              ? verifiedPeer.copyWith(
                  alias: customAlias.trim(),
                  isTrusted:
                      saveAsTrusted || isPeerTrusted(verifiedPeer.nodeId, cleanIp),
                )
              : verifiedPeer.copyWith(
                  isTrusted:
                      saveAsTrusted || isPeerTrusted(verifiedPeer.nodeId, cleanIp),
                );
      _discoveryService.registerVerifiedPeer(finalPeer, pin: true);
      if (finalPeer.isTrusted) {
        _savedContacts[finalPeer.nodeId] = finalPeer;
        await _persistContactsAndMessages();
      }
      selectPeer(finalPeer);
      _setBanner('Connesso con successo a ${finalPeer.alias} ($cleanIp)!');
      return true;
    } else {
      final PeerNode fallbackNode = PeerNode(
        nodeId: 'manual-$cleanIp:$resolvedPort',
        alias: (customAlias != null && customAlias.trim().isNotEmpty)
            ? customAlias.trim()
            : 'Dispositivo Wi-Fi ($cleanIp)',
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
      _setBanner(
        'Nodo $cleanIp aggiunto. Richiesta di tunnel Wi-Fi inviata al dispositivo.',
      );
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

  Future<void> saveGoogleOAuthCredentials({
    required String clientId,
    required String clientSecret,
  }) async {
    _googleDesktopClientId = clientId.trim();
    _googleDesktopClientSecret = clientSecret.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('google_client_id', _googleDesktopClientId);
    await prefs.setString('google_client_secret', _googleDesktopClientSecret);
    notifyListeners();
  }

  /// VERO Login Google OAuth 2.0:
  /// - Su Android: usa GoogleSignIn nativo.
  /// - Su Windows Desktop: avvia il flusso OAuth 2.0 Authorization Code + PKCE (RFC 8252)
  ///   indirizzando il browser a `https://accounts.google.com/o/oauth2/v2/auth`,
  ///   scambiando il codice su `https://oauth2.googleapis.com/token` e leggendo il profilo
  ///   reale da `https://www.googleapis.com/oauth2/v3/userinfo`.
  Future<void> signInWithGoogle() async {
    if (_isAuthenticatingGoogle) return;
    _isAuthenticatingGoogle = true;
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        final GoogleSignIn googleSignIn =
            GoogleSignIn(scopes: ['openid', 'email', 'profile']);
        final GoogleSignInAccount? account = await googleSignIn.signIn();
        if (account != null) {
          await _saveGoogleProfile(
            name: account.displayName ?? account.email.split('@').first,
            email: account.email,
            photoUrl: account.photoUrl,
          );
        }
        return;
      }

      if (_googleDesktopClientId.isEmpty) {
        _setBanner(
          'Configura prima il tuo Google OAuth Desktop Client ID nelle Impostazioni per avviare il login Google.',
          isError: true,
        );
        return;
      }

      await _startRealGoogleDesktopOAuthPkce();
    } catch (e) {
      _setBanner('Errore durante l\'accesso Google OAuth 2.0: $e', isError: true);
    } finally {
      _isAuthenticatingGoogle = false;
      notifyListeners();
    }
  }

  String _generateCodeVerifier() {
    final math.Random random = math.Random.secure();
    final List<int> values = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  String _computeCodeChallenge(String verifier) {
    final List<int> bytes = ascii.encode(verifier);
    final Digest digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<void> _startRealGoogleDesktopOAuthPkce() async {
    await _localAuthServer?.close(force: true);
    _localAuthServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final int port = _localAuthServer!.port;
    final String redirectUri = 'http://127.0.0.1:$port/callback';

    final String codeVerifier = _generateCodeVerifier();
    final String codeChallenge = _computeCodeChallenge(codeVerifier);
    final String stateToken = const Uuid().v4();

    final Uri googleAuthUri = Uri.https(
      'accounts.google.com',
      '/o/oauth2/v2/auth',
      {
        'client_id': _googleDesktopClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': stateToken,
        'access_type': 'offline',
        'prompt': 'select_account',
      },
    );

    if (Platform.isWindows) {
      await Process.run(
        'rundll32',
        ['url.dll,FileProtocolHandler', googleAuthUri.toString()],
      );
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [googleAuthUri.toString()]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [googleAuthUri.toString()]);
    }

    final Completer<void> doneCompleter = Completer<void>();

    _localAuthServer!.listen((HttpRequest request) async {
      if (request.uri.path == '/callback') {
        final String? returnedState = request.uri.queryParameters['state'];
        final String? code = request.uri.queryParameters['code'];
        final String? error = request.uri.queryParameters['error'];

        if (error != null || code == null || returnedState != stateToken) {
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            _buildOAuthResultHtml(
              success: false,
              message:
                  'Autorizzazione Google annullata o non valida (${error ?? "state mismatch"}).',
            ),
          );
          await request.response.close();
          if (!doneCompleter.isCompleted) {
            doneCompleter.completeError(
              Exception(error ?? 'OAuth state mismatch'),
            );
          }
          return;
        }

        try {
          final Map<String, dynamic> profile = await _exchangeCodeForProfile(
            code: code,
            codeVerifier: codeVerifier,
            redirectUri: redirectUri,
          );

          final String name =
              (profile['name'] as String?) ?? 'Utente Google';
          final String email =
              (profile['email'] as String?) ?? '';
          final String? picture = profile['picture'] as String?;

          request.response.headers.contentType = ContentType.html;
          request.response.write(
            _buildOAuthResultHtml(
              success: true,
              message:
                  'Accesso Google completato come <b>$name</b> ($email). Puoi chiudere questa scheda.',
            ),
          );
          await request.response.close();

          await _saveGoogleProfile(
            name: name,
            email: email,
            photoUrl: picture,
          );
          if (!doneCompleter.isCompleted) doneCompleter.complete();
        } catch (err) {
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            _buildOAuthResultHtml(
              success: false,
              message: 'Errore scambio token OAuth 2.0: $err',
            ),
          );
          await request.response.close();
          if (!doneCompleter.isCompleted) doneCompleter.completeError(err);
        } finally {
          await _localAuthServer?.close(force: true);
          _localAuthServer = null;
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });

    await doneCompleter.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () async {
        await _localAuthServer?.close(force: true);
        _localAuthServer = null;
        throw TimeoutException('Tempo scaduto per il login Google nel browser.');
      },
    );
  }

  Future<Map<String, dynamic>> _exchangeCodeForProfile({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final HttpClient httpClient = HttpClient();
    try {
      // 1. Scambio Authorization Code -> Access Token & ID Token
      final HttpClientRequest tokenReq = await httpClient.postUrl(
        Uri.parse('https://oauth2.googleapis.com/token'),
      );
      tokenReq.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );

      final Map<String, String> bodyParams = {
        'client_id': _googleDesktopClientId,
        'code': code,
        'code_verifier': codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      };
      if (_googleDesktopClientSecret.isNotEmpty) {
        bodyParams['client_secret'] = _googleDesktopClientSecret;
      }

      final String formBody = bodyParams.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      tokenReq.write(formBody);

      final HttpClientResponse tokenResp = await tokenReq.close();
      final String tokenRaw = await tokenResp.transform(utf8.decoder).join();
      final Map<String, dynamic> tokenJson =
          jsonDecode(tokenRaw) as Map<String, dynamic>;

      if (tokenResp.statusCode != 200 || tokenJson['access_token'] == null) {
        throw Exception(
          tokenJson['error_description'] ??
              tokenJson['error'] ??
              'Risposta token non valida (${tokenResp.statusCode})',
        );
      }

      final String accessToken = tokenJson['access_token'] as String;

      // 2. Recupero profilo reale Google tramite endpoint OpenID UserInfo
      final HttpClientRequest userReq = await httpClient.getUrl(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
      );
      userReq.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
      final HttpClientResponse userResp = await userReq.close();
      final String userRaw = await userResp.transform(utf8.decoder).join();

      if (userResp.statusCode != 200) {
        throw Exception('Impossibile recuperare userinfo Google ($userRaw)');
      }

      return jsonDecode(userRaw) as Map<String, dynamic>;
    } finally {
      httpClient.close();
    }
  }

  String _buildOAuthResultHtml({
    required bool success,
    required String message,
  }) {
    final String borderColor = success ? '#10B981' : '#EF4444';
    final String title =
        success ? '✓ Autenticazione Google Riuscita' : '✕ Errore Autenticazione';
    return '''
<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="UTF-8">
  <title>LanPulse P2P - Google OAuth 2.0</title>
  <style>
    body { font-family: 'Segoe UI', sans-serif; background: #0B1120; color: #F8FAFC; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .card { background: #1E293B; padding: 36px; border-radius: 18px; width: 400px; text-align: center; border: 1px solid $borderColor; box-shadow: 0 20px 45px rgba(0,0,0,0.5); }
    h2 { color: $borderColor; margin-top: 0; }
    p { color: #CBD5E1; font-size: 14.5px; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="card">
    <h2>$title</h2>
    <p>$message</p>
  </div>
</body>
</html>
''';
  }

  Future<void> _saveGoogleProfile({
    required String name,
    required String email,
    String? photoUrl,
  }) async {
    _googleDisplayName = name;
    _googleEmail = email;
    _googlePhotoUrl = photoUrl;
    _localAlias = '$name (${Platform.isWindows ? "PC" : "Android"})';
    _discoveryService.updateAlias(_localAlias);
    _transferService.localAlias = _localAlias;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('google_name', name);
    await prefs.setString('google_email', email);
    await prefs.setString('local_alias', _localAlias);
    if (photoUrl != null) {
      await prefs.setString('google_photo', photoUrl);
    }
    _setBanner('Account Google verificato: $name ($email)');
    notifyListeners();
  }

  Future<void> signOutGoogle() async {
    try {
      if (Platform.isAndroid) {
        await GoogleSignIn().signOut();
      }
    } catch (_) {}

    _googleDisplayName = null;
    _googleEmail = null;
    _googlePhotoUrl = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('google_name');
    await prefs.remove('google_email');
    await prefs.remove('google_photo');
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
        'Impossibile inviare il messaggio a ${target.alias} (${target.ipAddress}). Verifica che sia online.',
        isError: true,
      );
    }
  }

  /// Seleziona e invia un file usando il protocollo frammentato a 64 KB
  Future<void> pickAndSendFile({PeerNode? targetOverride}) async {
    if (_isTransferring) return;
    final PeerNode? target = targetOverride ?? _selectedPeer;
    if (target == null) {
      _setBanner(
        'Seleziona prima un dispositivo a cui inviare il file.',
        isError: true,
      );
      return;
    }

    selectPeer(target);

    FilePickerResult? result;
    try {
      // Con file grandi evitiamo di caricare l'intero file in memoria, usando il path nativo
      result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
        withReadStream: true,
      );
    } catch (e) {
      _setBanner('Errore apertura selettore file: $e', isError: true);
      return;
    }

    if (result == null || result.files.isEmpty) return;
    final PlatformFile picked = result.files.single;

    final String fileName = picked.name;
    final int totalBytes = picked.path != null && File(picked.path!).existsSync()
        ? await File(picked.path!).length()
        : picked.size;

    _isTransferring = true;
    _activeTransferProgress = 0.0;
    _statusBanner = !target.isTrusted
        ? 'In attesa che ${target.alias} accetti la richiesta di trasferimento...'
        : 'Invio frammentato di "$fileName" in corso...';
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
      _setBanner('File "$fileName" inviato con successo a ${target.alias}!');
    } catch (e) {
      _setBanner(
        'Trasferimento file interrotto verso ${target.alias}:$e',
        isError: true,
      );
    } finally {
      _isTransferring = false;
      _activeTransferProgress = 0.0;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localAuthServer?.close(force: true);
    _soundService.dispose();
    _discoveryService.dispose();
    _transferService.dispose();
    super.dispose();
  }
}
