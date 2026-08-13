import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/update_service.dart';

void main() {
  group('updateNotesFrom', () {
    test('берёт заметки новой версии из version.json', () {
      // Попап звал обновиться и показывал заметки УСТАНОВЛЕННОЙ сборки — они
      // зашиты в неё константой. Человек видел один и тот же список раз за
      // разом: «второй или третий раз вижу» (13 августа 2026).
      final notes = updateNotesFrom(
        {'notes': '— Своё настроение\n— Пуши на Android'},
        russian: true,
        fallback: 'старый список',
      );

      expect(notes, '— Своё настроение\n— Пуши на Android');
    });

    test('на английском берёт свою колонку', () {
      final notes = updateNotesFrom(
        {'notes': 'русский текст', 'notesEn': 'english text'},
        russian: false,
        fallback: 'fallback',
      );

      expect(notes, 'english text');
    });

    test('английских заметок нет — показываем русские, а не заглушку', () {
      final notes = updateNotesFrom(
        {'notes': 'русский текст'},
        russian: false,
        fallback: 'fallback',
      );

      expect(notes, 'русский текст');
    });

    test('старый релиз без заметок — прежний текст из сборки', () {
      // version.json прошлых релизов поля не знает, и попап не должен
      // остаться пустым.
      final notes = updateNotesFrom(
        {'versionCode': 190},
        russian: true,
        fallback: 'старый список',
      );

      expect(notes, 'старый список');
    });

    test('пустая строка считается отсутствием заметок', () {
      final notes = updateNotesFrom(
        {'notes': '   '},
        russian: true,
        fallback: 'старый список',
      );

      expect(notes, 'старый список');
    });
  });
}
