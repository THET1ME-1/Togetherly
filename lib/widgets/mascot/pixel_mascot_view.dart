import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/mascot_anim.dart';
import '../../models/mascot_frame.dart';
import '../../models/mascot_sleep.dart';
import '../../services/offline/media_view_cache.dart';

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

class _PixelMascotViewState extends State<PixelMascotView>
    with SingleTickerProviderStateMixin {
  ui.Image? _sheet;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// Кадры гонит тикер, а не таймер.
  ///
  /// `Timer.periodic` живёт по своим часам: он тикал десять раз в секунду и
  /// тогда, когда главная скрыта под чужим экраном, и каждый тик перестраивал
  /// виджет через `setState`. Тикер будит нас там, где рисуется кадр, и
  /// замирает вместе с экраном (`TickerMode`), а перерисовка идёт мимо дерева —
  /// прямо в painter. Анимация при этом та же: те же кадры, та же скорость,
  /// те же сцены.
  Ticker? _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  Duration _lastStep = Duration.zero;
  int _frame = 0;

  /// Прокрутка списка, в котором живёт персонаж.
  ///
  /// Галерея строит всех разом (`GridView` с `shrinkWrap` не ленивый), поэтому
  /// без этой проверки тридцать персонажей тикали бы одновременно, включая
  /// тех, кого не видно.
  ScrollPosition? _scroll;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scroll?.removeListener(_syncPlayback);
    _scroll = Scrollable.maybeOf(context)?.position;
    _scroll?.addListener(_syncPlayback);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPlayback());
  }

  /// Персонаж за краем экрана замирает, у края — снова играет.
  void _syncPlayback() {
    final ticker = _ticker;
    if (!mounted || ticker == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final visible = mascotOnScreen(
      top: top,
      bottom: top + box.size.height,
      screenHeight: MediaQuery.sizeOf(context).height,
    );
    if (visible && !ticker.isActive && !_state.oneShot) {
      ticker.start();
    } else if (!visible && ticker.isActive) {
      ticker.stop();
    }
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
    _scroll?.removeListener(_syncPlayback);
    _ticker?.dispose();
    _repaint.dispose();
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  void _load() {
    if (_listener != null) _stream?.removeListener(_listener!);
    // Атлас качается один раз и живёт в кэше картинок: маскот из каталога не
    // должен тянуть сеть при каждом открытии главной.
    final provider = CachedNetworkImageProvider(widget.anim.sheetUrl, cacheManager: OfflineImageCacheManager.instance);
    _stream = provider.resolve(const ImageConfiguration());
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _sheet = info.image);
    }, onError: (_, _) {});
    _stream!.addListener(_listener!);
  }

  void _restart() {
    _frame = 0;
    _lastStep = Duration.zero;
    _repaint.value++;
    _ticker ??= createTicker(_onTick);
    if (!_ticker!.isActive) _ticker!.start();
  }

  void _onTick(Duration elapsed) {
    final step = mascotFrameStep(widget.anim.fps);
    if (elapsed - _lastStep < step) return;
    _lastStep = elapsed;

    final next = nextMascotFrame(
      frame: _frame,
      cols: widget.anim.cols,
      oneShot: _state.oneShot,
    );
    _frame = next.frame;
    // Петля закончилась: решаем, чем персонаж займётся на следующем круге.
    if (next.looped && !next.finished && _state == MascotAnimState.live) {
      _pickScene();
    }
    _repaint.value++;
    if (next.finished) {
      _ticker?.stop();
      widget.onOneShotDone?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    if (sheet == null) return SizedBox.square(dimension: widget.size);
    return CustomPaint(
      size: Size.square(widget.size),
      // Кадр painter берёт сам на каждой перерисовке: дерево виджетов при
      // смене кадра не трогаем вовсе.
      painter: _MascotPainter(
        sheet: sheet,
        srcOf: () => widget.anim.rectRow(_row, _frame, level: widget.level),
        repaint: _repaint,
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({
    required this.sheet,
    required this.srcOf,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ui.Image sheet;
  final ui.Rect Function() srcOf;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      sheet,
      srcOf(),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(covariant _MascotPainter old) => old.sheet != sheet;
}
