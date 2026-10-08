import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/season_chest.dart';

/// Такт сбоя кнопки «Открыть 3/3» на странице сезонного сундука.
enum GlitchPhase { calm, dim, split, neg, peak, ghost }

/// Сбой кнопки по макету «Кнопка 666», вариант А (08.10.2026): кнопка мигает,
/// рвётся полосами на «13/13», один кадр вспыхивает негативом, на миг стоит
/// «666» на крови, а после возврата «666» ещё полсекунды просвечивает сквозь
/// настоящее число. Всё вместе — 0,9 с. Первый раз через 5–9 с на странице,
/// дальше раз в 10–18 с.
///
/// Подменяется только надпись: нажатие во время сбоя открывает сундук как
/// обычно, а читалка экрана слышит настоящее число.
class SeasonGlitch extends ChangeNotifier {
  SeasonGlitch(this.spec, {math.Random? random}) : _r = random ?? math.Random();

  final SeasonGlitchSpec spec;
  final math.Random _r;

  GlitchPhase phase = GlitchPhase.calm;

  /// Что стоит вместо счётчика; null — настоящее число.
  String? text;

  /// Сила разрыва 0..1 и номер кадра — по нему слои берут свои полосы.
  double power = 0;
  int frame = 0;

  /// Телефон мелко дрожит, пока надпись рвётся.
  bool get shaking => phase == GlitchPhase.split || phase == GlitchPhase.peak;

  /// Можно ли сорваться прямо сейчас: кнопка свободна, страница на экране.
  bool Function() canRun = () => true;

  /// Пик сбоя: вибрация и треск.
  VoidCallback? onPeak;

  /// Уменьшение движения: без мигания и разрывов, только подмена числа.
  bool reduced = false;

  Timer? _timer;
  int _run = 0;
  bool _disposed = false;

  bool get scheduled => _timer != null;

  void start() {
    if (_timer != null || _disposed) return;
    _schedule(first: true);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _run++;
    _set(GlitchPhase.calm, text: null, power: 0);
  }

  void _schedule({bool first = false}) {
    final ms = first ? 5000 + _r.nextInt(4000) : 10000 + _r.nextInt(8000);
    _timer = Timer(Duration(milliseconds: ms), () async {
      if (_disposed || _timer == null) return;
      if (canRun()) await play();
      if (_disposed || _timer == null) return;
      _schedule();
    });
  }

  void _set(GlitchPhase p, {String? text, double? power}) {
    phase = p;
    this.text = text;
    if (power != null) this.power = power;
    frame++;
    if (!_disposed) notifyListeners();
  }

  /// Один сбой целиком. Можно звать и руками (превью).
  Future<void> play() async {
    final run = ++_run;
    Future<bool> wait(int ms) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      return run == _run && !_disposed;
    }

    if (reduced) {
      _set(GlitchPhase.peak, text: spec.peak, power: 0);
      onPeak?.call();
      if (!await wait(700)) return;
      _set(GlitchPhase.calm, text: null, power: 0);
      return;
    }
    // 1. мигание, как от просевшего напряжения
    for (final d in const [60, 40, 70]) {
      _set(phase == GlitchPhase.dim ? GlitchPhase.calm : GlitchPhase.dim, text: null, power: 0);
      if (!await wait(d)) return;
    }
    // 2. «13/13», порванное полосами; каждый третий кадр с битыми знаками
    for (var k = 0; k < 4; k++) {
      _set(GlitchPhase.split, text: k % 3 == 2 ? garble(spec.mid, k) : spec.mid, power: 1);
      if (!await wait(40)) return;
    }
    // 3. вспышка-негатив, один кадр
    _set(GlitchPhase.neg, text: spec.peak, power: 0);
    if (!await wait(45)) return;
    // 4. «666» на крови, разрыв затихает
    onPeak?.call();
    for (var k = 0; k < 9; k++) {
      _set(GlitchPhase.peak, text: spec.peak, power: math.max(0.15, 1 - k / 9));
      if (!await wait(40)) return;
    }
    // 5. битый кадр и возврат, «666» просвечивает и тает
    _set(GlitchPhase.split, text: garble(spec.mid, 7), power: 1);
    if (!await wait(50)) return;
    _set(GlitchPhase.ghost, text: null, power: 0);
    if (!await wait(30)) return;
    _set(GlitchPhase.calm, text: null, power: 0);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// Битые знаки: цифры подменены похожими буквами.
String garble(String s, int k) {
  // Только знаки, которые есть в Unbounded: чужой глиф пришёл бы из
  // запасного шрифта и выдал бы подмену как поломку.
  const swaps = {
    '3': ['З'],
    '1': ['l', 'I'],
    '6': ['б'],
    '/': ['|'],
  };
  final out = StringBuffer();
  var i = 0;
  for (final ch in s.split('')) {
    final alts = swaps[ch];
    out.write(alts != null && (i + k) % 2 == 0 ? alts[(i + k) ~/ 2 % alts.length] : ch);
    i++;
  }
  return out.toString();
}

/// Надпись кнопки в три слоя — основной и два цветовых канала, — которые
/// сбой рвёт полосами, плюс послеобраз пика.
class GlitchLabel extends StatelessWidget {
  const GlitchLabel({super.key, required this.glitch, required this.prefix, required this.real, required this.style});

  final SeasonGlitch glitch;

  /// «Открыть»; счётчик — [real] или подмена из сбоя.
  final String prefix;
  final String real;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final g = glitch;
    final shown = '$prefix ${g.text ?? real}';
    final torn = g.power > 0 && (g.phase == GlitchPhase.split || g.phase == GlitchPhase.peak);
    final r = math.Random(g.frame * 7919);
    double rnd() => r.nextDouble() * 2 - 1;
    Widget layer(Color? color) =>
        Text(shown, maxLines: 1, softWrap: false, style: color == null ? style : style.copyWith(color: color));
    final y1 = r.nextDouble() * 0.6, y2 = math.min(1.0, y1 + 0.15 + r.nextDouble() * 0.3);
    return Stack(
      alignment: Alignment.center,
      children: [
        // послеобраз: «666» тает сквозь настоящее число
        AnimatedOpacity(
          opacity: g.phase == GlitchPhase.ghost ? 0.55 : 0,
          duration: g.phase == GlitchPhase.ghost ? Duration.zero : const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          child: Text(
            '$prefix ${g.spec.peak}',
            maxLines: 1,
            softWrap: false,
            style: style.copyWith(color: const Color(0xFFFF2A4A)),
          ),
        ),
        if (torn) ...[
          Transform.translate(
            offset: Offset(rnd() * 9 * g.power, 0),
            child: ClipRect(clipper: _Band(y1, y2), child: layer(const Color(0xFFFF2A4A))),
          ),
          Transform.translate(
            offset: Offset(rnd() * 7 * g.power, 0),
            child: ClipRect(
              clipper: _Band(math.max(0, y1 - 0.2), math.min(1, y2 + 0.2)),
              child: layer(const Color(0xFF19E6FF)),
            ),
          ),
        ],
        Transform(
          alignment: Alignment.center,
          transform: torn
              ? (Matrix4.translationValues(rnd() * 3 * g.power, 0, 0)..multiply(Matrix4.skewX(rnd() * 0.17 * g.power)))
              : Matrix4.identity(),
          child: layer(null),
        ),
      ],
    );
  }
}

/// Горизонтальная полоса надписи от [top] до [bottom] (доли высоты).
class _Band extends CustomClipper<Rect> {
  const _Band(this.top, this.bottom);

  final double top, bottom;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, size.height * top, size.width, size.height * bottom);

  @override
  bool shouldReclip(_Band old) => old.top != top || old.bottom != bottom;
}

/// Строки развёртки поверх кнопки, пока она рвётся.
class GlitchScanlines extends CustomPainter {
  const GlitchScanlines();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x52000000);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), p);
    }
  }

  @override
  bool shouldRepaint(GlitchScanlines old) => false;
}
