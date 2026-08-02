import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Куда увели палец во время записи.
enum VoiceGesture {
  /// Держим на месте — пишем.
  recording,

  /// Увели влево за порог — отпустишь, и запись пропадёт.
  cancelling,

  /// Увели вверх за порог — запись закрепится, палец можно убрать.
  locking,
}

/// Одна кнопка справа от поля ввода: пока текста нет — микрофон, с первым
/// символом — самолётик.
///
/// Переход между ними плавный (значок сменяется поворотом и масштабом, фон
/// перетекает из тональной поверхности в `primary`), поэтому кнопка читается
/// как одна и та же, просто в другом настроении.
///
/// Жесты записи повторяют привычную механику: держишь — пишет, ведёшь влево —
/// отмена, вверх — закрепление. На каждом переломе короткая вибрация, чтобы
/// понять происходящее, не глядя на экран.
class SendMicButton extends StatefulWidget {
  final bool hasText;

  /// Правим сообщение — вместо самолётика галочка, микрофон недоступен.
  final bool editing;

  final Color primary;
  final Color onPrimary;
  final Color idleBackground;
  final Color idleForeground;

  final VoidCallback onSend;

  /// Палец опустился на микрофон: начинаем запись.
  final VoidCallback onRecordStart;

  /// Палец поехал: сообщаем экрану, что будет при отпускании.
  final ValueChanged<VoiceGesture> onRecordGesture;

  /// Палец поднялся: [cancelled] — стереть, [locked] — оставить запись идти.
  final void Function({required bool cancelled, required bool locked})
      onRecordEnd;

  const SendMicButton({
    super.key,
    required this.hasText,
    required this.editing,
    required this.primary,
    required this.onPrimary,
    required this.idleBackground,
    required this.idleForeground,
    required this.onSend,
    required this.onRecordStart,
    required this.onRecordGesture,
    required this.onRecordEnd,
  });

  @override
  State<SendMicButton> createState() => _SendMicButtonState();
}

class _SendMicButtonState extends State<SendMicButton> {
  /// Сдвиг пальца, после которого жест засчитывается. Порог небольшой —
  /// «чуть-чуть влево» должно хватать, — но не настолько, чтобы дрожь руки
  /// отменяла запись.
  static const double _cancelAt = 56;
  static const double _lockAt = 48;

  bool _pressing = false;
  VoiceGesture _gesture = VoiceGesture.recording;
  Offset _shift = Offset.zero;

  void _report(VoiceGesture g) {
    if (g == _gesture) return;
    _gesture = g;
    HapticFeedback.selectionClick();
    widget.onRecordGesture(g);
  }

  void _start() {
    if (widget.hasText || widget.editing) return;
    setState(() {
      _pressing = true;
      _gesture = VoiceGesture.recording;
      _shift = Offset.zero;
    });
    HapticFeedback.mediumImpact();
    widget.onRecordStart();
  }

  void _move(Offset delta) {
    if (!_pressing) return;
    setState(() => _shift = delta);
    if (delta.dx <= -_cancelAt) {
      _report(VoiceGesture.cancelling);
    } else if (delta.dy <= -_lockAt) {
      _report(VoiceGesture.locking);
    } else {
      _report(VoiceGesture.recording);
    }
  }

  void _end() {
    if (!_pressing) return;
    final cancelled = _gesture == VoiceGesture.cancelling;
    final locked = _gesture == VoiceGesture.locking;
    setState(() {
      _pressing = false;
      _shift = Offset.zero;
    });
    if (cancelled) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    widget.onRecordEnd(cancelled: cancelled, locked: locked);
    _gesture = VoiceGesture.recording;
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.hasText || widget.editing;
    final cancelling = _pressing && _gesture == VoiceGesture.cancelling;
    final cs = Theme.of(context).colorScheme;
    final bg = cancelling
        ? cs.errorContainer
        : (active || _pressing ? widget.primary : widget.idleBackground);
    final fg = cancelling
        ? cs.onErrorContainer
        : (active || _pressing ? widget.onPrimary : widget.idleForeground);

    // Кнопка едет за пальцем, но вдвое медленнее и в пределах жеста: движение
    // читается, а палец не теряет цель.
    final follow = _pressing
        ? Offset(
            (_shift.dx / 2).clamp(-_cancelAt.toDouble(), 0.0),
            (_shift.dy / 2).clamp(-_lockAt.toDouble(), 0.0),
          )
        : Offset.zero;

    return Transform.translate(
      offset: follow,
      child: AnimatedScale(
        scale: _pressing ? 1.28 : (active ? 1 : 0.94),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: GestureDetector(
          onTap: active ? widget.onSend : null,
          onLongPressStart: active ? null : (_) => _start(),
          onLongPressMoveUpdate:
              active ? null : (d) => _move(d.localOffsetFromOrigin),
          onLongPressEnd: active ? null : (_) => _end(),
          onLongPressCancel: active ? null : _end,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutBack,
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween<double>(begin: 0.6, end: 1).animate(anim),
                child: ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
              ),
              child: Icon(
                cancelling
                    ? Icons.delete_outline_rounded
                    : widget.editing
                        ? Icons.check_rounded
                        : widget.hasText
                            ? Icons.send_rounded
                            : Icons.mic_rounded,
                key: ValueKey(
                    '${cancelling}_${widget.editing}_${widget.hasText}'),
                color: fg,
                size: 21,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
