import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'note_shape_view.dart';
import 'note_shapes.dart';

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
/// Жесты записи: держишь — пишет, ведёшь влево — отмена, вверх —
/// закрепление, отпустил на месте — отправилось. На каждом переломе короткая
/// вибрация, чтобы понять происходящее, не глядя на экран.
class SendMicButton extends StatefulWidget {
  final bool hasText;

  /// Правим сообщение — вместо самолётика галочка, микрофон недоступен.
  final bool editing;

  /// Режим фигурки: вместо микрофона на кнопке стоит выбранная форма.
  final bool noteMode;

  /// Какая форма нарисована на кнопке. null — обычный микрофон.
  final NoteShape? noteShape;

  /// Короткое касание переключает микрофон и фигурку. Запись короче 0,8 с и
  /// так отбрасывается, поэтому место под тап было свободно.
  final VoidCallback? onModeToggle;

  /// Держать палец не обязательно: удержание ЗАПУСКАЕТ съёмку, дальше она
  /// идёт сама, а отправляют её кнопкой. Так снимают фигурку — держать
  /// телефон одной рукой и одновременно давить кнопку неудобно, а кадр от
  /// этого дрожит. У голосовых прежний порядок: отпустил — отправилось.
  final bool handsFree;

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
    this.noteMode = false,
    this.noteShape,
    this.onModeToggle,
    this.handsFree = false,
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

  /// Столько палец должен пролежать, чтобы касание стало записью.
  ///
  /// Раньше запись стартовала прямо с касания, и это ломало две вещи разом:
  /// тап поднимал микрофон или камеру (камера падала на занятом микрофоне, а
  /// система спрашивала разрешение посреди чата), а переключение режима не
  /// срабатывало вовсе — экран в этот момент считал, что запись ещё идёт.
  /// Двести миллисекунд человек не замечает, зато кнопка сразу отвечает
  /// нажатием: она вырастает от касания, а не от начала записи.
  static const Duration _holdDelay = Duration(milliseconds: 200);

  bool _pressing = false;
  VoiceGesture _gesture = VoiceGesture.recording;
  Offset _shift = Offset.zero;

  /// Палец пролежал дольше окна тапа — значит человек записывает, а не
  /// переключает режим. Считаем таймером, а не часами: системное время
  /// прыгает (перевод часов, синхронизация), и на прыжке запись превратилась
  /// бы в переключение.
  Timer? _holdTimer;

  /// Запись уже началась (порог удержания пройден).
  bool _recording = false;

  /// Где палец лёг на кнопку: сдвиг считаем от этой точки, а не от центра.
  Offset _origin = Offset.zero;

  void _report(VoiceGesture g) {
    if (g == _gesture) return;
    _gesture = g;
    HapticFeedback.selectionClick();
    widget.onRecordGesture(g);
  }

  /// Палец лёг на кнопку: отвечаем нажатием сразу, а запись ставим на таймер.
  void _press() {
    if (widget.hasText || widget.editing) return;
    _recording = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDelay, _beginRecording);
    setState(() {
      _pressing = true;
      _gesture = VoiceGesture.recording;
      _shift = Offset.zero;
    });
    HapticFeedback.selectionClick();
  }

  /// Порог пройден — теперь это запись.
  void _beginRecording() {
    _holdTimer = null;
    if (!_pressing || !mounted) return;
    _recording = true;
    HapticFeedback.mediumImpact();
    widget.onRecordStart();
  }

  void _move(Offset delta) {
    if (!_pressing) return;
    // Палец поехал до порога — это не запись и не тап, а промах или прокрутка.
    if (!_recording && delta.distance > 18) {
      _holdTimer?.cancel();
      _holdTimer = null;
      setState(() {
        _pressing = false;
        _shift = Offset.zero;
      });
      return;
    }
    if (!_recording) return;
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
    _holdTimer?.cancel();
    _holdTimer = null;
    final wasRecording = _recording;
    _recording = false;
    setState(() {
      _pressing = false;
      _shift = Offset.zero;
    });

    // Записи не было — значит это тап, и он меняет режим. Ни микрофон, ни
    // камера при этом не поднимаются: экрану нечего останавливать.
    if (!wasRecording) {
      _gesture = VoiceGesture.recording;
      widget.onModeToggle?.call();
      return;
    }

    // Руки свободны: палец подняли, съёмка продолжается. Отмену жестом влево
    // всё равно уважаем — она уже привычна по голосовым.
    if (widget.handsFree && _gesture != VoiceGesture.cancelling) {
      _gesture = VoiceGesture.recording;
      HapticFeedback.lightImpact();
      widget.onRecordEnd(cancelled: false, locked: true);
      return;
    }

    final cancelled = _gesture == VoiceGesture.cancelling;
    final locked = _gesture == VoiceGesture.locking;
    if (cancelled) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    widget.onRecordEnd(cancelled: cancelled, locked: locked);
    _gesture = VoiceGesture.recording;
  }

  /// Что нарисовано на кнопке прямо сейчас.
  Widget _glyph(bool cancelling, bool locking, Color fg) {
    final shape = widget.noteShape;
    final plain = cancelling || locking || widget.editing || widget.hasText;
    if (!plain && widget.noteMode && shape != null) {
      return NoteShapeGlyph(
        key: ValueKey('note_${shape.id}'),
        shape: shape,
        size: 21,
        color: fg,
      );
    }
    return Icon(
      cancelling
          ? Icons.delete_outline_rounded
          : locking
              ? Icons.lock_rounded
              : widget.editing
                  ? Icons.check_rounded
                  : widget.hasText
                      ? Icons.send_rounded
                      : Icons.mic_rounded,
      key: ValueKey('${cancelling}_${locking}_'
          '${widget.editing}_${widget.hasText}'),
      color: fg,
      size: 21,
    );
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.hasText || widget.editing;
    final cancelling = _pressing && _gesture == VoiceGesture.cancelling;
    final locking = _pressing && _gesture == VoiceGesture.locking;
    final cs = Theme.of(context).colorScheme;
    final bg = cancelling
        ? cs.errorContainer
        : (active || _pressing ? widget.primary : widget.idleBackground);
    final fg = cancelling
        ? cs.onErrorContainer
        : (active || _pressing ? widget.onPrimary : widget.idleForeground);

    // Кнопка едет за пальцем, но вдвое медленнее и в пределах жеста: движение
    // читается, а палец не теряет цель.
    // Кнопка едет за пальцем вдвое медленнее и в пределах жеста: влево до
    // корзины, вверх до замка. Движение читается, а палец не теряет цель.
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
        // Запись начинается от касания, а не после долгого нажатия. Раньше
        // стоял onLongPress: полсекунды кнопка молчала, и человек успевал
        // решить, что она не работает. Listener берёт палец сразу и держит
        // его до отпускания, поэтому короткое касание тоже пишет — просто
        // очень недолго.
        child: Listener(
          onPointerDown: active
              ? null
              : (e) {
                  _origin = e.position;
                  _press();
                },
          onPointerMove: active ? null : (e) => _move(e.position - _origin),
          onPointerUp: active ? null : (_) => _end(),
          onPointerCancel: active ? null : (_) => _end(),
          child: GestureDetector(
            onTap: active ? widget.onSend : null,
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
                child: _glyph(cancelling, locking, fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
