import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/partner_note.dart';

/// TOG-13: заметка партнёра обновлялась только после перезахода. Событие
/// карточки партнёра обновляло парный виджет, а текст заметки лежал в
/// хранилище виджетов до полной синхронизации на входе в приложение.
void main() {
  test('подпись заметки — текст и время', () {
    expect(
      noteSignatureOf({
        'data': {
          'note': {'text': 'Купи молоко', 'author': 'Аня', 'at': 5},
        },
      }),
      'Купи молоко|5',
    );
  });

  test('нет заметки или кривые данные — пустая подпись', () {
    expect(noteSignatureOf({}), '');
    expect(noteSignatureOf({'data': {}}), '');
    expect(noteSignatureOf({'data': 'мусор'}), '');
    expect(noteSignatureOf({'data': {'note': 'мусор'}}), '');
  });

  test('заметка партнёра обновляется по его событию', () {
    final src = File('lib/services/widget_service.dart').readAsStringSync();
    final start = src.indexOf('void listenToPartner(String partnerUid) {');
    final body = src.substring(start, src.indexOf('\n  }\n', start));
    expect(body, contains('noteSignatureOf('));
    expect(body, contains('refreshNote('));
  });

  test('лист правки подтягивает свежую заметку', () {
    final src = File('lib/widgets/note_editor_sheet.dart').readAsStringSync();
    expect(src, contains('refreshNote('));
  });

  test('фоновое обновление виджетов обновляет и листик заметки', () {
    final src = File('lib/services/home_widget_service.dart').readAsStringSync();
    final start = src.indexOf('Future<void> backgroundRefreshAll({');
    final body = src.substring(start, src.indexOf('\n  }\n', start));
    expect(body, contains('_syncNoteFromCloud('));
  });
}
