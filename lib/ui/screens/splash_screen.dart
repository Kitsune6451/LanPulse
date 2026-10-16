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
  late final Animation<double> _logoLeftOffset;
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

    // 1. Battito del logo mentre si trova esattamente al centro (0.0s -> 0.55s)
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.82, end: 1.24)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.24, end: 0.94)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.94, end: 1.12)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 14,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.12, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 61,
      ),
    ]).animate(_controller);

    // Onda d'urto circolare durante il battito centrale
    _rippleRadius = Tween<double>(begin: 0.85, end: 1.90).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutQuart),
      ),
    );

    _rippleOpacity = Tween<double>(begin: 0.65, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    // 2. Traslazione del logo dal centro esatto (106px) verso sinistra (18px) dopo 0.55s
    _logoLeftOffset = Tween<double>(begin: 106.0, end: 18.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.28, 0.65, curve: Curves.easeInOutCubic),
      ),
    );

    // 3. Comparsa progressiva a destra della scritta "LAN \n PULSE" mentre il logo trasla
    _textRevealFactor = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.34, 0.74, curve: Curves.easeOutCubic),
      ),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.36, 0.72, curve: Curves.easeOut),
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
        // AnimatedBuilder fondamentale per ridisegnare ogni frame dell'animazione!
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return SizedBox(
              width: 290,
              height: 110,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  // Scritta "LAN \n PULSE" perfettamente centrata in verticale accanto al logo
                  Positioned(
                    left: 112,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: _textRevealFactor.value,
                          child: Opacity(
                            opacity: _textOpacity.value,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'LAN',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    height: 0.95,
                                    letterSpacing: 3.5,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'PULSE',
                                  style: TextStyle(
                                    fontSize: 32,
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
                  ),

                  // Logo che parte al centro (left: 106), batte e poi trasla a sinistra (left: 18)
                  Positioned(
                    left: _logoLeftOffset.value,
                    top: 16,
                    child: SizedBox(
                      width: 78,
                      height: 78,
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
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
