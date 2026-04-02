import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Кнопка «Я скучаю» — соревновательный режим.
/// • Слева — мой счётчик, справа — счётчик партнёра
/// • Заливка как у дня в мини-календаре: мой цвет слева, цвет партнёра справа
/// • Анимация нажатия (scale bounce) + летящие сердечки
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

  // -- Per-user counters --
  int _myCount = 0;
  int _partnerCount = 0;
  StreamSubscription? _countSub;

  // -- Fill ratio animation --
  double _prevRatio = 0.5;
  double _currentRatio = 0.5;

  // -- Scale animation --
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  // -- Floating hearts --
  final List<_FloatingHeart> _hearts = [];
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.90,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
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
    _countSub = _fb.listenToMissYouCounts(
      groupId: widget.groupId,
      onData: (counts) {
        if (!mounted) return;
        final myUid = _fb.uid ?? '';
        final myC = counts[myUid] ?? 0;
        final partnerC = counts.entries
            .where((e) => e.key != myUid)
            .fold(0, (sum, e) => sum + e.value);
        final total = myC + partnerC;
        final newRatio = total == 0 ? 0.5 : (myC / total).clamp(0.0, 1.0);
        setState(() {
          _prevRatio = _currentRatio;
          _currentRatio = newRatio;
          _myCount = myC;
          _partnerCount = partnerC;
        });
      },
    );
  }

  Future<void> _onTap() async {
    if (!widget.enabled || widget.groupId.isEmpty) return;
    HapticFeedback.mediumImpact();
    await _scaleController.forward();
    _scaleController.reverse();
    _spawnHearts();
    await _fb.sendMissYou(
      groupId: widget.groupId,
      senderName: widget.senderName,
    );
  }

  void _spawnHearts() {
    final emojis = ['💕', '💗', '💖', '💘', '💝', '✨'];
    for (int i = 0; i < 3; i++) {
      final heart = _FloatingHeart(
        emoji: emojis[_random.nextInt(emojis.length)],
        controller: AnimationController(
          vsync: this,
          duration: Duration(milliseconds: 650 + _random.nextInt(450)),
        ),
        dx: (_random.nextDouble() - 0.5) * 70,
        endDy: -48 - _random.nextDouble() * 32,
        size: 11 + _random.nextDouble() * 8,
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
    _countSub?.cancel();
    for (final h in _hearts) {
      h.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final btnColor = widget.theme.promptButtonColor;
    final total = _myCount + _partnerCount;
    final hasData = total > 0;

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.4,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // -- Floating hearts --
          ..._hearts.map(
            (h) => AnimatedBuilder(
              animation: h.controller,
              builder: (_, __) {
                final t = h.controller.value;
                final ct = Curves.easeOut.transform(t);
                return Positioned(
                  left: 20 + h.dx * ct,
                  bottom: 22 + (-h.endDy * ct),
                  child: Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: Text(h.emoji, style: TextStyle(fontSize: h.size)),
                  ),
                );
              },
            ),
          ),

          // -- Main button --
          AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (_, child) =>
                Transform.scale(scale: _scaleAnimation.value, child: child),
            child: GestureDetector(
              onTap: _onTap,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_currentRatio),
                tween: Tween(begin: _prevRatio, end: _currentRatio),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOut,
                builder: (_, ratio, __) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: hasData
                            ? LinearGradient(
                                stops: [ratio, ratio],
                                colors: [
                                  btnColor.withOpacity(0.78),
                                  btnColor.withOpacity(0.28),
                                ],
                              )
                            : null,
                        color: hasData ? null : btnColor.withOpacity(0.11),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: btnColor.withOpacity(hasData ? 0.0 : 0.22),
                        ),
                        boxShadow: hasData
                            ? [
                                BoxShadow(
                                  color: btnColor.withOpacity(0.18),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CountBadge(
                            count: _myCount,
                            color: btnColor,
                            hasData: hasData,
                            isOnDarkSide: hasData && ratio > 0.15,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            s.iMissYou,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: hasData ? Colors.white : btnColor,
                            ),
                          ),
                          const SizedBox(width: 7),
                          _CountBadge(
                            count: _partnerCount,
                            color: btnColor,
                            hasData: hasData,
                            isOnDarkSide: hasData && ratio > 0.85,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  final bool hasData;
  final bool isOnDarkSide;

  const _CountBadge({
    required this.count,
    required this.color,
    required this.hasData,
    required this.isOnDarkSide,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isOnDarkSide ? Colors.white : color;
    final bgColor = isOnDarkSide
        ? Colors.white.withOpacity(0.20)
        : color.withOpacity(0.12);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: textColor,
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
