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
      // Шторка уведомлений и звонок дают inactive → resumed без paused.
      final watch = AdShowWatch();
      watch.onState(AppLifecycleState.inactive);
      watch.onState(AppLifecycleState.resumed);
      expect(watch.finished, isFalse);
    });

    test('скрытое окно тоже считается уходом', () {
      // На части телефонов полноэкранная реклама даёт hidden вместо paused.
      final watch = AdShowWatch();
      watch.onState(AppLifecycleState.hidden);
      watch.onState(AppLifecycleState.resumed);
      expect(watch.finished, isTrue);
    });

    test('предохранитель — минута с небольшим, а не две', () {
      // Ролик у сетей до шестидесяти секунд; всё, что дольше, человек уже
      // считает зависанием.
      expect(kAdShowGuard.inSeconds, lessThanOrEqualTo(75));
      expect(kAdShowGuard.inSeconds, greaterThanOrEqualTo(60));
    });
  });
}
