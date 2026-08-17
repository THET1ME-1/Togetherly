// Заметки к версии не должны приезжать кракозябрами.
//
// 17.08.2026 в окне «Доступно обновление» вместо русского текста стояло
// «â Ð Ð¸ÐÐ¶ÐµÑ Ñ Ð²ÐµÐ½Ñ». Причина: version.json лежит файлом релиза и
// отдаётся без charset в Content-Type, а пакет http в этом случае разбирает
// ответ как latin-1. Читать надо байты.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/update_service.dart';

void main() {
  const notes = 'Виджеты снова видны, чат больше не путает порядок';

  test('байты UTF-8 читаются верно', () {
    final bytes = utf8.encode(jsonEncode({'notes': notes}));
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(updateNotesFrom(data, russian: true, fallback: ''), notes);
  });

  test('разбор как latin-1 ломает текст — так и было в жалобе', () {
    final bytes = utf8.encode(jsonEncode({'notes': notes}));
    // Именно это делал пакет http, когда сервер не назвал кодировку.
    final broken = jsonDecode(latin1.decode(bytes)) as Map<String, dynamic>;
    expect(updateNotesFrom(broken, russian: true, fallback: ''), isNot(notes));
  });

  test('английские заметки берутся для нерусской локали', () {
    final data = {'notes': notes, 'notesEn': 'Widgets are back'};
    expect(updateNotesFrom(data, russian: false, fallback: ''), 'Widgets are back');
  });

  test('пустые заметки отдают запасной текст', () {
    expect(updateNotesFrom(const {}, russian: true, fallback: 'Что нового'),
        'Что нового');
  });
}
