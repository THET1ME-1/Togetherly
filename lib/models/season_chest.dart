import 'dart:ui' show Color;

import 'package:flutter/animation.dart' show Cubic;

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
    this.curtainNight,
    this.curtainDay,
    this.files = const {},
    this.glitch,
    this.musicPlaylist = const [],
    this.musicFadeMs = 3500,
    this.home = false,
  });

  /// Этот сундук стоит на главной вместо обычного, пока идёт сезон
  /// (`data.home`). Решает сервер: снял флаг — на главной снова обычный.
  final bool home;

  /// Мелодии страницы по очереди (имена файлов); пусто — один файл `music`
  /// по кругу. Первая играет первой.
  final List<String> musicPlaylist;

  /// Сколько длится плавный переход между мелодиями.
  final int musicFadeMs;

  /// Адреса мелодий в порядке игры.
  List<String> get musicUrls {
    final list = [for (final name in musicPlaylist) ?files[name]];
    if (list.isNotEmpty) return list;
    final one = files['music'];
    return one == null ? const [] : [one];
  }

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

  /// Занавес в ночь (на сезонный сундук) и обратно в день; null — страница
  /// меняется без занавеса.
  final SeasonCurtain? curtainNight, curtainDay;

  /// Адреса файлов по имени без расширения: idle, open, still, card_back,
  /// card_front, curtain_night_sheet, curtain_day_sheet, drop_on, drop_off,
  /// music_*, thunder, static.
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
      curtainNight: SeasonCurtain.fromJson(c['night'], files),
      curtainDay: SeasonCurtain.fromJson(c['day'], files),
      files: files,
      glitch: SeasonGlitchSpec.fromJson(j['glitch']),
      musicPlaylist: [
        if (j['music'] is Map && (j['music'] as Map)['playlist'] is List)
          for (final n in (j['music'] as Map)['playlist'] as List) '$n',
      ],
      musicFadeMs: ms(j['music'], 'fadeMs', 3500).clamp(0, 15000),
      home: j['home'] == true,
    );
  }

  static List<SeasonChest> listFromJson(Object? raw) => [
    if (raw is List)
      for (final r in raw) ?SeasonChest.fromJson(r),
  ];
}

/// Занавес смены страницы: неподвижный лист 104% ширины и 135% высоты
/// экрана, который приложение двигает по вертикали (как макет двигал SVG).
/// Покадровое видео во весь экран телефон не успевал декодировать, и занавес
/// зависал (1.35.0+245). Сдвиг — в долях высоты листа: за [inMs] от [from] к
/// [mid] (экран закрыт, страница под ним меняется), [holdMs] стоит, за
/// [outMs] уходит к [to].
class SeasonCurtain {
  const SeasonCurtain({
    required this.sheetUrl,
    this.inMs = 620,
    this.holdMs = 0,
    this.outMs = 760,
    required this.from,
    required this.mid,
    required this.to,
  });

  final String sheetUrl;
  final int inMs, holdMs, outMs;
  final double from, mid, to;

  int get totalMs => inMs + holdMs + outMs;

  /// Экран закрыт — момент, когда страница меняется под занавесом.
  int get coverMs => inMs;

  /// Сдвиг листа (в долях его высоты) в момент [ms] от начала: въезд
  /// разгоняется, выезд тормозит.
  double offsetAt(double ms) {
    if (ms <= 0) return from;
    if (ms < inMs) return from + (mid - from) * _easeIn.transform(ms / inMs);
    if (ms < inMs + holdMs) return mid;
    if (ms >= totalMs) return to;
    return mid + (to - mid) * _easeOut.transform((ms - inMs - holdMs) / outMs);
  }

  // те же кривые, что у макета: cubic-bezier(.55,0,.8,.3) и (.2,.6,.3,1)
  static const _easeIn = Cubic(0.55, 0, 0.8, 0.3);
  static const _easeOut = Cubic(0.2, 0.6, 0.3, 1);

  static SeasonCurtain? fromJson(Object? raw, Map<String, String> files) {
    if (raw is! Map) return null;
    final url = files['${raw['sheet'] ?? ''}'];
    double? d(String k) => raw[k] is num ? (raw[k] as num).toDouble() : null;
    int i(String k, int def) => raw[k] is num ? (raw[k] as num).toInt().clamp(0, 5000) : def;
    final from = d('from'), mid = d('mid'), to = d('to');
    if (url == null || from == null || mid == null || to == null) return null;
    return SeasonCurtain(
      sheetUrl: url,
      inMs: i('inMs', 620),
      holdMs: i('holdMs', 0),
      outMs: i('outMs', 760),
      from: from,
      mid: mid,
      to: to,
    );
  }
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
