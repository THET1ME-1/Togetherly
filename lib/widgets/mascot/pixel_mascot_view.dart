import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/mascot_anim.dart';
import '../../models/mascot_sleep.dart';

/// Проигрыватель пиксельного маскота: рисует кадр из атласа.
///
/// Пиксель-арт нельзя сглаживать — иначе он превращается в мыло, поэтому
/// картинка рисуется через `drawImageRect` с `FilterQuality.none`, а не через
/// обычный `Image` с масштабированием.
///
/// Разовые состояния (подрос, обрадовался, приземлился) проигрываются один раз
/// и возвращают маскота к обычной жизни: об этом сообщает [onOneShotDone].
class PixelMascotView extends StatefulWidget {
  const PixelMascotView({
    super.key,
    required this.anim,
    required this.state,
    this.size = 96,
    this.level = 3,
    this.sleep = SleepWindow.standard,
    this.onOneShotDone,
  });

  final MascotAnim anim;
  final MascotAnimState state;
  final double size;

  /// Ступень роста 1..3 — считается по длине серии.
  final int level;

  /// Когда персонаж уходит в ночную сцену. Задаёт человек в настройках, у
  /// каждого персонажа своё окно; умолчание — прежние 23:00–07:00.
  final SleepWindow sleep;
  final VoidCallback? onOneShotDone;

  @override
  State<PixelMascotView> createState() => _PixelMascotViewState();
}

class _PixelMascotViewState extends State<PixelMascotView> {
  ui.Image? _sheet;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Timer? _ticker;
  int _frame = 0;

  /// Своя сцена, которую персонаж разыгрывает прямо сейчас. Пусто — обычная
  /// жизнь. Ночная сцена включается по часам и не сменяется, пока ночь.
  String _scene = '';
  final math.Random _rnd = math.Random();

  MascotAnimState get _state =>
      widget.anim.has(widget.state) ? widget.state : MascotAnimState.live;

  /// Имя строки атласа для текущего кадра.
  String get _row => _state != MascotAnimState.live
      ? _state.name
      : widget.anim.idleRow(DateTime.now(), widget.sleep, scene: _scene);

  /// Что показать после того, как петля покоя доиграла.
  ///
  /// Раз в несколько кругов персонаж разыгрывает свою сцену: чистит перья,
  /// зевает, поворачивается спиной. Без этого он выглядит зациклённым
  /// роликом, а с ним — живущим своей жизнью.
  void _pickScene() {
    final scenes = widget.anim.extraIdles;
    if (scenes.isEmpty) return;
    if (_scene.isNotEmpty) {
      _scene = '';
      return;
    }
    if (_rnd.nextInt(3) == 0) _scene = scenes[_rnd.nextInt(scenes.length)];
  }

  @override
  void initState() {
    super.initState();
    _load();
    _restart();
  }

  @override
  void didUpdateWidget(covariant PixelMascotView old) {
    super.didUpdateWidget(old);
    if (old.anim.sheetUrl != widget.anim.sheetUrl) _load();
    // Ступень меняется вместе с серией: кадры надо гнать с начала, иначе
    // подросший маскот доигрывает старую петлю в новом теле.
    if (old.state != widget.state || old.level != widget.level) {
      _scene = '';
      _restart();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  void _load() {
    if (_listener != null) _stream?.removeListener(_listener!);
    // Атлас качается один раз и живёт в кэше картинок: маскот из каталога не
    // должен тянуть сеть при каждом открытии главной.
    final provider = CachedNetworkImageProvider(widget.anim.sheetUrl);
    _stream = provider.resolve(const ImageConfiguration());
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _sheet = info.image);
    }, onError: (_, _) {});
    _stream!.addListener(_listener!);
  }

  void _restart() {
    _ticker?.cancel();
    _frame = 0;
    final fps = widget.anim.fps <= 0 ? 10 : widget.anim.fps;
    _ticker = Timer.periodic(Duration(milliseconds: (1000 / fps).round()), (_) {
      if (!mounted) return;
      setState(() => _frame++);
      if (_frame >= widget.anim.cols) {
        if (_state.oneShot) {
          _ticker?.cancel();
          widget.onOneShotDone?.call();
          return;
        }
        // Петля закончилась: решаем, чем персонаж займётся на следующем круге.
        _frame = 0;
        if (_state == MascotAnimState.live) _pickScene();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    if (sheet == null) return SizedBox.square(dimension: widget.size);
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _MascotPainter(
        sheet: sheet,
        src: widget.anim.rectRow(_row, _frame, level: widget.level),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  const _MascotPainter({required this.sheet, required this.src});

  final ui.Image sheet;
  final ui.Rect src;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      sheet,
      src,
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(covariant _MascotPainter old) =>
      old.sheet != sheet || old.src != src;
}
