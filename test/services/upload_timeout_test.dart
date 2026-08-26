import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/upload_timeout.dart';

/// Срок заливки считается от размера файла.
///
/// Пока он был жёсткими шестьюдесятью секундами, за тридцать дней 155 заливок
/// оборвались на полуслове — 93 из них картинки холста. Шестьдесят секунд на
/// мегабайтную картинку по мобильной сети не хватает, а на трёхсотмегабайтный
/// ролик их не хватает подавно.
void main() {
  group('uploadTimeoutFor', () {
    test('мелочь получает нижний порог, а не пропорцию', () {
      // Голосовое на 40 КБ ушло бы за секунду, но сеть бывает и такая, что
      // рукопожатие занимает полминуты.
      expect(uploadTimeoutFor(40 * 1024), kUploadTimeoutMin);
    });

    test('мегабайтам достаётся время на передачу', () {
      final t = uploadTimeoutFor(6 * 1024 * 1024);
      expect(t, greaterThan(kUploadTimeoutMin));
      expect(t, const Duration(seconds: 60 + 6 * 15));
    });

    test('срок растёт вместе с файлом', () {
      expect(
        uploadTimeoutFor(20 * 1024 * 1024),
        greaterThan(uploadTimeoutFor(5 * 1024 * 1024)),
      );
    });

    test('у потолка есть предел — заливка не висит вечно', () {
      expect(uploadTimeoutFor(300 * 1024 * 1024), kUploadTimeoutMax);
    });

    test('пустой файл не даёт нулевого срока', () {
      expect(uploadTimeoutFor(0), kUploadTimeoutMin);
    });
  });

  group('uploadWorthRetry', () {
    test('обрыв по сроку стоит повторить', () {
      expect(uploadWorthRetry(408), isTrue);
      expect(uploadWorthRetry(null), isTrue);
    });

    test('отказ сервера повторять бессмысленно', () {
      // Ни протухшая сессия, ни запрет доступа, ни слишком большой файл со
      // второй попытки не изменятся.
      expect(uploadWorthRetry(401), isFalse);
      expect(uploadWorthRetry(403), isFalse);
      expect(uploadWorthRetry(400), isFalse);
      expect(uploadWorthRetry(413), isFalse);
    });

    test('сервер прилёг — вторая попытка уместна', () {
      expect(uploadWorthRetry(502), isTrue);
      expect(uploadWorthRetry(503), isTrue);
    });

    test('слишком частые запросы повторяем, но не мгновенно', () {
      expect(uploadWorthRetry(429), isTrue);
    });
  });
}
