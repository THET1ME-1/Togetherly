import 'package:flutter/material.dart';

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
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: background ?? scheme.surfaceContainerHigh,
    isScrollControlled: true,
    // Именно это не даёт листу залезть под вырез сверху и под кнопки снизу.
    useSafeArea: true,
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
