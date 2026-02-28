import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Компактная кнопка «Я скучаю» для хедера — стиль как у бейджа типа отношений.
/// • Анимация нажатия (scale bounce)
/// • Счётчик нажатий с pop-анимацией
/// • Огонёк серии (streak badge)
/// • Летящие сердечки
class MissYouButton extends StatefulWidget {
  final AppTheme theme;
  final String groupId;
  final String senderName;
  final bool enabled;

  const MissYouButton({
    super.key,
    required this.theme,
    required this.groupId,
    required this.senderName,
    this.enabled = true,
  });

  @override
  State<MissYouButton> createState() => _MissYouButtonState();
}

class _MissYouButtonState extends State<MissYouButton>
    with TickerProviderStateMixin {
  final FirebaseService _fb = FirebaseService();

  // -- State --
  int _totalCount = 0;
  int _streak = 0;
  Timer? _streakTimer;
  StreamSubscription? _countSub;

  // -- Animations --
  late AnimationController _scaleController;
  late AnimationController _counterController;
  late AnimationController _glowController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _counterAnimation;
  late Animation<double> _glowAnimation;

  // -- Floating hearts --
  final List<_FloatingHeart> _hearts = [];
  final _random = Random();

  // -- Counter --
  int _displayedCount = 0;
  int _previousCount = 0;

  @override
  void initState() {
    super.initState();

    // Scale on tap (bounce)
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));

    // Counter pop
    _counterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _counterAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 40),
          TweenSequenceItem(tween: Tween(begin: 1.4, end: 0.9), weight: 30),
          TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 30),
        ]).animate(
          CurvedAnimation(parent: _counterController, curve: Curves.easeOut),
        );

    // Glow for streak
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _glowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _glowController, curve: Curves.easeOut));

    _startListening();
  }

  @override
  void didUpdateWidget(covariant MissYouButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId) {
      _countSub?.cancel();
      _startListening();
    }
  }

  void _startListening() {
    _countSub?.cancel();
    if (widget.groupId.isEmpty) return;
    _countSub = _fb.listenToMissYouCount(
      groupId: widget.groupId,
      onData: (count) {
        if (!mounted) return;
        _previousCount = _displayedCount;
        setState(() => _totalCount = count);
        _animateCounter();
      },
    );
  }

  void _animateCounter() {
    final end = _totalCount;
    _counterController.forward(from: 0);
    _counterController.addListener(_counterTickListener);
    _counterController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _counterController.removeListener(_counterTickListener);
        if (mounted) setState(() => _displayedCount = end);
      }
    });
    if (_previousCount == 0 && end > 0) {
      setState(() => _displayedCount = end);
    }
  }

  void _counterTickListener() {
    final progress = _counterController.value;
    final newVal = (_previousCount + (_totalCount - _previousCount) * progress)
        .round();
    if (newVal != _displayedCount && mounted) {
      setState(() => _displayedCount = newVal);
    }
  }

  Future<void> _onTap() async {
    if (!widget.enabled || widget.groupId.isEmpty) return;

    HapticFeedback.mediumImpact();

    // Bounce
    await _scaleController.forward();
    _scaleController.reverse();

    // Streak
    setState(() => _streak++);
    _streakTimer?.cancel();
    _streakTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _glowController.reverse();
        setState(() => _streak = 0);
      }
    });
    if (_streak > 1) _glowController.forward();

    // Hearts
    _spawnHearts();

    // Firebase
    await _fb.sendMissYou(
      groupId: widget.groupId,
      senderName: widget.senderName,
    );
  }

  void _spawnHearts() {
    final emojis = ['💕', '💗', '💖', '💘', '💝', '✨'];
    final count = 2 + _streak.clamp(0, 4);
    for (int i = 0; i < count; i++) {
      final heart = _FloatingHeart(
        emoji: emojis[_random.nextInt(emojis.length)],
        controller: AnimationController(
          vsync: this,
          duration: Duration(milliseconds: 700 + _random.nextInt(500)),
        ),
        dx: (_random.nextDouble() - 0.5) * 80,
        endDy: -50 - _random.nextDouble() * 40,
        size: 12 + _random.nextDouble() * 8,
      );
      heart.controller.forward().then((_) {
        heart.controller.dispose();
        if (mounted) setState(() => _hearts.remove(heart));
      });
      setState(() => _hearts.add(heart));
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _counterController.dispose();
    _glowController.dispose();
    _countSub?.cancel();
    _streakTimer?.cancel();
    for (final h in _hearts) {
      h.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final btnColor = widget.theme.promptButtonColor;
    final opacity = widget.enabled ? 1.0 : 0.4;

    return Opacity(
      opacity: opacity,
      child: SizedBox(
        height: 36,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Floating hearts
            ..._hearts.map(
              (h) => AnimatedBuilder(
                animation: h.controller,
                builder: (context, child) {
                  final t = h.controller.value;
                  final curvedT = Curves.easeOut.transform(t);
                  return Positioned(
                    left: 20 + h.dx * curvedT,
                    bottom: 18 + (-h.endDy * curvedT),
                    child: Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: Text(h.emoji, style: TextStyle(fontSize: h.size)),
                    ),
                  );
                },
              ),
            ),

            // Button
            AnimatedBuilder(
              animation: Listenable.merge([_scaleAnimation, _glowAnimation]),
              builder: (context, child) {
                final tapScale = _scaleAnimation.value;
                final glow = _glowAnimation.value;

                return Transform.scale(
                  scale: tapScale,
                  child: GestureDetector(
                    onTap: _onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: btnColor.withOpacity(0.13 + glow * 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: btnColor.withOpacity(0.15 + glow * 0.2),
                        ),
                        boxShadow: glow > 0
                            ? [
                                BoxShadow(
                                  color: Colors.orange.withOpacity(glow * 0.25),
                                  blurRadius: 10,
                                  spreadRadius: glow * 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('💌', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 4),
                          Text(
                            s.iMissYou,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: btnColor,
                            ),
                          ),
                          // Counter
                          if (_totalCount > 0) ...[
                            const SizedBox(width: 4),
                            AnimatedBuilder(
                              animation: _counterAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _counterAnimation.value,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: btnColor.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$_displayedCount',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: btnColor,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Streak fire badge
            if (_streak > 1)
              Positioned(
                top: 0,
                right: -6,
                child: AnimatedBuilder(
                  animation: _glowAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 0.5 + _glowAnimation.value * 0.5,
                      child: Opacity(
                        opacity: _glowAnimation.value,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B35), Color(0xFFFF3D00)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Text(
                            '🔥$_streak',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FloatingHeart {
  final String emoji;
  final AnimationController controller;
  final double dx;
  final double endDy;
  final double size;

  _FloatingHeart({
    required this.emoji,
    required this.controller,
    required this.dx,
    required this.endDy,
    required this.size,
  });
}
