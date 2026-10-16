import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/p2p_controller.dart';
import 'ui/screens/splash_screen.dart';

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

  ThemeData _buildFintechTheme(
    P2PController controller,
    Brightness brightness,
  ) {
    final bool isDark = brightness == Brightness.dark;
    final Color seed = isDark
        ? controller.themePreset.darkSeed
        : controller.themePreset.lightSeed;
    const double radius = 16.0;

    final Color bgColor = isDark
        ? (controller.useAmoledBlack
            ? const Color(0xFF000000)
            : const Color(0xFF090D16))
        : const Color(0xFFF4F6F9);

    final Color surfaceColor = isDark
        ? (controller.useAmoledBlack
            ? const Color(0xFF0C0C0E)
            : const Color(0xFF111726))
        : const Color(0xFFFFFFFF);

    final Color borderColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: surfaceColor,
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgColor,
      useMaterial3: true,
      dividerTheme: DividerThemeData(color: borderColor, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borderColor, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 4),
          side: BorderSide(color: borderColor),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: seed.withValues(alpha: 0.16),
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: seed, width: 1.5),
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
      darkTheme: _buildFintechTheme(controller, Brightness.dark),
      theme: _buildFintechTheme(controller, Brightness.light),
      home: const LanPulseSplashScreen(),
    );
  }
}
