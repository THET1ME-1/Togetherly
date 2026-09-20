// Подпись настроения по полу.
//
// Жалоба 14.08.2026: «а еще нет разделения по полу… у парня тоже "устала"».
// В русском «Устал» и «Устала» — разные слова, и виджет с настроением показывал
// парню женскую форму. Формы лежат в словаре под ключами `ru_m` / `es_f`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_entry.dart';
import 'package:love_app/services/locale_service.dart';

void main() {
  MoodOption mood(String id) => MoodOption.byId(id)!;

  group('русский', () {
    setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

    test('парню — мужская форма', () {
      expect(mood('tired').localizedLabelFor('male'), 'Устал');
      expect(mood('upset').localizedLabelFor('male'), 'Расстроен');
      expect(mood('sick').localizedLabelFor('male'), 'Болен');
      expect(mood('cool').localizedLabelFor('male'), 'Крутой');
    });

    test('девушке — женская', () {
      expect(mood('tired').localizedLabelFor('female'), 'Устала');
      expect(mood('upset').localizedLabelFor('female'), 'Расстроена');
      expect(mood('sick').localizedLabelFor('female'), 'Больна');
      expect(mood('cool').localizedLabelFor('female'), 'Крутая');
    });

    test('пол не указан — обычная подпись', () {
      expect(mood('tired').localizedLabelFor(''), mood('tired').localizedLabel);
    });

    test('настроения без рода не меняются', () {
      expect(mood('happy').localizedLabelFor('male'), mood('happy').localizedLabel);
      expect(mood('kiss').localizedLabelFor('female'), mood('kiss').localizedLabel);
    });
  });

  group('языки с родом', () {
    test('испанский', () {
      LocaleService.instance.setLanguage(AppLanguage.es);
      expect(mood('tired').localizedLabelFor('male'), 'Cansado');
      expect(mood('tired').localizedLabelFor('female'), 'Cansada');
    });

    test('французский', () {
      LocaleService.instance.setLanguage(AppLanguage.fr);
      expect(mood('tired').localizedLabelFor('female'), 'Fatiguée');
    });

    test('итальянский', () {
      LocaleService.instance.setLanguage(AppLanguage.it);
      expect(mood('sick').localizedLabelFor('female'), 'Malata');
    });
  });

  group('языки без рода', () {
    test('английский отдаёт одну форму обоим', () {
      LocaleService.instance.setLanguage(AppLanguage.en);
      expect(mood('tired').localizedLabelFor('male'), 'Tired');
      expect(mood('tired').localizedLabelFor('female'), 'Tired');
    });

    test('немецкий тоже', () {
      LocaleService.instance.setLanguage(AppLanguage.de);
      expect(mood('tired').localizedLabelFor('male'), 'Müde');
      expect(mood('tired').localizedLabelFor('female'), 'Müde');
    });
  });

  // Жалоба из приёмной 13.09.2026 (обращение 154): «пол указан мой, т.е.
  // мужской, но в тестах и в статусах в женском роде». Мужские формы лежали в
  // словаре с августа, но брал их только виджет рабочего стола: выбор
  // настроения, шапка главной, лист дня и уведомление показывали «Устала».
  group('в самом приложении', () {
    setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));
    tearDown(() => MoodGenders.mine = '');

    test('своё настроение подписывается по своему полу', () {
      MoodGenders.mine = 'male';
      expect(mood('tired').myLabel, 'Устал');
      expect(mood('cool').myLabel, 'Крутой');
      MoodGenders.mine = 'female';
      expect(mood('tired').myLabel, 'Устала');
      MoodGenders.mine = '';
      expect(mood('tired').myLabel, mood('tired').localizedLabel);
    });

    test('запись настроения подписывается по полу того, чья она', () {
      final e = MoodEntry(
        id: '1',
        moodId: 'sick',
        imagePath: '',
        label: 'Больна',
        timestamp: DateTime(2026, 9, 19),
      );
      expect(e.labelFor('male'), 'Болен');
      expect(e.labelFor('female'), 'Больна');
      expect(e.labelFor(''), e.localizedLabel);
    });

    test('пол пользователя доезжает до подписей', () {
      final src = File('lib/models/user_data.dart').readAsStringSync();
      expect(src, contains('MoodGenders.mine = genderToStorage()'));
    });

    test('выбор настроения показывает и сохраняет подпись по своему полу', () {
      final src = File('lib/screens/home/widgets/mood_picker_dialog.dart')
          .readAsStringSync();
      expect(src, isNot(contains('mood.localizedLabel')));
      expect(src, contains('mood.myLabel'));
    });

    test('шапка главной подписывает партнёра по его полу', () {
      final src = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(src, contains('_memberMoodFromEntry(_moodService.myMoodToday, MoodGenders.mine)'));
      expect(src, contains('_moodService.partnerMoodToday(uid), _partnerGender)'));
    });
  });
}
