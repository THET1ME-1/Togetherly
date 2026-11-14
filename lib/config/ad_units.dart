/// Рекламные блоки: у Android и iOS они РАЗНЫЕ.
///
/// В РСЯ приложения заведены по отдельности (19386995 — Android, 19461868 —
/// iOS), и чужой блок показов не даёт вовсе: до 21.08.2026 на iPhone
/// подставлялись андроидные, то есть реклама Яндекса там не работала совсем.
/// AdMob убран 28.09.2026 и вернулся 14.11.2026 запасной сетью: первым всегда
/// идёт Яндекс, AdMob грузится только после его отказа (Украина, где Яндекс
/// закрыт, и пустые ответы). Блоки AdMob заведены заново, по одному на
/// каждое место Яндекса.
///
/// Всё, что показывает рекламу, берёт идентификатор отсюда: раскиданные по
/// экранам строки уже разъезжались.
library;

class AdUnits {
  const AdUnits._();

  // ── Яндекс ────────────────────────────────────────────────────────────────
  static String yandexBanner({required bool ios}) =>
      ios ? 'R-M-19461868-1' : 'R-M-19386995-1';

  static String yandexRewarded({required bool ios}) =>
      ios ? 'R-M-19461868-2' : 'R-M-19386995-2';

  /// Отдельный блок сундука недели («Сундук» в кабинете, 28.09.2026): его
  /// показы и доход РСЯ считает своей строкой, не вперемешку с подарками и
  /// возвратом серии.
  static String yandexRewardedChest({required bool ios}) =>
      ios ? 'R-M-19461868-4' : 'R-M-19386995-4';

  /// Ролики гардероба Ту («Гардероб Ту (вещи за ролики)» в кабинете,
  /// 09.11.2026): вещи за ролик и вещи за монеты, взятые роликами.
  static String yandexRewardedWardrobe({required bool ios}) =>
      ios ? 'R-M-19461868-6' : 'R-M-19386995-6';

  static String yandexInterstitial({required bool ios}) =>
      ios ? 'R-M-19461868-3' : 'R-M-19386995-3';

  /// Межстраничная после выхода из комнаты совместного просмотра
  /// («Совместный просмотр» в кабинете, 19.10.2026): доход комнаты РСЯ
  /// считает своей строкой.
  static String yandexInterstitialRoom({required bool ios}) =>
      ios ? 'R-M-19461868-5' : 'R-M-19386995-5';

  // ── AdMob, запасная сеть (14.11.2026) ─────────────────────────────────────
  // Приложения в кабинете: Android ~3521559179, iOS ~9958268140 (stgroup.dev).
  static String admobBanner({required bool ios}) => ios
      ? 'ca-app-pub-1956369312643059/8998259200'
      : 'ca-app-pub-1956369312643059/8016350024';

  static String admobRewarded({required bool ios}) => ios
      ? 'ca-app-pub-1956369312643059/7685177530'
      : 'ca-app-pub-1956369312643059/2368612534';

  static String admobRewardedChest({required bool ios}) => ios
      ? 'ca-app-pub-1956369312643059/1582803615'
      : 'ca-app-pub-1956369312643059/2624422544';

  static String admobRewardedWardrobe({required bool ios}) => ios
      ? 'ca-app-pub-1956369312643059/2177040841'
      : 'ca-app-pub-1956369312643059/4703790977';

  static String admobInterstitial({required bool ios}) => ios
      ? 'ca-app-pub-1956369312643059/4172648790'
      : 'ca-app-pub-1956369312643059/9137860001';

  static String admobInterstitialRoom({required bool ios}) => ios
      ? 'ca-app-pub-1956369312643059/6320124971'
      : 'ca-app-pub-1956369312643059/8303465490';

  /// Тестовые блоки Google для отладочной сборки: настоящие блоки в отладке
  /// запрещены правилами AdMob.
  static String admobTestBanner({required bool ios}) => ios
      ? 'ca-app-pub-3940256099942544/2934735716'
      : 'ca-app-pub-3940256099942544/6300978111';

  static String admobTestRewarded({required bool ios}) => ios
      ? 'ca-app-pub-3940256099942544/1712485313'
      : 'ca-app-pub-3940256099942544/5224354917';

  static String admobTestInterstitial({required bool ios}) => ios
      ? 'ca-app-pub-3940256099942544/4411468910'
      : 'ca-app-pub-3940256099942544/1033173712';
}
