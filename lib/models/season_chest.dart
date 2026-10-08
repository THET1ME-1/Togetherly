import 'dart:ui' show Color;

/// Сезонный сундук целиком с сервера (решение владельца 08.10.2026): запись
/// каталога вида `chest`, которую `/api/chest/state` отдаёт списком `seasons`,
/// пока идут её даты. Приложение своего кода под сезон не держит — имя,
/// цвета ночной страницы, анимации сундука, фон карточки, занавес смены
/// страницы и музыка приходят отсюда. Новый сундук — новая запись на сервере,
/// даты двигает `pocketbase/season_chest.py`.
class SeasonChest {
  const SeasonChest({
    required this.key,
    required this.set,
    required this.until,
    this.perDay = 3,
    this.names = const {},
    this.tags = const {},
    this.hints = const {},
    this.palette,
    this.flashColor,
    this.flashAtMs = 900,
    this.cardAspect = 600 / 516,
    this.track = const [],
    this.trackFrameMs = 60,
    this.wonAtMs = 2000,
    this.lockAtMs = 900,
    this.curtainNightMs = 1760,
    this.curtainNightCoverMs = 620,
    this.curtainDayMs = 1380,
    this.curtainDayCoverMs = 620,
    this.files = const {},
    this.glitch,
  });

  /// Сбой кнопки «Открыть 3/3» (макет «Кнопка 666»); null — кнопка честная.
  final SeasonGlitchSpec? glitch;

  /// Ключ в запросах (`chest=<ключ>`).
  final String key;

  /// Набор вещей (`data.set` у рамок, значков и подарков).
  final String set;

  /// День, с которого сундука уже нет (`ГГГГ-ММ-ДД`).
  final String until;
  final int perDay;
  final Map<String, String> names, tags, hints;

  /// Ночная страница; null — страница остаётся в теме пары.
  final SeasonPalette? palette;

  /// Вспышка на карточке, когда отлетает замок.
  final Color? flashColor;
  final int flashAtMs;

  /// Ширина к высоте карточки (фон рисуется под эту пропорцию).
  final double cardAspect;

  /// Где стоит приз в кадрах открытия: `[x, y, сторона]` в долях картинки.
  final List<List<double>?> track;
  final int trackFrameMs;
  final int wonAtMs;
  final int lockAtMs;
  final int curtainNightMs, curtainNightCoverMs, curtainDayMs, curtainDayCoverMs;

  /// Адреса файлов по имени без расширения: idle, open, still, card_back,
  /// card_front, curtain_night, curtain_day, drop_on, drop_off, music, thunder.
  final Map<String, String> files;

  String? file(String name) => files[name];

  static String _in(Map<String, String> m, String lang) {
    for (final l in [lang, 'en', 'ru']) {
      final v = m[l];
      if (v != null && v.isNotEmpty) return v;
    }
    return m.values.isEmpty ? '' : m.values.first;
  }

  String nameIn(String lang) => _in(names, lang);
  String hintIn(String lang) => _in(hints, lang);

  /// Подпись на карточке: `{date}` — дата конца сезона, её отдаёт [date].
  String tagIn(String lang, String date) => _in(tags, lang).replaceAll('{date}', date);

  /// Последний день сезона (до [until] не включая) — для подписи «до 31 октября».
  DateTime? get lastDay {
    final d = DateTime.tryParse(until);
    return d?.subtract(const Duration(days: 1));
  }

  static Map<String, String> _strMap(Object? v) =>
      v is Map ? {for (final e in v.entries) '${e.key}': '${e.value}'} : const {};

  static Color? _color(Object? v) {
    final s = '${v ?? ''}'.trim();
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s)) return null;
    return Color(0xFF000000 | int.parse(s.substring(1), radix: 16));
  }

  /// Описание из ответа сервера. Без ключа, набора или файлов сундука —
  /// null: показать нечего, кривая запись не должна ронять экран.
  static SeasonChest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final key = '${j['key'] ?? ''}'.trim();
    final set = '${j['set'] ?? ''}'.trim();
    final files = _strMap(j['files']);
    if (key.isEmpty || set.isEmpty || files['idle'] == null || files['open'] == null) return null;
    final track = <List<double>?>[];
    final t = j['track'];
    if (t is Map && t['frames'] is List) {
      for (final f in t['frames'] as List) {
        track.add(f is List && f.length == 3 ? [for (final v in f) (v as num).toDouble()] : null);
      }
    }
    int ms(Object? m, String k, int def) => m is Map && m[k] is num ? (m[k] as num).toInt() : def;
    final c = j['curtain'] is Map ? j['curtain'] as Map : const {};
    final flash = j['flash'] is Map ? j['flash'] as Map : const {};
    final aspect = j['cardAspect'];
    return SeasonChest(
      key: key,
      set: set,
      until: '${j['until'] ?? ''}',
      perDay: j['perDay'] is num ? (j['perDay'] as num).toInt() : 3,
      names: _strMap(j['name']),
      tags: _strMap(j['tag']),
      hints: _strMap(j['hint']),
      palette: SeasonPalette.fromJson(j['palette']),
      flashColor: _color(flash['color']),
      flashAtMs: ms(flash, 'atMs', 900),
      cardAspect: aspect is num && aspect > 0.5 && aspect < 3 ? aspect.toDouble() : 600 / 516,
      track: track,
      trackFrameMs: ms(t, 'frameMs', 60),
      wonAtMs: ms(t, 'wonAtMs', 2000),
      lockAtMs: ms(t, 'lockAtMs', 900),
      curtainNightMs: ms(c['night'], 'ms', 1760),
      curtainNightCoverMs: ms(c['night'], 'coverMs', 620),
      curtainDayMs: ms(c['day'], 'ms', 1380),
      curtainDayCoverMs: ms(c['day'], 'coverMs', 620),
      files: files,
      glitch: SeasonGlitchSpec.fromJson(j['glitch']),
    );
  }

  static List<SeasonChest> listFromJson(Object? raw) => [
    if (raw is List)
      for (final r in raw) ?SeasonChest.fromJson(r),
  ];
}

/// Чем срывается кнопка открытия: сперва [mid] рваными полосами, потом [peak]
/// на заливке [peakColor]. Счётчик подменяется только в надписи.
class SeasonGlitchSpec {
  const SeasonGlitchSpec({required this.mid, required this.peak, this.peakColor, this.onPeak});

  final String mid;
  final String peak;
  final Color? peakColor;
  final Color? onPeak;

  static SeasonGlitchSpec? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final mid = '${raw['mid'] ?? ''}'.trim(), peak = '${raw['peak'] ?? ''}'.trim();
    if (mid.isEmpty || peak.isEmpty) return null;
    return SeasonGlitchSpec(
      mid: mid,
      peak: peak,
      peakColor: SeasonChest._color(raw['peakColor']),
      onPeak: SeasonChest._color(raw['onPeak']),
    );
  }
}

/// Цвета ночной страницы сезонного сундука.
class SeasonPalette {
  const SeasonPalette({
    required this.page,
    required this.surface,
    required this.ink,
    required this.ink2,
    required this.fill,
    required this.onFill,
    required this.line,
  });

  final Color page, surface, ink, ink2, fill, onFill, line;

  static SeasonPalette? fromJson(Object? raw) {
    if (raw is! Map) return null;
    Color? c(String k) => SeasonChest._color(raw[k]);
    final page = c('page'), surface = c('surface'), ink = c('ink'), fill = c('fill'), onFill = c('onFill');
    if (page == null || surface == null || ink == null || fill == null || onFill == null) return null;
    return SeasonPalette(
      page: page,
      surface: surface,
      ink: ink,
      ink2: c('ink2') ?? ink,
      fill: fill,
      onFill: onFill,
      line: c('line') ?? ink,
    );
  }
}
