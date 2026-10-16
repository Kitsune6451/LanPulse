import 'dart:async';
import 'package:flutter/material.dart';
import 'adaptive_home_screen.dart';

class LanPulseSplashScreen extends StatefulWidget {
  const LanPulseSplashScreen({super.key});

  @override
  State<LanPulseSplashScreen> createState() => _LanPulseSplashScreenState();
}

class _LanPulseSplashScreenState extends State<LanPulseSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulseScale;
  late final Animation<double> _rippleRadius;
  late final Animation<double> _rippleOpacity;
  late final Animation<double> _textRevealFactor;
  late final Animation<double> _textOpacity;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );

    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.85, end: 1.22)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 16,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.22, end: 0.95)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.95, end: 1.12)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 16,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.12, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 56,
      ),
    ]).animate(_controller);

    _rippleRadius = Tween<double>(begin: 0.85, end: 1.85).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutQuart),
      ),
    );

    _rippleOpacity = Tween<double>(begin: 0.65, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
      ),
    );

    // Animazione di scorrimento/rivelazione della scritta da sinistra verso destra
    _textRevealFactor = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.28, 0.72, curve: Curves.easeInOutCubic),
      ),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.32, 0.70, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
    _navTimer = Timer(const Duration(milliseconds: 2000), _goToHome);
  }

  void _goToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => const AdaptiveHomeScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 280,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Logo centrato e allineato geometricamente a sinistra del blocco centrale
              Positioned(
                left: 20,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: _rippleRadius.value,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: accent.withValues(
                              alpha: _rippleOpacity.value,
                            ),
                            width: 2.2,
                          ),
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: _pulseScale.value,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent,
                              accent.withValues(alpha: 0.72),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.38),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          size: 44,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Scritta "LAN PULSE" posizionata esattamente a fianco del logo (left: 114)
              Positioned(
                left: 114,
                top: 26,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: _textRevealFactor.value,
                    child: FadeTransition(
                      opacity: _textOpacity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LAN',
                            style: TextStyle(
                              fontSize: 31,
                              fontWeight: FontWeight.w900,
                              height: 0.95,
                              letterSpacing: 3.5,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'PULSE',
                            style: TextStyle(
                              fontSize: 31,
                              fontWeight: FontWeight.w300,
                              height: 0.95,
                              letterSpacing: 4.5,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
