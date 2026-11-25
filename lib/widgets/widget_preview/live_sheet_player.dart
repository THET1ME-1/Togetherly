import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../services/widget_anim_service.dart';

/// Живое фото в превью парного виджета: кадры раскадровки по кругу.
///
/// Раскадровку (один webp, клетки по манифесту) готовит сервер, тот же файл
/// читает виджет на столе. Android играет её на самом виджете по нажатию,
/// виджет iPhone двигаться не умеет и показывает первый кадр — поэтому здесь,
/// в приложении, кадры идут всегда. Кадр выбирает то же правило, что у натива
/// (`WidgetAnimService.frameAt`), клетка обрезается под половину как `cover`.
class LiveSheetPlayer extends StatefulWidget {
  final String path;
  final WidgetAnimManifest manifest;

  const LiveSheetPlayer({super.key, required this.path, required this.manifest});

  @override
  State<LiveSheetPlayer> createState() => _LiveSheetPlayerState();
}

class _LiveSheetPlayerState extends State<LiveSheetPlayer>
    with SingleTickerProviderStateMixin {
  ui.Image? _sheet;
  late final Ticker _ticker;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    unawaited(_decode());
  }

  @override
  void didUpdateWidget(LiveSheetPlayer old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) unawaited(_decode());
  }

  Future<void> _decode() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _sheet?.dispose();
        _sheet = frame.image;
      });
      if (!_ticker.isActive) _ticker.start();
    } catch (e) {
      debugPrint('LiveSheetPlayer: не прочитать раскадровку: $e');
    }
  }

  void _onTick(Duration elapsed) {
    final next = WidgetAnimService.frameAt(widget.manifest, elapsed.inMilliseconds);
    if (next != _frame) setState(() => _frame = next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sheet?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    if (sheet == null) return const SizedBox.expand();
    return CustomPaint(
      painter: _CellPainter(sheet, WidgetAnimService.cellRect(widget.manifest, _frame)),
      size: Size.infinite,
    );
  }
}

class _CellPainter extends CustomPainter {
  final ui.Image sheet;
  final ({int left, int top, int size}) cell;

  _CellPainter(this.sheet, this.cell);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // cover: клетка квадратная, обрезаем её по пропорциям половины виджета
    final side = cell.size.toDouble();
    final aspect = size.width / size.height;
    final srcW = aspect >= 1 ? side : side * aspect;
    final srcH = aspect >= 1 ? side / aspect : side;
    final src = Rect.fromLTWH(
      cell.left + (side - srcW) / 2,
      cell.top + (side - srcH) / 2,
      srcW,
      srcH,
    );
    canvas.drawImageRect(sheet, src, Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_CellPainter old) => old.sheet != sheet || old.cell != cell;
}
