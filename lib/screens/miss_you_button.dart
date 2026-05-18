import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Кнопка «Я скучаю» — соревновательный режим.
///
/// Архитектура состояния:
///   _myCount      — последнее подтверждённое значение из Firebase
///   _partnerCount — то же для партнёра
///   _inFlightTaps — тапы, отправленные в Firebase но ещё не подтверждённые
///
/// Отображаемое значение = _myCount + _inFlightTaps.
/// При подтверждении Firebase delta вычитается из _inFlightTaps.
/// При ошибке записи — _inFlightTaps откатывается.
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

  // -- Подтверждённые Firebase-счётчики --
  int _myCount = 0;
  int _partnerCount = 0;
  StreamSubscription? _countSub;

  // -- Тапы в полёте (отправлены, но Firebase ещё не подтвердил) --
  int _inFlightTaps = 0;

  // -- Fill ratio animation (value = ratio, 0..1) --
  late AnimationController _fillController;

  // -- Scale animation (bounce при тапе) --
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  // -- Floating hearts --
  final List<_FloatingHeart> _hearts = [];
  final _random = Random();

  @override
  void initState() {
    super.initState();

    _fillController = AnimationController(
      vsync: this,
      value: 0.5,
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.92)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 82,
      ),
    ]).animate(_scaleController);

    _startListening();
  }

  @override
  void didUpdateWidget(covariant MissYouButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId) {
      _countSub?.cancel();
      _inFlightTaps = 0;
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
        final newMyCount = counts[myUid] ?? 0;
        final newPartnerCount = counts.entries
            .where((e) => e.key != myUid)
            .fold(0, (sum, e) => sum + e.value);

        // Вычитаем из _inFlightTaps подтверждённую дельту
        final confirmed = newMyCount - _myCount;
        if (confirmed > 0) {
          _inFlightTaps = max(0, _inFlightTaps - confirmed);
        }

        _myCount = newMyCount;
        _partnerCount = newPartnerCount;

        // Анимируем с учётом оставшихся in-flight тапов
        _animateToCurrentRatio();

        if (mounted) setState(() {});
      },
    );
  }

  /// Вычисляет ратио на основе (_myCount + _inFlightTaps) и анимирует к нему.
  void _animateToCurrentRatio() {
    final displayMy = _myCount + _inFlightTaps;
    final total = displayMy + _partnerCount;
    final ratio = total == 0 ? 0.5 : (displayMy / total).clamp(0.0, 1.0);
    _fillController.animateTo(
      ratio,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _onTap() async {
    if (!widget.enabled || widget.groupId.isEmpty) return;
    HapticFeedback.mediumImpact();
    _scaleController.forward(from: 0);
    _spawnHearts();

    // Оптимистичный инкремент — немедленно показываем результат
    _inFlightTaps++;
    _animateToCurrentRatio();
    if (mounted) setState(() {});

    try {
      await _fb.sendMissYou(
        groupId: widget.groupId,
        senderName: widget.senderName,
      );
      // Firebase-снимок придёт через _startListening и сам вычтет из _inFlightTaps.
      // Здесь ничего не делаем, чтобы избежать двойного декремента.
    } catch (_) {
      // Запись упала — откатываем in-flight тап
      if (mounted) {
        setState(() => _inFlightTaps = max(0, _inFlightTaps - 1));
        _animateToCurrentRatio();
      }
    }
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
    _fillController.dispose();
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
    // Для отображения счётчика показываем оптимистичное значение
    final displayMy = _myCount + _inFlightTaps;
    final total = displayMy + _partnerCount;
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
              builder: (_, child) {
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
              child: AnimatedBuilder(
                animation: _fillController,
                builder: (_, child) {
                  final ratio = _fillController.value;
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
                                  btnColor.withValues(alpha: 0.78),
                                  btnColor.withValues(alpha: 0.28),
                                ],
                              )
                            : null,
                        color: hasData
                            ? null
                            : btnColor.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: btnColor
                              .withValues(alpha: hasData ? 0.0 : 0.22),
                        ),
                        boxShadow: hasData
                            ? [
                                BoxShadow(
                                  color: btnColor.withValues(alpha: 0.18),
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
                            count: displayMy,
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
        ? Colors.white.withValues(alpha: 0.20)
        : color.withValues(alpha: 0.12);

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
