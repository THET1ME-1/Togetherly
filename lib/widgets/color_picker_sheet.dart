import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/locale_service.dart';
import '../utils/color_hex.dart';
import 'app_sheet.dart';

/// Полный выбор цвета: квадрат «насыщенность × яркость», полоса оттенка, поле
/// HEX и пипетка.
///
/// Двадцати готовых кружков не хватало ни для оттенка кожи, ни для того, чтобы
/// повторить цвет, которым рисовал вчера. Квадрат задаёт насыщенность и яркость
/// одним движением пальца — как в Procreate; отдельные ползунки на каждое
/// значение занимали бы вдвое больше места.
///
/// [onEyedropper] — включить пипетку на холсте. Лист при этом закрывается: цвет
/// берётся касанием самого рисунка, а не внутри листа. null — кнопки нет
/// (экраны, где холст снять нельзя).
Future<Color?> showColorPickerSheet({
  required BuildContext context,
  required Color initial,
  VoidCallback? onEyedropper,
}) {
  return showAppSheet<Color>(
    context,
    builder: (ctx) => _ColorPickerSheet(
      initial: initial,
      onEyedropper: onEyedropper,
    ),
  );
}

/// Недавно выбранные цвета — общий список для всех экранов рисования.
abstract final class RecentColors {
  static const String _key = 'draw_recent_colors';
  static const int limit = 8;

  static Future<List<Color>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    return raw
        .map(int.tryParse)
        .whereType<int>()
        .map((v) => Color(v))
        .toList();
  }

  /// Кладёт цвет в начало списка. Повтор поднимается наверх, а не двоится.
  static Future<void> remember(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    final value = color.toARGB32().toString();
    final next = [value, ...raw.where((v) => v != value)].take(limit).toList();
    await prefs.setStringList(_key, next);
  }
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({required this.initial, this.onEyedropper});

  final Color initial;
  final VoidCallback? onEyedropper;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv;
  late final TextEditingController _hexCtrl;
  List<Color> _recent = const [];

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexCtrl = TextEditingController(text: ColorHex.format(widget.initial));
    RecentColors.load().then((list) {
      if (mounted) setState(() => _recent = list);
    });
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  void _setColor(Color color, {bool fromHexField = false}) {
    setState(() {
      final hsv = HSVColor.fromColor(color);
      // Серый и чёрный оттенка не несут: `HSVColor.fromColor` вернёт для них
      // hue = 0, и ползунок оттенка прыгнет в красный. Держим прежний.
      _hsv = hsv.saturation == 0 ? hsv.withHue(_hsv.hue) : hsv;
      if (!fromHexField) _hexCtrl.text = ColorHex.format(color);
    });
  }

  /// Зовётся из квадрата и полосы оттенка: цвет крутят пальцем, и поле HEX
  /// показывает результат. При ручном вводе в поле мы в него не пишем — иначе
  /// каретка прыгала бы в конец на каждой букве.
  void _updateHsv(HSVColor next) {
    setState(() {
      _hsv = next;
      _hexCtrl.text = ColorHex.format(next.toColor());
    });
  }

  Future<void> _apply() async {
    final chosen = _color;
    await RecentColors.remember(chosen);
    if (mounted) Navigator.pop(context, chosen);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = LocaleService.current;
    final color = _color;

    return SheetScaffold(
      bottom: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                s.cancel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _apply,
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                s.selectAction,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.colorLabel,
                    style: TextStyle(
                      fontFamily: 'Unbounded',
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      fontVariations: const [FontVariation('wght', 700)],
                      letterSpacing: -0.3,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (widget.onEyedropper != null)
                  IconButton(
                    tooltip: s.eyedropper,
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onEyedropper!.call();
                    },
                    icon: const Icon(Icons.colorize_rounded, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.surfaceContainerHighest,
                      foregroundColor: cs.onSurfaceVariant,
                      minimumSize: const Size(44, 44),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SaturationValueField(
              hsv: _hsv,
              onChanged: (sat, val) =>
                  _updateHsv(_hsv.withSaturation(sat).withValue(val)),
            ),
            const SizedBox(height: 14),
            HueBar(
              hue: _hsv.hue,
              onChanged: (hue) => _updateHsv(_hsv.withHue(hue)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hexCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(9),
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[#0-9a-fA-F]')),
                    ],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                    decoration: InputDecoration(
                      labelText: 'HEX',
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cs.primary, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    onChanged: (raw) {
                      final parsed = ColorHex.parse(raw);
                      // Недописанный ввод не трогаем: поле само подскажет
                      // цветом-образцом, когда строка станет цветом.
                      if (parsed != null) _setColor(parsed, fromHexField: true);
                    },
                    onEditingComplete: () {
                      _hexCtrl.text = ColorHex.format(_color);
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ),
              ],
            ),
            if (_recent.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                s.recentColors,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _recent.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 9),
                  itemBuilder: (_, i) {
                    final c = _recent[i];
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _setColor(c);
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.outlineVariant),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Квадрат «насыщенность × яркость»
// ─────────────────────────────────────────────────────────────────────────────

/// Поле «насыщенность × яркость». Публичное: его же показывает панель
/// инструментов рисования, чтобы цвет подбирали не уходя с холста.
class SaturationValueField extends StatelessWidget {
  const SaturationValueField({
    super.key,
    required this.hsv,
    required this.onChanged,
    this.height = 180,
  });

  final HSVColor hsv;
  final void Function(double saturation, double value) onChanged;

  /// Высота поля. В листе цвета оно во весь рост, в панели холста ниже:
  /// там под ним ещё палитра и полоса оттенка, а холст не должен уезжать.
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        void handle(Offset local) {
          final sat = (local.dx / width).clamp(0.0, 1.0);
          final val = 1 - (local.dy / height).clamp(0.0, 1.0);
          onChanged(sat, val);
        }

        return GestureDetector(
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: SizedBox(
            width: width,
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // Слева направо — набор насыщенности, сверху вниз — потеря
                  // яркости. Два градиента поверх друг друга дают ровно ту же
                  // картинку, что рисуют пиксельно, но без своего painter'а.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white,
                            HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black, Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: hsv.saturation * width - 11,
                    top: (1 - hsv.value) * height - 11,
                    child: _Knob(color: hsv.toColor()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Полоса оттенка
// ─────────────────────────────────────────────────────────────────────────────

/// Полоса оттенка. Публичная по той же причине, что и [SaturationValueField].
class HueBar extends StatelessWidget {
  const HueBar({super.key, required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  static const List<Color> _spectrum = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const height = 28.0;

        void handle(Offset local) =>
            onChanged((local.dx / width).clamp(0.0, 1.0) * 360);

        return GestureDetector(
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height / 2),
                      gradient: const LinearGradient(colors: _spectrum),
                    ),
                  ),
                ),
                Positioned(
                  left: (hue / 360) * width - 13,
                  top: 1,
                  child: _Knob(
                    color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({required this.color, this.size = 22});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }
}
