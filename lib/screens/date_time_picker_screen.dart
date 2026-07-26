import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../utils/date_wheel.dart';

/// Полноэкранный выбор даты и времени крупными барабанами.
///
/// Пришёл на смену нижнему листу с полем «ДД.ММ.ГГГГ»: в лист крупная
/// типографика не влезала, месяц наезжал на год, а год обрезался. На своём
/// экране места хватает, и надписи видны целиком — длинные месяцы («сентября»)
/// ужимаются по ширине колонки, а не режутся.
///
/// Барабаны — родной [ListWheelScrollView]: он сам даёт снап, инерцию и
/// затухание к краям, из-за которого и получается силуэт песочных часов.
class DateTimePickerScreen extends StatefulWidget {
  const DateTimePickerScreen({
    super.key,
    required this.title,
    required this.theme,
    required this.firstYear,
    required this.lastYear,
    this.initial,
    this.withTime = true,
  });

  final String title;
  final AppTheme theme;
  final int firstYear;
  final int lastYear;
  final DateTime? initial;

  /// Показывать ли вкладку времени. Для дня рождения время лишнее.
  final bool withTime;

  @override
  State<DateTimePickerScreen> createState() => _DateTimePickerScreenState();
}

class _DateTimePickerScreenState extends State<DateTimePickerScreen> {
  late int _day;
  late int _month;
  late int _year;
  late int _hour;
  late int _minute;

  /// false — крутим дату, true — время. Барабаны меняются на месте, экран не
  /// прыгает: высота области выбора одна и та же.
  bool _timeTab = false;

  late final FixedExtentScrollController _dayCtrl;
  late final FixedExtentScrollController _monthCtrl;
  late final FixedExtentScrollController _yearCtrl;
  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;

  static const double _extent = 62;

  AppTheme get _t => widget.theme;
  AppStrings get _s => LocaleService.current;

  @override
  void initState() {
    super.initState();
    final init = widget.initial ?? DateTime.now();
    _year = init.year.clamp(widget.firstYear, widget.lastYear);
    _month = init.month;
    _day = DateWheel.clampDay(init.day, _year, _month);
    _hour = init.hour;
    _minute = init.minute;

    _dayCtrl = FixedExtentScrollController(initialItem: _day - 1);
    _monthCtrl = FixedExtentScrollController(initialItem: _month - 1);
    _yearCtrl =
        FixedExtentScrollController(initialItem: _year - widget.firstYear);
    _hourCtrl = FixedExtentScrollController(initialItem: _hour);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _dayCtrl.dispose();
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  int get _daysInMonth => DateWheel.daysInMonth(_year, _month);

  /// После смены месяца или года день может не влезть (31 марта → февраль).
  /// Прижимаем и барабан, и значение, иначе выбранное и видимое разъедутся.
  void _syncDay() {
    final clamped = DateWheel.clampDay(_day, _year, _month);
    if (clamped == _day) return;
    _day = clamped;
    _dayCtrl.animateToItem(
      clamped - 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _submit() => Navigator.of(context).pop(
        DateWheel.build(
          year: _year,
          month: _month,
          day: _day,
          hour: widget.withTime ? _hour : 0,
          minute: widget.withTime ? _minute : 0,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.themeFor(_t).colorScheme;

    return Scaffold(
      backgroundColor: _t.bgGradient.last,
      body: SafeArea(
        child: Column(
          children: [
            _header(cs),
            if (widget.withTime) _tabs(cs),
            Expanded(child: _wheels(cs)),
            _actions(cs),
          ],
        ),
      ),
    );
  }

  // ── шапка ─────────────────────────────────────────────────────────────────

  Widget _header(ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.arrow_back_rounded, color: _t.textPrimary),
                  tooltip: _s.cancel,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 2,
                    style: TextStyle(
                      fontFamily: ProfileTheme.displayFont,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.1,
                      color: _t.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Выбранное словами: барабан читают краем глаза, а тут дата видна
            // целиком и без сокращений.
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                _spelled(),
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 15,
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  String _spelled() {
    final months = _s.cycleMonthsGenitive;
    final date = '$_day ${months[_month - 1]} $_year';
    if (!widget.withTime) return date;
    final h = _hour.toString().padLeft(2, '0');
    final m = _minute.toString().padLeft(2, '0');
    return '$date, $h:$m';
  }

  // ── переключатель ─────────────────────────────────────────────────────────

  Widget _tabs(ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(_s.pickerDateTab)),
            ButtonSegment(value: true, label: Text(_s.pickerTimeTab)),
          ],
          selected: {_timeTab},
          showSelectedIcon: false,
          onSelectionChanged: (v) {
            HapticFeedback.selectionClick();
            setState(() => _timeTab = v.first);
          },
        ),
      );

  // ── барабаны ──────────────────────────────────────────────────────────────

  Widget _wheels(ColorScheme cs) => Stack(
        alignment: Alignment.center,
        children: [
          // Подложка выбранной строки. Лежит под барабанами и во всю ширину:
          // так три колонки читаются как одна строка, а не три отдельных.
          Center(
            child: Container(
              height: _extent * 1.22,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(26),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _timeTab ? _timeWheels(cs) : _dateWheels(cs),
          ),
        ],
      );

  Widget _dateWheels(ColorScheme cs) => Row(
        children: [
          // Пропорции подобраны под самый длинный месяц: «сентября» должно
          // помещаться целиком, поэтому средняя колонка заметно шире.
          Expanded(flex: 22, child: _wheel(
            cs: cs,
            controller: _dayCtrl,
            count: _daysInMonth,
            builder: (i) => '${i + 1}',
            onChanged: (i) => setState(() => _day = i + 1),
          )),
          Expanded(flex: 40, child: _wheel(
            cs: cs,
            controller: _monthCtrl,
            count: 12,
            builder: (i) => _s.cycleMonthsGenitive[i],
            onChanged: (i) => setState(() {
              _month = i + 1;
              _syncDay();
            }),
          )),
          Expanded(flex: 28, child: _wheel(
            cs: cs,
            controller: _yearCtrl,
            count: widget.lastYear - widget.firstYear + 1,
            builder: (i) => '${widget.firstYear + i}',
            onChanged: (i) => setState(() {
              _year = widget.firstYear + i;
              _syncDay();
            }),
          )),
        ],
      );

  Widget _timeWheels(ColorScheme cs) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 130,
            child: _wheel(
              cs: cs,
              controller: _hourCtrl,
              count: 24,
              loop: true,
              builder: (i) => i.toString().padLeft(2, '0'),
              onChanged: (i) => setState(() => _hour = i),
            ),
          ),
          Text(
            ':',
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: cs.onPrimaryContainer,
            ),
          ),
          SizedBox(
            width: 130,
            child: _wheel(
              cs: cs,
              controller: _minuteCtrl,
              count: 60,
              loop: true,
              builder: (i) => i.toString().padLeft(2, '0'),
              onChanged: (i) => setState(() => _minute = i),
            ),
          ),
        ],
      );

  Widget _wheel({
    required ColorScheme cs,
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int) builder,
    required ValueChanged<int> onChanged,
    bool loop = false,
  }) {
    Widget cell(int i) {
      final selected = controller.hasClients
          ? (controller.selectedItem % count) == i
          : false;
      return Center(
        // Длинное слово ужимается, а не обрезается: «сентября» обязано
        // читаться целиком, иначе весь смысл крупной типографики теряется.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              builder(i),
              maxLines: 1,
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 34,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: -1,
                color: selected ? cs.onPrimaryContainer : _t.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    void changed(int i) {
      HapticFeedback.selectionClick();
      onChanged(loop ? i % count : i);
    }

    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _extent,
      physics: const FixedExtentScrollPhysics(),
      // Затухание к краям — тот самый силуэт песочных часов из референса.
      overAndUnderCenterOpacity: 0.32,
      perspective: 0.0022,
      diameterRatio: 2.1,
      onSelectedItemChanged: changed,
      childDelegate: loop
          ? ListWheelChildLoopingListDelegate(
              children: List.generate(count, cell))
          : ListWheelChildBuilderDelegate(
              childCount: count, builder: (_, i) => cell(i)),
    );
  }

  // ── кнопки ────────────────────────────────────────────────────────────────

  Widget _actions(ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                child: Text(
                  _s.cancel,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _t.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  _s.done,
                  style: const TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
