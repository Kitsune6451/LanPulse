import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/network_constants.dart';
import '../models/p2p_packet.dart';
import '../models/peer_node.dart';
import '../services/discovery_service.dart';
import '../services/socket_transfer_service.dart';

class P2PController extends ChangeNotifier {
  late final String localNodeId;
  late String _localAlias;
  late final DiscoveryService _discoveryService;
  late final SocketTransferService _transferService;

  List<PeerNode> _peers = [];
  PeerNode? _selectedPeer;
  final List<P2PChatMessage> _messages = [];
  double _activeTransferProgress = 0.0;
  bool _isTransferring = false;
  String? _errorBanner;

  // Impostazioni & Account Google
  bool _isDarkMode = true;
  bool _useAmoledBlack = false;
  bool _autoAcceptFiles = true;
  String? _googleDisplayName;
  String? _googleEmail;
  String? _googlePhotoUrl;

  List<PeerNode> get peers => _peers;
  PeerNode? get selectedPeer => _selectedPeer;
  String get localAlias => _localAlias;
  String? get localIp => _discoveryService.localIp;
  List<String> get allLocalIps => _discoveryService.allLocalIps;
  int get tcpPort => NetworkConstants.tcpTransferPort;
  bool get isTransferring => _isTransferring;
  double get activeTransferProgress => _activeTransferProgress;
  String? get errorBanner => _errorBanner;

  bool get isDarkMode => _isDarkMode;
  bool get useAmoledBlack => _useAmoledBlack;
  bool get autoAcceptFiles => _autoAcceptFiles;
  bool get isGoogleSignedIn => _googleEmail != null;
  String? get googleDisplayName => _googleDisplayName;
  String? get googleEmail => _googleEmail;
  String? get googlePhotoUrl => _googlePhotoUrl;

  List<P2PChatMessage> get messagesForSelectedPeer {
    if (_selectedPeer == null) return [];
    return _messages.where((m) => m.peerId == _selectedPeer!.nodeId).toList();
  }

  P2PController() {
    localNodeId = const Uuid().v4().substring(0, 8);
    _localAlias = Platform.isWindows
        ? 'PC-${Platform.localHostname}'
        : 'S25-Node-$localNodeId';

    _discoveryService = DiscoveryService(
      localNodeId: localNodeId,
      localAlias: _localAlias,
    );

    _transferService = SocketTransferService(
      localNodeId: localNodeId,
      localAlias: _localAlias,
    );

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadSavedSettings();

    // Richiede i permessi su Android solo dopo l'inizializzazione dell'Activity
    if (Platform.isAndroid) {
      try {
        await [
          Permission.nearbyWifiDevices,
          Permission.locationWhenInUse,
        ].request();
      } catch (e) {
        debugPrint('Avviso permessi Android: $e');
      }
    }

    await _initializeNetworking();
  }

  Future<void> _loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAlias = prefs.getString('local_alias');
      if (savedAlias != null && savedAlias.isNotEmpty) {
        _localAlias = savedAlias;
        _discoveryService.updateAlias(_localAlias);
      }
      _isDarkMode = prefs.getBool('dark_mode') ?? true;
      _useAmoledBlack = prefs.getBool('amoled_black') ?? false;
      _autoAcceptFiles = prefs.getBool('auto_accept_files') ?? true;
      _googleDisplayName = prefs.getString('google_name');
      _googleEmail = prefs.getString('google_email');
      _googlePhotoUrl = prefs.getString('google_photo');
      notifyListeners();
    } catch (_) {}
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
      // Se il messaggio arriva da un IP non ancora in lista, lo aggiunge automaticamente
      final bool knownPeer = _peers.any((p) => p.nodeId == msg.peerId);
      if (!knownPeer) {
        _selectedPeer ??= PeerNode(
          nodeId: msg.peerId,
          alias: msg.peerAlias,
          ipAddress: 'Rete Wi-Fi',
          tcpPort: NetworkConstants.tcpTransferPort,
          platform: PeerPlatform.unknown,
          lastSeen: DateTime.now(),
        );
      }
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
      notifyListeners();
    } catch (e) {
      _errorBanner = 'Errore avvio socket di rete: $e';
      notifyListeners();
    }
  }

  Future<void> refreshNetwork() async {
    _errorBanner = null;
    await _discoveryService.refreshNetworkAddresses();
    await _discoveryService.startDiscovery();
    notifyListeners();
  }

  void clearError() {
    _errorBanner = null;
    notifyListeners();
  }

  void selectPeer(PeerNode peer) {
    _selectedPeer = peer;
    _errorBanner = null;
    notifyListeners();
  }

  /// Connette direttamente a un dispositivo tramite indirizzo IP su rete Wi-Fi
  Future<bool> connectByIp({
    required String ipAddress,
    String? customAlias,
    int port = NetworkConstants.tcpTransferPort,
  }) async {
    final String cleanIp = ipAddress.trim();
    if (cleanIp.isEmpty) return false;

    try {
      // Verifica se la porta TCP del destinatario è raggiungibile sulla rete Wi-Fi
      final Socket testSocket = await Socket.connect(
        cleanIp,
        port,
        timeout: const Duration(seconds: 3),
      );
      await testSocket.close();
    } catch (_) {
      // Anche se il ping iniziale fallisce, aggiungiamo comunque il nodo per tentare l'invio
      _errorBanner =
          'Nodo aggiunto ($cleanIp:$port). Assicurati che LanPulse sia aperto anche sull\'altro dispositivo.';
    }

    final PeerNode manualPeer = _discoveryService.addManualPeer(
      ipAddress: cleanIp,
      customAlias: customAlias,
      tcpPort: port,
    );
    _selectedPeer = manualPeer;
    notifyListeners();
    return true;
  }

  Future<void> updateLocalAlias(String newAlias) async {
    if (newAlias.trim().isEmpty) return;
    _localAlias = newAlias.trim();
    _discoveryService.updateAlias(_localAlias);
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

  Future<void> toggleAutoAcceptFiles(bool value) async {
    _autoAcceptFiles = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_accept_files', value);
    notifyListeners();
  }

  /// Effettua il login tramite Google Sign-In nativo su Android/iOS o profilo Google
  Future<void> signInWithGoogle({
    String? fallbackName,
    String? fallbackEmail,
  }) async {
    try {
      if (Platform.isAndroid) {
        final GoogleSignIn googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
        final GoogleSignInAccount? account = await googleSignIn.signIn();
        if (account != null) {
          await _saveGoogleProfile(
            name: account.displayName ?? account.email.split('@').first,
            email: account.email,
            photoUrl: account.photoUrl,
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('Google Sign-In nativo richiede configurazione OAuth SHA-1: $e');
    }

    // Fallback immediato per Windows Desktop o build APK senza google-services.json
    if (fallbackEmail != null && fallbackEmail.trim().isNotEmpty) {
      final String email = fallbackEmail.trim();
      final String name = (fallbackName != null && fallbackName.trim().isNotEmpty)
          ? fallbackName.trim()
          : email.split('@').first;
      await _saveGoogleProfile(name: name, email: email, photoUrl: null);
    }
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('google_name', name);
    await prefs.setString('google_email', email);
    await prefs.setString('local_alias', _localAlias);
    if (photoUrl != null) {
      await prefs.setString('google_photo', photoUrl);
    }
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
      _errorBanner = null;
      notifyListeners();
    } catch (e) {
      _errorBanner =
          'Impossibile connettersi a ${target.alias} (${target.ipAddress}:${target.tcpPort}). Verifica che siete sulla stessa rete Wi-Fi.';
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
    _errorBanner = null;
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
      _errorBanner = 'Trasferimento file interrotto verso ${target.ipAddress}: $e';
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
