import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;

import '../dict_strings.dart' show trKey;
import '../services/locale_service.dart';
import '../theme/fonts.dart';
import 'app_sheet.dart';

const _widgetsChannel = MethodChannel('love_app/widgets');

/// Открывает лист «Виджет не появился»; на Xiaomi с кнопкой в окно
/// разрешений приложения. Зовут все места, где приложение просит лончер
/// поставить виджет: каталог виджетов и галерея рисунков.
Future<void> showWidgetPinHelp(BuildContext context) async {
  var xiaomi = false;
  try {
    xiaomi = await _widgetsChannel.invokeMethod<bool>('isXiaomiLauncher') ?? false;
  } catch (_) {}
  if (!context.mounted) return;
  await showAppSheet<void>(
    context,
    builder: (ctx) => WidgetPinHelpSheet(
      xiaomi: xiaomi,
      onOpenSettings: () {
        Navigator.of(ctx).pop();
        unawaited(_widgetsChannel
            .invokeMethod<bool>('openWidgetPermission')
            .catchError((_) => false));
      },
    ),
  );
}

/// Лист «Виджет не появился»: лончер молча не поставил виджет.
///
/// Обращения 25.11.2026 (Android, 1.44): «добавляю на рабочий стол, а ничего
/// не появляется». Чаще всего это Xiaomi без разрешения «Ярлыки на рабочем
/// столе». Лист даёт два выхода: поставить виджет руками с рабочего стола и,
/// на Xiaomi, открыть окно разрешений приложения ([onOpenSettings]).
class WidgetPinHelpSheet extends StatelessWidget {
  const WidgetPinHelpSheet({super.key, required this.xiaomi, this.onOpenSettings});

  final bool xiaomi;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = AppFonts.onest(size: 15, height: 1.4, color: scheme.onSurfaceVariant);
    return SheetScaffold(
      title: trKey('widgetPinSilentTitle'),
      bottom: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          key: const ValueKey('widget-pin-help-ok'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleService.current.gotIt),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(trKey('widgetPinSilentManual'), style: text),
            if (xiaomi) ...[
              const SizedBox(height: 12),
              Text(trKey('widgetPinXiaomiHint'), style: text),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('widget-pin-help-settings'),
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_rounded, size: 20),
                  label: Text(trKey('widgetPinOpenSettings')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
