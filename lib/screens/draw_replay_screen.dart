import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/canvas_background.dart';
import '../models/draw_replay.dart';
import '../models/draw_stroke.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../utils/canvas_image_cache.dart';
import '../widgets/draw/stroke_painting.dart';

/// «Как рисовали» — повтор появления рисунка.
///
/// Записывать процесс не нужно: порядок мазков лежит в базе, и повтор просто
/// прокручивает его. Отсюда и вход — обычный список штрихов холста.
class DrawReplayScreen extends StatefulWidget {
  const DrawReplayScreen({
    super.key,
    required this.strokes,
    required this.theme,
    this.background = CanvasBackground.plain,
    this.sheetRatio = 1.0,
    this.pixelCols,
    this.pixelRows,
  });

  final List<DrawStroke> strokes;
  final AppTheme theme;
  final CanvasBackground background;
  final double sheetRatio;
  final int? pixelCols;
  final int? pixelRows;

  @override
  State<DrawReplayScreen> createState() => _DrawReplayScreenState();
}

class _DrawReplayScreenState extends State<DrawReplayScreen>
    with SingleTickerProviderStateMixin {
  /// Кадры гонит Ticker, а не таймер: у таймера свои часы, и шаг то попадает
  /// в кадр, то нет — рисунок дёргается на ровном месте.
  late final Ticker _ticker;

  /// Прогресс уезжает в холст каналом: перестраивать весь экран на каждый
  /// кадр незачем, меняется только картинка.
  final ValueNotifier<int> _shown = ValueNotifier(0);

  late final List<DrawStroke> _strokes;
  late final int _total;
  late final Duration _base;

  bool _playing = true;
  double _speed = 1;
  Duration _elapsed = Duration.zero;
  Duration _lastTick = Duration.zero;

  /// Растры заливок и вставленных фото: повтор показывает и их (до 20.10.2026
  /// заливки в повторе не было вовсе).
  final CanvasImageCache _images = CanvasImageCache();

  @override
  void initState() {
    super.initState();
    // Проигрываем в порядке рисования: холст отдаёт штрихи по слоям.
    _strokes = replayOrder(widget.strokes);
    _total = totalReplayPoints(_strokes);
    _base = replayDuration(_total);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shown.dispose();
    _images.dispose();
    super.dispose();
  }

  void _onTick(Duration now) {
    final delta = now - _lastTick;
    _lastTick = now;
    if (!_playing || _total == 0) return;
    _elapsed += delta * _speed;
    if (_elapsed >= _base) {
      _elapsed = _base;
      _playing = false;
      if (mounted) setState(() {});
    }
    _shown.value =
        (_total * (_elapsed.inMicroseconds / _base.inMicroseconds)).round();
  }

  void _seek(double fraction) {
    _elapsed = _base * fraction.clamp(0.0, 1.0);
    _shown.value = (_total * fraction).round();
    if (_elapsed >= _base) _playing = false;
    setState(() {});
  }

  void _toggle() {
    setState(() {
      if (_elapsed >= _base) _elapsed = Duration.zero;
      _playing = !_playing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final t = widget.theme;
    final cs = ProfileTheme.schemeFor(t);

    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Text(
            s.drawReplay,
            style: const TextStyle(
              fontFamily: 'Unbounded',
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          backgroundColor: cs.surface,
        ),
        body: _total == 0
            ? Center(
                child: Text(
                  s.drawReplayEmpty,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AspectRatio(
                          aspectRatio: widget.sheetRatio,
                          child: RepaintBoundary(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: ColoredBox(
                                color: Colors.white,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (widget.background !=
                                        CanvasBackground.plain)
                                      CustomPaint(
                                        painter: CanvasBackgroundPainter(
                                          widget.background,
                                        ),
                                      ),
                                    CustomPaint(
                                      painter: _ReplayPainter(
                                        strokes: _strokes,
                                        shown: _shown,
                                        images: _images,
                                        pixelCols: widget.pixelCols,
                                        pixelRows: widget.pixelRows,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _controls(cs, s),
                ],
              ),
      ),
    );
  }

  Widget _controls(ColorScheme cs, AppStrings s) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: _shown,
              builder: (_, value, _) => Slider(
                value: _total == 0 ? 0 : (value / _total).clamp(0.0, 1.0),
                onChanged: _seek,
              ),
            ),
            Row(
              children: [
                IconButton.filled(
                  onPressed: _toggle,
                  icon: Icon(
                    _playing
                        ? Icons.pause_rounded
                        : _elapsed >= _base
                            ? Icons.replay_rounded
                            : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  s.drawReplaySpeed,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                for (final speed in const [0.5, 1.0, 2.0, 4.0])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      selected: _speed == speed,
                      showCheckmark: false,
                      // Пишем «0,5», а не «½»: дробь есть не во всех
                      // начертаниях Onest и на части устройств выпадает
                      // пустым квадратом.
                      label: Text(speed == 0.5 ? '×0,5' : '×${speed.toInt()}'),
                      onSelected: (_) => setState(() => _speed = speed),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplayPainter extends CustomPainter {
  _ReplayPainter({
    required this.strokes,
    required this.shown,
    required this.images,
    this.pixelCols,
    this.pixelRows,
  }) : super(repaint: Listenable.merge([shown, images]));

  final List<DrawStroke> strokes;
  final ValueNotifier<int> shown;
  final CanvasImageCache images;
  final int? pixelCols;
  final int? pixelRows;

  @override
  void paint(Canvas canvas, Size size) {
    // Показанное складывается по слоям тем же кодом, что и холст: каждый слой
    // отдельно, ластик стирает только свой, заливки лежат на своих местах.
    final visible = byLayer(strokesUpTo(strokes, shown.value));
    paintLayers(
      canvas,
      visible,
      size,
      pixelCols: pixelCols,
      pixelRows: pixelRows,
      imageOf: images.imageFor,
    );
  }

  @override
  bool shouldRepaint(covariant _ReplayPainter old) =>
      old.strokes != strokes ||
      old.pixelCols != pixelCols ||
      old.pixelRows != pixelRows;
}
