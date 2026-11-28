import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';

/// Сторож регистра в словаре.
///
/// Строчная буква в начале подписи — то, что бесит на экране сильнее всего:
/// «оформление, уведомления, данные» под заголовком настроек, «месячные» в
/// легенде календаря. 10 августа 2026 таких строк нашлось 42, все поправлены.
///
/// Но строчная буква бывает и законной: продолжение фразы после числа («5 дней
/// осталось»), единицы («км», «мин»), подстановка имени («от партнёра»), формат
/// поля («дд.мм.гггг»), стилизованные открытки. Такие ключи перечислены ниже —
/// список закрытый, поэтому новая строчная строка валит тест и требует решения:
/// либо заглавная, либо запись сюда с объяснением.
const _lowercaseOnPurpose = <String>{
  // Кусочки подписи «Придёт {t}» / «у вас {mine}»: встают внутрь фразы.
  'chatAtTime', 'chatTomorrowAt', 'chatDateAt',
  // Хвосты строки истории «Скучаю»: встают после имени или времени.
  'missYouInReplyTo',
  'missYouSeenAt',
  // Единица после числа в «Кольце года»: «69 мес.»
  'tgYearMonthsShort',
  // Склейки: строка дописывается к другой и середины фразы не начинает.
  'agreeToTermsAnd', 'welcomeTitle2', 'or', 'orManually', 'partnerFallback',
  'dayLogWhat',
  // Подписи после числа: «12 дней осталось», «3 фото на виджете».
  'daysCounterLabel', 'daysElapsed', 'daysInARow', 'daysLeft',
  // Ёлка пары: слово после числа («9 игрушек», «12 дней»), подпись под
  // названием («ещё пустая») и строчки под карточками листа («все на ёлке»).
  'xt.toys.1', 'xt.toys.2', 'xt.toys.5', 'xt.days.1', 'xt.days.2', 'xt.days.5',
  'xt.empty', 'xt.allOnTree', 'xt.fromChest', 'xt.on', 'xt.off', 'xt.styleNow', 'xt.styleSet', 'xt.byWhom',
  'daysShortElapsed', 'daysShortLeft', 'daysUntilAnniversary',
  'daysUntilBirthday', 'photoGridCountLabel', 'cycleDaysUnit',
  'vesselStoryDays',
  // Капсула времени: «182 дня / до открытия» под крупным числом.
  'capsuleUntilOpen',
  'tgCountdownDays', 'tgCountdownHours', 'tgCountdownMinutes',
  'fromGalleryLabel', 'fromMemories',
  // Подпись справа от числа: «+12 к общему числу».
  'love_total_change',
  // Легенда сетки года: подписи стоят внутри строки, рядом с образцами цвета
  // и числом — «в среднем 3,7 из 5 · 45 дней без отметки».
  'moodYearNoMark', 'moodYearWorse', 'moodYearBetter',
  'moodYearAverage', 'moodYearMissing',
  // Подписи метрик под цифрой в профиле.
  'statsDaysTogether', 'statsDrawings', 'statsMemories', 'statsStreak',
  'statsXp',
  // Единицы измерения.
  'unitCm', 'unitDayShort', 'unitHourShort', 'unitKm', 'unitM', 'unitMinShort',
  // Мелкие метки состояния у сообщения, аватара, карточки.
  'chatEdited', 'chatOnline', 'chatTypingShort', 'isListening', 'justNow',
  'liveLocationJustNow', 'dragHint', 'tgMoodNotSet',
  // Часы партнёра в шапке чата: «в сети · у неё 02:14» (TOG-48).
  'chatPartnerClockF', 'chatPartnerClockM', 'chatPartnerClockX',
  // Давность точки на виджете «Где мы»: «Аня · сейчас», как «12 мин. назад».
  'mapWidgetNow',
  // Форматы полей ввода — образец, а не фраза.
  'dateFormatHint', 'timeFormatHint',
  // Бумажные открытки: билет, чек, телеграмма, посылка. Нижний регистр там
  // часть рисунка, часть строк вообще уходит в toUpperCase.
  'pcDaysNearby', 'pcDaysOfLove', 'pcDaysTogether', 'pcMsgReceipt',
  'pcNightsUnderSky', 'pcParcelCare', 'pcParcelTo', 'pcReceiptTotal',
  'pcTelegramTitle', 'pcTicketRoute',
  // Виджет маскота: ступень и остаток стоят ВНУТРИ строки — «Пудя ·
  // подросток», «подросток · 12 дней серии», «до взрослого 18 дней». С
  // заглавной они выглядели бы вторым заголовком рядом с именем.
  'mascotStageBaby', 'mascotStageTeen', 'mascotStageAdult',
  'mascotWidgetToTeen', 'mascotWidgetToAdult', 'mascotWidgetGrown',
  // Подписи под числом в плитках: «12 · дней серии», «64 · рекорд».
  'mascotWidgetStreakLabel', 'mascotWidgetRecord',
  // Чек Togetherly Wallet: значение стоит справа от точек и продолжает строку
  // «Общий бюджет ······ на двоих».
  'walletRowBudgetValue', 'walletRowPersonalValue', 'walletRowSplitValue',
  'walletRowGoalsValue', 'walletRowBankValue', 'walletRowChatValue',
  // Подписи виджетов рабочего стола: слово при числе и хвосты фраз
  // («12 дней», «5 лет уже ❤️», «Я · не отмечено»), с заглавной их ставит
  // сам нативный код, где подпись начинает строку.
  'wlDaysOne', 'wlDaysFew', 'wlDaysMany', 'wlYearsOne', 'wlYearsFew', 'wlYearsMany',
  'wlYearsgenOne', 'wlYearsgenFew', 'wlYearsgenMany', 'wlMonthsOne', 'wlMonthsFew',
  'wlMonthsMany', 'wlMemoriesOne', 'wlMemoriesFew', 'wlMemoriesMany', 'wlHoursOne',
  'wlHoursFew', 'wlHoursMany', 'wlMinutesOne', 'wlMinutesFew', 'wlMinutesMany',
  'wlMonthsGen', 'wlWeekdays', 'wlDaysLeft', 'wlDaysTogether', 'wlNotMarked',
  'wlMatched', 'wlMoodGood', 'wlMoodOk', 'wlMoodBad', 'wlMonthsShort', 'wlFillsAtOnce',
  'wlSince', 'wlMissFromMeReply', 'wlMissFromMeName', 'wlDateDayMonth',
  'wlYearNth', 'wlYearTogether', 'wlYearsAlready', 'wlUntilMeet', 'wlInARow',
  'wlTogetherWord', 'wlDaysUntilYears',
  // Наши даты (TOG-61): слово после числа («6 дней», «Раз в 2 недели»),
  // уточнения серым рядом с главным («Каждую неделю  в воскресенье», «пн–пт»,
  // «последний четверг»), хвосты подписи через точку («· из профиля»,
  // «· добавила Лиза», «· исполнится 27», «через 6 дней»), склейки «до
  // 15 декабря», «в ср и вс», «за 2 дня в 9:00».
  'dt.daysWord.1', 'dt.daysWord.2', 'dt.daysWord.5',
  'dt.inDays.1', 'dt.inDays.2', 'dt.inDays.5',
  'dt.addedBy.f', 'dt.addedBy.m', 'dt.addedBy.x',
  'dt.fromProfile', 'dt.fromTimer', 'dt.turns', 'dt.phLocal',
  'dt.onWd.1', 'dt.onWd.2', 'dt.onWd.3', 'dt.onWd.4', 'dt.onWd.5', 'dt.onWd.6', 'dt.onWd.7',
  'dt.lastWd.1', 'dt.lastWd.2', 'dt.lastWd.3', 'dt.lastWd.4', 'dt.lastWd.5', 'dt.lastWd.6', 'dt.lastWd.7',
  'dt.monthDay', 'dt.rWeekdaysDetail', 'dt.onDays', 'dt.until', 'dt.and', 'dt.remAt', 'dt.remWillCome',
  'dt.unitDay.1', 'dt.unitDay.2', 'dt.unitDay.5',
  'dt.unitWeek.1', 'dt.unitWeek.2', 'dt.unitWeek.5',
  'dt.unitMonth.1', 'dt.unitMonth.2', 'dt.unitMonth.5',
  'dt.unitYear.1', 'dt.unitYear.2', 'dt.unitYear.5',
  'dt.uMinutes.1', 'dt.uMinutes.2', 'dt.uMinutes.5',
  'dt.uHours.1', 'dt.uHours.2', 'dt.uHours.5',
};

/// Строчная, законная только в отдельных языках.
///
/// Романские языки пишут названия документов со строчной внутри фразы: строки
/// склеиваются в «J’accepte les conditions d’utilisation» и «Acepto las
/// condiciones de uso», и заглавная там была бы ошибкой. В русском и английском
/// те же ключи — заголовки ссылок, поэтому исключение именно по языку.
const _lowercaseByLang = <String, Set<String>>{
  'fr': {'termsOfUse', 'privacyPolicyLink'},
  'es': {'termsOfUse', 'privacyPolicyLink'},
  'it': {'termsOfUse', 'privacyPolicyLink'},
  'pt': {'termsOfUse', 'privacyPolicyLink'},
};

bool _startsLower(String s) {
  final t = s.trimLeft();
  if (t.isEmpty) return false;
  final first = t[0];
  // Цифра, эмодзи или знак в начале регистру не подчиняются: «1 фото», «✂️ …».
  final isLetter = RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(first);
  return isLetter && first.toLowerCase() == first;
}

void main() {
  test('подписи начинаются с заглавной буквы', () {
    final offenders = <String>[];
    for (final entry in kStrings.entries) {
      if (_lowercaseOnPurpose.contains(entry.key)) continue;
      for (final lang in entry.value.entries) {
        if (_lowercaseByLang[lang.key]?.contains(entry.key) ?? false) continue;
        if (_startsLower(lang.value)) {
          offenders.add('${entry.key} (${lang.key}): «${lang.value}»');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'строчная буква в начале:\n${offenders.take(15).join('\n')}',
    );
  });

  test('список исключений не зарастает мёртвыми ключами', () {
    final gone = _lowercaseOnPurpose.where((k) => !kStrings.containsKey(k));
    expect(
      gone,
      isEmpty,
      reason: 'ключей уже нет в словаре: ${gone.join(', ')}',
    );
  });

  test('в строках нет двойных пробелов и висячих пробелов по краям', () {
    // Исключения: префиксы для склейки заканчиваются пробелом намеренно,
    // а вокруг буллета в подсказках рисования стоит разрядка.
    const spacedOnPurpose = <String>{
      'noAccount',
      'alreadyHaveAccountQuestion',
      'agreeToTermsPrefix',
      'agreeToTermsAnd',
      'welcomeTitle1',
      'drawHintEdit',
      'drawHintDraw',
      'cropAvatarTitle',
      // Склейка дней «ср и вс» — пробелы вокруг союза.
      'dt.and',
    };
    final offenders = <String>[];
    for (final entry in kStrings.entries) {
      if (spacedOnPurpose.contains(entry.key)) continue;
      for (final lang in entry.value.entries) {
        final v = lang.value;
        if (v != v.trim() || v.contains('  ')) {
          offenders.add('${entry.key} (${lang.key}): «$v»');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.take(10).join('\n'));
  });

  _tightLabels();

  test('термины не расходятся между строками', () {
    final ru = kStrings.values
        .map((e) => e['ru'] ?? '')
        .join(' ')
        .toLowerCase();
    // Магазин звался «Магазин Коинов», а внутри него — «Купить монеты».
    expect(
      ru.contains('коин'),
      isFalse,
      reason: 'вернулись «коины» вместо монет',
    );
    // Кнопка в приложении подписана «Скучаю».
    expect(
      ru.contains('«я скучаю»'),
      isFalse,
      reason: 'вернулось «Я скучаю» вместо «Скучаю»',
    );
  });
}

/// Узкие места: подписи, которые делят строку поровну и обрезаются молча.
///
/// Голден португальского показал «Em andame…» вместо «Em andamento»: три
/// фильтра достижений делят 360 dp, и на подпись остаётся около одиннадцати
/// знаков при кегле 13,5. Обрезка выглядит как опечатка, а не как поломка,
/// поэтому её и не замечают.
void _tightLabels() {
  test('подписи в тесных местах укладываются в лимит', () {
    // Ключ → предел знаков, снятый с рендера на 360 dp.
    const limits = <String, int>{
      'achFilterAll': 12,
      'achFilterUnlocked': 12,
      'achFilterInProgress': 12,
      'tgSizeHintCompact': 12,
      'tgSizeHintWide': 12,
      'tgSizeHintLarge': 12,
      'tgSizeHintStrip': 12,
      'themeFlavorSoft': 10,
      'themeFlavorJuicy': 10,
      'themeFlavorExact': 10,
      'themeModeLight': 10,
      'themeModeDark': 10,
      'themeModeSystem': 10,
    };
    final tooLong = <String>[];
    limits.forEach((key, limit) {
      for (final lang in kStrings[key]!.entries) {
        if (lang.value.length > limit) {
          tooLong.add(
            '$key (${lang.key}): «${lang.value}» '
            '${lang.value.length} > $limit',
          );
        }
      }
    });
    expect(tooLong, isEmpty, reason: tooLong.join('\n'));
  });
}
