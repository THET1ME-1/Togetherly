import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/ad_show_finished.dart';

/// Награда за досмотренный ролик, когда SDK промолчала.
///
/// За тридцать дней 214 показов кончились «монет нет», и в 188 случаях ролик
/// провёл на экране больше тридцати секунд — то есть люди досматривали и
/// оставались ни с чем. `onRewarded` при этом не приходил вовсе. Правило ниже
/// решает, засчитывать ли такой показ самим.
void main() {
  group('AdShowWatch считает, сколько реклама держала экран', () {
    test('время вне приложения — это и есть длительность ролика', () {
      final watch = AdShowWatch();
      watch.onState(AppLifecycleState.paused, at: DateTime(2026, 8, 26, 12, 0, 0));
      watch.onState(AppLifecycleState.resumed, at: DateTime(2026, 8, 26, 12, 0, 22));

      expect(watch.finished, isTrue);
      expect(watch.away, const Duration(seconds: 22));
    });

    test('мигание inactive длительность не набивает', () {
      final watch = AdShowWatch();
      watch.onState(AppLifecycleState.inactive, at: DateTime(2026, 8, 26, 12, 0, 0));
      watch.onState(AppLifecycleState.resumed, at: DateTime(2026, 8, 26, 12, 0, 40));

      expect(watch.finished, isFalse);
      expect(watch.away, Duration.zero);
    });
  });

  group('adRewardDeserved', () {
    test('показа не было — награды нет', () {
      expect(
        adRewardDeserved(
          shown: false,
          away: const Duration(seconds: 40),
          onScreen: const Duration(seconds: 40),
        ),
        isFalse,
      );
    });

    test('досмотренный ролик засчитывается по времени вне приложения', () {
      expect(
        adRewardDeserved(
          shown: true,
          away: const Duration(seconds: 16),
          onScreen: const Duration(seconds: 18),
        ),
        isTrue,
      );
    });

    test('закрыл на второй секунде — не засчитывается', () {
      expect(
        adRewardDeserved(
          shown: true,
          away: const Duration(seconds: 2),
          onScreen: const Duration(seconds: 3),
        ),
        isFalse,
      );
    });

    test('реклама рисуется внутри окна — считаем по времени с начала показа', () {
      // Часть сборок показывает ролик без смены жизненного цикла: приложение
      // остаётся на переднем плане, и `away` равен нулю.
      expect(
        adRewardDeserved(
          shown: true,
          away: Duration.zero,
          onScreen: const Duration(seconds: 30),
        ),
        isTrue,
      );
    });

    test('досмотрел две минуты внутри окна — награда положена', () {
      // Живой случай с прода: у 60 последних потерянных наград медиана времени
      // на экране 120 секунд, а `seconds_behind_ad` не приходит вовсе — реклама
      // Яндекса рисуется без ухода приложения в фон. Прежняя верхняя граница
      // (предохранитель ожидания, 70 с) отвергала ровно тех, кто досмотрел.
      expect(
        adRewardDeserved(
          shown: true,
          away: Duration.zero,
          onScreen: const Duration(seconds: 120),
        ),
        isTrue,
      );
    });

    test('минута на экране и пара секунд в фоне — награда положена', () {
      // Живые случаи 09.10.2026 (обращение 246, «после рекламы серия не
      // возвращается и сундук не работает»): ролик держал экран 47–64 с, а
      // приложение уходило в фон лишь на 2–14 с. Ненулевой `away` отправлял
      // такие показы мимо проверки по времени на экране, и досмотревший
      // оставался без награды.
      for (final (away, onScreen) in [(3, 47), (2, 55), (9, 64), (14, 62)]) {
        expect(
          adRewardDeserved(
            shown: true,
            away: Duration(seconds: away),
            onScreen: Duration(seconds: onScreen),
          ),
          isTrue,
          reason: 'away $away с, на экране $onScreen с',
        );
      }
    });

    test('внутри окна дольше разумного — это отложенный телефон', () {
      expect(
        adRewardDeserved(
          shown: true,
          away: Duration.zero,
          onScreen: kAdOnScreenSane + const Duration(seconds: 1),
        ),
        isFalse,
      );
    });

    test('телефон отложили на час — это не просмотр', () {
      expect(
        adRewardDeserved(
          shown: true,
          away: const Duration(minutes: 40),
          onScreen: const Duration(minutes: 40),
        ),
        isFalse,
      );
    });

    test('ждали предохранителя, но экран так и не уходил — не засчитываем', () {
      // Ни ухода, ни закрытия: SDK молчала с самого начала, ролика человек не
      // видел. Такие случаи (`ad_shown: false`) в журнале тоже есть.
      expect(
        adRewardDeserved(
          shown: false,
          away: Duration.zero,
          onScreen: const Duration(seconds: 70),
        ),
        isFalse,
      );
    });

    test('порог совпадает с обещанием — короче него награды не бывает', () {
      expect(
        adRewardDeserved(
          shown: true,
          away: kAdWatchedEnough - const Duration(seconds: 1),
          onScreen: kAdWatchedEnough - const Duration(seconds: 1),
        ),
        isFalse,
      );
      expect(
        adRewardDeserved(
          shown: true,
          away: kAdWatchedEnough,
          onScreen: kAdWatchedEnough,
        ),
        isTrue,
      );
    });
  });
}
