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

  ThemeData _buildTheme(P2PController controller, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final Color seed = isDark
        ? controller.themePreset.darkSeed
        : controller.themePreset.lightSeed;
    final double radius = controller.uiStyle.borderRadius;

    final Color bgColor = isDark
        ? (controller.useAmoledBlack
            ? const Color(0xFF000000)
            : const Color(0xFF0B1120))
        : const Color(0xFFF8FAFC);

    final Color cardColor = isDark
        ? (controller.useAmoledBlack
            ? const Color(0xFF0D0D0D)
            : const Color(0xFF1E293B))
        : Colors.white;

    return ThemeData(
      brightness: brightness,
      colorSchemeSeed: seed,
      scaffoldBackgroundColor: bgColor,
      useMaterial3: true,
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: controller.uiStyle == AppUiStyle.minimalistFlat ? 0 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<P2PController>();

    return MaterialApp(
      title: 'LanPulse P2P',
      debugShowCheckedModeBanner: false,
      themeMode: controller.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      darkTheme: _buildTheme(controller, Brightness.dark),
      theme: _buildTheme(controller, Brightness.light),
      home: const AdaptiveHomeScreen(),
    );
  }
}
