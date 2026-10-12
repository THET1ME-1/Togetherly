import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/room_window.dart';
import 'package:love_app/services/watch_room_service.dart';

/// Комната на iPhone теряла касания у каждого четвёртого (замер 06–11.10.2026:
/// 430 заходов из 1331 без единого касания, на Android 8%). Три правки одного
/// механизма — Flutter 3.38.10, политика жестов, Flutter 3.47.6 — долю не
/// сдвинули. Пока комната встроена в экран Flutter, каждое касание сначала
/// проходит через него. Нативное окно убирает Flutter с пути пальца, а доля
/// людей, которым его открывать, приходит с сервера: так новое окно можно
/// сравнить со старым на живых людях и откатить без релиза.
void main() {
  group('доля с сервера', () {
    test('поля нет, оно пустое или кривое — нативное окно не открываем', () {
      expect(roomNativeShare(null), 0);
      expect(roomNativeShare(''), 0);
      expect(roomNativeShare('много'), 0);
      expect(roomNativeShare(false), 0);
    });

    test('число и строка с числом читаются одинаково', () {
      expect(roomNativeShare(20), 20);
      expect(roomNativeShare('35'), 35);
      expect(roomNativeShare(12.7), 12);
    });

    test('значение зажато в 0…100', () {
      expect(roomNativeShare(250), 100);
      expect(roomNativeShare(-5), 0);
      expect(roomNativeShare(true), 100);
    });
  });

  group('корзина человека', () {
    test('одна и та же у одного человека и лежит в 0…99', () {
      for (final uid in ['na8ivynvjpggisy', 'ufge0IwvR4RehZ9TgKijm5xc9C32', 'a']) {
        final b = roomBucket(uid);
        expect(b, inInclusiveRange(0, 99));
        expect(roomBucket(uid), b);
      }
    });

    test('значение прибито: сменится хеш — люди перемешаются между окнами', () {
      // Замер сравнивает две группы, и человек не должен прыгать из одной в
      // другую от сборки к сборке.
      expect(roomBucket('na8ivynvjpggisy'), 33);
      expect(roomBucket('g7ax98j3u0yoy4p'), 36);
    });

    test('люди расходятся по корзинам примерно поровну', () {
      final hits = List<int>.filled(100, 0);
      for (var i = 0; i < 20000; i++) {
        hits[roomBucket('user$i')]++;
      }
      // По 200 на корзину; допуск широкий, ловим только явный перекос.
      expect(hits.reduce((a, b) => a < b ? a : b), greaterThan(140));
      expect(hits.reduce((a, b) => a > b ? a : b), lessThan(260));
    });
  });

  group('кому открывать нативное окно', () {
    bool opens({bool ios = true, bool reels = false, int share = 100, String uid = 'na8ivynvjpggisy'}) =>
        roomOpensNatively(ios: ios, reels: reels, share: share, uid: uid);

    test('Android остаётся как был при любой доле', () {
      expect(opens(ios: false, share: 100), isFalse);
    });

    test('лента вдвоём остаётся во встроенном окне', () {
      // У неё своя страница, отступы под строку состояния и скрытая лента
      // площадки: переводим только комнату.
      expect(opens(reels: true, share: 100), isFalse);
    });

    test('доля 0 выключает окно у всех, 100 включает всем', () {
      expect(opens(share: 0), isFalse);
      expect(opens(share: 100), isTrue);
    });

    test('человек попадает в долю по своей корзине', () {
      // Корзина 33: в двадцати процентах его нет, в сорока есть.
      expect(opens(share: 20), isFalse);
      expect(opens(share: 33), isFalse);
      expect(opens(share: 34), isTrue);
      expect(opens(share: 40), isTrue);
    });

    test('кто попал в меньшую долю, остаётся и в большей', () {
      for (var i = 0; i < 500; i++) {
        final uid = 'user$i';
        if (roomOpensNatively(ios: true, reels: false, share: 20, uid: uid)) {
          expect(roomOpensNatively(ios: true, reels: false, share: 50, uid: uid), isTrue, reason: uid);
        }
      }
    });

    test('без входа корзины нет: окно только при полной доле', () {
      expect(opens(uid: '', share: 99), isFalse);
      expect(opens(uid: '', share: 100), isTrue);
    });
  });

  group('метки в адресе комнаты', () {
    test('номер сборки уходит странице: замер касаний делится по сборкам', () {
      // До этого страница не знала, из какой сборки её открыли, и проверить
      // выпуск замером было нечем.
      final url = WatchRoomService.siteUrl('abcd2345', build: 250);
      expect(Uri.parse(url).queryParameters['b'], '250');
      expect(url, endsWith('#abcd2345'));
    });

    test('без номера сборки метки нет', () {
      expect(WatchRoomService.siteUrl('abcd2345'), 'https://togetherly.day/watch/room/#abcd2345');
      expect(Uri.parse(WatchRoomService.siteUrl('abcd2345', build: 0)).queryParameters.containsKey('b'), isFalse);
    });

    test('нативное окно помечено, встроенное нет', () {
      final native = WatchRoomService.siteUrl('abcd2345', nativeWindow: true);
      expect(Uri.parse(native).queryParameters['nb'], '1');
      final embedded = WatchRoomService.siteUrl('abcd2345', name: 'Саша');
      expect(Uri.parse(embedded).queryParameters.containsKey('nb'), isFalse);
    });

    test('ссылка для партнёра остаётся чистой', () {
      // Метки описывают этот телефон; партнёру они ни к чему.
      expect(WatchRoomService.siteUrl('abcd2345'), isNot(contains('nb=')));
    });
  });
}
