import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/ad_show_finished.dart';

/// Реклама закрылась — а событие об этом от SDK не пришло.
///
/// По журналу: 9528 случаев «показан ролик, награды нет», и человек проводит
/// на этом экране **120 секунд медианы** — ровно предохранитель, стоявший на
/// две минуты. Ни одного случая «закрыл сам» (59 из 59 досмотрели до конца).
/// Всё это время вход в совместный просмотр стоит: жалоба звучит как
/// «посмотрел рекламу и ничего, в комнату не перекидывает».
///
/// Полноэкранная реклама уводит приложение с переднего плана, и её закрытие
/// видно по возврату: ушли и вернулись — значит показ окончен.
void main() {
  group('adShowFinished', () {
    test('ушли на рекламу и вернулись — показ окончен', () {
      final watch = AdShowWatch();
      watch.onState(AppLifecycleState.inactive);
      watch.onState(AppLifecycleState.paused);
      expect(watch.finished, isFalse, reason: 'реклама ещё на экране');
      watch.onState(AppLifecycleState.resumed);
      expect(watch.finished, isTrue);
    });

    test('пока не уходили — возврат ничего не значит', () {
      // Показ мог не начаться вовсе: на iOS SDK Яндекса отвечает «no view
      // controller present». Один resumed без ухода — это не закрытие рекламы.
      final watch = AdShowWatch();
      watch.onState(AppLifecycleState.resumed);
      expect(watch.finished, isFalse);
    });

    test('мигание inactive без ухода в фон не считается', () {
      // Шторка уведомлений и звонок дают короткое inactive → resumed.
      final start = DateTime(2026, 10, 20, 11);
      final watch = AdShowWatch();
      watch.onState(AppLifecycleState.inactive, at: start);
      watch.onState(AppLifecycleState.resumed, at: start.add(const Duration(milliseconds: 800)));
      expect(watch.finished, isFalse);
    });

    test('полупрозрачная реклама: долгое inactive и возврат — показ окончен', () {
      // Яндекс на Android открывает рекламу полупрозрачным окном: приложение
      // под ним не уходит в фон, а только теряет фокус (20.10.2026, эмулятор).
      final start = DateTime(2026, 10, 20, 11);
      final watch = AdShowWatch();
      watch.onState(AppLifecycleState.inactive, at: start);
      expect(watch.finished, isFalse, reason: 'реклама ещё на экране');
      watch.onState(AppLifecycleState.resumed, at: start.add(const Duration(seconds: 95)));
      expect(watch.finished, isTrue);
      expect(watch.away, const Duration(seconds: 95));
    });

    test('за полупрозрачной рекламой ролик засчитывается по времени', () {
      final start = DateTime(2026, 10, 20, 11);
      final watch = AdShowWatch();
      watch.onState(AppLifecycleState.inactive, at: start);
      watch.onState(AppLifecycleState.resumed, at: start.add(const Duration(seconds: 40)));
      expect(adRewardDeserved(shown: true, away: watch.away, onScreen: Duration.zero), isTrue);
    });

    test('скрытое окно тоже считается уходом', () {
      // На части телефонов полноэкранная реклама даёт hidden вместо paused.
      final watch = AdShowWatch();
      watch.onState(AppLifecycleState.hidden);
      watch.onState(AppLifecycleState.resumed);
      expect(watch.finished, isTrue);
    });

    test('ушли под рекламу — она показана, даже если Яндекс промолчал', () {
      // Эмулятор 20.10.2026, сборка 253: окно рекламы открылось и шло две
      // минуты, а onAdShown так и не пришёл. Отчёт: ad_shown false, и через
      // 70 секунд вышло «не засчитан».
      final start = DateTime(2026, 10, 20, 12, 16, 41);
      final watch = AdShowWatch();
      expect(watch.sawAd, isFalse);
      watch.onState(AppLifecycleState.inactive, at: start);
      expect(watch.sawAd, isTrue, reason: 'реклама на экране прямо сейчас');
      watch.onState(AppLifecycleState.resumed, at: start.add(const Duration(minutes: 2)));
      expect(watch.sawAd, isTrue, reason: 'реклама была и закрылась');
    });

    test('короткое мигание без рекламы показом не считается', () {
      final start = DateTime(2026, 10, 20, 12);
      final watch = AdShowWatch();
      watch.onState(AppLifecycleState.inactive, at: start);
      watch.onState(AppLifecycleState.resumed, at: start.add(const Duration(milliseconds: 500)));
      expect(watch.sawAd, isFalse);
    });

    test('показанная реклама ждёт своего закрытия дольше предохранителя', () {
      // Яндекс крутит пачки из трёх роликов, это больше 70 секунд. Пока
      // реклама на экране, решать «закрылась» по часам нельзя: сундук
      // открывался под рекламой, а «не засчитан» выходил поверх неё.
      expect(adCloseWaitLimit(shown: false), kAdShowGuard);
      // Человек может забыть закрыть рекламу: ждём, пока закроет.
      expect(adCloseWaitLimit(shown: true), greaterThanOrEqualTo(const Duration(minutes: 30)));
    });

    test('предохранитель — минута с небольшим, а не две', () {
      // Ролик у сетей до шестидесяти секунд; всё, что дольше, человек уже
      // считает зависанием.
      expect(kAdShowGuard.inSeconds, lessThanOrEqualTo(75));
      expect(kAdShowGuard.inSeconds, greaterThanOrEqualTo(60));
    });
  });
}
