import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../app_sheet.dart';

/// Холст для своего настроения: нарисовать мордочку пальцем.
///
/// Полноценный `draw_screen` сюда не годится — он завязан на общий холст пары
/// (`coloringId`, обмен штрихами, слои) и весит четыре с половиной тысячи
/// строк. Здесь нужен квадрат, кисть, ластик и «готово».
///
/// Возвращает PNG 512×512 или null, если человек закрыл лист.
Future<Uint8List?> showMoodDrawSheet(BuildContext context) {
  return showAppSheet<Uint8List>(
    context,
    builder: (_) => const _MoodDrawSheet(),
  );
}

class _Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool eraser;

  _Stroke(this.points, this.color, this.width, this.eraser);
}

class _MoodDrawSheet extends StatefulWidget {
  const _MoodDrawSheet();

  @override
  State<_MoodDrawSheet> createState() => _MoodDrawSheetState();
}

class _MoodDrawSheetState extends State<_MoodDrawSheet> {
  static const List<Color> _palette = [
    Color(0xFF1F2430),
    Color(0xFFFFC800),
    Color(0xFFF06EAF),
    Color(0xFF62B8E8),
    Color(0xFF5FBF7F),
    Color(0xFFFA282F),
  ];

  final GlobalKey _canvasKey = GlobalKey();
  final List<_Stroke> _strokes = [];
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  Color _color = _palette.first;
  double _width = 14;
  bool _eraser = false;
  bool _saving = false;

  @override
  void dispose() {
    _repaint.dispose();
    super.dispose();
  }

  void _startStroke(Offset p) {
    _strokes.add(_Stroke([p], _color, _width, _eraser));
    _repaint.value++;
  }

  void _extendStroke(Offset p) {
    if (_strokes.isEmpty) return;
    _strokes.last.points.add(p);
    _repaint.value++;
  }

  /// Снимок холста в PNG. Размер 512 — как у картинок каталожных паков.
  Future<void> _done() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final side = boundary.size.width;
      final image = await boundary.toImage(pixelRatio: 512 / side);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted || data == null) return;
      Navigator.of(context).pop(data.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final t = context.appTheme;
    final cs = ProfileTheme.schemeFor(t);

    return SheetScaffold(
      title: s.customMoodDrawTitle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: RepaintBoundary(
                  key: _canvasKey,
                  child: Container(
                    color: Colors.white,
                    child: GestureDetector(
                      onPanStart: (d) => _startStroke(d.localPosition),
                      onPanUpdate: (d) => _extendStroke(d.localPosition),
                      child: CustomPaint(
                        painter: _MoodDrawPainter(_strokes, _repaint),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final c in _palette)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _color = c;
                          _eraser = false;
                        });
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: !_eraser && _color == c
                              ? Border.all(color: cs.primary, width: 3)
                              : null,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: () => setState(() => _eraser = !_eraser),
                  isSelected: _eraser,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  tooltip: s.customMoodEraser,
                ),
                IconButton.filledTonal(
                  onPressed: _strokes.isEmpty
                      ? null
                      : () {
                          _strokes.removeLast();
                          _repaint.value++;
                          setState(() {});
                        },
                  icon: const Icon(Icons.undo),
                  tooltip: s.customMoodUndo,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: _width,
              min: 4,
              max: 40,
              onChanged: (v) => setState(() => _width = v),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _strokes.isEmpty || _saving ? null : _done,
                child: Text(s.customMoodDrawDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodDrawPainter extends CustomPainter {
  final List<_Stroke> strokes;

  _MoodDrawPainter(this.strokes, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    // Ластик стирает по общему слою, поэтому холст рисуется в отдельный слой:
    // без него BlendMode.clear выел бы и белую подложку под ним.
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.eraser ? Colors.transparent : stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = stroke.eraser ? BlendMode.clear : BlendMode.srcOver;

      if (stroke.points.length == 1) {
        canvas.drawPoints(ui.PointMode.points, stroke.points,
            paint..strokeCap = StrokeCap.round);
        continue;
      }
      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MoodDrawPainter old) => true;
}
