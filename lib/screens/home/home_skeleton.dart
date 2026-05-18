import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  InheritedWidget: передаёт primary-цвет темы вниз без prop-drilling
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonTheme extends InheritedWidget {
  final Color primary;

  const _SkeletonTheme({required this.primary, required super.child});

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonTheme>()?.primary ??
      const Color(0xFFE5E7EB);

  @override
  bool updateShouldNotify(_SkeletonTheme old) => old.primary != primary;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Skeleton shimmer — пульсирующий прямоугольник-заглушка
// ─────────────────────────────────────────────────────────────────────────────

class _Shimmer extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final bool circle;
  final Duration delay;

  const _Shimmer({
    this.width = double.infinity,
    required this.height,
    this.radius = 12,
    this.delay = Duration.zero,
  }) : circle = false;

  const _Shimmer.circle({required double size, this.delay = Duration.zero})
      : width = size,
        height = size,
        radius = 999,
        circle = true;

  @override
  Widget build(BuildContext context) {
    final primary = _SkeletonTheme.of(context);
    final baseColor = primary.withValues(alpha: 0.10);
    final shimmerColor = Colors.white.withValues(alpha: 0.75);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(circle ? height / 2 : radius),
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1400.ms,
          delay: delay + 200.ms,
          color: shimmerColor,
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Скелетон шапки (HomeHeader)
// ─────────────────────────────────────────────────────────────────────────────

class HomeSkeletonHeader extends StatelessWidget {
  final Color primary;

  const HomeSkeletonHeader({super.key, required this.primary});

  @override
  Widget build(BuildContext context) {
    return _SkeletonTheme(
      primary: primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
        child: Row(
          children: [
            // Два кружка-аватара, стопка
            SizedBox(
              width: 28 + 40.0,
              height: 48,
              child: Stack(
                clipBehavior: Clip.none,
                children: const [
                  Positioned(
                    left: 0,
                    top: 4,
                    child: _Shimmer.circle(size: 40, delay: Duration.zero),
                  ),
                  Positioned(
                    left: 28,
                    top: 4,
                    child: _Shimmer.circle(
                      size: 40,
                      delay: Duration(milliseconds: 80),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const _Shimmer(
              width: 110,
              height: 34,
              radius: 100,
              delay: Duration(milliseconds: 120),
            ),
            const Spacer(),
            const _Shimmer(
              width: 90,
              height: 34,
              radius: 100,
              delay: Duration(milliseconds: 160),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Скелетон тела главного экрана (HomeBody)
// ─────────────────────────────────────────────────────────────────────────────

class HomeSkeletonBody extends StatelessWidget {
  final Color primary;

  const HomeSkeletonBody({super.key, required this.primary});

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return _SkeletonTheme(
      primary: primary,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: safeBottom + 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SizedBox(height: 16),
                  _SkeletonMiniCalendar(),
                  SizedBox(height: 8),
                  _SkeletonTimerCard(),
                  _SkeletonActionButtons(),
                  SizedBox(height: 8),
                  _SkeletonMascotRow(),
                  SizedBox(height: 40),
                ],
              ),
            ),
            const _SkeletonMemoryLane(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Мини-календарь настроений: ряд пилюль
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonMiniCalendar extends StatelessWidget {
  const _SkeletonMiniCalendar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      child: Row(
        children: List.generate(5, (i) {
          return Padding(
            padding: EdgeInsets.only(right: i < 4 ? 10 : 0),
            child: _Shimmer(
              width: 74,
              height: 118,
              radius: 100,
              delay: Duration(milliseconds: i * 80),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Таймер-карточка: большой круг
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonTimerCard extends StatelessWidget {
  const _SkeletonTimerCard();

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final innerW = screenW - 48;
    final dialSize = innerW * 0.95;
    final containerH = dialSize + 55;

    return SizedBox(
      height: containerH,
      child: Center(
        child: _Shimmer.circle(
          size: dialSize,
          delay: const Duration(milliseconds: 150),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  4 кнопки действий
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonActionButtons extends StatelessWidget {
  const _SkeletonActionButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final dy = (i == 1 || i == 2) ? 11.0 : 0.0;
        return Padding(
          padding: EdgeInsets.only(right: i < 3 ? 10 : 0),
          child: Transform.translate(
            offset: Offset(0, dy),
            child: _Shimmer(
              width: 74,
              height: 118,
              radius: 100,
              delay: Duration(milliseconds: 250 + i * 60),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Строка маскота
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonMascotRow extends StatelessWidget {
  const _SkeletonMascotRow();

  @override
  Widget build(BuildContext context) {
    final primary = _SkeletonTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          _Shimmer.circle(
            size: 48,
            delay: Duration(milliseconds: 400),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Shimmer(
                  height: 13,
                  radius: 6,
                  delay: Duration(milliseconds: 420),
                ),
                SizedBox(height: 6),
                _Shimmer(
                  width: 80,
                  height: 11,
                  radius: 6,
                  delay: Duration(milliseconds: 440),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          _Shimmer(
            width: 20,
            height: 20,
            radius: 4,
            delay: Duration(milliseconds: 460),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Memory Lane Preview: заголовок + 3 карточки
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonMemoryLane extends StatelessWidget {
  const _SkeletonMemoryLane();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Shimmer(
                width: 120,
                height: 20,
                radius: 6,
                delay: Duration(milliseconds: 500),
              ),
              _Shimmer(
                width: 70,
                height: 20,
                radius: 6,
                delay: Duration(milliseconds: 540),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(3, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Shimmer(
                height: 88,
                radius: 20,
                delay: Duration(milliseconds: 580 + i * 80),
              ),
            );
          }),
        ],
      ),
    );
  }
}
