import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Фоны чата, нарисованные кодом.
///
/// Картинок в ассетах нет намеренно: фон должен следовать за темой пары, а
/// двадцать палитр на семь фонов — это сто сорок файлов. Каждый узор рисуется
/// painter'ом от ролей схемы, поэтому в любой теме и в тёмной, и в светлой он
/// остаётся в тон и не спорит с пузырями.
///
/// Правило для всех узоров: контраст держим низким. Фон — это фон; всё, что
/// заметнее пузыря, мешает читать переписку.
enum ChatBackground {
  /// Ровная поверхность, как было раньше.
  plain,

  /// Мягкое свечение из верхнего угла — самый спокойный из непустых.
  dawn,

  /// Редкие сердечки вразнобой.
  hearts,

  /// Косая штриховка тонкими линиями.
  weave,

  /// Точки по сетке с лёгким сдвигом.
  dots,

  /// Крупные круги, уходящие за края.
  bubbles,

  /// Ночное небо с редкими звёздами.
  night,
}

/// Описание фона: как называть в списке и как рисовать.
class ChatBackgroundSpec {
  const ChatBackgroundSpec({required this.id, required this.painterOf});

  final ChatBackground id;

  /// Painter под конкретную схему. null — рисовать нечего, только заливка.
  final CustomPainter? Function(ColorScheme scheme) painterOf;
}

/// Каталог. Порядок = порядок в листе выбора.
final Map<ChatBackground, ChatBackgroundSpec> kChatBackgrounds = {
  ChatBackground.plain: ChatBackgroundSpec(
    id: ChatBackground.plain,
    painterOf: (_) => null,
  ),
  ChatBackground.dawn: ChatBackgroundSpec(
    id: ChatBackground.dawn,
    painterOf: (cs) => _DawnPainter(cs),
  ),
  ChatBackground.hearts: ChatBackgroundSpec(
    id: ChatBackground.hearts,
    painterOf: (cs) => _HeartsPainter(cs),
  ),
  ChatBackground.weave: ChatBackgroundSpec(
    id: ChatBackground.weave,
    painterOf: (cs) => _WeavePainter(cs),
  ),
  ChatBackground.dots: ChatBackgroundSpec(
    id: ChatBackground.dots,
    painterOf: (cs) => _DotsPainter(cs),
  ),
  ChatBackground.bubbles: ChatBackgroundSpec(
    id: ChatBackground.bubbles,
    painterOf: (cs) => _BubblesPainter(cs),
  ),
  ChatBackground.night: ChatBackgroundSpec(
    id: ChatBackground.night,
    painterOf: (cs) => _NightPainter(cs),
  ),
};

/// Что стоит у нового человека. Точки — самый нейтральный узор: заметен ровно
/// настолько, чтобы экран не выглядел пустым листом, и не спорит ни с одной из
/// двадцати палитр.
const ChatBackground kDefaultChatBackground = ChatBackground.dots;

/// Разбор сохранённого значения. Неизвестное имя (старая версия, опечатка) —
/// это фон по умолчанию, а не исключение: фон не та вещь, из-за которой стоит
/// ронять экран.
ChatBackground chatBackgroundFromName(String? name) {
  if (name == null || name.isEmpty) return kDefaultChatBackground;
  for (final b in ChatBackground.values) {
    if (b.name == name) return b;
  }
  return kDefaultChatBackground;
}

/// Виджет фона: заливка surface плюс узор поверх.
class ChatBackgroundView extends StatelessWidget {
  const ChatBackgroundView({
    super.key,
    required this.background,
    required this.scheme,
  });

  final ChatBackground background;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final painter = kChatBackgrounds[background]?.painterOf(scheme);
    return Container(
      color: scheme.surface,
      child: painter == null
          ? null
          : CustomPaint(painter: painter, size: Size.infinite),
    );
  }
}

// ── Узоры ───────────────────────────────────────────────────────────────────
// Все painter'ы держат `shouldRepaint` на сравнении схемы: перекрашивать надо
// при смене темы, а не на каждом кадре списка сообщений.

class _DawnPainter extends CustomPainter {
  const _DawnPainter(this.cs);
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    // Два мягких пятна из противоположных углов. Радиус берём от диагонали,
    // поэтому на планшете свечение не превращается в точку.
    final d = math.sqrt(size.width * size.width + size.height * size.height);
    void glow(Offset center, Color color, double k) {
      final rect = Rect.fromCircle(center: center, radius: d * k);
      canvas.drawCircle(
        center,
        d * k,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    glow(Offset(size.width * 0.1, 0), cs.primary.withValues(alpha: 0.16), 0.6);
    glow(Offset(size.width * 0.95, size.height),
        cs.tertiary.withValues(alpha: 0.13), 0.55);
  }

  @override
  bool shouldRepaint(_DawnPainter old) => old.cs != cs;
}

class _HeartsPainter extends CustomPainter {
  const _HeartsPainter(this.cs);
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = cs.primary.withValues(alpha: 0.07);
    const step = 92.0;
    var row = 0;
    for (double y = -20; y < size.height + step; y += step) {
      // Каждый второй ряд сдвинут на полшага: сетка перестаёт читаться рядами.
      final offset = row.isEven ? 0.0 : step / 2;
      for (double x = -20 + offset; x < size.width + step; x += step) {
        final wobble = ((row * 7 + x) % 13) - 6;
        _heart(canvas, Offset(x, y + wobble), 13 + (wobble.abs() % 4), paint);
      }
      row++;
    }
  }

  void _heart(Canvas canvas, Offset c, double s, Paint paint) {
    final p = Path()
      ..moveTo(c.dx, c.dy + s * 0.75)
      ..cubicTo(c.dx - s * 1.2, c.dy - s * 0.2, c.dx - s * 0.5, c.dy - s * 1.1,
          c.dx, c.dy - s * 0.35)
      ..cubicTo(c.dx + s * 0.5, c.dy - s * 1.1, c.dx + s * 1.2, c.dy - s * 0.2,
          c.dx, c.dy + s * 0.75)
      ..close();
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(_HeartsPainter old) => old.cs != cs;
}

class _WeavePainter extends CustomPainter {
  const _WeavePainter(this.cs);
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = cs.onSurface.withValues(alpha: 0.05)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const step = 26.0;
    // Диагональ в одну сторону: перекрестие даёт клетку, а она уже спорит с
    // прямоугольными пузырями.
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_WeavePainter old) => old.cs != cs;
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.cs);
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = cs.onSurface.withValues(alpha: 0.07);
    const step = 30.0;
    var row = 0;
    for (double y = 10; y < size.height; y += step) {
      final offset = row.isEven ? 0.0 : step / 2;
      for (double x = 10 + offset; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.8, paint);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.cs != cs;
}

class _BubblesPainter extends CustomPainter {
  const _BubblesPainter(this.cs);
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    // Позиции заданы долями от размера, а не пикселями: узор одинаково лежит
    // и на узком экране, и на планшете.
    const spots = <(double, double, double)>[
      (0.08, 0.12, 0.30),
      (0.86, 0.26, 0.22),
      (0.24, 0.55, 0.18),
      (0.92, 0.72, 0.34),
      (0.14, 0.88, 0.26),
    ];
    for (final (fx, fy, fr) in spots) {
      canvas.drawCircle(
        Offset(size.width * fx, size.height * fy),
        size.width * fr,
        Paint()..color = cs.primary.withValues(alpha: 0.055),
      );
    }
  }

  @override
  bool shouldRepaint(_BubblesPainter old) => old.cs != cs;
}

class _NightPainter extends CustomPainter {
  const _NightPainter(this.cs);
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    // Затемнение снизу вверх — небо, а не просто точки.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.primary.withValues(alpha: 0.10),
            cs.primary.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );
    // Звёзды раскладываем детерминированным генератором: узор одинаков между
    // кадрами и перерисовками, мерцания при скролле нет.
    final rnd = math.Random(7);
    for (var i = 0; i < 70; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 0.7 + rnd.nextDouble() * 1.4;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = cs.onSurface.withValues(alpha: 0.05 + rnd.nextDouble() * 0.07),
      );
    }
  }

  @override
  bool shouldRepaint(_NightPainter old) => old.cs != cs;
}
