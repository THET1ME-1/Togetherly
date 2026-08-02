import 'package:flutter/foundation.dart';
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
  /// Таймер и волна приходят слушателями, а не значениями.
  ///
  /// Замеры идут каждые 60 мс. Пока они лежали в состоянии экрана чата, на
  /// каждый тик перестраивался весь экран со списком сообщений — запись шла
  /// с частотой кадра в секунду. Теперь на тик отвечают только эти два
  /// маленьких поддерева.
  final ValueListenable<Duration> elapsed;

  /// Последние замеры громкости 0..1 — бегущая волна.
  final ValueListenable<List<double>> levels;

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
                child: ValueListenableBuilder<Duration>(
                  valueListenable: elapsed,
                  builder: (_, value, _) => Text(
                    VoiceNote.formatDuration(value),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: cancelling ? cs.onErrorContainer : cs.onSurface,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<List<double>>(
                  valueListenable: levels,
                  builder: (_, value, _) => CustomPaint(
                    size: const Size(double.infinity, 26),
                    painter: _LiveWavePainter(
                      levels: value,
                      color: cancelling ? cs.onErrorContainer : cs.primary,
                    ),
                  ),
                ),
              ),
              // Куда вести палец: корзина для отмены, замок для
              // закрепления. Одних слов мало — человек не станет вести палец
              // непонятно куда и до какого места.
              if (!locked) ...[
                const SizedBox(width: 8),
                _GestureTarget(
                  icon: Icons.delete_outline_rounded,
                  arrow: Icons.keyboard_arrow_left_rounded,
                  arrowFirst: true,
                  active: cancelling,
                  activeBackground: cs.error,
                  activeForeground: cs.onError,
                  idleForeground: cs.onSurfaceVariant,
                ),
                // При отмене замок прячется: жест уже занят, и вторая цель
                // в красной полосе только сбивает.
                if (!cancelling) ...[
                  const SizedBox(width: 4),
                  _GestureTarget(
                    icon: Icons.lock_outline_rounded,
                    arrow: Icons.keyboard_arrow_up_rounded,
                    arrowFirst: false,
                    active: gesture == VoiceGesture.locking,
                    activeBackground: cs.primary,
                    activeForeground: cs.onPrimary,
                    idleForeground: cs.onSurfaceVariant,
                  ),
                ],
              ],
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

/// Значок цели жеста: иконка со стрелкой, которая наливается цветом, когда
/// палец прошёл порог и жест засчитан.
class _GestureTarget extends StatelessWidget {
  const _GestureTarget({
    required this.icon,
    required this.arrow,
    required this.arrowFirst,
    required this.active,
    required this.activeBackground,
    required this.activeForeground,
    required this.idleForeground,
  });

  final IconData icon;
  final IconData arrow;
  final bool arrowFirst;
  final bool active;
  final Color activeBackground;
  final Color activeForeground;
  final Color idleForeground;

  @override
  Widget build(BuildContext context) {
    final fg = active ? activeForeground : idleForeground;
    final parts = [
      Icon(arrow, size: 15, color: fg),
      Icon(icon, size: 17, color: fg),
    ];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.symmetric(horizontal: active ? 8 : 4, vertical: 6),
      decoration: BoxDecoration(
        color: active ? activeBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: arrowFirst ? parts : parts.reversed.toList(),
      ),
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
