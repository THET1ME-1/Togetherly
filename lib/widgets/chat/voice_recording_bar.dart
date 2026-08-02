import 'package:flutter/material.dart';

import '../../models/voice_note.dart';
import '../../services/locale_service.dart';
import 'send_mic_button.dart';

/// Полоса, которая подменяет поле ввода на время записи.
///
/// Пока палец держит микрофон, здесь идёт таймер, живая волна и подсказка, что
/// будет при отпускании. Закрепили запись — вместо подсказки появляются «Отмена»
/// и кнопка «Отправить»: руки свободны, говорить можно сколько нужно.
class VoiceRecordingBar extends StatelessWidget {
  final Duration elapsed;

  /// Последние замеры громкости 0..1 — бегущая волна.
  final List<double> levels;

  /// Что случится, если сейчас отпустить палец.
  final VoiceGesture gesture;

  /// Запись закреплена: палец убран, пишем дальше.
  final bool locked;

  final VoidCallback onCancel;
  final VoidCallback onSend;

  const VoiceRecordingBar({
    super.key,
    required this.elapsed,
    required this.levels,
    required this.gesture,
    required this.locked,
    required this.onCancel,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = LocaleService.current;
    final cancelling = gesture == VoiceGesture.cancelling;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!locked)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: cancelling ? FontWeight.w700 : FontWeight.w500,
                color: cancelling ? cs.error : cs.onSurfaceVariant,
              ),
              child: Text(
                cancelling
                    ? s.voiceReleaseToCancel
                    : gesture == VoiceGesture.locking
                        ? s.voiceReleaseToLock
                        : s.voiceSlideHints,
              ),
            ),
          ),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: cancelling ? cs.errorContainer : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              _RecDot(color: cancelling ? cs.onErrorContainer : cs.error),
              const SizedBox(width: 10),
              SizedBox(
                width: 42,
                child: Text(
                  VoiceNote.formatDuration(elapsed),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: cancelling ? cs.onErrorContainer : cs.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: CustomPaint(
                  size: const Size(double.infinity, 26),
                  painter: _LiveWavePainter(
                    levels: levels,
                    color: cancelling ? cs.onErrorContainer : cs.primary,
                  ),
                ),
              ),
              if (locked) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(s.cancel),
                ),
                IconButton.filled(
                  onPressed: onSend,
                  icon: const Icon(Icons.send_rounded, size: 19),
                  style: IconButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    minimumSize: const Size(40, 40),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RecDot extends StatefulWidget {
  final Color color;
  const _RecDot({required this.color});

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 1, end: .25).animate(_c),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      );
}

/// Бегущая волна текущей громкости: новое приходит справа, старое уезжает влево.
class _LiveWavePainter extends CustomPainter {
  final List<double> levels;
  final Color color;

  const _LiveWavePainter({required this.levels, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    const barW = 3.0;
    final fit = ((size.width + gap) / (barW + gap)).floor();
    if (fit <= 0) return;
    final shown = levels.length <= fit
        ? levels
        : levels.sublist(levels.length - fit);
    final paint = Paint()..color = color;
    // Рисуем от правого края: свежий замер всегда у кромки, как бегунок.
    for (var i = 0; i < shown.length; i++) {
      final v = shown[shown.length - 1 - i];
      final h = (size.height * (0.12 + v * 0.88)).clamp(3.0, size.height);
      final x = size.width - (i + 1) * (barW + gap);
      if (x < 0) break;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, barW, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LiveWavePainter old) =>
      old.levels != levels || old.color != color;
}
