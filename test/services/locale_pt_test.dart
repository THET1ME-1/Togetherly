import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/l10n/pt/daily_tasks.dart';
import 'package:love_app/l10n/pt/gifts.dart';
import 'package:love_app/l10n/pt/inline.dart';
import 'package:love_app/l10n/uk/inline.dart';
import 'package:love_app/l10n/zh/inline.dart';
import 'package:love_app/models/daily_task.dart';
import 'package:love_app/models/gift.dart';
import 'package:love_app/models/tu_wear.dart';
import 'package:love_app/services/locale_service.dart';

/// Португальский: словарь целиком плюс свои числительные и даты.
///
/// Норма бразильская: обращение на «você». `LocaleService.detect` отправляет в
/// `pt` и `pt-BR`, и `pt-PT` — колонка словаря одна на всех, а говорящих в
/// Бразилии на порядок больше.
void main() {
  late AppStrings pt;

  setUp(() {
    LocaleService.instance.setLanguage(AppLanguage.pt);
    pt = LocaleService.instance.strings;
  });

  test('словарь переведён целиком', () {
    final missing = kStrings.entries
        .where((e) => (e.value['pt'] ?? '').isEmpty)
        .map((e) => e.key)
        .toList();
    expect(missing, isEmpty, reason: 'без португальского: ${missing.take(15)}');
  });

  test('простые строки идут из португальской колонки', () {
    expect(pt.save, 'Salvar');
    expect(pt.memoryLane, 'Mural de lembranças');
    expect(pt.coinBalance, 'Moedas');
  });

  test('ноль во множественном, единица в единственном', () {
    expect(pt.timerDaysCount(0), '0 dias');
    expect(pt.timerDaysCount(1), '1 dia');
    expect(pt.timerDaysCount(9), '9 dias');
    expect(pt.coinsPlus(1), '+1 moeda');
    expect(pt.coinsPlus(8), '+8 moedas');
    expect(pt.memoriesUnit(1), 'lembrança');
    expect(pt.memoriesUnit(2), 'lembranças');
    expect(pt.tgMonthsCaption(1), 'mês');
    expect(pt.tgMonthsCaption(3), 'meses');
  });

  test('даты португальские, первое число — 1º и с предлогом', () {
    expect(pt.fullMonths[3], 'março');
    expect(pt.longWeekdays.first, 'segunda-feira');
    expect(pt.chatDateHeader(DateTime(2001, 3, 1)), '1º de março de 2001');
    expect(pt.chatDateHeader(DateTime(2001, 3, 9)), '9 de março de 2001');
    // В карточку идёт короткая форма без «-feira», иначе строка вдвое длиннее.
    expect(pt.partnerMissPeak(pt.weekdayLong(1)), 'Mais na segunda');
  });

  test('обращение на você, а не tu', () {
    // «tu» дало бы «estás», «tens», «contigo» — так пишут в Португалии.
    final samples = [
      pt.howAreYouFeeling,
      pt.partnerWillSeeMood,
      pt.logoutConfirm,
      pt.chatEmptyGhostMine,
    ];
    for (final s in samples) {
      expect(
        RegExp(r'\b(estás|tens|podes|queres|contigo)\b').hasMatch(s),
        isFalse,
        reason: 'европейская форма в «$s»',
      );
    }
  });

  // Вне словаря (обращение из Бразилии 12.11.2026: «много полей по-английски,
  // хотя выбран португальский»). Словарь был переведён целиком, а строки из
  // экранов, задания дня и подарки шли по-английски: таблицы по английскому
  // образцу были только у китайского и украинского.
  group('вне словаря', () {
    tearDown(() => LocaleService.instance.setLanguage(AppLanguage.pt));

    test('строки из экранов — всё, что есть у китайского и украинского', () {
      // Таблицы китайского и украинского собирали обходом экранов: это опись
      // строк, живущих вне словаря.
      final missing = {...kZhByEnglish.keys, ...kUkByEnglish.keys}
          .where((k) => !kPtByEnglish.containsKey(k))
          .toList();
      expect(missing, isEmpty, reason: 'строки экранов: ${missing.take(8)}');
    });

    test('метки чисел те же, что в английской строке', () {
      final mark = RegExp(r'\{\d+\}');
      final broken = <String>[];
      kPtByEnglish.forEach((en, pt) {
        final want = mark.allMatches(en).map((m) => m[0]).toSet();
        final got = mark.allMatches(pt).map((m) => m[0]).toSet();
        if (want.length != got.length || !want.containsAll(got)) {
          broken.add('$en: $want ≠ $got');
        }
      });
      expect(broken, isEmpty, reason: broken.take(10).join('\n'));
    });

    test('задания дня переведены все, имя партнёра на месте', () {
      LocaleService.instance.setLanguage(AppLanguage.en);
      final broken = <String>[];
      for (final task in DailyTask.all) {
        final pt = kDailyTasksPt[task.id];
        if (pt == null) {
          broken.add('${task.id}: нет перевода');
        } else if (task.title('ZZ').contains('ZZ') != pt.contains('{p}')) {
          broken.add('${task.id}: {p}');
        }
      }
      expect(broken, isEmpty, reason: broken.take(10).join('\n'));
      final stray = kDailyTasksPt.keys
          .where((id) => !DailyTask.all.any((t) => t.id == id));
      expect(stray, isEmpty, reason: 'опечатка в id: ${stray.take(5)}');
    });

    test('подарки витрины и сундука названы', () {
      final missing = [...GiftCatalog.all, ...GiftCatalog.chest]
          .where((g) => !kGiftTitlesPt.containsKey(g.key))
          .map((g) => g.key)
          .toList();
      expect(missing, isEmpty, reason: 'подарки: $missing');
    });

    test('строка прямо в экране находит перевод, числа подставляются', () {
      expect(ruEn('Нет сети', 'Offline'), 'Sem conexão');
      expect(
        ruEn('Не хватает монет: нужно 30, у вас 12',
            'Not enough coins: 30 needed, you have 12'),
        'Moedas insuficientes: precisa de 30, você tem 12',
      );
      expect(trEnglish('Pick from 4381 icons'), 'Escolha entre 4381 ícones');
      expect(trEnglish('Some brand new line'), 'Some brand new line');
    });

    test('задание дня, подарок и раздел гардероба по-португальски', () {
      final task = DailyTask.all.firstWhere((t) => t.id == 'photo_smile');
      expect(task.title('Ana'), 'Uma selfie sorrindo para Ana');
      final heart = GiftCatalog.all.firstWhere((g) => g.key == 'heart');
      expect(heart.title, 'Coração');
      expect(tuWearCatName('glasses', ru: false), 'Óculos');
    });
  });
}
