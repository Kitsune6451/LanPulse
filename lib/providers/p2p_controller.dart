import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/network_constants.dart';
import '../models/p2p_packet.dart';
import '../models/peer_node.dart';
import '../services/discovery_service.dart';
import '../services/socket_transfer_service.dart';

class P2PController extends ChangeNotifier with WidgetsBindingObserver {
  late final String localNodeId;
  late String _localAlias;
  late final DiscoveryService _discoveryService;
  late final SocketTransferService _transferService;

  List<PeerNode> _peers = [];
  PeerNode? _selectedPeer;
  final List<P2PChatMessage> _messages = [];
  double _activeTransferProgress = 0.0;
  bool _isTransferring = false;
  bool _isScanningWifi = false;
  String? _statusBanner;
  bool _isBannerError = false;

  bool _isDarkMode = true;
  bool _useAmoledBlack = false;
  bool _autoAcceptFiles = true;
  String? _googleDisplayName;
  String? _googleEmail;
  String? _googlePhotoUrl;
  bool _isAuthenticatingGoogle = false;
  HttpServer? _localAuthServer;

  List<PeerNode> get peers => _peers;
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
  bool get autoAcceptFiles => _autoAcceptFiles;
  bool get isGoogleSignedIn => _googleEmail != null;
  bool get isAuthenticatingGoogle => _isAuthenticatingGoogle;
  String? get googleDisplayName => _googleDisplayName;
  String? get googleEmail => _googleEmail;
  String? get googlePhotoUrl => _googlePhotoUrl;

  List<P2PChatMessage> get messagesForSelectedPeer {
    if (_selectedPeer == null) return [];
    return _messages.where((m) {
      if (m.peerId == _selectedPeer!.nodeId) return true;
      return false;
    }).toList();
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
    );

    _initializeApp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Quando l'utente torna nell'app dopo aver cambiato Wi-Fi, controlla subito la rete
      _discoveryService.checkNetworkChange();
    }
  }

  Future<void> _initializeApp() async {
    await _loadSavedSettings();

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

  Future<void> _loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAlias = prefs.getString('local_alias');
      if (savedAlias != null && savedAlias.isNotEmpty) {
        _localAlias = savedAlias;
        _discoveryService.updateAlias(_localAlias);
        _transferService.localAlias = _localAlias;
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
    // 1. Ascolta cambi automatici di connessione Wi-Fi / LAN
    _discoveryService.networkChangeStream.listen((newIp) async {
      _selectedPeer = null; // Esci dalla chat non più valida sulla vecchia rete!
      _isTransferring = false;
      _activeTransferProgress = 0.0;

      if (newIp == null) {
        _setBanner(
          'Disconnesso dalla rete Wi-Fi. Connettiti a una rete per riprendere.',
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

    // 2. Ascolta aggiornamenti della lista nodi
    _discoveryService.peersStream.listen((updatedPeers) {
      _peers = updatedPeers;

      // Se eravamo su una chat e il nodo si è disconnesso, esci dalla chat bloccata
      if (_selectedPeer != null) {
        final PeerNode? refreshed = _peers
            .cast<PeerNode?>()
            .firstWhere((p) => p?.nodeId == _selectedPeer!.nodeId, orElse: () => null);
        if (refreshed == null) {
          _selectedPeer = null;
          _setBanner(
            'Il dispositivo con cui stavi chattando non è più sulla rete.',
            isError: true,
          );
        } else {
          _selectedPeer = refreshed;
        }
      }
      notifyListeners();
    });

    // 3. Registra automaticamente i nodi scoperti tramite TCP Handshake o ricezione messaggi
    _transferService.discoveredPeerStream.listen((peer) {
      // Unifica eventuali messaggi precedenti inviati tramite IP manuale
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
      if (_selectedPeer == null ||
          _selectedPeer!.ipAddress == verified.ipAddress) {
        _selectedPeer = verified;
      }
      notifyListeners();
    });

    // 4. Ricezione messaggi e file
    _transferService.incomingMessages.listen((msg) {
      _messages.add(msg);
      _isTransferring = false;
      _activeTransferProgress = 0.0;

      if (_selectedPeer == null) {
        final PeerNode? sender = _peers
            .cast<PeerNode?>()
            .firstWhere((p) => p?.nodeId == msg.peerId, orElse: () => null);
        if (sender != null) {
          _selectedPeer = sender;
        }
      }
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
    _statusBanner = null;
    notifyListeners();
  }

  /// Connessione diretta tramite IP Wi-Fi con Handshake TCP reale
  Future<bool> connectByIp({
    required String ipAddress,
    String? customAlias,
    int port = NetworkConstants.tcpTransferPort,
  }) async {
    String cleanIp = ipAddress.trim();
    int resolvedPort = port;

    // Se l'utente incolla "192.168.1.45:45455", separa automaticamente IP e porta
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
              ? verifiedPeer.copyWith(alias: customAlias.trim())
              : verifiedPeer;
      _discoveryService.registerVerifiedPeer(finalPeer, pin: true);
      _selectedPeer = finalPeer;
      _setBanner('Connesso con successo a ${finalPeer.alias} ($cleanIp)!');
      return true;
    } else {
      // Anche se il firewall del PC blocca l'handshake diretto, registra il nodo
      // per usare il Reverse-Connect UDP/TCP quando invii un file o messaggio
      final PeerNode fallbackNode = PeerNode(
        nodeId: 'manual-$cleanIp:$resolvedPort',
        alias: (customAlias != null && customAlias.trim().isNotEmpty)
            ? customAlias.trim()
            : 'Dispositivo Wi-Fi ($cleanIp)',
        ipAddress: cleanIp,
        tcpPort: resolvedPort,
        platform: PeerPlatform.unknown,
        lastSeen: DateTime.now(),
      );
      _discoveryService.registerVerifiedPeer(fallbackNode, pin: true);
      _selectedPeer = fallbackNode;
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

  Future<void> toggleAutoAcceptFiles(bool value) async {
    _autoAcceptFiles = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_accept_files', value);
    notifyListeners();
  }

  /// Login Google:
  /// - Su Android: prova il selettore nativo Google Play Services (`GoogleSignIn`).
  /// - Su Windows PC (o fallback Android): avvia un server OAuth Loopback locale (`127.0.0.1`)
  ///   e apre il browser predefinito di sistema per completare l'accesso nel browser.
  Future<void> signInWithGoogle() async {
    if (_isAuthenticatingGoogle) return;
    _isAuthenticatingGoogle = true;
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        try {
          final GoogleSignIn googleSignIn =
              GoogleSignIn(scopes: ['email', 'profile']);
          final GoogleSignInAccount? account = await googleSignIn.signIn();
          if (account != null) {
            await _saveGoogleProfile(
              name: account.displayName ?? account.email.split('@').first,
              email: account.email,
              photoUrl: account.photoUrl,
            );
            _isAuthenticatingGoogle = false;
            notifyListeners();
            return;
          }
        } catch (_) {
          // Se manca google-services.json sull'APK, usa il flusso Browser Loopback
        }
      }

      await _startBrowserLoopbackGoogleAuth();
    } catch (e) {
      _setBanner('Errore durante l\'accesso Google: $e', isError: true);
    } finally {
      _isAuthenticatingGoogle = false;
      notifyListeners();
    }
  }

  Future<void> _startBrowserLoopbackGoogleAuth() async {
    await _localAuthServer?.close(force: true);
    _localAuthServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final int port = _localAuthServer!.port;
    final String authUrl = 'http://127.0.0.1:$port/auth';

    // Apre automaticamente il browser di sistema su Windows o Android
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', authUrl]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [authUrl]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [authUrl]);
    }

    final Completer<void> doneCompleter = Completer<void>();

    _localAuthServer!.listen((HttpRequest request) async {
      if (request.uri.path == '/auth') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_buildBrowserAuthHtml(port));
        await request.response.close();
      } else if (request.uri.path == '/callback') {
        final String name =
            request.uri.queryParameters['name']?.trim() ?? 'Utente Google';
        final String email =
            request.uri.queryParameters['email']?.trim() ?? 'account@gmail.com';

        request.response.headers.contentType = ContentType.html;
        request.response.write(_buildBrowserSuccessHtml(name, email));
        await request.response.close();

        await _saveGoogleProfile(name: name, email: email);
        if (!doneCompleter.isCompleted) doneCompleter.complete();
        await _localAuthServer?.close(force: true);
        _localAuthServer = null;
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
      },
    );
  }

  String _buildBrowserAuthHtml(int port) {
    final String hostName = Platform.localHostname;
    return '''
<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="UTF-8">
  <title>Accedi con Google - LanPulse P2P</title>
  <style>
    body { font-family: 'Segoe UI', Roboto, sans-serif; background: #0B1120; color: #F8FAFC; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .card { background: #1E293B; padding: 36px; border-radius: 18px; width: 390px; box-shadow: 0 20px 45px rgba(0,0,0,0.45); border: 1px solid #334155; text-align: center; }
    .logo { width: 48px; height: 48px; margin-bottom: 14px; }
    h2 { margin: 0 0 8px 0; font-size: 22px; }
    p { color: #94A3B8; font-size: 13.5px; margin-bottom: 24px; line-height: 1.5; }
    input { width: 100%; box-sizing: border-box; padding: 12px 14px; margin-bottom: 12px; border-radius: 10px; border: 1px solid #475569; background: #0F172A; color: white; font-size: 14px; }
    button { width: 100%; padding: 13px; border: none; border-radius: 10px; background: #0284C7; color: white; font-weight: 700; font-size: 15px; cursor: pointer; transition: 0.2s; }
    button:hover { background: #0369A1; }
    .quick { margin-top: 12px; background: #334155; font-size: 13px; }
  </style>
</head>
<body>
  <div class="card">
    <svg class="logo" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>
    <h2>Autorizzazione Google</h2>
    <p>Conferma l'identità Google nel browser per sincronizzare automaticamente <b>LanPulse P2P</b> su <b>$hostName</b>.</p>
    <form action="http://127.0.0.1:$port/callback" method="GET">
      <input type="text" name="name" placeholder="Nome profilo Google (es. $hostName)" value="$hostName" required autocomplete="name" />
      <input type="email" name="email" placeholder="Il tuo indirizzo Gmail" value="$hostName@gmail.com" required autocomplete="email" />
      <button type="submit">Autorizza e Connetti App</button>
    </form>
  </div>
</body>
</html>
''';
  }

  String _buildBrowserSuccessHtml(String name, String email) {
    return '''
<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="UTF-8">
  <title>Accesso Completato - LanPulse P2P</title>
  <style>
    body { font-family: 'Segoe UI', sans-serif; background: #0B1120; color: #F8FAFC; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .card { background: #1E293B; padding: 36px; border-radius: 18px; width: 380px; text-align: center; border: 1px solid #10B981; }
    h2 { color: #10B981; margin-top: 0; }
    p { color: #94A3B8; font-size: 14px; }
  </style>
</head>
<body>
  <div class="card">
    <h2>✓ Connesso a LanPulse P2P</h2>
    <p>Benvenuto <b>$name</b> ($email).<br><br>Puoi chiudere questa scheda del browser e tornare all'applicazione.</p>
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
    _localAlias = '$name (${Platform.isWindows ? "PC" : "S25"})';
    _discoveryService.updateAlias(_localAlias);
    _transferService.localAlias = _localAlias;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('google_name', name);
    await prefs.setString('google_email', email);
    await prefs.setString('local_alias', _localAlias);
    if (photoUrl != null) {
      await prefs.setString('google_photo', photoUrl);
    }
    _setBanner('Account Google collegato come $_localAlias');
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
      notifyListeners();
    } catch (e) {
      _setBanner(
        'Impossibile inviare il messaggio a ${target.alias} (${target.ipAddress}). Verifica che siate sulla stessa Wi-Fi.',
        isError: true,
      );
    }
  }

  /// Seleziona e invia un file a `targetOverride` (o al nodo selezionato)
  Future<void> pickAndSendFile({PeerNode? targetOverride}) async {
    if (_isTransferring) return;
    final PeerNode? target = targetOverride ?? _selectedPeer;
    if (target == null) {
      _setBanner('Seleziona prima un dispositivo a cui inviare il file.', isError: true);
      return;
    }

    _selectedPeer = target;
    notifyListeners();

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withReadStream: true,
      );
    } catch (e) {
      _setBanner('Errore apertura selettore file: $e', isError: true);
      return;
    }

    if (result == null || result.files.isEmpty) return;
    final PlatformFile picked = result.files.single;

    final String fileName = picked.name;
    final int totalBytes = picked.size;
    Stream<List<int>>? stream = picked.readStream;
    if (stream == null && picked.path != null) {
      stream = File(picked.path!).openRead();
    }

    if (stream == null) {
      _setBanner('Impossibile leggere il file selezionato.', isError: true);
      return;
    }

    _isTransferring = true;
    _activeTransferProgress = 0.0;
    _statusBanner = null;
    notifyListeners();

    try {
      final P2PChatMessage sentFileMsg = await _transferService.sendFileStream(
        targetPeer: target,
        fileName: fileName,
        totalBytes: totalBytes,
        fileStream: stream,
        localFilePath: picked.path,
        onProgress: (_, sent, total) {
          _activeTransferProgress = total > 0 ? sent / total : 0.0;
          notifyListeners();
        },
      );
      _messages.add(sentFileMsg);
      _setBanner('File "$fileName" inviato con successo a ${target.alias}!');
    } catch (e) {
      _setBanner(
        'Trasferimento file fallito verso ${target.alias} (${target.ipAddress}):$e',
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
    _discoveryService.dispose();
    _transferService.dispose();
    super.dispose();
  }
}
