import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
///
/// Кадры гонит [Ticker], а не `Timer.periodic`: таймер живёт по своим часам и
/// с развёрткой экрана не совпадает — кадр то догоняет её, то ждёт лишние
/// шестнадцать миллисекунд, и персонаж дёргается на ровном месте. Тикер будит
/// виджет ровно там, где кадр рисуется, а заодно молчит, пока экран под другим
/// маршрутом (`TickerMode`), — прежний таймер крутил кадры и в свёрнутом
/// приложении.
///
/// Кадр уезжает в painter значением [ValueNotifier], поэтому дерево виджетов
/// не перестраивается вовсе: десять раз в секунду идёт только перерисовка, и
/// та заперта в [RepaintBoundary].
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

class _PixelMascotViewState extends State<PixelMascotView>
    with SingleTickerProviderStateMixin {
  ui.Image? _sheet;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Ticker? _ticker;
  int _frame = 0;

  /// Что рисовать прямо сейчас: строка атласа и номер кадра в ней. Запись, а
  /// не свой класс, — у записей структурное равенство, поэтому повтор того же
  /// кадра слушателей не будит.
  final ValueNotifier<(String, int)> _cel = ValueNotifier<(String, int)>(
    ('', 0),
  );

  /// Сколько держится один кадр и когда сменился прошлый.
  Duration _step = const Duration(milliseconds: 100);
  Duration _shown = Duration.zero;

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
    // Останавливаем явно, а не полагаемся на уничтожение: `Ticker.dispose`
    // гасит бегущий тикер молча, и в коде не видно, что персонаж перестал
    // двигаться. Стережёт `test/widgets/mascot_ticker_dispose_test.dart`.
    _ticker?.stop();
    _ticker?.dispose();
    _cel.dispose();
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
    _frame = 0;
    _shown = Duration.zero;
    final fps = widget.anim.fps <= 0 ? 10 : widget.anim.fps;
    _step = Duration(milliseconds: (1000 / fps).round());
    _cel.value = (_row, 0);
    _ticker ??= createTicker(_onTick);
    if (!_ticker!.isActive) _ticker!.start();
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _shown < _step) return;
    // Шаг прибавляем, а не приравниваем к текущему времени: так кадры идут
    // ровно по своей сетке. А если экран не рисовался долго (ушли в другое
    // приложение), сетку сбрасываем — иначе персонаж отыгрывает пропущенное
    // ускоренной перемоткой.
    _shown = (elapsed - _shown > _step * 2) ? elapsed : _shown + _step;
    _advance();
  }

  /// Следующий кадр петли.
  void _advance() {
    var next = _frame + 1;
    if (next >= widget.anim.cols) {
      if (_state.oneShot) {
        _ticker?.stop();
        widget.onOneShotDone?.call();
        return;
      }
      // Петля закончилась: решаем, чем персонаж займётся на следующем круге.
      next = 0;
      if (_state == MascotAnimState.live) _pickScene();
    }
    _frame = next;
    _cel.value = (_row, _frame);
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    if (sheet == null) return SizedBox.square(dimension: widget.size);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _MascotPainter(
          sheet: sheet,
          anim: widget.anim,
          level: widget.level,
          cel: _cel,
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({
    required this.sheet,
    required this.anim,
    required this.level,
    required this.cel,
  }) : super(repaint: cel);

  final ui.Image sheet;
  final MascotAnim anim;
  final int level;

  /// Кадр приходит сюда напрямую: смена кадра перерисовывает картинку, не
  /// трогая дерево виджетов.
  final ValueListenable<(String, int)> cel;

  @override
  void paint(Canvas canvas, Size size) {
    final (row, frame) = cel.value;
    canvas.drawImageRect(
      sheet,
      anim.rectRow(row, frame, level: level),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(covariant _MascotPainter old) =>
      old.sheet != sheet || old.anim != anim || old.level != level;
}
