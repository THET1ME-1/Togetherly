import 'package:flutter/material.dart';

import '../services/app_icon_service.dart';

// Выбор иконки с 25.11.2026 живёт на своём экране
// (`lib/screens/settings/app_icon_screen.dart`), листа снизу больше нет. Здесь
// остались значок и помощники, их же берёт строка в настройках.

/// Значок «как на столе»: у рисунков — сама картинка, у тем — буквы «TY»
/// цветом темы на её фоне.
///
/// Показывает ровно то, что нарисовано в `mipmap`, поэтому цвета берутся из
/// той же таблицы, что и ассеты (`tool/gen_app_icons.py`), а картинка — из того
/// же файла, из которого сделаны launcher-иконки (`tool/gen_main_icon.py`).
class AppIconBadge extends StatelessWidget {
  const AppIconBadge({super.key, required this.option, this.size = 28});

  final AppIconOption option;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size * 0.22);
    final asset = option.asset;
    if (asset != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: option.background,
          borderRadius: radius,
          // У рисунка свой фон, кайма только отделяет его от похожей
          // подложки и не спорит с картинкой.
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        // Ассет 512x512 в плитке: разворачиваем в её размер, не в свой.
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: option.background,
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      alignment: Alignment.center,
      child: Text(
        'TY',
        style: TextStyle(
          fontFamily: 'Onest',
          fontSize: size * 0.42,
          height: 1.0,
          fontWeight: FontWeight.w600,
          color: option.letters,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Опция по id — с откатом на первую, чтобы неизвестное значение из prefs не
/// роняло экран.
AppIconOption appIconOptionOf(String id) => AppIconService.options.firstWhere(
  (o) => o.id == id,
  orElse: () => AppIconService.options.first,
);

String appIconNameOf(String id) {
  final o = appIconOptionOf(id);
  return o.name;
}
