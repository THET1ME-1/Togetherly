import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Полоса затемнения над высоким листом, в точках: касание по ней закрывает
/// лист.
const double kSheetTopGap = 56;

/// [showModalBottomSheet] с теми же параметрами, но высокий лист не дорастает
/// до верха экрана (TOG-39).
///
/// Лист с длинным содержимым вставал под строку состояния, затемнения над
/// ним не оставалось, а смахивание вниз по списку только листало список. На
/// айфоне системного «назад» нет, и такой лист закрывали перезапуском
/// (обращение 471, iPhone SE). Здесь лист всегда ниже строки состояния, а
/// над ним остаётся полоса [topGap]. Пока открыта клавиатура, полоса отдаёт
/// место полю ввода.
///
/// Листу, который сам держит свою высоту ([DraggableScrollableSheet]), полоса
/// не нужна: [topGap] = 0.
Future<T?> showModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  RouteSettings? routeSettings,
  double topGap = kSheetTopGap,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: true,
    routeSettings: routeSettings,
    builder: (ctx) => SheetHeightCap(gap: topGap, child: builder(ctx)),
  );
}

/// Не даёт листу дорасти до самого верха: над ним остаётся полоса [gap].
///
/// Пока открыта клавиатура, полосы нет: место нужнее полю ввода, а закрывать
/// лист посреди набора незачем.
class SheetHeightCap extends StatelessWidget {
  const SheetHeightCap({
    super.key,
    this.gap = kSheetTopGap,
    required this.child,
  });

  final double gap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    // Строение одно при любой клавиатуре: смени его, и поле ввода внутри
    // пересоздастся, потеряет фокус и сразу спрячет клавиатуру.
    return LayoutBuilder(
      builder: (context, box) {
        final free = typing || gap <= 0 || !box.hasBoundedHeight;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: free ? double.infinity : math.max(0, box.maxHeight - gap),
          ),
          child: child,
        );
      },
    );
  }
}

/// Нижний лист приложения: выезжает снизу, углы 28, хват для пальца, и низ
/// всегда выше системных кнопок.
///
/// Отдельный хелпер, потому что вручную это забывается: половина листов в
/// проекте открывалась без `useSafeArea`, и на телефонах с кнопочной навигацией
/// последняя строка пряталась под панелью. Здесь про отступ помнить не нужно —
/// [SheetScaffold] добавляет и системный отступ снизу, и отступ под клавиатуру.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool expand = false,
  Color? background,
}) {
  final scheme = Theme.of(context).colorScheme;
  // Под вырез сверху и под строку состояния лист не залезает, и над высоким
  // листом остаётся полоса, касание по которой его закрывает.
  return showModalSheet<T>(
    context: context,
    backgroundColor: background ?? scheme.surfaceContainerHigh,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) => expand
        ? SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.9,
            child: builder(ctx),
          )
        : builder(ctx),
  );
}

/// Каркас содержимого нижнего листа: хват, заголовок, отступы.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    this.title,
    this.action,
    required this.child,
    this.bottom,
  });

  final String? title;

  /// Кнопка справа от заголовка.
  final Widget? action;

  final Widget child;

  /// Прижатое к низу действие — уже с отступом под системные кнопки.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    // Клавиатура и системная панель складываются: под открытой клавиатурой
    // отступ снизу уже не нужен, иначе лист подпрыгивает.
    final bottomGap = media.viewInsets.bottom > 0
        ? media.viewInsets.bottom
        : media.padding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (title != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontFamily: 'Unbounded',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontVariations: const [FontVariation('wght', 700)],
                        letterSpacing: -0.3,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Flexible(child: child),
          if (bottom != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: bottom!,
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
