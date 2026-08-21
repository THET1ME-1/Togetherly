/// Рекламные блоки: у Android и iOS они РАЗНЫЕ.
///
/// В РСЯ приложения заведены по отдельности (19386995 — Android, 19461868 —
/// iOS), и чужой блок показов не даёт вовсе: до 21.08.2026 на iPhone
/// подставлялись андроидные, то есть реклама Яндекса там не работала совсем.
/// У AdMob то же самое — unit принадлежит своему приложению.
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

  static String yandexInterstitial({required bool ios}) =>
      ios ? 'R-M-19461868-3' : 'R-M-19386995-3';

  // ── AdMob ─────────────────────────────────────────────────────────────────
  static String admobBanner({required bool ios}) =>
      ios ? '' : 'ca-app-pub-1956369312643059/2560361524';

  static String admobRewarded({required bool ios}) =>
      ios ? '' : 'ca-app-pub-1956369312643059/7521878316';

  static String admobInterstitial({required bool ios}) => ios
      ? 'ca-app-pub-1956369312643059/2147075746'
      : 'ca-app-pub-1956369312643059/3192564102';
}
