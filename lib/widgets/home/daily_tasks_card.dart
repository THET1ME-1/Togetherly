import 'package:flutter/material.dart';

import '../../models/daily_task.dart';
import '../../models/symbol_catalog.dart';
import '../../services/daily_task_service.dart';
import '../../dict_strings.dart';
import '../../theme/fonts.dart';

/// Задания дня на главной: три штуки, галочка за каждое. Закрыли все три —
/// четвёртой строкой открывается бонусное, без монеты.
///
/// Карточка того же вида, что остальные блоки главной — тональный контейнер,
/// радиус 28, без теней и обводок. Задание закрывается самим действием:
/// добавили пин нужного типа в ленту — галочка встала, монета пришла.
///
/// Строка при этом нажимается и ведёт прямо в форму нужного типа
/// ([onOpenTask]) — прежде человек читал «Сфоткай небо» и шёл искать, откуда
/// добавляют пин. Колбэк необязателен: без него строки остаются просто
/// списком (так карточка стоит в витрине тем).
class DailyTasksCard extends StatefulWidget {
  const DailyTasksCard({
    super.key,
    required this.groupId,
    required this.partnerName,
    this.onOpenTask,
  });

  final String groupId;

  /// Имя партнёра подставляется в текст задания вместо токена.
  final String partnerName;

  /// Открыть форму создания пина под это задание.
  final void Function(DailyTask task)? onOpenTask;

  @override
  State<DailyTasksCard> createState() => _DailyTasksCardState();
}

class _DailyTasksCardState extends State<DailyTasksCard> {
  final DailyTaskService _tasks = DailyTaskService.instance;

  @override
  void initState() {
    super.initState();
    _tasks.addListener(_onChanged);
  }

  @override
  void dispose() {
    _tasks.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groupId.isEmpty) return const SizedBox.shrink();
    final today = _tasks.today;
    if (today.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final done = _tasks.doneCount;
    final all = _tasks.allDone;
    final bonus = _tasks.bonus;
    final bonusDone = _tasks.bonusDone;
    // Подпись под заголовком: пока основные не закрыты — как пользоваться,
    // открылся бонус — что он без монеты, закрыт и он — до завтра.
    final hint = bonusDone || (all && bonus == null)
        ? trKey('tasks_all_done')
        : all
            ? trKey('tasks_bonus_hint')
            : trKey(widget.onOpenTask != null
                ? 'tasks_tap_hint'
                : 'tasks_add_hint');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trKey('tasks_title'),
                  style: AppFonts.unbounded(
                      size: 17, weight: 600, color: cs.onSurface),
                ),
              ),
              // Счётчик таблеткой: сколько закрыто из трёх. Когда всё готово,
              // таблетка наливается — видно, не читая цифр.
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: all ? cs.primary : cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$done/${today.length}',
                  style: AppFonts.onest(
                    size: 12.5,
                    weight: 700,
                    color: all ? cs.onPrimary : cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: AppFonts.onest(size: 12.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final task in today)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TaskRow(
                task: task,
                done: _tasks.isDone(task),
                partnerName: widget.partnerName,
                scheme: cs,
                onTap: widget.onOpenTask == null
                    ? null
                    : () => widget.onOpenTask!(task),
              ),
            ),
          // Бонус встаёт четвёртой строкой, только когда закрыты три
          // основных: раньше он отвлекал бы от них.
          if (bonus != null)
            _TaskRow(
              task: bonus,
              done: bonusDone,
              partnerName: widget.partnerName,
              scheme: cs,
              bonusLabel: trKey('tasks_bonus_label'),
              onTap: widget.onOpenTask == null
                  ? null
                  : () => widget.onOpenTask!(bonus),
            ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.done,
    required this.partnerName,
    required this.scheme,
    this.onTap,
    this.bonusLabel,
  });

  final DailyTask task;
  final bool done;
  final String partnerName;
  final ColorScheme scheme;
  final VoidCallback? onTap;

  /// Ярлык над текстом бонусного задания. У основных его нет.
  final String? bonusLabel;

  @override
  Widget build(BuildContext context) {
    final row = _row();
    if (onTap == null) return row;
    // Закрытое задание тоже открывается: поделиться ещё раз можно, просто
    // монеты за это уже не будет — предел сторожит сервер.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: row,
        ),
      ),
    );
  }

  Widget _row() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: done ? scheme.primary : Colors.transparent,
            border: done
                ? null
                : Border.all(color: scheme.outlineVariant, width: 2),
            borderRadius: BorderRadius.circular(9),
          ),
          child: done
              ? Icon(Icons.check_rounded, size: 17, color: scheme.onPrimary)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bonusLabel != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      bonusLabel!,
                      style: AppFonts.onest(
                        size: 11,
                        weight: 700,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                Text(
                  task.title(partnerName),
                  style: AppFonts.onest(
                    size: 14.5,
                    height: 1.35,
                    weight: done ? 500 : 600,
                    color: done ? scheme.onSurfaceVariant : scheme.onSurface,
                    // Закрытое задание гасим цветом, а не зачёркиванием:
                    // строка остаётся читаемой, а список не пестрит линиями.
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Значок типа пина — Material Symbols, как везде в интерфейсе.
        // Эмодзи здесь выбивались из набора: своя палитра, свой вес, своя
        // отрисовка на каждом телефоне.
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SymbolIcon(
            task.symbol,
            size: 19,
            color: done ? scheme.onSurfaceVariant : scheme.primary,
          ),
        ),
      ],
    );
  }
}
