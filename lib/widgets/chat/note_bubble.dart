import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../models/chat_msg.dart';
import '../../models/shape_note.dart';
import '../../services/chat_service.dart';
import '../../dict_strings.dart' show trKey;
import '../../services/note_player_service.dart';
import '../../services/note_send_status.dart';
import '../../services/offline/connectivity_service.dart';
import '../../services/offline/outbox_service.dart';
import '../common/m3_loading.dart';
import '../storage_image.dart';
import 'note_shape_view.dart';
import 'note_shapes.dart';

/// Фигурка в ленте чата: видео в форме, обод по контуру, время под ней.
///
/// Подложки нет — фигура сама себе пузырь. Паттерн в чате уже есть: сообщение
/// из одних эмодзи тоже рисуется голым.
///
/// Пока фигурка не играет, в ней стоит обложка — кадр из середины ролика,
/// приехавший вместе с сообщением. Видео тянется только тогда, когда доходит
/// очередь смотреть: в ленте их бывает десяток подряд.
class NoteBubble extends StatefulWidget {
  final ChatMsg msg;
  final bool isMine;

  /// Сторона квадрата, в который вписана форма.
  final double size;

  /// Партнёр прочитал до этого времени — по нему рисуются галочки.
  final int partnerReadTs;

  /// Открыть во весь экран (долгое нажатие).
  final VoidCallback? onOpenFull;

  /// Автовоспроизведение при появлении в кадре.
  final bool autoplay;

  /// Плеер подменяется в тестах: настоящий поднимает `VideoPlayerController`,
  /// которого в тестовой среде нет.
  final NotePlayer? player;

  const NoteBubble({
    super.key,
    required this.msg,
    required this.isMine,
    required this.size,
    required this.partnerReadTs,
    this.onOpenFull,
    this.autoplay = true,
    this.player,
  });

  @override
  State<NoteBubble> createState() => _NoteBubbleState();
}

class _NoteBubbleState extends State<NoteBubble> {
  late final NotePlayer _player = widget.player ?? NotePlayerService.instance;

  /// Свой кружок слушает ещё и отправку: очередь, её провалы и проценты
  /// сжатия. Чужому это ни к чему.
  late final Listenable _watch = widget.isMine
      ? Listenable.merge([
          _player,
          NoteSendStatus.instance,
          OutboxService.instance.pendingCount,
          OutboxService.instance.poisonCount,
        ])
      : _player;

  NoteSendView get _sendView => noteSendView(
        mine: widget.isMine,
        pending: OutboxService.instance.isPending('chat_messages', widget.msg.id),
        poisoned:
            OutboxService.instance.isPoisoned('chat_messages', widget.msg.id),
        active: NoteSendStatus.instance.of(widget.msg.id),
      );

  /// Фигурку уже смотрели. Отметка серверная (`note_seen_at`), ставит
  /// смотрящий — автору важно знать, что дошло до глаз.
  bool _seen = false;

  /// Видно ли фигурку сейчас. Ушла с экрана — снимаем её с плеера, иначе
  /// звук продолжает идти из ниоткуда.
  double _visible = 0;

  /// Эту же фигурку открыли во весь экран — плеер теперь его.
  bool _openedFull = false;

  @override
  void initState() {
    super.initState();
    _seen = widget.msg.noteSeen;
  }

  @override
  void didUpdateWidget(covariant NoteBubble old) {
    super.didUpdateWidget(old);
    // Отметку мог поставить второй телефон того же человека — приезжает
    // дельтой, и точка должна погаснуть без перезахода.
    if (widget.msg.noteSeen != old.msg.noteSeen) _seen = widget.msg.noteSeen;
  }

  @override
  void dispose() {
    // Ту же фигурку мог открыть полноэкранный просмотр — останавливать её,
    // уходя с ленты, нельзя.
    if (!_openedFull) unawaited(_player.stop(onlyIf: widget.msg.id));
    super.dispose();
  }

  ShapeNote get _note => widget.msg.note!;

  void _markSeen() {
    if (_seen || widget.isMine) return;
    setState(() => _seen = true);
    unawaited(ChatService.instance.markNoteSeen(widget.msg.id));
  }

  void _onVisibility(VisibilityInfo info) {
    if (!mounted) return;
    // Поверх чата открыт другой экран (полноэкранный просмотр этой же
    // фигурки) — тогда лента не хозяйка плееру. Иначе выходило так: просмотр
    // запускал видео, лента через полсекунды считала себя невидимой и глушила
    // ЕГО ЖЕ воспроизведение — на весь экран оставалась пустая форма.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final was = _visible;
    _visible = info.visibleFraction;
    // Уехала за край — глушим: продолжать играть за пределами экрана незачем.
    if (_visible < 0.25 && was >= 0.25) {
      unawaited(_player.stop(onlyIf: widget.msg.id));
      return;
    }
    if (!widget.autoplay) return;
    if (_visible >= 0.6 && was < 0.6 && !_player.isCurrent(widget.msg.id)) {
      _markSeen();
      unawaited(_player.open(
        messageId: widget.msg.id,
        url: _note.url,
        knownDuration: _note.duration,
        auto: true,
      ));
    }
  }

  Future<void> _onTap() async {
    if (_player.isCurrent(widget.msg.id)) {
      // Играет молча — тап даёт звук; со звуком — ставит на паузу.
      if (_player.state.muted) {
        await _player.toggleSound();
      } else {
        await _player.togglePlay();
      }
      return;
    }
    _markSeen();
    await _player.open(
      messageId: widget.msg.id,
      url: _note.url,
      knownDuration: _note.duration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shape = noteShapeById(widget.msg.noteShape);

    return VisibilityDetector(
      key: ValueKey('note-vis-${widget.msg.id}'),
      onVisibilityChanged: _onVisibility,
      child: AnimatedBuilder(
        animation: _watch,
        builder: (context, _) {
          final current = _player.isCurrent(widget.msg.id);
          final st = _player.state;
          final playing = current && st.playing;
          final unseen = !_seen && !widget.isMine;
          final send = _sendView;
          final sending = send == NoteSendView.compressing ||
              send == NoteSendView.uploading ||
              send == NoteSendView.waiting;
          // Кружок заиграл не от касания по нему (следующий после досмотренного,
          // полный экран) — он тоже считается просмотренным.
          if (playing && unseen) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _markSeen();
            });
          }
          // Обод при отправке показывает, сколько сжато; загрузка — почти
          // полный круг, на ней мы долю не знаем.
          final sendProgress = switch (send) {
            NoteSendView.compressing =>
              0.08 + 0.72 * (NoteSendStatus.instance.of(widget.msg.id)?.progress ?? 0),
            NoteSendView.uploading => 0.9,
            NoteSendView.waiting => 0.08,
            NoteSendView.failed => 1.0,
            NoteSendView.none => null,
          };

          return Column(
            crossAxisAlignment: widget.isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _onTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _NoteRing(
                      shape: shape,
                      size: widget.size,
                      player: _player,
                      messageId: widget.msg.id,
                      playing: playing,
                      unseen: unseen,
                      sendProgress: sendProgress,
                      // Просмотренный обод не гаснет в серую нитку: он остаётся
                      // цветом темы, только тише.
                      color: send == NoteSendView.failed
                          ? cs.error
                          : (unseen || sendProgress != null)
                              ? cs.primary
                              : cs.primary.withValues(alpha: 0.35),
                      child: _content(current, cs),
                    ),
                    // Кнопки появляются, только когда кружок включён: на каждом
                    // кружке ленты они висели всегда и засоряли её. Живут в
                    // самой широкой части формы — у звёздочки и клевера углы
                    // за контуром.
                    if (current && !st.loading)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: widget.size * 0.08,
                        child: Center(
                          // Играет молча — подсказываем словами, что звук
                          // включается касанием: значок без подписи не
                          // понимали. «Развернуть» встаёт на её место, когда
                          // звук включён: вдвоём они не помещались в узкий
                          // низ круга.
                          child: st.muted && playing
                              ? _SoundHint(maxWidth: widget.size * 0.62)
                              : widget.onOpenFull == null
                                  ? const SizedBox.shrink()
                                  : GestureDetector(
                                      onTap: () {
                                        _openedFull = true;
                                        widget.onOpenFull!.call();
                                      },
                                      child: const _Glyph(
                                          icon: Icons.open_in_full_rounded),
                                    ),
                        ),
                      ),
                    if (current && st.loading)
                      Positioned.fill(
                        child: Center(
                          child: M3Loading(size: 34, color: cs.primary),
                        ),
                      ),
                    if (!current && sending)
                      Positioned.fill(
                        child: Center(
                          child: send == NoteSendView.waiting
                              ? _Badge(
                                  color: cs.surfaceContainerHigh,
                                  child: Icon(Icons.schedule_rounded,
                                      size: 22, color: cs.onSurfaceVariant),
                                )
                              : M3Loading(
                                  size: 34,
                                  color: cs.primary,
                                  contained: true,
                                  containerColor: cs.surfaceContainerHigh,
                                ),
                        ),
                      ),
                    if (!current && send == NoteSendView.failed)
                      Positioned.fill(
                        child: Center(
                          child: GestureDetector(
                            onTap: _retry,
                            child: _Badge(
                              color: cs.errorContainer,
                              child: Icon(Icons.refresh_rounded,
                                  size: 24, color: cs.onErrorContainer),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              _meta(cs, current, st, unseen, send),
            ],
          );
        },
      ),
    );
  }

  Widget _content(bool current, ColorScheme cs) {
    final c = _player.controller;
    if (current && c != null && c.value.isInitialized) {
      // Кадр вписывается в квадрат по большей стороне: у формы нет пустых
      // полей, а лицо в центре не режется.
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

  Widget _cover(ColorScheme cs) {
    final thumb = _note.thumbUrl;
    if (thumb.isEmpty) {
      return ColoredBox(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.videocam_rounded,
              size: widget.size * 0.22, color: cs.onSurfaceVariant),
        ),
      );
    }
    // Путь без схемы — это наш файл на диске, и сетевому загрузчику его
    // отдавать нельзя: `flutter_cache_manager` разбирает его как адрес и
    // падает с «No host specified in URI …/note_outbox/note_…». Файл к тому
    // времени мог уже уехать на сервер и удалиться, поэтому промах — это
    // заглушка, а не попытка скачать путь.
    if (!thumb.startsWith('pb://') && !thumb.startsWith('http')) {
      final local = File(thumb);
      if (local.existsSync()) return Image.file(local, fit: BoxFit.cover);
      return ColoredBox(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.videocam_rounded,
              size: widget.size * 0.22, color: cs.onSurfaceVariant),
        ),
      );
    }
    return StorageImage(
      imageUrl: thumb,
      fit: BoxFit.cover,
      memCacheWidth: (widget.size * 2).round(),
      placeholder: (_, _) => ColoredBox(color: cs.surfaceContainerHighest),
    );
  }

  void _retry() => unawaited(
      OutboxService.instance.retryPoisonFor('chat_messages', widget.msg.id));

  Widget _meta(ColorScheme cs, bool current, NotePlayback st, bool unseen,
      NoteSendView send) {
    final shown = current && st.position > Duration.zero
        ? st.duration - st.position
        : _note.duration;
    final style = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    if (send == NoteSendView.failed) {
      // Кнопка, а не подпись: по мелкому тексту в ленте не попадают.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: cs.error),
          const SizedBox(width: 4),
          Text(trKey('noteSendFailed'),
              style: style.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          TextButton(
            onPressed: _retry,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
            ),
            child: Text(trKey('noteSendRetry')),
          ),
        ],
      );
    }
    final sendingLabel = switch (send) {
      NoteSendView.compressing => trKey('noteSendCompressing').replaceAll(
          '{p}',
          '${((NoteSendStatus.instance.of(widget.msg.id)?.progress ?? 0) * 100).round()}'),
      NoteSendView.uploading => trKey('noteSendUploading'),
      NoteSendView.waiting => ConnectivityService.instance.isOnline
          ? trKey('noteSendQueued')
          : trKey('noteSendOffline'),
      _ => null,
    };
    if (sendingLabel != null) {
      return Text(sendingLabel, style: style.copyWith(color: cs.primary));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (unseen) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        Text(ShapeNote.formatDuration(shown), style: style),
        const SizedBox(width: 6),
        Text(_time(widget.msg.ts), style: style),
        if (widget.isMine) ...[
          const SizedBox(width: 4),
          Icon(
            widget.msg.ts <= widget.partnerReadTs
                ? Icons.done_all_rounded
                : Icons.done_rounded,
            size: 14,
            color: widget.msg.ts <= widget.partnerReadTs
                ? const Color(0xFF8FD3FF)
                : cs.onSurfaceVariant,
          ),
        ],
      ],
    );
  }

  static String _time(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}

/// Обод по контуру формы. Пока фигурка играет, доля считается каждый кадр —
/// поэтому обод здесь свой виджет со своим тикером: перерисовывается только он.
class _NoteRing extends StatefulWidget {
  final NoteShape shape;
  final double size;
  final NotePlayer player;
  final String messageId;
  final bool playing;
  final bool unseen;

  /// Доля отправки своего кружка; null — не отправляется.
  final double? sendProgress;
  final Color color;
  final Widget child;

  const _NoteRing({
    required this.shape,
    required this.size,
    required this.player,
    required this.messageId,
    required this.playing,
    required this.unseen,
    this.sendProgress,
    required this.color,
    required this.child,
  });

  @override
  State<_NoteRing> createState() => _NoteRingState();
}

class _NoteRingState extends State<_NoteRing>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _NoteRing old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) _sync();
    if (!widget.playing) _progress.value = widget.sendProgress ?? 1;
  }

  void _sync() {
    if (widget.playing && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration _) {
    if (!widget.player.isCurrent(widget.messageId)) return;
    _progress.value = widget.player.smoothProgress();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NoteShapeView(
      shape: widget.shape,
      size: widget.size,
      ringColor: widget.color,
      ringWidth: 4,
      // Обод есть всегда: у непросмотренного он яркий, у просмотренного тихий.
      // Пока он пропадал совсем, кружок после просмотра выглядел выключенным.
      ringProgress: widget.playing ? 0 : (widget.sendProgress ?? 1),
      ringListenable: widget.playing ? _progress : null,
      ringValue: widget.playing ? () => _progress.value : null,
      child: widget.child,
    );
  }
}

class _Glyph extends StatelessWidget {
  final IconData icon;
  const _Glyph({required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0x66000000),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      );
}


/// Круглая подложка под значок посреди кружка.
class _Badge extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Badge({required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: child,
      );
}

/// «Коснитесь — звук» поверх кружка, который играет молча.
class _SoundHint extends StatelessWidget {
  final double maxWidth;
  const _SoundHint({required this.maxWidth});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0x66000000),
            borderRadius: BorderRadius.circular(16),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.volume_off_rounded, size: 17, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  trKey('noteTapForSound'),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
