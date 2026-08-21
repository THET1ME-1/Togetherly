import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/profile_theme.dart';
import '../../utils/readable_text.dart';
import '../../models/draw_quick_tools.dart';
import '../color_picker_sheet.dart';

/// Нижняя панель холста: пузырь в углу и лист со всем остальным.
///
/// До 20.08.2026 внизу стояли два прокручиваемых ряда кнопок. Прокрутка вбок
/// прячет половину инструментов за краем: до фигур, слоёв и фона добирались
/// смахиванием, а на узком экране их не было видно вовсе. Вместо этого —
/// направление «одна кнопка»: на холсте виден текущий инструмент и текущий
/// цвет, всё прочее приезжает листом по касанию.

/// Пузырь в углу холста: цвет слева, инструмент справа.
///
/// Заливка приходит параметром, а не берётся из `primaryContainer`: у тем,
/// нарисованных руками, контейнер — это чуть тонированный фон, и пузырь на
/// белом холсте пропадал бы совсем.
class DrawToolBubble extends StatelessWidget {
  const DrawToolBubble({
    super.key,
    required this.color,
    required this.icon,
    required this.fill,
    required this.onFill,
    required this.onTap,
  });

  final Color color;
  final IconData icon;

  /// Цвет темы (`AppTheme.fillColor`) и то, что читается поверх него.
  final Color fill;
  final Color onFill;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: fill,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Кружок цвета обведён цветом надписи: белая краска на светлой
                // заливке иначе исчезает.
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: onFill, width: 2),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 22, color: onFill),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Лист с инструментами: ряд кнопок, толщина, цвет.
class DrawToolsSheet extends StatelessWidget {
  const DrawToolsSheet({
    super.key,
    required this.tool,
    required this.tools,
    required this.color,
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    required this.palette,
    required this.fill,
    required this.onFill,
    required this.labelThickness,
    required this.labelColor,
    required this.toolLabels,
    required this.onTool,
    required this.onWidth,
    required this.onColor,
    required this.onMoreColors,
    required this.onEyedropper,
    required this.eyedropperLabel,
    required this.onBrushSettings,
    required this.brushSettingsLabel,
    required this.symmetryOn,
    required this.closeLabel,
    this.side = false,
    required this.onClose,
  });

  final DrawQuickTool tool;

  /// Состав панели и порядок кнопок — их собирает человек в настройках.
  final List<DrawQuickTool> tools;

  final Color color;
  final double width;
  final double minWidth;
  final double maxWidth;

  /// Восемь цветов ряда: столько влезает на 320 точках без прокрутки.
  final List<Color> palette;

  /// Цвет темы (`AppTheme.fillColor`) и то, что читается поверх него. Именно
  /// им красятся выбранный инструмент, полоса толщины и кольцо у цвета:
  /// `primaryContainer` у нарисованных руками тем — тонированный фон, и всё
  /// выбранное сливалось бы с невыбранным.
  final Color fill;
  final Color onFill;

  final String labelThickness;
  final String labelColor;

  /// Подписи кнопок для чтения с экрана и всплывающих подсказок.
  final Map<DrawQuickTool, String> toolLabels;

  final ValueChanged<DrawQuickTool> onTool;
  final ValueChanged<double> onWidth;
  final ValueChanged<Color> onColor;
  final VoidCallback onMoreColors;

  /// Пипетка стоит в строке заголовка «Цвет», а не в ряду инструментов:
  /// снять цвет с холста — это про цвет, и путь к ней теперь один тап, а не
  /// три через лист палитры.
  final VoidCallback onEyedropper;
  final String eyedropperLabel;

  /// Настройки кисти: плавность, ровные фигуры, симметрия. Кнопка стоит в
  /// строке «Толщина» — там же, где остальное про саму линию.
  final VoidCallback onBrushSettings;
  final String brushSettingsLabel;

  /// Симметрия включена — кнопку подсвечиваем: режим меняет каждый мазок, и
  /// человек должен видеть это, не открывая лист.
  final bool symmetryOn;

  /// Подпись кнопки «свернуть» для чтения с экрана.
  final String closeLabel;

  /// Колонка сбоку вместо листа снизу. Лёжа экран низкий: лист съел бы холст
  /// целиком, поэтому панель встаёт справа и прокручивается внутри себя.
  final bool side;

  /// Свернуть лист обратно в пузырь: тап по ручке или потяг вниз.
  final VoidCallback onClose;

  static const Map<DrawQuickTool, IconData> icons = {
    DrawQuickTool.brush: Icons.brush_rounded,
    DrawQuickTool.eraser: Icons.auto_fix_normal_rounded,
    DrawQuickTool.fill: Icons.format_color_fill_rounded,
    DrawQuickTool.shapes: Icons.category_rounded,
    DrawQuickTool.layers: Icons.layers_rounded,
    DrawQuickTool.image: Icons.image_rounded,
    DrawQuickTool.palm: Icons.pan_tool_rounded,
    DrawQuickTool.select: Icons.highlight_alt_rounded,
    DrawQuickTool.background: Icons.texture_rounded,
    DrawQuickTool.clear: Icons.delete_outline_rounded,
    DrawQuickTool.replay: Icons.play_circle_outline_rounded,
  };

  /// Что подсвечивается как выбранное. Фон, очистка и повтор — действия: они
  /// срабатывают и отпускают, поэтому «включённого» состояния у них нет.
  static const Set<DrawQuickTool> selectable = {
    DrawQuickTool.brush,
    DrawQuickTool.eraser,
    DrawQuickTool.fill,
    DrawQuickTool.shapes,
    DrawQuickTool.layers,
    DrawQuickTool.image,
    DrawQuickTool.palm,
    DrawQuickTool.select,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hsv = HSVColor.fromColor(color);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: side
            ? const BorderRadius.horizontal(left: Radius.circular(28))
            : const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        left: false,
        child: Padding(
          padding: side
              ? const EdgeInsets.fromLTRB(14, 10, 14, 10)
              : const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _body(cs, hsv),
        ),
      ),
    );
  }

  Widget _body(ColorScheme cs, HSVColor hsv) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _children(cs, hsv),
    );
    // Сбоку экран низкий, и содержимое в него не всегда влезает: пусть
    // прокручивается внутри колонки, а не режется по краю.
    return side ? SingleChildScrollView(child: content) : content;
  }

  List<Widget> _children(ColorScheme cs, HSVColor hsv) {
    return [
      _handle(cs),
      const SizedBox(height: 6),
      _tools(cs),
      SizedBox(height: side ? 12 : 16),
      Row(
        children: [
          _label(cs, labelThickness),
          const Spacer(),
          _roundButton(
            cs,
            icon: Icons.tune_rounded,
            label: brushSettingsLabel,
            onTap: onBrushSettings,
            active: symmetryOn,
          ),
        ],
      ),
      const SizedBox(height: 8),
      _thickness(cs),
      SizedBox(height: side ? 12 : 16),
      Row(
        children: [
          _label(cs, labelColor),
          const Spacer(),
          _roundButton(
            cs,
            icon: Icons.colorize_rounded,
            label: eyedropperLabel,
            onTap: onEyedropper,
          ),
        ],
      ),
      const SizedBox(height: 8),
      _swatches(cs),
      // Сбоку подбор цвета не помещается и уезжает под нижний край: колонка
      // высотой с лежащий телефон и так занята инструментами. Полный подбор
      // остаётся в один тап — за радужным кружком в ряду красок.
      if (!side) ...[
        const SizedBox(height: 12),
        // Поле ниже, чем в листе палитры: под ним ещё полоса оттенка, а холст
        // сверху не должен схлопываться в щель.
        SaturationValueField(
          hsv: hsv,
          height: 132,
          onChanged: (sat, val) =>
              onColor(hsv.withSaturation(sat).withValue(val).toColor()),
        ),
        const SizedBox(height: 12),
        HueBar(
          hue: hsv.hue,
          onChanged: (hue) => onColor(hsv.withHue(hue).toColor()),
        ),
      ],
    ];
  }

  /// Как свернуть панель. Снизу это полоска — её тянут вниз, и она же
  /// нажимается. Сбоку тянуть некуда, поэтому там обычная кнопка со стрелкой.
  Widget _handle(ColorScheme cs) {
    if (side) {
      return Align(
        alignment: Alignment.centerRight,
        child: _roundButton(
          cs,
          icon: Icons.chevron_right_rounded,
          label: closeLabel,
          onTap: onClose,
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 0) onClose();
      },
      child: SizedBox(
        height: 22,
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  /// Подпись раздела общим стилем приложения, но приглушённая: акцентная
  /// спорила бы с выбранным инструментом и полосой рядом.
  Widget _label(ColorScheme cs, String text) => Text(
        text.toUpperCase(),
        style: ProfileTheme.sectionLabel(cs, color: cs.onSurfaceVariant),
      );

  /// Шесть инструментов в ряд: делят ширину поровну и помещаются на 320
  /// точках, поэтому прокрутки тут нет и быть не должно. В боковой колонке
  /// ряд разбит надвое — иначе кнопки становятся уже пальца.
  Widget _tools(ColorScheme cs) {
    // Сбоку колонка узкая, там в ряд помещается три кнопки, снизу — шесть.
    final perRow = side ? 3 : 6;
    final rows = quickToolRows(tools.length, perRow: perRow);
    if (rows <= 1) return _toolsRow(cs, tools, perRow);
    return Column(
      children: [
        for (var i = 0; i < rows; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _toolsRow(
            cs,
            tools.sublist(
              i * perRow,
              ((i + 1) * perRow).clamp(0, tools.length),
            ),
            perRow,
          ),
        ],
      ],
    );
  }

  /// Ряд кнопок. Неполный ряд добивается пустотой, иначе три кнопки во втором
  /// ряду растянулись бы на всю ширину и разъехались с первым.
  Widget _toolsRow(ColorScheme cs, List<DrawQuickTool> row, int perRow) {
    return Row(
      children: [
        for (final t in row) ...[
          Expanded(
            child: Tooltip(
              message: toolLabels[t] ?? '',
              child: Semantics(
                button: true,
                selected: t == tool && selectable.contains(t),
                label: toolLabels[t],
                child: Material(
                  color: t == tool && selectable.contains(t)
                      ? fill
                      : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onTool(t);
                    },
                    child: SizedBox(
                      height: side ? 44 : 46,
                      child: Icon(
                        icons[t],
                        size: 21,
                        color: t == tool && selectable.contains(t)
                            ? onFill
                            // Очистка стирает всё разом: пусть выделяется
                            // среди соседей, к которым тянутся не глядя.
                            : t == DrawQuickTool.clear
                                ? cs.error
                                : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (t != row.last) const SizedBox(width: 8),
        ],
        for (var i = row.length; i < perRow; i++) ...[
          const SizedBox(width: 8),
          const Expanded(child: SizedBox.shrink()),
        ],
      ],
    );
  }

  /// Толщина: полоса заполняется вместе со значением, число стоит справа
  /// внутри неё — так видно и на глаз, и точно.
  Widget _thickness(ColorScheme cs) {
    final fraction = ((width - minWidth) / (maxWidth - minWidth)).clamp(0.0, 1.0);
    // Заливка полосы мягче выбранного инструмента: рядом с ним полный цвет
    // читался бы второй кнопкой, а не значением.
    final track = cs.surfaceContainerHigh;
    final bar = Color.lerp(track, fill, 0.7)!;
    // Число сидит справа, и при большой толщине заливка доезжает до него —
    // тогда читаемость считаем по ней, а не по треку.
    final under = fraction > 0.86 ? bar : track;
    return LayoutBuilder(
      builder: (context, box) {
        void handle(double dx) {
          final v = (dx / box.maxWidth).clamp(0.0, 1.0);
          onWidth(minWidth + v * (maxWidth - minWidth));
        }

        return GestureDetector(
          onPanDown: (d) => handle(d.localPosition.dx),
          onPanUpdate: (d) => handle(d.localPosition.dx),
          onTapDown: (d) => handle(d.localPosition.dx),
          child: Container(
            height: side ? 42 : 46,
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(23),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // heightFactor обязателен: в Stack ограничения свободные, и
                // без него полоса заполнения выходит нулевой высоты — её
                // просто не видно, сколько ни крась.
                FractionallySizedBox(
                  widthFactor: fraction == 0 ? 0.001 : fraction,
                  heightFactor: 1,
                  child: DecoratedBox(decoration: BoxDecoration(color: bar)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: Text(
                      width.round().toString(),
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        // Цифры не пляшут при перетаскивании.
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: readableTextOn(under),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Маленькая круглая кнопка у заголовка раздела.
  Widget _roundButton(
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        selected: active,
        child: Material(
          color: active ? fill : cs.surfaceContainerHigh,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(
                icon,
                size: 18,
                color: active ? onFill : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Кружок краски. Выбранный обведён кольцом с зазором, а не толстой рамкой:
  /// рамка съедает сам цвет, и тёмные краски становятся неразличимы.
  ///
  /// Габарит у выбранного тот же, что у остальных: восемь кружков делят
  /// строку, и на 320 точках каждому достаётся около 32 — кольцо крупнее
  /// вылезло бы за свою долю жёлтой полосой переполнения.
  Widget _swatch(ColorScheme cs, Color c, bool selected) {
    final size = side ? 28.0 : 30.0;
    if (!selected) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: fill, width: 2.5),
      ),
      child: Center(
        child: Container(
          width: size - 6,
          height: size - 6,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
      ),
    );
  }

  /// Готовые цвета плюс кнопка своей палитры — она радужная, чтобы её не
  /// принимали за ещё один цвет.
  Widget _swatches(ColorScheme cs) {
    return Row(
      children: [
        for (final c in palette) ...[
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onColor(c);
              },
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: _swatch(cs, c, c.toARGB32() == color.toARGB32()),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: GestureDetector(
            onTap: onMoreColors,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Container(
                width: side ? 28 : 30,
                height: side ? 28 : 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outlineVariant),
                  gradient: const SweepGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
                child: Icon(Icons.add_rounded, size: 16, color: cs.onSurface),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
