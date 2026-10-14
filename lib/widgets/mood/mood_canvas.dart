import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Холст своего настроения: рисуют пальцем прямо в листе «Новое настроение».
///
/// Полноценный `draw_screen` сюда не годится — он завязан на общий холст пары
/// (обмен штрихами, слои) и весит четыре с половиной тысячи строк. Здесь нужен
/// квадрат, шесть красок, ластик и отмена.
///
/// Точки и толщина хранятся в ДОЛЯХ стороны: холст на экране и картинка
/// 512×512 рисуются одним кодом и совпадают пиксель в пиксель по смыслу.
class MoodStroke {
  final List<Offset> points;
  final Color color;

  /// Толщина в долях стороны холста.
  final double width;

  /// Ластик рисует цветом фона: фон у рисунка всегда белый, и на сохранённой
  /// картинке стёртое тоже белое, а не прозрачная дыра.
  final bool eraser;

  MoodStroke({
    required List<Offset> points,
    required this.color,
    required this.width,
    this.eraser = false,
  }) : points = List.of(points);
}

/// Краски холста — те же шесть, что были у прежнего листа рисунка.
const List<Color> kMoodInks = [
  Color(0xFF1F2430),
  Color(0xFFFFC800),
  Color(0xFFF06EAF),
  Color(0xFF62B8E8),
  Color(0xFF5FBF7F),
  Color(0xFFFA282F),
];

/// Толщина кисти: на холсте в 264 точки это около двенадцати, ластик вдвое шире.
const double kMoodBrush = 0.045;
const double kMoodEraser = 0.09;

const Color _paper = Color(0xFFFFFFFF);

/// Рисует штрихи на белом листе [size]. Одна функция и для холста на экране,
/// и для сохраняемой картинки, и для рисунка-примера в пустом наборе.
void paintMoodStrokes(Canvas canvas, Size size, List<MoodStroke> strokes) {
  canvas.drawRect(Offset.zero & size, Paint()..color = _paper);
  final side = size.shortestSide;
  for (final s in strokes) {
    if (s.points.isEmpty) continue;
    final paint = Paint()
      ..color = s.eraser ? _paper : s.color
      ..strokeWidth = s.width * side
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    Offset at(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    if (s.points.length == 1) {
      canvas.drawCircle(at(s.points.first), s.width * side / 2, paint);
      continue;
    }
    final path = Path()..moveTo(at(s.points.first).dx, at(s.points.first).dy);
    for (var i = 1; i < s.points.length; i++) {
      final p = at(s.points[i]);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }
}

/// Рисунок → PNG [size]×[size] на белом. Сторона 512 — как у картинок паков.
Future<Uint8List> renderStrokesPng(List<MoodStroke> strokes, {int size = 512}) async {
  final recorder = ui.PictureRecorder();
  final side = size.toDouble();
  paintMoodStrokes(Canvas(recorder), Size(side, side), strokes);
  final image = await recorder.endRecording().toImage(size, size);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

class _StrokesPainter extends CustomPainter {
  final List<MoodStroke> strokes;

  _StrokesPainter(this.strokes, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) => paintMoodStrokes(canvas, size, strokes);

  // Список штрихов правится на месте (дописывается, отменяется), поэтому по
  // ссылке перемены не видно: перерисовываем всегда, это дёшево.
  @override
  bool shouldRepaint(covariant _StrokesPainter old) => true;
}

/// Неподвижный рисунок из штрихов: пример в пустом наборе.
class MoodStrokesView extends StatelessWidget {
  final List<MoodStroke> strokes;

  const MoodStrokesView({super.key, required this.strokes});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _StaticStrokesPainter(strokes), size: Size.infinite);
}

class _StaticStrokesPainter extends CustomPainter {
  final List<MoodStroke> strokes;

  const _StaticStrokesPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) => paintMoodStrokes(canvas, size, strokes);

  @override
  bool shouldRepaint(covariant _StaticStrokesPainter old) => old.strokes != strokes;
}

/// Квадрат, по которому рисуют пальцем. Список штрихов принадлежит листу:
/// холст его только дописывает и зовёт [onChanged] на каждом новом штрихе.
class MoodCanvas extends StatefulWidget {
  final List<MoodStroke> strokes;
  final Color color;
  final bool eraser;
  final VoidCallback onChanged;

  const MoodCanvas({
    super.key,
    required this.strokes,
    required this.color,
    required this.eraser,
    required this.onChanged,
  });

  @override
  State<MoodCanvas> createState() => _MoodCanvasState();
}

class _MoodCanvasState extends State<MoodCanvas> {
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  /// Палец, который рисует. Второй палец не начинает свой штрих поверх.
  int? _pointer;

  @override
  void dispose() {
    _repaint.dispose();
    super.dispose();
  }

  Offset _share(Offset local, Size size) => Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );

  void _noDrag(DragUpdateDetails _) {}

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      // Рисуем по сырым касаниям: они не спорят с прокруткой листа. А сами
      // перетаскивания забирает пустой детектор ниже — иначе вертикальный
      // штрих уводил бы лист вверх, а не оставлял линию.
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          widget.strokes.add(MoodStroke(
            points: [_share(e.localPosition, size)],
            color: widget.color,
            width: widget.eraser ? kMoodEraser : kMoodBrush,
            eraser: widget.eraser,
          ));
          _repaint.value++;
          widget.onChanged();
        },
        onPointerMove: (e) {
          if (e.pointer != _pointer || widget.strokes.isEmpty) return;
          widget.strokes.last.points.add(_share(e.localPosition, size));
          _repaint.value++;
        },
        onPointerUp: (e) {
          if (e.pointer == _pointer) _pointer = null;
        },
        onPointerCancel: (e) {
          if (e.pointer == _pointer) _pointer = null;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: _noDrag,
          onHorizontalDragUpdate: _noDrag,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _StrokesPainter(widget.strokes, _repaint),
              size: size,
            ),
          ),
        ),
      );
    });
  }
}
