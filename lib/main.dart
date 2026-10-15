import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'providers/p2p_controller.dart';
import 'ui/screens/adaptive_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    await [
      Permission.nearbyWifiDevices,
      Permission.storage,
    ].request();
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => P2PController(),
      child: const LanPulseApp(),
    ),
  );
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
