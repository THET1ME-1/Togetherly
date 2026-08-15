import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож личного вида холста.
///
/// Как человек держит лист — масштаб, сдвиг, поворот — его личное дело. Поворот
/// когда-то ехал к обоим через `canvas_meta.canvas_rotation`: партнёр развернул
/// лист щипком, и лист разворачивался у второго посреди его же мазка. Сперва
/// это сняли с раскрасок, где у каждого своя половина, а 15 августа 2026 — и с
/// общего холста, по жалобе «человек должен двигать холст локально».
///
/// Общими остаются штрихи, фон, очистка и раскраска: то, что видно в самом
/// рисунке. Колонка в базе осталась ради старых сборок — они в неё ещё пишут,
/// но читать её мы больше не читаем.
void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('поворот листа не уезжает партнёру', () {
    final offenders = <String>[];
    final sender = RegExp(r'setRotation\s*\(');

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      for (final match in sender.allMatches(source)) {
        final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Поворот листа личный — писать его в canvas_meta нельзя: '
          '${offenders.join(', ')}',
    );
  });

  test('чужой поворот листа не применяется', () {
    final offenders = <String>[];
    final reader = RegExp(r"canvas_rotation|rotationMilliRadians");

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      for (final match in reader.allMatches(source)) {
        // Упоминание в комментарии — не чтение поля.
        final lineStart = source.lastIndexOf('\n', match.start) + 1;
        final head = source.substring(lineStart, match.start).trimLeft();
        if (head.startsWith('//') || head.startsWith('///')) continue;
        final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Поворот листа партнёра читать нельзя — лист развернётся у '
          'человека посреди мазка: ${offenders.join(', ')}',
    );
  });
}
