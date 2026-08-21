import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:video_player/video_player.dart';

import '../../models/chat_msg.dart';
import '../../models/shape_note.dart';
import '../../services/chat_service.dart';
import '../../services/locale_service.dart';
import '../../services/note_export_service.dart';
import '../../services/note_player_service.dart';
import '../../widgets/chat/note_shape_view.dart';
import '../../widgets/chat/note_shapes.dart';
import '../../widgets/storage_image.dart';

/// Фигурка во весь экран: крупный кадр, полоса времени и сердечки.
///
/// Двойной тап ставит сердечко на текущей секунде. Автор при следующем
/// просмотре увидит его ровно там же — в этом вся затея: отозваться не «под
/// сообщением», а в том месте, где стало тепло.
///
/// Экран получает не одну фигурку, а все фигурки переписки: свайп вбок листает
/// по ним, не возвращаясь в ленту. Плеер при этом остаётся один — соседнюю
/// открываем только тогда, когда до неё долистали.
class NoteViewerScreen extends StatefulWidget {
  /// Фигурки переписки в порядке ленты, от старых к новым.
  final List<ChatMsg> notes;

  /// С какой открыли просмотр.
  final int index;

  final String myUid;

  /// Плеер подменяется в тестах: настоящий поднимает `VideoPlayerController`,
  /// которого в тестовой среде нет.
  final NotePlayer? player;

  const NoteViewerScreen({
    super.key,
    required this.notes,
    required this.index,
    required this.myUid,
    this.player,
  });

  @override
  State<NoteViewerScreen> createState() => _NoteViewerScreenState();
}

class _NoteViewerScreenState extends State<NoteViewerScreen>
    with TickerProviderStateMixin {
  late final NotePlayer _player = widget.player ?? NotePlayerService.instance;

  /// Какую фигурку смотрим сейчас.
  late int _index = widget.index.clamp(0, widget.notes.length - 1);

  ChatMsg get _msg => widget.notes[_index];
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  /// Сердечки, которые уже всплыли в этом заходе: каждое всплывает один раз
  /// за проигрывание, иначе на паузе они молотили бы без остановки.
  final Set<int> _shown = <int>{};
  final List<_Pop> _pops = <_Pop>[];

  /// Свои отметки этого захода — они уже уехали в очередь, но их надо
  /// показывать на полосе сразу.
  late List<double> _hearts = List<double>.of(_msg.note?.hearts ?? const []);

  /// Свайп вниз едет своим каналом: `setState` на каждое движение пальца
  /// перестраивал бы весь экран вместе с кадром видео.
  final ValueNotifier<double> _dragY = ValueNotifier<double>(0);

  /// Когда в последний раз пробовали переоткрыть плеер.
  DateTime? _lastRetry;

  /// Видео так и не поехало. Пустая форма без объяснения читается как
  /// зависший экран — а это ровно то, чем баг и выглядел.
  bool _stuck = false;
  Timer? _stuckTimer;

  /// Идёт сохранение в галерею: файл готовит сервер, это пара секунд.
  bool _saving = false;

  ShapeNote get _note => _msg.note!;

  /// Палец на полосе времени: пока он там, бегунок слушается его, а не плеера.
  double? _scrub;

  @override
  void initState() {
    super.initState();
    _ticker.start();
    _openCurrent();
  }

  /// Ставит на плеер ту фигурку, которую сейчас смотрим.
  void _openCurrent() {
    _stuckTimer?.cancel();
    _lastRetry = null;
    _scrub = null;
    _shown.clear();
    _hearts = List<double>.of(_msg.note?.hearts ?? const []);
    _progress.value = 0;
    _stuckTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_player.isCurrent(_msg.id) && _player.state.playing) return;
      setState(() => _stuck = true);
    });
    // Открываем со звуком: сюда заходят смотреть, а не проматывать.
    unawaited(_player.open(
      messageId: _msg.id,
      url: _note.url,
      knownDuration: _note.duration,
      sound: true,
    ));
  }

  /// Переход к соседней фигурке переписки. За краем ничего не делаем: пружины
  /// на пустоту тут не будет, а лишний рывок читается как сбой.
  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.notes.length) return;
    unawaited(_player.stop(onlyIf: _msg.id));
    HapticFeedback.selectionClick();
    setState(() {
      _index = next;
      _stuck = false;
    });
    _openCurrent();
  }

  @override
  void dispose() {
    _stuckTimer?.cancel();
    _ticker.dispose();
    _progress.dispose();
    _dragY.dispose();
    for (final p in _pops) {
      p.ctrl.dispose();
    }
    _pops.clear();
    unawaited(_player.stop(onlyIf: _msg.id));
    super.dispose();
  }

  void _onTick(Duration _) {
    // Плеер мог забрать кто-то другой (лента под нами, второй экран, сбой
    // загрузки). Экран открыт — значит фигурка должна играть здесь: молча
    // переоткрываем, но не чаще раза в полторы секунды, чтобы не устроить
    // карусель open/stop.
    if (!_player.isCurrent(_msg.id)) {
      final now = DateTime.now();
      if (_lastRetry == null ||
          now.difference(_lastRetry!) > const Duration(milliseconds: 1500)) {
        _lastRetry = now;
        unawaited(_player.open(
          messageId: _msg.id,
          url: _note.url,
          knownDuration: _note.duration,
          sound: true,
        ));
      }
      return;
    }
    if (_stuck && _player.state.playing) {
      // Поехало со второй попытки — убираем сообщение.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _stuck = false);
      });
    }
    // Палец ведёт по полосе — бегунок его и слушается: иначе плеер тянул бы
    // метку обратно к своей позиции, и полоса дралась бы с рукой.
    if (_scrub != null) return;
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
    unawaited(ChatService.instance.addNoteHeart(_msg.id, _hearts));
  }

  /// Сохраняет фигурку в галерею: квадратный ролик с формой и подписью.
  Future<void> _save() async {
    if (_saving) return;
    final s = LocaleService.current;
    setState(() => _saving = true);
    _toast(s.noteSaving);
    final out = await NoteExportService.saveToGallery(_msg.id);
    if (!mounted) return;
    setState(() => _saving = false);
    // Код ответа в тосте — не техническая утечка, а единственный способ понять
    // причину по жалобе «не сохраняется»: разбор такой жалобы вслепую стоит
    // вечера.
    final code = out.status == null ? '' : ' · ${out.status}';
    _toast(switch (out.result) {
      NoteExportResult.saved => s.noteSaved,
      NoteExportResult.noAccess => s.noteSaveNoAccess,
      NoteExportResult.serverFailed => '${s.noteSaveServerFailed}$code',
      NoteExportResult.saveFailed => out.reason == null
          ? s.noteSaveFailed
          : '${s.noteSaveFailed} · ${out.reason}',
    });
  }

  /// Ведём бегунок за пальцем. Плееру ничего не говорим до отпускания: seek на
  /// каждое движение — это по десятку перемоток в секунду, видео от них
  /// захлёбывается и дёргается кадрами.
  void _scrubTo(double fraction, {bool commit = false}) {
    final v = fraction.clamp(0.0, 1.0);
    _scrub = v;
    _progress.value = v;
    if (commit) _commitScrub();
  }

  void _commitScrub() {
    final v = _scrub;
    if (v == null) return;
    _scrub = null;
    unawaited(_player.seekFraction(v));
  }

  void _toast(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = LocaleService.current;
    final w = MediaQuery.of(context).size.width;
    final side = math.min(w * 0.9, 460.0);
    final shape = noteShapeById(_msg.noteShape);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: GestureDetector(
        onDoubleTap: _addHeart,
        onTap: () => _player.togglePlay(),
        onVerticalDragUpdate: (d) =>
            _dragY.value = math.max(0, _dragY.value + d.delta.dy),
        onVerticalDragEnd: (_) {
          if (_dragY.value > 90) {
            Navigator.of(context).maybePop();
          } else {
            _dragY.value = 0;
          }
        },
        // Вбок — соседняя фигурка переписки. Считаем по скорости броска, а не
        // по пройденному пути: короткий резкий свайп тут привычнее долгого
        // протягивания через пол-экрана.
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -250) {
            _go(1);
          } else if (v > 250) {
            _go(-1);
          }
        },
        child: Stack(
          children: [
            // Раньше фоном стояла та же обложка, размытая на 34 — это полный
            // проход по кадру каждые шестнадцать миллисекунд поверх живого
            // видео, и на телефоне экран переставал отвечать. Сплошная
            // поверхность стоит ноль и не спорит с кадром.
            Positioned.fill(
              child: ColoredBox(color: cs.surfaceContainerLowest),
            ),
            SafeArea(
              child: ValueListenableBuilder<double>(
                valueListenable: _dragY,
                builder: (context, dy, child) => Transform.translate(
                  offset: Offset(0, dy),
                  child: child,
                ),
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
                            if (_stuck)
                              Positioned(
                                bottom: 0,
                                child: FilledButton.tonalIcon(
                                  onPressed: () {
                                    setState(() => _stuck = false);
                                    _lastRetry = null;
                                    unawaited(_player.open(
                                      messageId: _msg.id,
                                      url: _note.url,
                                      knownDuration: _note.duration,
                                      sound: true,
                                    ));
                                  },
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text(s.retry),
                                ),
                              ),
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
              _msg.name,
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
          // Сохранение в галерею: сервер собирает квадратный ролик с формой и
          // подписью, поэтому кнопка ненадолго уходит в ожидание.
          IconButton(
            onPressed: _saving ? null : _save,
            tooltip: LocaleService.current.noteSaveToGallery,
            icon: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: cs.onSurfaceVariant,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _content(ColorScheme cs) {
    final c = _player.controller;
    final size = c?.value.size ?? Size.zero;
    if (_player.isCurrent(_msg.id) &&
        c != null &&
        c.value.isInitialized &&
        size.width > 0 &&
        size.height > 0) {
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(c),
        ),
      );
    }
    return _cover(cs);
  }

  Widget _cover(ColorScheme cs) {
    final thumb = _note.thumbUrl;
    if (thumb.isEmpty) {
      // Обложки нет (старая фигурка или кадр не снялся) — показываем, что
      // видео едет, а не пустую форму: пустота читается как зависание.
      return ColoredBox(
        color: cs.surfaceContainerHigh,
        child: Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
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
                builder: (context, c) => GestureDetector(
                  key: const ValueKey('noteTimeline'),
                  // Зона касания вдвое выше самой полосы: попасть пальцем в
                  // четыре пикселя нельзя, а промах читается как «не работает».
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) =>
                      _scrubTo(d.localPosition.dx / c.maxWidth, commit: true),
                  onHorizontalDragStart: (d) =>
                      _scrubTo(d.localPosition.dx / c.maxWidth),
                  onHorizontalDragUpdate: (d) =>
                      _scrubTo(d.localPosition.dx / c.maxWidth),
                  onHorizontalDragEnd: (_) => _commitScrub(),
                  onHorizontalDragCancel: _commitScrub,
                  child: SizedBox(
                  height: 44,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 26,
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
                          top: 26,
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
                      // Ручка: без неё непонятно, что полосу можно тянуть.
                      ValueListenableBuilder<double>(
                        valueListenable: _progress,
                        builder: (_, p, _) => Positioned(
                          left: (c.maxWidth * p) - 6,
                          top: 22,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
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
                            top: 10,
                            child: Icon(Icons.favorite_rounded,
                                size: 14, color: cs.primary),
                          ),
                    ],
                  ),
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
