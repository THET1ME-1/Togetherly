import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../../models/chat_msg.dart';
import '../../models/shape_note.dart';
import '../../services/chat_service.dart';
import '../../services/locale_service.dart';
import '../../services/note_player_service.dart';
import '../../widgets/chat/note_shape_view.dart';
import '../../widgets/chat/note_shapes.dart';
import '../../widgets/storage_image.dart';

/// Фигурка во весь экран: крупный кадр, полоса времени и сердечки.
///
/// Двойной тап ставит сердечко на текущей секунде. Автор при следующем
/// просмотре увидит его ровно там же — в этом вся затея: отозваться не «под
/// сообщением», а в том месте, где стало тепло.
class NoteViewerScreen extends StatefulWidget {
  final ChatMsg msg;
  final bool isMine;

  const NoteViewerScreen({super.key, required this.msg, required this.isMine});

  @override
  State<NoteViewerScreen> createState() => _NoteViewerScreenState();
}

class _NoteViewerScreenState extends State<NoteViewerScreen>
    with TickerProviderStateMixin {
  final NotePlayerService _player = NotePlayerService.instance;
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  /// Сердечки, которые уже всплыли в этом заходе: каждое всплывает один раз
  /// за проигрывание, иначе на паузе они молотили бы без остановки.
  final Set<int> _shown = <int>{};
  final List<_Pop> _pops = <_Pop>[];

  /// Свои отметки этого захода — они уже уехали в очередь, но их надо
  /// показывать на полосе сразу.
  late List<double> _hearts = List<double>.of(widget.msg.note?.hearts ?? const []);

  double _dragY = 0;

  ShapeNote get _note => widget.msg.note!;

  @override
  void initState() {
    super.initState();
    _ticker.start();
    // Открываем со звуком: сюда заходят смотреть, а не проматывать.
    unawaited(_player.open(
      messageId: widget.msg.id,
      url: _note.url,
      knownDuration: _note.duration,
      sound: true,
    ));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _progress.dispose();
    unawaited(_player.stop(onlyIf: widget.msg.id));
    super.dispose();
  }

  void _onTick(Duration _) {
    if (!_player.isCurrent(widget.msg.id)) return;
    final p = _player.smoothProgress();
    _progress.value = p;
    final total = _player.state.duration.inMilliseconds;
    if (total <= 0 || !_player.state.playing) return;
    final now = p * total / 1000;
    for (var i = 0; i < _hearts.length; i++) {
      if (_shown.contains(i)) continue;
      if ((now - _hearts[i]).abs() < 0.25) {
        _shown.add(i);
        _pop(fromAuthor: true);
      }
    }
  }

  void _pop({required bool fromAuthor}) {
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    final rnd = math.Random();
    final pop = _Pop(
      ctrl: ctrl,
      dx: (rnd.nextDouble() - 0.5) * 90,
      scale: 0.8 + rnd.nextDouble() * 0.5,
    );
    setState(() => _pops.add(pop));
    ctrl.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _pops.remove(pop));
      ctrl.dispose();
    });
  }

  void _addHeart() {
    final st = _player.state;
    final total = st.duration.inMilliseconds;
    if (total <= 0) return;
    final at = (_progress.value * total / 1000);
    setState(() {
      _hearts = [..._hearts, at]..sort();
      _shown.add(_hearts.indexOf(at)); // своё всплывает сразу, второй раз не надо
    });
    _pop(fromAuthor: false);
    unawaited(ChatService.instance.addNoteHeart(widget.msg.id, _hearts));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = LocaleService.current;
    final w = MediaQuery.of(context).size.width;
    final side = math.min(w * 0.9, 460.0);
    final shape = noteShapeById(widget.msg.noteShape);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: GestureDetector(
        onDoubleTap: _addHeart,
        onTap: () => _player.togglePlay(),
        onVerticalDragUpdate: (d) =>
            setState(() => _dragY = math.max(0, _dragY + d.delta.dy)),
        onVerticalDragEnd: (_) {
          if (_dragY > 90) {
            Navigator.of(context).maybePop();
          } else {
            setState(() => _dragY = 0);
          }
        },
        child: Stack(
          children: [
            // Фон — та же обложка, размытая: экран не проваливается в чёрное,
            // а остаётся тем же кадром.
            if (_note.hasThumb)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.22,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                    child: _cover(cs, fill: true),
                  ),
                ),
              ),
            SafeArea(
              child: Transform.translate(
                offset: Offset(0, _dragY),
                child: Column(
                  children: [
                    _header(cs),
                    Expanded(
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedBuilder(
                              animation: _player,
                              builder: (context, _) => NoteShapeView(
                                shape: shape,
                                size: side,
                                ringColor: cs.primary,
                                trackColor:
                                    cs.outlineVariant.withValues(alpha: 0.45),
                                ringWidth: 5,
                                ringListenable: _progress,
                                ringValue: () => _progress.value,
                                child: _content(cs),
                              ),
                            ),
                            for (final p in _pops)
                              _PopHeart(pop: p, color: cs.primary),
                          ],
                        ),
                      ),
                    ),
                    _timeline(cs),
                    const SizedBox(height: 10),
                    Text(
                      s.noteViewerHint,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(foregroundColor: cs.onSurface),
          ),
          Expanded(
            child: Text(
              widget.msg.name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AnimatedBuilder(
            animation: _player,
            builder: (context, _) => IconButton(
              onPressed: () => _player.toggleSound(),
              icon: Icon(_player.state.muted
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded),
              style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(ColorScheme cs) {
    final c = _player.controller;
    if (_player.isCurrent(widget.msg.id) && c != null && c.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      );
    }
    return _cover(cs);
  }

  Widget _cover(ColorScheme cs, {bool fill = false}) {
    final thumb = _note.thumbUrl;
    if (thumb.isEmpty) return ColoredBox(color: cs.surfaceContainerHigh);
    if (!thumb.startsWith('pb://') &&
        !thumb.startsWith('http') &&
        File(thumb).existsSync()) {
      return Image.file(File(thumb), fit: BoxFit.cover);
    }
    return StorageImage(
      imageUrl: thumb,
      fit: BoxFit.cover,
      placeholder: (_, _) => ColoredBox(color: cs.surfaceContainerHigh),
    );
  }

  /// Полоса времени с отметками сердечек — по ней видно, где именно партнёру
  /// стало тепло.
  Widget _timeline(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: AnimatedBuilder(
        animation: _player,
        builder: (context, _) {
          final total = _player.state.duration.inMilliseconds > 0
              ? _player.state.duration
              : _note.duration;
          return Column(
            children: [
              LayoutBuilder(
                builder: (context, c) => SizedBox(
                  height: 22,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 9,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: _progress,
                        builder: (_, p, _) => Positioned(
                          left: 0,
                          top: 9,
                          child: Container(
                            width: c.maxWidth * p,
                            height: 4,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      for (final h in _hearts)
                        if (total.inMilliseconds > 0)
                          Positioned(
                            left: (c.maxWidth *
                                    (h * 1000 / total.inMilliseconds)
                                        .clamp(0.0, 1.0)) -
                                7,
                            top: 0,
                            child: Icon(Icons.favorite_rounded,
                                size: 14, color: cs.primary),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    builder: (_, p, _) => Text(
                      ShapeNote.formatDuration(total * p),
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    ShapeNote.formatDuration(total),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Pop {
  final AnimationController ctrl;
  final double dx;
  final double scale;
  const _Pop({required this.ctrl, required this.dx, required this.scale});
}

/// Всплывающее сердечко: летит вверх и тает. Ничего не считает, поэтому живёт
/// своим слоем и не трогает ни кадр, ни полосу времени.
class _PopHeart extends StatelessWidget {
  final _Pop pop;
  final Color color;

  const _PopHeart({required this.pop, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pop.ctrl,
      builder: (context, _) {
        final t = pop.ctrl.value;
        final rise = Curves.easeOutCubic.transform(t);
        final fade = t < 0.15
            ? t / 0.15
            : (1 - ((t - 0.15) / 0.85)).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(pop.dx * rise, -180 * rise),
          child: Opacity(
            opacity: fade,
            child: Transform.scale(
              scale: pop.scale * (0.7 + 0.5 * Curves.easeOutBack.transform(t)),
              child: Icon(Icons.favorite_rounded, size: 44, color: color),
            ),
          ),
        );
      },
    );
  }
}
