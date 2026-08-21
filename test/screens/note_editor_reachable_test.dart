import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Общая заметка пары: где её вообще можно написать.
///
/// Жалоба 21.08.2026: «куда написать, чтобы у партнёра было видно запись?
/// никак не могу найти». И правда: лист правки открывался ТОЛЬКО тапом по
/// виджету на рабочем столе (`loveapp://note`), а внутри приложения входа не
/// было вовсе. На Android тап открывает свою активность и всё выглядит
/// рабочим; на iPhone человек остаётся ни с чем — и ищет в приложении, где
/// искать нечего.
void main() {
  test('лист заметки открывается не только из виджета', () {
    final calls = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final text = file.readAsStringSync();
      if (!text.contains('showNoteEditorSheet(')) continue;
      if (file.path.endsWith('note_editor_sheet.dart')) continue; // объявление
      calls.add(file.path);
    }
    expect(
      calls.length,
      greaterThanOrEqualTo(2),
      reason: 'кроме перехода с виджета нужен вход из самого приложения, '
          'иначе заметку не найти: $calls',
    );
  });
}
