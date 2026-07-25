// Разметки виджетов рабочего стола инфлейтит RemoteViews, а он принимает не
// любой View, а только классы из своего белого списка. Всё остальное даёт
// InflateException уже на устройстве: лончер рисует серую плашку
// «Невозможно загрузить виджет», и понять причину без logcat невозможно.
//
// Так уже случилось: в четырёх новых разметках стояла распорка <Space>, и ни
// один новый виджет не вставал на рабочий стол. Тест ловит это на CI.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Классы, помеченные @RemoteView в Android SDK, — только их разрешено
/// инфлейтить в виджете. Список из документации RemoteViews.
const _allowed = {
  // Контейнеры
  'FrameLayout',
  'GridLayout',
  'LinearLayout',
  'RelativeLayout',
  // Адаптерные
  'AdapterViewFlipper',
  'GridView',
  'ListView',
  'StackView',
  'ViewFlipper',
  // Виджеты
  'AnalogClock',
  'Button',
  'Chronometer',
  'ImageButton',
  'ImageView',
  'ProgressBar',
  'TextClock',
  'TextView',
  // Служебное
  'ViewStub',
  'merge',
  'include',
  'requestFocus',
};

/// Разметки, которые попадают в RemoteViews: у каждой есть свой
/// appwidget-provider в res/xml.
List<File> _widgetLayouts() {
  final xmlDir = Directory('android/app/src/main/res/xml');
  final layoutDir = Directory('android/app/src/main/res/layout');
  if (!xmlDir.existsSync() || !layoutDir.existsSync()) return const [];

  final names = <String>{};
  final re = RegExp(r'android:(?:initialLayout|previewLayout)="@layout/(\w+)"');
  for (final f in xmlDir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.xml')) continue;
    final text = f.readAsStringSync();
    if (!text.contains('<appwidget-provider')) continue;
    for (final m in re.allMatches(text)) {
      names.add(m.group(1)!);
    }
  }

  return names
      .map((n) => File('${layoutDir.path}/$n.xml'))
      .where((f) => f.existsSync())
      .toList();
}

void main() {
  test('в разметках виджетов только классы из белого списка RemoteViews', () {
    final layouts = _widgetLayouts();
    expect(layouts, isNotEmpty,
        reason: 'не нашлось ни одной разметки виджета — проверь пути');

    final tag = RegExp(r'<([A-Za-z][\w.]*)');
    final violations = <String>[];

    for (final file in layouts) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Комментарии и XML-декларация — не теги.
        if (line.trimLeft().startsWith('<!--') ||
            line.trimLeft().startsWith('<?')) {
          continue;
        }
        for (final m in tag.allMatches(line)) {
          final name = m.group(1)!;
          if (_allowed.contains(name)) continue;
          final short = file.uri.pathSegments.last;
          violations.add('$short:${i + 1} — <$name>');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'RemoteViews не умеет инфлейтить эти классы, на рабочем столе '
          'будет «Невозможно загрузить виджет»:\n${violations.join('\n')}',
    );
  });

  test('у каждого appwidget-provider есть previewImage', () {
    // Лончеры без поддержки previewLayout (в том числе MIUI) без картинки
    // не показывают виджет в списке вовсе.
    final dir = Directory('android/app/src/main/res/xml');
    if (!dir.existsSync()) return;

    final missing = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.xml')) continue;
      final text = f.readAsStringSync();
      if (!text.contains('<appwidget-provider')) continue;
      if (!text.contains('android:previewImage=')) {
        missing.add(f.uri.pathSegments.last);
      }
    }

    expect(missing, isEmpty,
        reason: 'без previewImage виджет не появится в списке: $missing');
  });
}
