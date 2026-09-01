// Название системного таймера пары.
//
// Предлог был вшит по-английски — `'$label with $name'`, — поэтому русская
// пара видела в поле «Название» строку «Влюблённые with akio». Теперь шаблон
// живёт в словаре, а старым парам название чинит разовая миграция.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/timer_service.dart';

Future<void> _switchTo(AppLanguage lang) async {
  SharedPreferences.setMockInitialValues({'app_language': lang.code});
  await LocaleService.instance.init();
  await LocaleService.instance.setLanguage(lang);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('предлог берётся из языка интерфейса', () async {
    await _switchTo(AppLanguage.ru);
    expect(
      LocaleService.current.timerTitleWithPartner('Влюблённые', 'akio'),
      'Влюблённые с akio',
    );

    await _switchTo(AppLanguage.en);
    expect(
      LocaleService.current.timerTitleWithPartner('In Love', 'akio'),
      'In Love with akio',
    );

    await _switchTo(AppLanguage.de);
    expect(
      LocaleService.current.timerTitleWithPartner('Verliebt', 'akio'),
      'Verliebt mit akio',
    );
  });

  test('старое название с английским with переводится один раз', () async {
    await _switchTo(AppLanguage.ru);
    final service = TimerService();
    await service.addTimer(
      id: TimerService.systemTimerId,
      title: 'Влюблённые with akio',
      startDate: DateTime(2026, 6, 30),
      isSystem: true,
      isDefault: true,
    );

    await service.migrateSystemTimerTitle(
      relationshipLabel: 'Влюблённые',
      partnerName: 'akio',
    );
    expect(service.systemTimer!.title, 'Влюблённые с akio');
  });

  test('переименованный руками таймер миграция не трогает', () async {
    await _switchTo(AppLanguage.ru);
    final service = TimerService();
    await service.addTimer(
      id: TimerService.systemTimerId,
      title: 'Наши дни with akio',
      startDate: DateTime(2026, 6, 30),
      isSystem: true,
      isDefault: true,
    );

    await service.migrateSystemTimerTitle(
      relationshipLabel: 'Влюблённые',
      partnerName: 'akio',
    );
    expect(service.systemTimer!.title, 'Наши дни with akio');
  });
}
