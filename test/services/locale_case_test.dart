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
  // Склейки: строка дописывается к другой и середины фразы не начинает.
  'agreeToTermsAnd', 'welcomeTitle2', 'or', 'orManually', 'partnerFallback',
  'dayLogWhat',
  // Подписи после числа: «12 дней осталось», «3 фото на виджете».
  'daysCounterLabel', 'daysElapsed', 'daysInARow', 'daysLeft',
  'daysShortElapsed', 'daysShortLeft', 'daysUntilAnniversary',
  'daysUntilBirthday', 'photoGridCountLabel', 'cycleDaysUnit',
  'tgCountdownDays', 'tgCountdownHours', 'tgCountdownMinutes',
  'fromGalleryLabel', 'fromMemories',
  // Подпись справа от числа: «+12 к общему числу».
  'love_total_change',
  // Подписи метрик под цифрой в профиле.
  'statsDaysTogether', 'statsDrawings', 'statsMemories', 'statsStreak',
  'statsXp',
  // Единицы измерения.
  'unitCm', 'unitDayShort', 'unitHourShort', 'unitKm', 'unitM', 'unitMinShort',
  // Мелкие метки состояния у сообщения, аватара, карточки.
  'chatEdited', 'chatOnline', 'chatTypingShort', 'isListening', 'justNow',
  'liveLocationJustNow', 'dragHint', 'tgMoodNotSet',
  // Форматы полей ввода — образец, а не фраза.
  'dateFormatHint', 'timeFormatHint',
  // Бумажные открытки: билет, чек, телеграмма, посылка. Нижний регистр там
  // часть рисунка, часть строк вообще уходит в toUpperCase.
  'pcDaysNearby', 'pcDaysOfLove', 'pcDaysTogether', 'pcMsgReceipt',
  'pcNightsUnderSky', 'pcParcelCare', 'pcParcelTo', 'pcReceiptTotal',
  'pcTelegramTitle', 'pcTicketRoute',
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
