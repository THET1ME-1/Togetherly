import 'package:flutter/material.dart';

import '../services/app_icon_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import 'app_sheet.dart';

/// Лист «Иконка приложения»: основная (рисунок) плюс тринадцать значков под
/// темы Togetherly.
///
/// Жил внутри профиля и пропал при переезде настроек на отдельный экран: строку
/// вырезали вместе со старой вёрсткой блоков, а в новый экран не перенесли.
/// Сервис, значки и alias'ы в манифесте при этом остались на месте — не хватало
/// только входа.
///
/// Возвращает id выбранной иконки или null, если человек ничего не менял.
Future<String?> showAppIconSheet(
  BuildContext context, {
  required AppTheme theme,
  required String currentId,
}) {
  // Тему снимаем ДО открытия: лист живёт в дереве навигатора и переживает
  // экран, а обращение к состоянию мёртвого экрана уже давало падения.
  final scheme = ProfileTheme.themeFor(theme).colorScheme;

  return showAppSheet<String>(
    context,
    background: scheme.surfaceContainer,
    builder: (_) => _AppIconBody(scheme: scheme, currentId: currentId),
  );
}

/// Значок «как на столе»: у основной иконки — сама картинка, у тем — буквы
/// «TY» цветом темы на её фоне.
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
          border: Border.all(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        // Ассет 512x512 в плитке 60: разворачиваем в её размер, не в свой.
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

class _AppIconBody extends StatefulWidget {
  const _AppIconBody({required this.scheme, required this.currentId});

  final ColorScheme scheme;
  final String currentId;

  @override
  State<_AppIconBody> createState() => _AppIconBodyState();
}

class _AppIconBodyState extends State<_AppIconBody> {
  late String _selected = widget.currentId;
  bool _busy = false;

  /// Отказ показываем полосой внутри листа, а не снекбаром: снекбар уезжает
  /// ПОД лист, и любая неудача выглядит как мёртвая кнопка.
  String? _error;

  Future<void> _apply(String id) async {
    if (_busy) return;
    if (id == _selected) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await AppIconService.instance.setIcon(id);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = LocaleService.current.appIconChangeFailed;
      });
      return;
    }
    setState(() {
      _busy = false;
      _selected = id;
    });
    Navigator.of(context).maybePop(id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final s = LocaleService.current;
    final ru = LocaleService.instance.isRussian;

    return SheetScaffold(
      title: s.appIconTitle,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.appIconUpdateHint,
              // Шрифт задаём явно: лист живёт в дереве навигатора и текстовую
              // тему экрана не наследует — без этого подписи уходят в
              // системный шрифт.
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                for (final o in AppIconService.options) _choice(o, ru, scheme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice(AppIconOption o, bool ru, ColorScheme scheme) {
    final selected = o.id == _selected;
    return InkWell(
      onTap: _busy ? null : () => _apply(o.id),
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                // Обводка повторяет форму значка, а не круг: внешний радиус =
                // радиус иконки плюс отступ.
                borderRadius: BorderRadius.circular(60 * 0.22 + 3),
                border: Border.all(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: AppIconBadge(option: o, size: 60),
            ),
            const SizedBox(height: 6),
            Text(
              o.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
