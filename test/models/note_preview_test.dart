import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/note_preview.dart';

/// Превью заметки в каталоге виджетов.
///
/// Жалоба 20.09.2026: «Текст на заметке в приложении не меняется». И не мог:
/// в превью был зашит демонстрационный текст про молоко, а настоящая заметка
/// живёт в ключе `note_<группа>_text` и туда не попадала вовсе.
void main() {
  test('написанную заметку показываем как есть', () {
    expect(notePreviewText('Спасибо', demo: 'молоко'), 'Спасибо');
  });

  test('пустая заметка — показываем образец, а не пустой листик', () {
    expect(notePreviewText('', demo: 'молоко'), 'молоко');
    expect(notePreviewText('   ', demo: 'молоко'), 'молоко');
  });

  test('пробелы по краям не уезжают в виджет', () {
    expect(notePreviewText('  Спасибо  ', demo: 'молоко'), 'Спасибо');
  });

  test('в превью каталога нет зашитого текста заметки', () {
    final src = File('lib/screens/widget_screen.dart').readAsStringSync();
    expect(src.contains('Купи молоко'), isFalse,
        reason: 'демо-текст перекрывал настоящую заметку');
    expect(src.contains('_noteText'), isTrue,
        reason: 'превью обязано читать настоящую заметку');
  });
}
