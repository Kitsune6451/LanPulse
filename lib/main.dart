import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'providers/p2p_controller.dart';
import 'ui/screens/adaptive_home_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (Platform.isAndroid) {
      try {
        await [
          Permission.nearbyWifiDevices,
          Permission.locationWhenInUse,
        ].request();
      } catch (e) {
        debugPrint('Errore richiesta permessi nativi: $e');
      }
    }

    runApp(
      ChangeNotifierProvider(
        create: (_) => P2PController(),
        child: const LanPulseApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Eccezione non gestita all\'avvio: $error');
  });
}

class LanPulseApp extends StatelessWidget {
  const LanPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LanPulse P2P',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF0284C7),
        useMaterial3: true,
      ),
      home: const AdaptiveHomeScreen(),
    );
  }
}
