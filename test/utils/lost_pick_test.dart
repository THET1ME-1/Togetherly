import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:love_app/utils/lost_pick.dart';

// Жалоба 01.09.2026 (Юлия, realme C67, Android 14): «нажимаю „добавить“,
// выскакивает галерея, через 3-5 секунд, пока я выбираю снимки, меня выкидывает
// из приложения и вылезает окно Google Play».
//
// Приложение не падает — его убивает система, пока оно ждёт в фоне за открытым
// системным выбором фото. На бюджетных телефонах с ColorOS это обычное дело.
// Выбранный снимок при этом остаётся у плагина, и Android отдаёт его при
// следующем запуске — но забрать его было некому, поэтому фото просто
// пропадало, а человек видел чужое окно и решал, что приложение сломано.
//
// Решение о том, что делать с уцелевшим результатом, вынесено сюда: намерение
// («куда человек добавлял») переживает смерть процесса в настройках, а сам файл
// приходит от плагина.
void main() {
  group('lostPickFrom', () {
    test('файл вернулся и намерение известно — отдаём оба', () {
      final got = lostPickFrom(
        intent: 'memory',
        files: [XFile('/tmp/a.jpg')],
      );

      expect(got, isNotNull);
      expect(got!.intent, 'memory');
      expect(got.files.single.path, '/tmp/a.jpg');
    });

    test('несколько снимков доезжают все', () {
      final got = lostPickFrom(
        intent: 'memory',
        files: [XFile('/tmp/a.jpg'), XFile('/tmp/b.jpg')],
      );

      expect(got!.files, hasLength(2));
    });

    test('без файлов возвращать нечего', () {
      expect(lostPickFrom(intent: 'memory', files: const []), isNull);
    });

    test('файл есть, а намерение потеряно — молчим', () {
      // Куда его класть, неизвестно: подсунуть снимок в случайную форму хуже,
      // чем не подсунуть вовсе.
      expect(
        lostPickFrom(intent: null, files: [XFile('/tmp/a.jpg')]),
        isNull,
      );
    });

    test('чужое намерение не трогаем', () {
      // Аватар и обложку восстанавливает не этот путь: там своя форма и свои
      // правила обрезки.
      expect(
        lostPickFrom(
          intent: 'avatar',
          files: [XFile('/tmp/a.jpg')],
          accept: const {'memory'},
        ),
        isNull,
      );
    });
  });
}
