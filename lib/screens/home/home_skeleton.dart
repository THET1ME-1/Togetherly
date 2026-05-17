import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Skeleton shimmer — пульсирующий прямоугольник-заглушка
// ─────────────────────────────────────────────────────────────────────────────

class _Shimmer extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final bool circle;

  const _Shimmer({
    this.width = double.infinity,
    required this.height,
    this.radius = 12,
    this.circle = false,
  });

  const _Shimmer.circle({required double size})
      : width = size,
        height = size,
        radius = 999,
        circle = true;

  @override
  Widget build(BuildContext context) {
    final base = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(circle ? height / 2 : radius),
      ),
    );

    return base
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1200.ms,
          delay: 200.ms,
          color: const Color(0xFFF3F4F6),
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Скелетон шапки (HomeHeader)
// ─────────────────────────────────────────────────────────────────────────────

class HomeSkeletonHeader extends StatelessWidget {
  const HomeSkeletonHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
      child: Row(
        children: [
          // Два кружка-аватара, стопка
          SizedBox(
            width: 28 + 40.0,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned(
                  left: 0,
                  top: 4,
                  child: _Shimmer.circle(size: 40),
                ),
                const Positioned(
                  left: 28,
                  top: 4,
                  child: _Shimmer.circle(size: 40),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Бейдж статуса
          const _Shimmer(width: 110, height: 34, radius: 100),
          const Spacer(),
          // Кнопка «скучаю»
          const _Shimmer(width: 90, height: 34, radius: 100),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Скелетон тела главного экрана (HomeBody)
// ─────────────────────────────────────────────────────────────────────────────

class HomeSkeletonBody extends StatelessWidget {
  const HomeSkeletonBody({super.key});

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: safeBottom + 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ── Mini Mood Calendar ─────────────────────────────────────
                _SkeletonMiniCalendar(),
                const SizedBox(height: 8),

                // ── Expandable Timer Card (большой круг) ───────────────────
                _SkeletonTimerCard(),

                // ── 4 кнопки действий ──────────────────────────────────────
                _SkeletonActionButtons(),

                const SizedBox(height: 8),

                // ── Строчка маскота / connect ───────────────────────────────
                _SkeletonMascotRow(),

                const SizedBox(height: 40),
              ],
            ),
          ),

          // ── Memory Lane Preview ────────────────────────────────────────────
          _SkeletonMemoryLane(),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Мини-календарь настроений: ряд пилюль 74×118
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonMiniCalendar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      child: Row(
        children: List.generate(5, (i) {
          // Небольшая задержка у каждого столбца для волнового эффекта
          final delay = (i * 80).ms;
          return Padding(
            padding: EdgeInsets.only(right: i < 4 ? 10 : 0),
            child: Container(
              width: 74,
              height: 118,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(100),
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .shimmer(
                  duration: 1200.ms,
                  delay: delay + 200.ms,
                  color: const Color(0xFFF3F4F6),
                ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Таймер-карточка: большой круг, почти на всю ширину
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonTimerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final innerW = screenW - 48; // horizontal padding 24+24
    final dialSize = innerW * 0.95;
    final containerH = dialSize + 55;

    return SizedBox(
      height: containerH,
      child: Center(
        child: Container(
          width: dialSize,
          height: dialSize,
          decoration: const BoxDecoration(
            color: Color(0xFFE5E7EB),
            shape: BoxShape.circle,
          ),
        )
            .animate(onPlay: (c) => c.repeat())
            .shimmer(
              duration: 1200.ms,
              delay: 300.ms,
              color: const Color(0xFFF3F4F6),
            ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  4 кнопки: пилюли 74×118, две средние смещены вниз на 11
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonActionButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final dy = (i == 1 || i == 2) ? 11.0 : 0.0;
        final delay = (i * 60).ms;
        return Padding(
          padding: EdgeInsets.only(right: i < 3 ? 10 : 0),
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Container(
              width: 74,
              height: 118,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(100),
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .shimmer(
                  duration: 1200.ms,
                  delay: delay + 400.ms,
                  color: const Color(0xFFF3F4F6),
                ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Строка маскота: левый кружок + две текстовых линии + стрелка
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonMascotRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Кружок маскота
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFE5E7EB),
              shape: BoxShape.circle,
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                duration: 1200.ms,
                delay: 500.ms,
                color: const Color(0xFFF3F4F6),
              ),
          const SizedBox(width: 12),
          // Две строки текста
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Shimmer(height: 13, radius: 6),
                const SizedBox(height: 6),
                const _Shimmer(width: 80, height: 11, radius: 6),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Иконка стрелки
          const _Shimmer(width: 20, height: 20, radius: 4),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1200.ms,
          delay: 500.ms,
          color: const Color(0xFFF3F4F6),
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Memory Lane Preview: заголовок + 3 карточки
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonMemoryLane extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок + кнопка "показать все"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _Shimmer(width: 120, height: 20, radius: 6),
              const _Shimmer(width: 70, height: 20, radius: 6),
            ],
          ),
          const SizedBox(height: 16),
          // 3 карточки памяти
          ...List.generate(3, (i) {
            final delay = (600 + i * 80).ms;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(20),
                ),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .shimmer(
                    duration: 1200.ms,
                    delay: delay,
                    color: const Color(0xFFF3F4F6),
                  ),
            );
          }),
        ],
      ),
    );
  }
}
