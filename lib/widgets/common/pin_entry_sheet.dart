import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'm3_num_pad.dart';

/// Ввод PIN секретных воспоминаний: четыре крупные ячейки и своя клавиатура.
///
/// Раньше это было маленькое текстовое поле, а полэкрана занимала системная
/// клавиатура с буквами, которые тут не нужны. Ячейки показывают, сколько
/// цифр осталось, и заполняются на глазах.
class PinEntry extends StatefulWidget {
  const PinEntry({
    super.key,
    required this.create,
    required this.onDone,
    this.error,
    this.confirmHint,
    this.mismatchError,
  });

  /// true — PIN задают впервые (спрашиваем дважды),
  /// false — вводят существующий (отдаём сразу).
  final bool create;

  /// Зовётся ровно один раз, когда пароль набран целиком: при создании — после
  /// совпавшего повтора.
  final ValueChanged<String> onDone;

  /// Текст ошибки под ячейками («не тот PIN»).
  final String? error;

  /// Подсказка на втором шаге создания («Повторите пароль»).
  final String? confirmHint;

  /// Что показать, когда повтор не совпал с первым вводом.
  final String? mismatchError;

  static const int length = 4;

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry> {
  String _value = '';
  bool _sent = false;

  /// Первый набор при создании пароля. Пусто — идёт первый шаг.
  ///
  /// Повтор появился после письма в поддержку: человек «неправильно изначально
  /// ввёл пароль», и четыре случайные цифры молча стали паролем, потому что
  /// подтверждения не спрашивали.
  String _first = '';

  /// Ошибка расхождения — своя, поверх той, что пришла снаружи.
  String? _mismatch;

  void _type(String digit) {
    if (_value.length >= PinEntry.length || _sent) return;
    setState(() {
      _value += digit;
      _mismatch = null;
    });
    if (_value.length != PinEntry.length) return;

    if (!widget.create) {
      // Отдаём один раз: без этого лишние нажатия по заполненным ячейкам
      // вызывали бы проверку снова и снова.
      _sent = true;
      widget.onDone(_value);
      return;
    }

    if (_first.isEmpty) {
      setState(() {
        _first = _value;
        _value = '';
      });
      return;
    }

    if (_first == _value) {
      _sent = true;
      widget.onDone(_value);
      return;
    }

    // Не совпало — начинаем с первого шага, иначе непонятно, какой из двух
    // наборов был опечаткой.
    setState(() {
      _mismatch = widget.mismatchError;
      _first = '';
      _value = '';
    });
  }

  void _backspace() {
    if (_value.isEmpty || _sent) return;
    HapticFeedback.selectionClick();
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  /// Сброс после неверного PIN — экран остаётся, ячейки пустеют.
  void reset() => setState(() {
        _value = '';
        _sent = false;
        _first = '';
        _mismatch = null;
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < PinEntry.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: _cell(cs, i),
              ),
          ],
        ),
        if (_mismatch != null) ...[
          const SizedBox(height: 14),
          Text(
            _mismatch!,
            style: TextStyle(fontSize: 13.5, color: cs.error),
          ),
        ] else if (widget.error != null) ...[
          const SizedBox(height: 14),
          Text(
            widget.error!,
            style: TextStyle(fontSize: 13.5, color: cs.error),
          ),
        ] else if (widget.create &&
            _first.isNotEmpty &&
            widget.confirmHint != null) ...[
          const SizedBox(height: 14),
          Text(
            widget.confirmHint!,
            style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 26),
        M3NumPad(onDigit: _type, onBackspace: _backspace),
      ],
    );
  }

  Widget _cell(ColorScheme cs, int i) {
    final filled = i < _value.length;
    return AnimatedContainer(
      key: ValueKey('pin-cell-$i'),
      duration: const Duration(milliseconds: 160),
      width: 56,
      height: 68,
      decoration: BoxDecoration(
        color: filled ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: filled ? cs.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Center(
        child: AnimatedScale(
          scale: filled ? 1 : 0.4,
          duration: const Duration(milliseconds: 160),
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? cs.primary : cs.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}
