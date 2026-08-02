import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/chat_msg.dart';
import '../../models/voice_note.dart';
import '../../services/chat_service.dart';
import '../../services/voice_player_service.dart';

/// Плеер голосового сообщения внутри пузыря чата.
///
/// Волна из сорока столбиков — та самая огибающая, что сняли при записи
/// ([VoicePeaks]), поэтому она рисуется мгновенно и одинаково у обоих. Файл
/// тянется только по нажатию «слушать».
///
/// Цвета приходят снаружи: пузырь бывает и `primary`, и тональный, и своего
/// цвета в милой обёртке, и контраст текста уже посчитан вызывающим
/// (`readable_text.dart`).
class VoiceBubble extends StatefulWidget {
  final ChatMsg msg;

  /// Цвет содержимого пузыря (столбики, время, значок).
  final Color foreground;

  /// Фон кнопки «слушать» — обычно контрастная к пузырю поверхность.
  final Color buttonBackground;

  /// Цвет значка на кнопке.
  final Color buttonForeground;

  /// Своё сообщение: у него не показываем отметку «не прослушано».
  final bool isMine;

  const VoiceBubble({
    super.key,
    required this.msg,
    required this.foreground,
    required this.buttonBackground,
    required this.buttonForeground,
    required this.isMine,
  });

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final VoicePlayerService _player = VoicePlayerService.instance;

  /// Голосовое уже слушали. Отметка серверная (`voice_heard_at`): отправителю
  /// важно видеть, что его сообщение дошло до ушей, а не только до экрана.
  bool _heard = false;

  @override
  void initState() {
    super.initState();
    _heard = widget.msg.voiceHeard;
  }

  @override
  void didUpdateWidget(covariant VoiceBubble old) {
    super.didUpdateWidget(old);
    // Отметку мог поставить второй телефон того же человека — приезжает
    // дельтой, и точка должна погаснуть без перезахода.
    if (widget.msg.voiceHeard != old.msg.voiceHeard) {
      _heard = widget.msg.voiceHeard;
    }
  }

  VoiceNote get _voice => widget.msg.voice!;

  Future<void> _toggle() async {
    // Отмечаем на первом же запуске, а не в конце: важно, что человек услышал
    // голос, а не дослушал ли до последней секунды.
    if (!_heard && !widget.isMine) {
      setState(() => _heard = true);
      unawaited(ChatService.instance.markVoiceHeard(widget.msg.id));
    }
    await _player.toggle(
      messageId: widget.msg.id,
      url: _voice.url,
      knownDuration: _voice.duration,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _player,
      builder: (context, _) {
        final current = _player.isCurrent(widget.msg.id);
        final st = _player.state;
        final playing = current && st.playing;
        final loading = current && st.loading;
        final progress = current ? st.progress : 0.0;
        final shown = current && st.position > Duration.zero
            ? st.position
            : _voice.duration;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PlayButton(
              playing: playing,
              loading: loading,
              background: widget.buttonBackground,
              foreground: widget.buttonForeground,
              onTap: _toggle,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 30,
                    child: LayoutBuilder(
                      builder: (context, c) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) {
                          if (!current) return;
                          _player.seekFraction(
                              widget.msg.id, d.localPosition.dx / c.maxWidth);
                        },
                        child: CustomPaint(
                          size: Size(c.maxWidth, 30),
                          painter: _WavePainter(
                            peaks: _voice.peaks,
                            progress: progress,
                            color: widget.foreground,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        VoiceNote.formatDuration(shown),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: widget.foreground.withValues(alpha: .72),
                        ),
                      ),
                      // У себя показываем, послушал ли партнёр; у чужого —
                      // точку «ещё не слушал».
                      if (widget.isMine && _heard) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.hearing_rounded,
                            size: 13,
                            color: widget.foreground.withValues(alpha: .8)),
                      ] else if (!widget.isMine && !_heard) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: widget.foreground,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (current)
                        _SpeedChip(
                          speed: st.speed,
                          color: widget.foreground,
                          onTap: () async {
                            await _player.cycleSpeed();
                            if (mounted) setState(() {});
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Кнопка «слушать»: скруглённый квадрат в покое, круг во время звучания.
class _PlayButton extends StatelessWidget {
  final bool playing;
  final bool loading;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(playing ? 21 : 15),
        ),
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: foreground,
                ),
              )
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(playing),
                  size: 22,
                  color: foreground,
                ),
              ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  final double speed;
  final Color color;
  final VoidCallback onTap;

  const _SpeedChip({
    required this.speed,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = speed == speed.roundToDouble()
        ? '${speed.toInt()}×'
        : '${speed.toString().replaceAll('.', ',')}×';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: .85),
          ),
        ),
      ),
    );
  }
}

/// Волна из сорока столбиков; прослушанное — в полную силу, остальное приглушено.
class _WavePainter extends CustomPainter {
  final List<double> peaks;
  final double progress;
  final Color color;

  const _WavePainter({
    required this.peaks,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    const gap = 2.0;
    final barW = (size.width - gap * (peaks.length - 1)) / peaks.length;
    if (barW <= 0) return;
    final playedTo = size.width * progress;
    final quiet = Paint()..color = color.withValues(alpha: .38);
    final loud = Paint()..color = color;

    for (var i = 0; i < peaks.length; i++) {
      final x = i * (barW + gap);
      final h = (size.height * peaks[i]).clamp(3.0, size.height);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - h) / 2, barW, h),
        Radius.circular(barW / 2),
      );
      canvas.drawRRect(rect, x + barW / 2 <= playedTo ? loud : quiet);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.color != color || old.peaks != peaks;
}
