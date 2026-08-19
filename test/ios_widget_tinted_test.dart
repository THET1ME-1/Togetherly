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

  test('пометку получает КАЖДАЯ картинка, а не только фото-виджеты', () {
    // Жалобы 19.08.2026 со снимками: на тонированной теме виджеты стоят
    // сплошными белыми (в тёмной — чёрными) прямоугольниками, а у настроений
    // «пишет какие эмоции отмечены, а стикеры не показывает». Так iOS 18 и
    // рисует картинку без `widgetAccentedRenderingMode(.fullColor)`: берёт её
    // альфу как маску и заливает цветом акцента. Непрозрачное фото при этом
    // превращается в залитый прямоугольник во весь виджет.
    final offenders = <String>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('Image(uiImage:')) continue;
        // Модификатор ставится сразу за resizable(), поэтому смотрим сам вызов
        // и три строки следом — цепочка бывает разбита переносами.
        final chain = lines.skip(i).take(4).join(' ');
        if (chain.contains('tgFullColorImage()')) continue;
        offenders.add('$name:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Картинка станет силуэтом на тонированной теме:\n'
            '${offenders.join('\n')}');
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

  test('сплошных подложек мимо адаптивных хелперов не осталось', () {
    // Тонированная тема выбрасывает наши цвета: всё, что не помечено
    // `widgetAccentable`, становится белым с сохранением альфы. Непрозрачная
    // подложка превращается в белый прямоугольник, а текст поверх — в такой
    // же белый. Снимки 19.08.2026: виджеты стоят пустыми формами, а на
    // обычной теме те же виджеты видны.
    const palette = {'WidgetTheme.swift', 'SharedStore.swift', 'WidgetGraphics.swift'};
    final offenders = <String>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      if (palette.contains(name)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//')) continue;
        final direct = RegExp(r'\.background\(\s*(Color|LinearGradient)')
            .hasMatch(line);
        final layer = RegExp(r'^(Color|LinearGradient)\(').hasMatch(line);
        // Объявление темы (`var gradient: LinearGradient { … }`) — не подложка:
        // сам градиент дальше уходит в адаптивный хелпер.
        final isDeclaration = i > 0 &&
            lines
                .sublist((i - 2).clamp(0, i), i)
                .any((prev) => prev.contains(': LinearGradient {'));
        if ((direct || layer) && !isDeclaration) {
          offenders.add('$name:${i + 1}: $line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Подложка съест собственный текст на тонированной теме:\n'
            '${offenders.join('\n')}');
  });

  test('у главного содержимого есть пометка акцента', () {
    // Без `widgetAccentable` весь виджет уходит в белую группу: на
    // тонированной теме он выглядит выцветшим и не берёт цвет, выбранный
    // человеком. Помечаем смысловой центр — числа, сердце, значки.
    final marked = files
        .where((f) => f.readAsStringSync().contains('widgetAccentable()'))
        .length;
    expect(marked, greaterThanOrEqualTo(6),
        reason: 'Пометку получили только $marked файлов из ${files.length}');
  });
}
