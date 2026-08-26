import 'dart:convert';

/// Что открывается просмотром рекламы.
///
/// Реклама торгует ВРЕМЕНЕМ: тема и фоны даются на срок, а владение навсегда,
/// монеты сверх дневных трёх и Togetherly+ за неё не выдаются никогда. Иначе
/// проба заменяет покупку — один rewarded приносит около 0,3 ₽, а тема стоит
/// 30 монет, и отдавать её насовсем значит продавать себе в убыток.
enum AdGrantKind { theme, canvasBg, widgetPhoto }

/// Ключ награды в json профиля.
///
/// Меняя строку, поправь словарь `RULES` в `pb_hooks/coins.pb.js`: расхождение
/// ничем себя не выдаёт — кнопка нажимается, сервер отвечает отказом, человек
/// видит «не сработало». Стережёт `test/services/ad_grants_wiring_test.dart`.
String adGrantKey(AdGrantKind k) => switch (k) {
      AdGrantKind.theme => 'theme',
      AdGrantKind.canvasBg => 'canvas_bg',
      AdGrantKind.widgetPhoto => 'widget_photo',
    };

/// Обратный разбор ключа. Незнакомый ключ — null, а не исключение: поле правит
/// сервер, и новая награда не имеет права ронять старую сборку.
AdGrantKind? adGrantKindOf(String key) => switch (key) {
      'theme' => AdGrantKind.theme,
      'canvas_bg' => AdGrantKind.canvasBg,
      'widget_photo' => AdGrantKind.widgetPhoto,
      _ => null,
    };

/// Сколько просмотров стоит награда.
const Map<AdGrantKind, int> kAdGrantViews = {
  AdGrantKind.theme: 2,
  AdGrantKind.canvasBg: 1,
  AdGrantKind.widgetPhoto: 1,
};

/// Сколько награда живёт. У фона холста ноль: он считается до конца суток, а
/// не фиксированным сроком от момента выдачи.
const Map<AdGrantKind, Duration> kAdGrantDuration = {
  AdGrantKind.theme: Duration(days: 7),
  AdGrantKind.canvasBg: Duration.zero,
  AdGrantKind.widgetPhoto: Duration(days: 7),
};

/// Через сколько награду можно взять снова. Ноль — без ограничения.
const Map<AdGrantKind, Duration> kAdGrantCooldown = {
  AdGrantKind.theme: Duration(days: 14),
  AdGrantKind.canvasBg: Duration.zero,
  AdGrantKind.widgetPhoto: Duration.zero,
};

/// Общий потолок просмотров в сутки на аккаунт. Монетные три входят сюда же —
/// потолок один на всю рекламу, иначе счётчики разъезжаются.
const int kAdDailyViewCap = 8;

/// Темы, которые даются на пробу: «Северное сияние», «Мятная», «Закатная»,
/// «Медовая». Все двадцать пять открывать нельзя — проба заменила бы покупку.
const Set<int> kAdTrialThemes = {8, 9, 13, 16};

/// Одна выданная награда.
class AdGrant {
  const AdGrant({
    required this.id,
    required this.untilMs,
    required this.takenMs,
  });

  /// Что открыто: номер темы строкой или id фона.
  final String id;

  /// До какого момента действует, epoch-ms.
  final int untilMs;

  /// Когда выдана, epoch-ms. По ней считается кулдаун.
  final int takenMs;

  bool activeAt(DateTime now) => untilMs > now.millisecondsSinceEpoch;
}

/// Набор наград из поля `users.ad_grants`.
class AdGrants {
  const AdGrants(this._items);

  final Map<AdGrantKind, AdGrant> _items;

  static const AdGrants empty = AdGrants({});

  bool get isEmpty => _items.isEmpty;

  /// Разбирает json профиля.
  ///
  /// Кривое значение даёт пустой набор, а не падение: поле пишет сервер, и одна
  /// опечатка не имеет права гасить экран оформления.
  static AdGrants parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return empty;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return empty;
    }
    if (decoded is! Map) return empty;
    final out = <AdGrantKind, AdGrant>{};
    decoded.forEach((key, value) {
      final kind = adGrantKindOf('$key');
      if (kind == null || value is! Map) return;
      out[kind] = AdGrant(
        id: '${value['id'] ?? ''}',
        untilMs: (value['until'] as num?)?.toInt() ?? 0,
        takenMs: (value['taken'] as num?)?.toInt() ?? 0,
      );
    });
    return AdGrants(out);
  }

  /// Действующая награда этого вида или null.
  AdGrant? activeFor(AdGrantKind kind, DateTime now) {
    final g = _items[kind];
    if (g == null || !g.activeAt(now)) return null;
    return g;
  }

  /// Номер темы, открытой пробой.
  int? themeTrialId(DateTime now) {
    final g = activeFor(AdGrantKind.theme, now);
    if (g == null) return null;
    return int.tryParse(g.id);
  }

  /// Можно ли взять награду снова.
  bool canTake(AdGrantKind kind, DateTime now) {
    final cooldown = kAdGrantCooldown[kind] ?? Duration.zero;
    if (cooldown == Duration.zero) return true;
    final g = _items[kind];
    if (g == null || g.takenMs <= 0) return true;
    final next = DateTime.fromMillisecondsSinceEpoch(g.takenMs).add(cooldown);
    return !now.isBefore(next);
  }
}

/// Чем кончилась просьба о награде.
enum AdGrantOutcome { ok, cooldown, rateLimited, failed }

/// Ответ сервера на просьбу о временной награде.
class AdGrantResult {
  const AdGrantResult._(this.kind, {this.days = 0});

  final AdGrantOutcome kind;

  /// Сколько дней до следующей пробы. Заполнено только у [AdGrantOutcome.cooldown].
  final int days;

  static const AdGrantResult ok = AdGrantResult._(AdGrantOutcome.ok);
  static const AdGrantResult rateLimited =
      AdGrantResult._(AdGrantOutcome.rateLimited);
  static const AdGrantResult failed = AdGrantResult._(AdGrantOutcome.failed);

  factory AdGrantResult.cooldown(int days) =>
      AdGrantResult._(AdGrantOutcome.cooldown, days: days);
}
