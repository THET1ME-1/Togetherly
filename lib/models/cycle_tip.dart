import 'package:flutter/material.dart';

import '../services/locale_service.dart';

/// Совет на дни месячных.
///
/// Тексты живут в [AppStrings] (три места, как всё в проекте), здесь только
/// порядок и значки. Про лекарства нарочно без названий: приложение не врач, а
/// «выпей такое-то» из подсказки легко становится чужой ответственностью.
/// Совет про боль вместо препарата отправляет к врачу там, где это нужно.
class CycleTip {
  const CycleTip({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Семь советов в том порядке, в каком они нужны: сперва то, что снимает
  /// боль прямо сейчас, потом уход и еда, и в конце слова поддержки.
  static List<CycleTip> all(AppStrings s) => [
        CycleTip(
          icon: Icons.local_fire_department_rounded,
          title: s.cycleTipWarmTitle,
          body: s.cycleTipWarmBody,
        ),
        CycleTip(
          icon: Icons.thermostat_rounded,
          title: s.cycleTipFeetTitle,
          body: s.cycleTipFeetBody,
        ),
        CycleTip(
          icon: Icons.medication_liquid_rounded,
          title: s.cycleTipPainTitle,
          body: s.cycleTipPainBody,
        ),
        CycleTip(
          icon: Icons.shower_rounded,
          title: s.cycleTipShowerTitle,
          body: s.cycleTipShowerBody,
        ),
        CycleTip(
          icon: Icons.schedule_rounded,
          title: s.cycleTipChangeTitle,
          body: s.cycleTipChangeBody,
        ),
        CycleTip(
          icon: Icons.restaurant_rounded,
          title: s.cycleTipIronTitle,
          body: s.cycleTipIronBody,
        ),
        CycleTip(
          icon: Icons.favorite_rounded,
          title: s.cycleTipRestTitle,
          body: s.cycleTipRestBody,
        ),
      ];
}
