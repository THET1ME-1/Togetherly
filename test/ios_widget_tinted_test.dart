import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож тонированных виджетов iOS.
///
/// В настройке экрана «Домой» есть режимы «Прозрачные» и «Однотонные»: система
/// перекрашивает всё содержимое виджета одним цветом по своей подложке. Наши
/// заливки при этом ложились ПОВЕРХ текста, и на видео тестера (13 августа
/// 2026) виджеты Togetherly выглядели пустыми белыми формами — ни чисел, ни
/// подписей. Лечится тем, что в этих режимах фон рисует система, а не мы.
///
/// Проверить это на Linux нечем: Xcode здесь нет, а расплата за пропуск — ещё
/// один релиз с пустыми виджетами. Поэтому сторожим исходники.
void main() {
  final dir = Directory('ios/TogetherlyWidget');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.swift'))
      .toList();

  String read(String name) =>
      File('ios/TogetherlyWidget/$name').readAsStringSync();

  test('фон виджета зависит от режима отрисовки', () {
    final theme = read('WidgetTheme.swift');
    expect(theme.contains(r'@Environment(\.widgetRenderingMode)'), isTrue,
        reason: 'Общий фон обязан спрашивать режим отрисовки');
    expect(theme.contains('containerBackground(.clear, for: .widget)'), isTrue,
        reason: 'В тонированном режиме фон отдаём системе');
  });

  test('никто не заливает фон мимо адаптивных хелперов', () {
    // Прямой `containerBackground(<цвет>)` вне модификатора означает заливку,
    // которую система покрасит поверх текста.
    final offenders = <String>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.contains('containerBackground(')) continue;
        if (line.startsWith('//') || line.startsWith('///')) continue;
        // Внутри самих модификаторов вызов законен: там уже проверен режим.
        final isInsideModifier = line.startsWith('content.');
        final isClear = line.contains('.clear');
        if (isInsideModifier || isClear) continue;
        offenders.add('$name:${i + 1}: $line');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Заливка мимо режима отрисовки:\n${offenders.join('\n')}');
  });

  test('фотографии остаются цветными в тонированном режиме', () {
    final theme = read('WidgetTheme.swift');
    expect(theme.contains('widgetAccentedRenderingMode(.fullColor)'), isTrue,
        reason: 'Иначе фото партнёра превращается в силуэт');
    final photos = read('PhotoWidgets.swift');
    expect(photos.contains('tgFullColorImage()'), isTrue);
  });

  test('пустой фото-виджет называет себя, а не соседа', () {
    final photos = read('PhotoWidgets.swift');
    // Подпись «Фото дня» жила в общем плейсхолдере, поэтому в галерее её видели
    // и у «Фото партнёра», и у «Моего фото».
    expect(photos.contains('enum PhotoWidgetKind'), isTrue);
    for (final kind in ['kind: .mine', 'kind: .partner', 'kind: .day']) {
      expect(photos.contains(kind), isTrue, reason: 'Нет вида $kind');
    }
    final hardcoded = RegExp(r'Text\("Фото дня"\)').allMatches(photos).length;
    expect(hardcoded, 0,
        reason: 'Подпись пустого состояния берётся из вида виджета');
  });
}
