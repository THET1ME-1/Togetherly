import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../models/chat_msg.dart';
import '../../models/shape_note.dart';
import '../../services/chat_service.dart';
import '../../services/note_player_service.dart';
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

  const NoteBubble({
    super.key,
    required this.msg,
    required this.isMine,
    required this.size,
    required this.partnerReadTs,
    this.onOpenFull,
    this.autoplay = true,
  });

  @override
  State<NoteBubble> createState() => _NoteBubbleState();
}

class _NoteBubbleState extends State<NoteBubble> {
  final NotePlayerService _player = NotePlayerService.instance;

  /// Фигурку уже смотрели. Отметка серверная (`note_seen_at`), ставит
  /// смотрящий — автору важно знать, что дошло до глаз.
  bool _seen = false;

  /// Видно ли фигурку сейчас. Ушла с экрана — снимаем её с плеера, иначе
  /// звук продолжает идти из ниоткуда.
  double _visible = 0;

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
    unawaited(_player.stop(onlyIf: widget.msg.id));
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
        animation: _player,
        builder: (context, _) {
          final current = _player.isCurrent(widget.msg.id);
          final st = _player.state;
          final playing = current && st.playing;
          final unseen = !_seen && !widget.isMine;

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
                      color: unseen ? cs.primary : cs.outlineVariant,
                      child: _content(current, cs),
                    ),
                    // Значки живут в самой широкой части формы, а не по углам:
                    // у звёздочки и клевера углы за контуром.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: widget.size * 0.06,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (current && st.muted && playing) ...[
                            const _Glyph(icon: Icons.volume_off_rounded),
                            const SizedBox(width: 8),
                          ],
                          if (widget.onOpenFull != null)
                            GestureDetector(
                              onTap: widget.onOpenFull,
                              child: const _Glyph(
                                  icon: Icons.open_in_full_rounded),
                            ),
                        ],
                      ),
                    ),
                    if (current && st.loading)
                      Positioned.fill(
                        child: Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              _meta(cs, current, st, unseen),
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
    if (!thumb.startsWith('pb://') &&
        !thumb.startsWith('http') &&
        File(thumb).existsSync()) {
      return Image.file(File(thumb), fit: BoxFit.cover);
    }
    return StorageImage(
      imageUrl: thumb,
      fit: BoxFit.cover,
      memCacheWidth: (widget.size * 2).round(),
      placeholder: (_, _) => ColoredBox(color: cs.surfaceContainerHighest),
    );
  }

  Widget _meta(ColorScheme cs, bool current, NotePlayback st, bool unseen) {
    final shown = current && st.position > Duration.zero
        ? st.duration - st.position
        : _note.duration;
    final style = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
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
  final NotePlayerService player;
  final String messageId;
  final bool playing;
  final bool unseen;
  final Color color;
  final Widget child;

  const _NoteRing({
    required this.shape,
    required this.size,
    required this.player,
    required this.messageId,
    required this.playing,
    required this.unseen,
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
    if (!widget.playing) _progress.value = widget.unseen ? 1 : 0;
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
      ringProgress: widget.playing ? 0 : (widget.unseen ? 1 : 0),
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
