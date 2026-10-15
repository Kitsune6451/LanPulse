import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/p2p_controller.dart';
import 'ui/screens/adaptive_home_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    runApp(
      ChangeNotifierProvider(
        create: (_) => P2PController(),
        child: const LanPulseApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Eccezione non gestita: $error\n$stack');
  });
}

class LanPulseApp extends StatelessWidget {
  const LanPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<P2PController>();

    return MaterialApp(
      title: 'LanPulse P2P',
      debugShowCheckedModeBanner: false,
      themeMode: controller.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF38BDF8),
        scaffoldBackgroundColor: controller.useAmoledBlack
            ? const Color(0xFF000000)
            : const Color(0xFF0B1120),
        useMaterial3: true,
      ),
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF0284C7),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        useMaterial3: true,
      ),
      home: const AdaptiveHomeScreen(),
    );
  }
}
