import 'package:flutter/material.dart';

import '../../models/daily_task.dart';
import '../../services/daily_task_service.dart';
import '../../services/locale_service.dart';
import '../../theme/fonts.dart';

/// Задания дня на главной: три штуки, галочка за каждое.
///
/// Карточка того же вида, что остальные блоки главной — тональный контейнер,
/// радиус 28, без теней и обводок. Задание закрывается не кнопкой, а самим
/// действием: добавили пин нужного типа в ленту — галочка встала, монета
/// пришла. Поэтому строки не нажимаются, они показывают, что сделать.
class DailyTasksCard extends StatefulWidget {
  const DailyTasksCard({
    super.key,
    required this.groupId,
    required this.partnerName,
  });

  final String groupId;

  /// Имя партнёра подставляется в текст задания вместо токена.
  final String partnerName;

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
    final ru = LocaleService.instance.isRussian;
    final done = _tasks.doneCount;
    final all = _tasks.allDone;

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
                  ru ? 'Задания дня' : 'Today’s tasks',
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
            all
                ? (ru ? 'Всё на сегодня — до завтра' : 'All done — see you tomorrow')
                : (ru
                    ? 'Добавьте пин в ленту, и задание закроется само'
                    : 'Add a pin to the feed and the task closes itself'),
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
              ),
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
  });

  final DailyTask task;
  final bool done;
  final String partnerName;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
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
            child: Text(
              task.title(partnerName),
              style: AppFonts.onest(
                size: 14.5,
                height: 1.35,
                weight: done ? 500 : 600,
                color: done ? scheme.onSurfaceVariant : scheme.onSurface,
                // Закрытое задание гасим цветом, а не зачёркиванием: строка
                // остаётся читаемой, а список не пестрит линиями.
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          task.emoji,
          style: const TextStyle(fontSize: 16),
        ),
      ],
    );
  }
}
