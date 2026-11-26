import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/coloring_figures.dart';
import '../../models/coloring_picture.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';

/// Лист «Кто на рисунке»: на каждой половине раскраски — девушка или парень.
///
/// Выбор по половинам отдельно: пара из двух девушек ставит девушку на обе,
/// пара, где он хочет красить левую, меняет только её. Сверху — сам лист в
/// выбранном виде, чтобы было видно, что выйдет. Половину, на которой уже есть
/// краска или хозяин которой нажал «Готово», поменять нельзя: заливки легли бы
/// мимо линий другого рисунка.
///
/// Возвращает выбор или null, если лист закрыли смахиванием.
Future<ColoringFigures?> showColoringFiguresSheet(
  BuildContext context, {
  required AppTheme theme,
  required ColoringPicture picture,
  required ColoringFigures initial,
  required ColoringSide? mySide,
  bool leftLocked = false,
  bool rightLocked = false,
}) {
  return showModalBottomSheet<ColoringFigures>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: theme.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _ColoringFiguresSheet(
      theme: theme,
      picture: picture,
      initial: initial,
      mySide: mySide,
      leftLocked: leftLocked,
      rightLocked: rightLocked,
    ),
  );
}

class _ColoringFiguresSheet extends StatefulWidget {
  const _ColoringFiguresSheet({
    required this.theme,
    required this.picture,
    required this.initial,
    required this.mySide,
    required this.leftLocked,
    required this.rightLocked,
  });

  final AppTheme theme;
  final ColoringPicture picture;
  final ColoringFigures initial;
  final ColoringSide? mySide;
  final bool leftLocked;
  final bool rightLocked;

  @override
  State<_ColoringFiguresSheet> createState() => _ColoringFiguresSheetState();
}

class _ColoringFiguresSheetState extends State<_ColoringFiguresSheet> {
  late ColoringFigures _figures = widget.initial;

  AppTheme get _t => widget.theme;

  /// Текст на заливке цветом темы: в тёмной теме заливка светлая, и белый
  /// на ней не читается.
  Color get _onPrimary => AppThemes.onColor(_t.primary, mode: _t.brightness);

  bool _locked(ColoringSide side) =>
      side == ColoringSide.left ? widget.leftLocked : widget.rightLocked;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _t.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            trKey('coloringFiguresTitle'),
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: _t.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            trKey('coloringFiguresHint'),
            style: TextStyle(fontSize: 14, color: _t.textMuted),
          ),
          const SizedBox(height: 16),
          Center(child: _preview()),
          const SizedBox(height: 16),
          for (final side in ColoringSide.values) ...[
            _sideRow(s, side),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          FilledButton(
            key: const ValueKey('coloring-figures-done'),
            onPressed: () => Navigator.of(context).pop(_figures),
            style: FilledButton.styleFrom(
              backgroundColor: _t.primary,
              foregroundColor: _onPrimary,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(s.done),
          ),
        ],
      ),
    );
  }

  /// Лист в выбранном виде: две половины контура рядом на белой бумаге.
  Widget _preview() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _t.divider),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Row(
              children: [
                for (final side in ColoringSide.values)
                  Expanded(
                    child: Image.asset(
                      widget.picture.halfAsset(side, _figures.on(side)),
                      key: ValueKey('coloring-figures-preview-${side.name}'),
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sideRow(AppStrings s, ColoringSide side) {
    final locked = _locked(side);
    final owner = widget.mySide == null
        ? null
        : (side == widget.mySide ? s.coloringMyHalf : trKey('coloringPartnerHalf'));
    final sideName = trKey(side == ColoringSide.left ? 'coloringSideLeft' : 'coloringSideRight');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: sideName,
              style: TextStyle(fontWeight: FontWeight.w700, color: _t.textPrimary),
            ),
            if (owner != null)
              TextSpan(text: ' · $owner', style: TextStyle(color: _t.textMuted)),
            if (locked)
              TextSpan(
                text: ' · ${trKey('coloringFigureLocked')}',
                style: TextStyle(color: _t.textMuted),
              ),
          ]),
          style: const TextStyle(fontSize: 14),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final figure in ColoringFigure.values) ...[
              if (figure != ColoringFigure.values.first) const SizedBox(width: 8),
              Expanded(child: _figureButton(s, side, figure, locked)),
            ],
          ],
        ),
      ],
    );
  }

  /// Кнопки поровну на всю ширину: выбранная залита, вторая — тональная.
  Widget _figureButton(AppStrings s, ColoringSide side, ColoringFigure figure, bool locked) {
    final selected = _figures.on(side) == figure;
    final label = figure == ColoringFigure.girl ? s.girl : s.boy;
    final onPressed = locked || selected
        ? null
        : () => setState(() => _figures = _figures.withSide(side, figure));
    final key = ValueKey('coloring-figure-${side.name}-${figure.name}');
    final shape = const StadiumBorder();
    const padding = EdgeInsets.symmetric(vertical: 12);
    if (selected) {
      return FilledButton(
        key: key,
        onPressed: locked ? null : () {},
        style: FilledButton.styleFrom(
          backgroundColor: _t.primary,
          foregroundColor: _onPrimary,
          disabledBackgroundColor: _t.primary.withValues(alpha: 0.45),
          disabledForegroundColor: _onPrimary,
          shape: shape,
          padding: padding,
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    return OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _t.textPrimary,
        side: BorderSide(color: _t.divider),
        shape: shape,
        padding: padding,
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
