import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Фон холста.
///
/// Рисуется кодом, а не картинками: текстура должна тянуться под любой размер
/// холста и подстраиваться под тему, а PNG пришлось бы держать в трёх
/// плотностях и всё равно мылить на больших экранах.
enum CanvasBackground {
  plain,
  grid,
  dots,
  notebook,
  millimeter,
  kraft,
  chalkboard,
  music,
  stars,
  hearts,
  watercolor,
  film,
}

/// Описание фона: как называется, сколько стоит и какими красками рисуется.
class CanvasBackgroundSpec {
  const CanvasBackgroundSpec({
    required this.id,
    required this.price,
    required this.paper,
    required this.ink,
    this.accent,
    this.dark = false,
  });

  final CanvasBackground id;

  /// Цена в монетах. 0 — доступен всем.
  final int price;

  /// Цвет самой бумаги.
  final Color paper;

  /// Цвет линовки, точек, клетки.
  final Color ink;

  /// Второй цвет для фонов, где он нужен (сердечки, звёзды).
  final Color? accent;

  /// Тёмная бумага: рисовать поверх неё нужно светлым.
  final bool dark;
}

/// Каталог фонов. Порядок тот же, что на экране выбора.
const Map<CanvasBackground, CanvasBackgroundSpec> kCanvasBackgrounds = {
  CanvasBackground.plain: CanvasBackgroundSpec(
    id: CanvasBackground.plain,
    price: 0,
    paper: Color(0xFFFFFFFF),
    ink: Color(0x00000000),
  ),
  CanvasBackground.grid: CanvasBackgroundSpec(
    id: CanvasBackground.grid,
    price: 0,
    paper: Color(0xFFFDFDFF),
    ink: Color(0xFFD7DDE8),
  ),
  CanvasBackground.dots: CanvasBackgroundSpec(
    id: CanvasBackground.dots,
    price: 0,
    paper: Color(0xFFFFFDFB),
    ink: Color(0xFFD3CFE6),
  ),
  CanvasBackground.notebook: CanvasBackgroundSpec(
    id: CanvasBackground.notebook,
    price: 30,
    paper: Color(0xFFFFFDF3),
    ink: Color(0xFFE4DFC8),
    accent: Color(0xFFE8A0A0),
  ),
  CanvasBackground.millimeter: CanvasBackgroundSpec(
    id: CanvasBackground.millimeter,
    price: 30,
    paper: Color(0xFFF7FFF7),
    ink: Color(0xFFBFE0BF),
    accent: Color(0xFF8FC98F),
  ),
  CanvasBackground.kraft: CanvasBackgroundSpec(
    id: CanvasBackground.kraft,
    price: 40,
    paper: Color(0xFFDCC09A),
    ink: Color(0x33FFFFFF),
  ),
  CanvasBackground.chalkboard: CanvasBackgroundSpec(
    id: CanvasBackground.chalkboard,
    price: 40,
    paper: Color(0xFF20301F),
    ink: Color(0x2AFFFFFF),
    dark: true,
  ),
  CanvasBackground.music: CanvasBackgroundSpec(
    id: CanvasBackground.music,
    price: 40,
    paper: Color(0xFFFFFEFA),
    ink: Color(0xFF2B2B2B),
  ),
  CanvasBackground.stars: CanvasBackgroundSpec(
    id: CanvasBackground.stars,
    price: 50,
    paper: Color(0xFF171F3D),
    ink: Color(0xFFFFFFFF),
    accent: Color(0xFF7C8BD9),
    dark: true,
  ),
  CanvasBackground.hearts: CanvasBackgroundSpec(
    id: CanvasBackground.hearts,
    price: 60,
    paper: Color(0xFFFFE9EF),
    ink: Color(0xFFF4A8BC),
  ),
  CanvasBackground.watercolor: CanvasBackgroundSpec(
    id: CanvasBackground.watercolor,
    price: 60,
    paper: Color(0xFFEAF4FF),
    ink: Color(0xFFCFE6F7),
    accent: Color(0xFFFFE3EC),
  ),
  CanvasBackground.film: CanvasBackgroundSpec(
    id: CanvasBackground.film,
    price: 60,
    paper: Color(0xFF15161A),
    ink: Color(0x1FFFFFFF),
    dark: true,
  ),
};

CanvasBackgroundSpec specOf(CanvasBackground bg) =>
    kCanvasBackgrounds[bg] ?? kCanvasBackgrounds[CanvasBackground.plain]!;

String backgroundToStorage(CanvasBackground bg) => bg.name;

CanvasBackground backgroundFromStorage(String? raw) =>
    CanvasBackground.values.firstWhere(
      (b) => b.name == raw,
      orElse: () => CanvasBackground.plain,
    );

/// Рисует фон холста.
///
/// Шаг узора задаётся в долях ширины, а не в пикселях: холст растягивается под
/// экран, и фиксированный шаг на планшете превратился бы в частую сетку.
class CanvasBackgroundPainter extends CustomPainter {
  const CanvasBackgroundPainter(this.background, {this.paperOverride});

  final CanvasBackground background;

  /// Свой цвет бумаги — когда пользователь залил фон вручную.
  final Color? paperOverride;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final spec = specOf(background);
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()..color = paperOverride ?? spec.paper);

    switch (background) {
      case CanvasBackground.plain:
        break;
      case CanvasBackground.grid:
        _grid(canvas, size, spec.ink, size.width / 22, 1);
      case CanvasBackground.dots:
        _dots(canvas, size, spec.ink, size.width / 18, 1.6);
      case CanvasBackground.notebook:
        _notebook(canvas, size, spec);
      case CanvasBackground.millimeter:
        _grid(canvas, size, spec.ink, size.width / 60, 0.6);
        _grid(canvas, size, spec.accent ?? spec.ink, size.width / 12, 1.2);
      case CanvasBackground.kraft:
        _noise(canvas, size, spec.ink, 900);
      case CanvasBackground.chalkboard:
        _noise(canvas, size, spec.ink, 500);
        _grid(canvas, size, spec.ink, size.width / 14, 0.8);
      case CanvasBackground.music:
        _staves(canvas, size, spec.ink);
      case CanvasBackground.stars:
        _stars(canvas, size, spec);
      case CanvasBackground.hearts:
        _hearts(canvas, size, spec.ink);
      case CanvasBackground.watercolor:
        _watercolor(canvas, size, spec);
      case CanvasBackground.film:
        _film(canvas, size, spec.ink);
    }
  }

  void _grid(Canvas canvas, Size size, Color color, double step, double width) {
    if (step <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _dots(Canvas canvas, Size size, Color color, double step, double r) {
    if (step <= 0) return;
    final paint = Paint()..color = color;
    for (var x = step; x < size.width; x += step) {
      for (var y = step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  void _notebook(Canvas canvas, Size size, CanvasBackgroundSpec spec) {
    final step = size.height / 16;
    final line = Paint()
      ..color = spec.ink
      ..strokeWidth = 1;
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    // Поле слева — по нему тетрадь и узнаётся.
    final margin = Paint()
      ..color = spec.accent ?? spec.ink
      ..strokeWidth = 1.4;
    final x = size.width * 0.12;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), margin);
  }

  void _staves(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final block = size.height / 5;
    final gap = block / 7;
    for (var b = 0; b < 5; b++) {
      final top = block * b + gap * 1.5;
      for (var i = 0; i < 5; i++) {
        final y = top + gap * i;
        if (y > size.height) break;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  void _stars(Canvas canvas, Size size, CanvasBackgroundSpec spec) {
    // Свой генератор с постоянным зерном: звёзды не должны прыгать при каждой
    // перерисовке холста.
    final rnd = math.Random(7);
    final small = Paint()..color = spec.accent ?? spec.ink;
    final big = Paint()..color = spec.ink;
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = rnd.nextDouble() * 1.2 + 0.4;
      canvas.drawCircle(Offset(x, y), r, r > 1.2 ? big : small);
    }
  }

  void _hearts(Canvas canvas, Size size, Color color) {
    final step = size.width / 7;
    final paint = Paint()..color = color;
    for (var row = 0; row * step < size.height + step; row++) {
      for (var col = 0; col * step < size.width + step; col++) {
        final dx = col * step + (row.isOdd ? step / 2 : 0);
        final dy = row * step;
        _heart(canvas, Offset(dx, dy), step * 0.26, paint);
      }
    }
  }

  void _heart(Canvas canvas, Offset c, double r, Paint paint) {
    canvas.drawCircle(c.translate(-r * 0.5, -r * 0.3), r * 0.55, paint);
    canvas.drawCircle(c.translate(r * 0.5, -r * 0.3), r * 0.55, paint);
    final path = Path()
      ..moveTo(c.dx - r * 1.02, c.dy - r * 0.12)
      ..lineTo(c.dx + r * 1.02, c.dy - r * 0.12)
      ..lineTo(c.dx, c.dy + r)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _watercolor(Canvas canvas, Size size, CanvasBackgroundSpec spec) {
    final rnd = math.Random(21);
    for (var i = 0; i < 7; i++) {
      final c = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      final r = size.width * (0.18 + rnd.nextDouble() * 0.22);
      final color = i.isEven ? spec.ink : (spec.accent ?? spec.ink);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55),
      );
    }
  }

  void _film(Canvas canvas, Size size, Color color) {
    // Перфорация по краям — то, по чему плёнка читается сразу.
    final hole = Paint()..color = color;
    final step = size.height / 12;
    final w = size.width * 0.045;
    for (var y = step * 0.5; y < size.height; y += step) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.02, y, w, step * 0.45),
          const Radius.circular(2),
        ),
        hole,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.935, y, w, step * 0.45),
          const Radius.circular(2),
        ),
        hole,
      );
    }
  }

  void _noise(Canvas canvas, Size size, Color color, int count) {
    final rnd = math.Random(3);
    final paint = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        rnd.nextDouble() * 1.1 + 0.3,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CanvasBackgroundPainter old) =>
      old.background != background || old.paperOverride != paperOverride;
}
