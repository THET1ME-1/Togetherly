import 'package:flutter/material.dart';

import '../../dict_strings.dart';

enum SaveButtonMode { idle, running, allSaved }

/// Что показывает разделённая кнопка — считается отдельно от отрисовки, чтобы
/// правило проверялось без экрана.
class SaveButtonState {
  final SaveButtonMode mode;

  /// Надпись на левой части: остаток «94», ход «37/94» или пусто.
  final String label;

  /// Доля готового для кольца, только у [SaveButtonMode.running].
  final double progress;

  const SaveButtonState(this.mode, this.label, [this.progress = 0]);
}

/// [total] — сколько файлов у воспоминания, [saved] — сколько уже в галерее
/// этого телефона. [done] и [jobTotal] — идущее задание, если оно есть.
SaveButtonState saveButtonState({
  required int total,
  required int saved,
  int? done,
  int? jobTotal,
}) {
  if (done != null && jobTotal != null && jobTotal > 0) {
    return SaveButtonState(
        SaveButtonMode.running, '$done/$jobTotal', done / jobTotal);
  }
  final left = (total - saved).clamp(0, total);
  if (left == 0 && total > 0) {
    return const SaveButtonState(SaveButtonMode.allSaved, '');
  }
  return SaveButtonState(SaveButtonMode.idle, '$left');
}

/// Разделённая кнопка M3 «сохранить всё · выбрать» (направление A макета
/// «Сохранить воспоминание»).
///
/// Была круглая кнопка скачивания, которая уводила в браузер с одним кадром.
/// Теперь левая часть сразу отправляет в галерею всё, чего там ещё нет, и
/// показывает, сколько это; правая открывает лист «Что сохранить». Пока идёт
/// сохранение, левая часть — кольцо и «37/94», правая — отмена. Когда всё уже
/// в галерее, левая часть с отметкой тоже открывает выбор: сохранять заново
/// нечего, а выбрать отдельный кадр можно.
///
/// Форма — по спецификации split button: внешние углы полные, внутренние
/// маленькие, зазор в две точки. Цвет — тональный `secondaryContainer`, как
/// у соседних круглых кнопок панели; главная заливка остаётся у «Закрепить».
class SaveSplitButton extends StatelessWidget {
  const SaveSplitButton({
    super.key,
    required this.state,
    required this.onSaveAll,
    required this.onChoose,
    required this.onCancel,
    this.height = 54,
  });

  static const Key mainKey = ValueKey('save-split-main');
  static const Key trailingKey = ValueKey('save-split-trailing');

  final SaveButtonState state;
  final VoidCallback onSaveAll;
  final VoidCallback onChoose;
  final VoidCallback onCancel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = cs.onSecondaryContainer;
    final outer = Radius.circular(height / 2);
    const inner = Radius.circular(6);

    final running = state.mode == SaveButtonMode.running;
    final allSaved = state.mode == SaveButtonMode.allSaved;

    final Widget leading = running
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              value: state.progress.clamp(0.02, 1.0),
              strokeWidth: 3,
              color: fg,
              backgroundColor: fg.withValues(alpha: 0.2),
            ),
          )
        : Icon(
            allSaved ? Icons.download_done_rounded : Icons.download_rounded,
            size: 22,
            color: fg,
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: running
              ? trKey('islandSaving')
              : allSaved
                  ? trKey('saveAllDoneTooltip')
                  : trKey('saveAllTooltip'),
          child: _Segment(
            key: mainKey,
            height: height,
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.horizontal(left: outer, right: inner),
            padding: const EdgeInsets.only(left: 16, right: 14),
            onTap: running ? null : (allSaved ? onChoose : onSaveAll),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                if (state.label.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Text(
                    state.label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: fg,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 2),
        Tooltip(
          message: running
              ? trKey('saveCancelTooltip')
              : trKey('saveChooseTooltip'),
          child: _Segment(
            key: trailingKey,
            height: height,
            width: 42,
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.horizontal(left: inner, right: outer),
            onTap: running ? onCancel : onChoose,
            child: Icon(
              running ? Icons.close_rounded : Icons.expand_more_rounded,
              size: 22,
              color: fg,
            ),
          ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.height,
    required this.color,
    required this.borderRadius,
    required this.child,
    this.onTap,
    this.width,
    this.padding = EdgeInsets.zero,
  });

  final double height;
  final double? width;
  final Color color;
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          width: width,
          padding: padding,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}
