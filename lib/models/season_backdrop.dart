import 'dart:math' as math;
import 'dart:ui' show Brightness, Color;

import 'package:material_color_utilities/material_color_utilities.dart';

/// Сезонный фон главной (макет «Хэллоуин поверх главной», вариант Б,
/// 08.10.2026): призрак за матовым стеклом лежит под интерфейсом и виден в
/// просветах между блоками. Как и сезонный сундук, живёт целиком на сервере —
/// запись каталога вида `backdrop`, id `backdrop_<ключ>`; даты двигает
/// `pocketbase/season_chest.py --kind backdrop`.
///
/// Картинка одна на обе темы: белая с прозрачностью (маска). Приложение
/// красит её цветом от темы — в светлой тёмной тенью, в тёмной бледным
/// свечением, иначе тёмная тень на тёмном фоне просто пропадает.
class SeasonBackdrop {
  const SeasonBackdrop({
    required this.key,
    required this.maskUrl,
    this.blurUrl,
    this.handUrl,
    this.from = '',
    this.until = '',
    this.cycleMs = 16000,
    this.inMs = 3800,
    this.holdMs = 5500,
    this.outMs = 3800,
    this.blur = 14,
    this.light = const BackdropTone(tone: 15, chroma: 40, opacity: 0.78),
    this.dark = const BackdropTone(tone: 88, chroma: 22, opacity: 0.42),
  });

  final String key;

  /// Маска во весь экран (белая, тень — прозрачностью).
  final String maskUrl;

  /// Та же маска, заранее размытая. Размытие на лету во весь экран дорого
  /// для слабых телефонов, поэтому призрак «подходит к стеклу» переходом от
  /// этой картинки к чёткой. Нет файла — просто проявление чёткой.
  final String? blurUrl;

  /// Ладонь, которая прижимается к стеклу там, где человек нажал на пустое
  /// место; null — нажатия ничего не делают.
  final String? handUrl;

  /// Первый день (`ГГГГ-ММ-ДД`, пусто — с любого дня).
  final String from;

  /// День, с которого фона уже нет; пусто — не показываем вовсе.
  final String until;

  /// Петля: проявление [inMs], [holdMs] прижат к стеклу, уход [outMs], дальше
  /// пусто до конца [cycleMs].
  final int cycleMs, inMs, holdMs, outMs;

  /// Насколько размыт призрак, пока не подошёл к стеклу.
  final double blur;

  final BackdropTone light, dark;

  static SeasonBackdrop? fromCatalog(Map<String, dynamic> row) {
    if (row['kind'] != 'backdrop') return null;
    final raw = row['data'];
    if (raw is! Map) return null;
    final d = raw.cast<String, dynamic>();
    final key = '${d['key'] ?? ''}'.trim();
    final files = d['files'] is Map ? (d['files'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final mask = files['mask'];
    if (key.isEmpty || mask is! String || mask.isEmpty) return null;
    final hand = files['hand'];
    final blurred = files['blur'];

    int ms(String k, int def) {
      final v = d[k];
      return v is num && v > 0 ? v.toInt() : def;
    }

    final cycle = ms('cycleMs', 16000).clamp(4000, 120000);
    var inMs = ms('inMs', 3800), holdMs = ms('holdMs', 5500), outMs = ms('outMs', 3800);
    // Фазы обязаны влезть в петлю: иначе призрак не уходил бы вовсе.
    final sum = inMs + holdMs + outMs;
    if (sum > cycle) {
      final k = cycle / sum;
      inMs = (inMs * k).floor();
      holdMs = (holdMs * k).floor();
      outMs = (outMs * k).floor();
    }
    final blur = d['blur'];
    return SeasonBackdrop(
      key: key,
      maskUrl: mask,
      blurUrl: blurred is String && blurred.isNotEmpty ? blurred : null,
      handUrl: hand is String && hand.isNotEmpty ? hand : null,
      from: _day(d['from']),
      until: _day(d['until']),
      cycleMs: cycle,
      inMs: inMs,
      holdMs: holdMs,
      outMs: outMs,
      blur: blur is num ? blur.toDouble().clamp(0, 40) : 14,
      light: BackdropTone.fromJson(d['light'], const BackdropTone(tone: 15, chroma: 40, opacity: 0.78)),
      dark: BackdropTone.fromJson(d['dark'], const BackdropTone(tone: 88, chroma: 22, opacity: 0.42)),
    );
  }

  static String _day(Object? v) {
    final s = '${v ?? ''}'.trim();
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) ? s : '';
  }

  /// Идёт ли фон в этот момент по часам человека.
  bool isOn(DateTime now) {
    if (until.isEmpty) return false;
    final day = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (from.isNotEmpty && day.compareTo(from) < 0) return false;
    return day.compareTo(until) < 0;
  }

  static SeasonBackdrop? activeOf(Iterable<SeasonBackdrop> list, DateTime now) {
    for (final b in list) {
      if (b.isOn(now)) return b;
    }
    return null;
  }

  /// Кадр петли на момент [ms] от её начала.
  BackdropPhase phaseAt(int ms) {
    final t = ms % cycleMs;
    double p;
    if (t < inMs) {
      p = _ease(t / inMs);
    } else if (t < inMs + holdMs) {
      p = 1;
    } else if (t < inMs + holdMs + outMs) {
      p = _ease(1 - (t - inMs - holdMs) / outMs);
    } else {
      p = 0;
    }
    return BackdropPhase(opacity: p, blur: blur * (1 - p), scale: 1 + 0.04 * (1 - p));
  }

  static double _ease(double x) => x <= 0 ? 0 : x >= 1 ? 1 : 0.5 - 0.5 * math.cos(math.pi * x);

  BackdropTone _toneOf(Brightness b) => b == Brightness.dark ? dark : light;

  /// Цвет призрака: оттенок темы ([accent]) на заданной светлоте и насыщенности.
  Color tint(Brightness brightness, Color accent) {
    final s = _toneOf(brightness);
    if (s.color != null) return s.color!;
    final hue = Hct.fromInt(accent.toARGB32()).hue;
    return Color(Hct.from(hue, s.chroma, s.tone).toInt());
  }

  double opacity(Brightness brightness) => _toneOf(brightness).opacity;
}

/// Как красить призрака в одной из тем.
class BackdropTone {
  const BackdropTone({required this.tone, required this.chroma, required this.opacity, this.color});

  final double tone, chroma, opacity;

  /// Явный цвет с сервера, сильнее расчёта от темы.
  final Color? color;

  static BackdropTone fromJson(Object? raw, BackdropTone def) {
    if (raw is! Map) return def;
    double num_(Object? v, double d, double lo, double hi) => v is num ? v.toDouble().clamp(lo, hi) : d;
    Color? color;
    final c = raw['color'];
    if (c is String) {
      final hex = c.replaceFirst('#', '');
      final v = int.tryParse(hex, radix: 16);
      if (v != null && hex.length == 6) color = Color(0xFF000000 | v);
    }
    return BackdropTone(
      tone: num_(raw['tone'], def.tone, 0, 100),
      chroma: num_(raw['chroma'], def.chroma, 0, 120),
      opacity: num_(raw['opacity'], def.opacity, 0, 1),
      color: color,
    );
  }
}

/// Кадр петли: прозрачность, размытие и масштаб призрака.
class BackdropPhase {
  const BackdropPhase({required this.opacity, required this.blur, required this.scale});
  final double opacity, blur, scale;
}
