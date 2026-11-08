import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';

/// Барабан месяца и года прямо на календаре настроений.
///
/// Просьба владельца 08.11.2026: по нажатию на «Ноябрь 2026» выбирать месяц
/// и год барабаном, а не листать стрелками год назад по месяцу. Вид тот же,
/// что у выбора даты (`date_time_picker_screen.dart`): строка выбора на
/// подложке, крупный шрифт, затухание к краям. Календарь меняется сразу,
/// пока крутится барабан.
class MonthYearWheel extends StatefulWidget {
  const MonthYearWheel({
    super.key,
    required this.year,
    required this.month,
    required this.firstYear,
    required this.lastYear,
    required this.onChanged,
    this.yearOnly = false,
    this.scheme,
  });

  /// Цвета экрана. Календарь красится темой пары, а не темой приложения:
  /// без схемы подложка выходила фиолетовой.
  final ColorScheme? scheme;

  final int year;
  final int month;
  final int firstYear;
  final int lastYear;

  /// Год и месяц (1–12) после прокрутки.
  final void Function(int year, int month) onChanged;

  /// В режиме «Год» месяц не выбирают.
  final bool yearOnly;

  @override
  State<MonthYearWheel> createState() => _MonthYearWheelState();
}

class _MonthYearWheelState extends State<MonthYearWheel> {
  static const double _extent = 44;

  late int _year = widget.year.clamp(widget.firstYear, widget.lastYear);
  late int _month = widget.month;
  late final FixedExtentScrollController _monthCtrl =
      FixedExtentScrollController(initialItem: _month - 1);
  late final FixedExtentScrollController _yearCtrl =
      FixedExtentScrollController(initialItem: _year - widget.firstYear);

  @override
  void dispose() {
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme ?? Theme.of(context).colorScheme;
    final months = LocaleService.current.fullMonths; // [0] пустой
    return SizedBox(
      height: _extent * 3.4,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Подложка выбранной строки во всю ширину: колонки читаются одной
          // строкой «Ноябрь 2026».
          Container(
            height: _extent * 1.1,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          Row(
            children: [
              if (!widget.yearOnly)
                Expanded(
                  flex: 3,
                  child: _wheel(
                    key: const ValueKey('month_wheel'),
                    cs: cs,
                    controller: _monthCtrl,
                    count: 12,
                    selected: _month - 1,
                    label: (i) => months[i + 1],
                    onChanged: (i) {
                      setState(() => _month = i + 1);
                      widget.onChanged(_year, _month);
                    },
                  ),
                ),
              Expanded(
                flex: 2,
                child: _wheel(
                  key: const ValueKey('year_wheel'),
                  cs: cs,
                  controller: _yearCtrl,
                  count: widget.lastYear - widget.firstYear + 1,
                  selected: _year - widget.firstYear,
                  label: (i) => '${widget.firstYear + i}',
                  onChanged: (i) {
                    setState(() => _year = widget.firstYear + i);
                    widget.onChanged(_year, _month);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wheel({
    required Key key,
    required ColorScheme cs,
    required FixedExtentScrollController controller,
    required int count,
    required int selected,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
  }) {
    return ListWheelScrollView.useDelegate(
      key: key,
      controller: controller,
      itemExtent: _extent,
      physics: const FixedExtentScrollPhysics(),
      overAndUnderCenterOpacity: 0.32,
      perspective: 0.0022,
      diameterRatio: 2.1,
      onSelectedItemChanged: (i) {
        HapticFeedback.selectionClick();
        onChanged(i);
      },
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (_, i) => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label(i),
                maxLines: 1,
                style: TextStyle(
                  fontFamily: ProfileTheme.displayFont,
                  fontSize: 22,
                  fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: -0.5,
                  color: i == selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
