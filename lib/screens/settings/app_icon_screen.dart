import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../services/app_icon_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/app_icon_sheet.dart';

/// Открыть экран иконки. Тему снимаем до перехода: экран переживает лист
/// настроек, из которого его открыли.
Future<void> openAppIconScreen(
  BuildContext context, {
  required AppTheme theme,
  required String currentId,
  ValueChanged<String>? onChanged,
}) {
  final scheme = ProfileTheme.themeFor(theme).colorScheme;
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AppIconScreen(
        scheme: scheme,
        currentId: currentId,
        onChanged: onChanged,
      ),
    ),
  );
}

/// Экран «Иконка приложения» (25.11.2026, был листом снизу; владелец: «зачем
/// попап, экран сделай нормальный, но красивый»).
///
/// Сверху рабочий стол в миниатюре: выбранная иконка стоит в ряду среди
/// соседей и подписана «Togetherly», как её увидит человек. Ниже две группы:
/// рисунки крупно и буквы цветом темы. Нажатие сразу меняет иконку и
/// оставляет человека на экране, чтобы сравнить.
class AppIconScreen extends StatefulWidget {
  const AppIconScreen({
    super.key,
    required this.scheme,
    required this.currentId,
    this.onChanged,
  });

  final ColorScheme scheme;
  final String currentId;

  /// Иконка сменилась на устройстве.
  final ValueChanged<String>? onChanged;

  @override
  State<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends State<AppIconScreen> {
  late String _selected = widget.currentId;
  bool _busy = false;
  String? _error;

  Future<void> _apply(String id) async {
    if (_busy || id == _selected) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await AppIconService.instance.setIcon(id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _selected = id;
      } else {
        _error = LocaleService.current.appIconChangeFailed;
      }
    });
    if (ok) widget.onChanged?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    final s = LocaleService.current;
    final art = AppIconService.options.where((o) => o.asset != null).toList();
    final letters = AppIconService.options.where((o) => o.asset == null).toList();
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(
            s.appIconTitle,
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          // На планшете сетка не расползается по всей ширине.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.paddingOf(context).bottom + 32,
              ),
              children: [
                _HomePreview(option: appIconOptionOf(_selected), scheme: cs),
                const SizedBox(height: 10),
                Text(
                  s.appIconUpdateHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 13,
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),
                ],
                _GroupTitle(trKey('appicon_group_art'), cs),
                _IconGrid(
                  items: art,
                  selected: _selected,
                  busy: _busy,
                  scheme: cs,
                  // Рисунков три, и они всегда в один ряд, даже на 320 точках.
                  minTile: 80,
                  maxColumns: art.length,
                  onTap: _apply,
                ),
                _GroupTitle(trKey('appicon_group_colors'), cs),
                _IconGrid(
                  items: letters,
                  selected: _selected,
                  busy: _busy,
                  scheme: cs,
                  minTile: 72,
                  maxColumns: 6,
                  onTap: _apply,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Рабочий стол в миниатюре: обои цветом темы, ряд из четырёх мест, во
/// втором — выбранная иконка с подписью. Соседи — пустые светлые плитки, чтобы
/// не придумывать чужие приложения.
class _HomePreview extends StatelessWidget {
  const _HomePreview({required this.option, required this.scheme});

  final AppIconOption option;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primaryContainer, cs.tertiaryContainer],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final slot = ((box.maxWidth - 3 * 14) / 4).clamp(0.0, 76.0);
          final icon = slot * 0.82;
          Widget place({Widget? child, required bool mine}) => SizedBox(
            width: slot,
            child: Column(
              children: [
                SizedBox(
                  width: icon,
                  height: icon,
                  child: child ??
                      DecoratedBox(
                        decoration: BoxDecoration(
                          // Тон обоев чуть темнее: соседи видны и в светлой
                          // теме, где белая плитка тонула в розовом.
                          color: Color.lerp(cs.primaryContainer, cs.onPrimaryContainer, 0.10),
                          borderRadius: BorderRadius.circular(icon * 0.22),
                        ),
                      ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 16,
                  // Подпись как у лончера: тёмная и целиком, на узком экране
                  // ужимается, а не обрезается.
                  child: mine
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Togetherly',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontFamily: ProfileTheme.bodyFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        )
                      : Center(
                          child: Container(
                            width: slot * 0.5,
                            height: 6,
                            decoration: BoxDecoration(
                              color: cs.onPrimaryContainer.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              place(mine: false),
              place(
                mine: true,
                // Смена иконки — мягкое перетекание, без прыжка.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.94, end: 1.0).animate(a),
                      child: child,
                    ),
                  ),
                  child: AppIconBadge(
                    key: ValueKey(option.id),
                    option: option,
                    size: icon,
                  ),
                ),
              ),
              place(mine: false),
              place(mine: false),
            ],
          );
        },
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text, this.scheme);

  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: ProfileTheme.displayFont,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
  );
}

/// Ровная сетка: колонок столько, сколько влезает плиток не уже [minTile] и не
/// уже самой длинной подписи одним словом, плитки тянутся на всю строку,
/// неполный ряд прижат влево. Высота подписи одна на группу.
class _IconGrid extends StatelessWidget {
  const _IconGrid({
    required this.items,
    required this.selected,
    required this.busy,
    required this.scheme,
    required this.minTile,
    required this.maxColumns,
    required this.onTap,
  });

  final List<AppIconOption> items;
  final String selected;
  final bool busy;
  final ColorScheme scheme;
  final double minTile;
  final int maxColumns;
  final ValueChanged<String> onTap;

  static const double _gap = 12;
  static const double _ring = 2.5;
  static const double _ringGap = 3;

  TextStyle _label(bool on) => TextStyle(
    fontFamily: ProfileTheme.bodyFont,
    fontSize: 12,
    height: 1.3,
    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
    color: on ? scheme.primary : scheme.onSurfaceVariant,
  );

  /// Ширина самого длинного слова подписей: плитка не уже его, иначе слово
  /// рвётся посередине («Фиолетов / ая» на узком экране).
  double _longestWord(TextScaler scale) {
    var widest = 0.0;
    for (final o in items) {
      for (final word in o.name.split(' ')) {
        final p = TextPainter(
          text: TextSpan(text: word, style: _label(true)),
          textDirection: TextDirection.ltr,
          textScaler: scale,
          maxLines: 1,
        )..layout();
        if (p.width > widest) widest = p.width;
        p.dispose();
      }
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final least = [minTile, _longestWord(scale) + 6].reduce((a, b) => a > b ? a : b);
        final cols = ((width + _gap) / (least + _gap)).floor().clamp(1, maxColumns);
        final tile = ((width - _gap * (cols - 1)) / cols).floorToDouble();
        // Подпись в одну строку, если все влезают; иначе у всех две.
        var lines = 1;
        for (final o in items) {
          final p = TextPainter(
            text: TextSpan(text: o.name, style: _label(true)),
            textDirection: TextDirection.ltr,
            textScaler: scale,
            maxLines: 2,
          )..layout(maxWidth: tile);
          if (p.computeLineMetrics().length > 1) lines = 2;
          p.dispose();
        }
        final labelHeight = scale.scale(12) * 1.3 * lines + 2;
        return Wrap(
          spacing: _gap,
          runSpacing: 16,
          children: [for (final o in items) _tile(o, tile, labelHeight)],
        );
      },
    );
  }

  Widget _tile(AppIconOption o, double tile, double labelHeight) {
    final on = o.id == selected;
    // Значок занимает плитку целиком, за вычетом кольца выбора; на планшете
    // буквенный значок не раздувается больше 76.
    final icon = (tile - 2 * (_ring + _ringGap)).clamp(0.0, maxColumns <= 3 ? 132.0 : 76.0);
    final radius = icon * 0.22;
    return Semantics(
      selected: on,
      button: true,
      label: o.name,
      child: InkWell(
        onTap: busy ? null : () => onTap(o.id),
        borderRadius: BorderRadius.circular(radius + _ring + _ringGap),
        child: SizedBox(
          width: tile,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(_ringGap),
                decoration: BoxDecoration(
                  // Кольцо повторяет форму значка: радиус иконки плюс зазор и
                  // толщина кольца.
                  borderRadius: BorderRadius.circular(radius + _ringGap + _ring),
                  border: Border.all(
                    color: on ? scheme.primary : Colors.transparent,
                    width: _ring,
                  ),
                ),
                child: AppIconBadge(option: o, size: icon),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: labelHeight,
                child: Text(
                  o.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _label(on),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
