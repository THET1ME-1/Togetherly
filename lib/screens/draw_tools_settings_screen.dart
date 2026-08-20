import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/draw_quick_tools.dart';
import '../services/locale_service.dart';
import '../services/ui_prefs.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';

/// Настройка панели быстрого доступа холста: что в ней стоит и в каком порядке.
///
/// Порядок задаётся перетаскиванием, состав — переключателями. Набор живёт на
/// устройстве: это привычка руки, а не общее имущество пары.
class DrawToolsSettingsScreen extends StatefulWidget {
  const DrawToolsSettingsScreen({super.key, required this.theme});

  final AppTheme theme;

  @override
  State<DrawToolsSettingsScreen> createState() =>
      _DrawToolsSettingsScreenState();
}

class _DrawToolsSettingsScreenState extends State<DrawToolsSettingsScreen> {
  List<DrawQuickTool> _shown = kDefaultQuickTools;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _shown = parseQuickTools(p.getString(UiPrefs.kDrawQuickTools));
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(UiPrefs.kDrawQuickTools, encodeQuickTools(_shown));
  }

  void _apply(List<DrawQuickTool> next) {
    HapticFeedback.selectionClick();
    setState(() => _shown = next);
    _save();
  }

  String _label(AppStrings s, DrawQuickTool tool) => switch (tool) {
        DrawQuickTool.brush => s.brush,
        DrawQuickTool.eraser => s.eraser,
        DrawQuickTool.fill => s.fillBg,
        DrawQuickTool.shapes => s.drawShapes,
        DrawQuickTool.layers => s.drawLayers,
        DrawQuickTool.image => s.addPhoto,
        DrawQuickTool.palm => s.palmTool,
        DrawQuickTool.background => s.drawBackgrounds,
        DrawQuickTool.clear => s.clearCanvas,
        DrawQuickTool.replay => s.drawReplay,
      };

  static const Map<DrawQuickTool, IconData> _icons = {
    DrawQuickTool.brush: Icons.brush_rounded,
    DrawQuickTool.eraser: Icons.auto_fix_normal_rounded,
    DrawQuickTool.fill: Icons.format_color_fill_rounded,
    DrawQuickTool.shapes: Icons.category_rounded,
    DrawQuickTool.layers: Icons.layers_rounded,
    DrawQuickTool.image: Icons.image_rounded,
    DrawQuickTool.palm: Icons.pan_tool_rounded,
    DrawQuickTool.background: Icons.texture_rounded,
    DrawQuickTool.clear: Icons.delete_outline_rounded,
    DrawQuickTool.replay: Icons.play_circle_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = ProfileTheme.schemeFor(widget.theme);
    final hidden =
        DrawQuickTool.values.where((t) => !_shown.contains(t)).toList();
    final full = _shown.length >= kMaxQuickTools;

    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          title: Text(
            s.drawToolsTitle,
            style: const TextStyle(
              fontFamily: 'Unbounded',
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
        ),
        body: !_loaded
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    s.drawToolsReorder,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s.drawToolsShown.toUpperCase(),
                    style: ProfileTheme.sectionLabel(cs),
                  ),
                  const SizedBox(height: 8),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorder: (from, to) {
                      final next = List.of(_shown);
                      final item = next.removeAt(from);
                      next.insert(from < to ? to - 1 : to, item);
                      _apply(next);
                    },
                    children: [
                      for (var i = 0; i < _shown.length; i++)
                        _row(
                          cs,
                          s,
                          _shown[i],
                          index: i,
                          shown: true,
                          // Кисть убрать нельзя: без неё холст перестаёт быть
                          // холстом, а вернуть её можно только отсюда же.
                          locked: _shown[i] == DrawQuickTool.brush,
                        ),
                    ],
                  ),
                  if (hidden.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      s.drawToolsHidden.toUpperCase(),
                      style: ProfileTheme.sectionLabel(cs),
                    ),
                    if (full) ...[
                      const SizedBox(height: 4),
                      Text(
                        s.drawToolsFull,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    for (final tool in hidden)
                      _row(cs, s, tool, shown: false, disabled: full),
                  ],
                  const SizedBox(height: 12),
                  // Кнопка внизу, а не в шапке: рядом с заголовком она резала
                  // название экрана на узком телефоне.
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _apply(List.of(kDefaultQuickTools)),
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: Text(s.drawToolsReset),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _row(
    ColorScheme cs,
    AppStrings s,
    DrawQuickTool tool, {
    int? index,
    required bool shown,
    bool locked = false,
    bool disabled = false,
  }) {
    void toggle() {
      if (locked) return;
      final next = List.of(_shown);
      if (shown) {
        next.remove(tool);
      } else {
        if (disabled) return;
        next.add(tool);
      }
      _apply(next);
    }

    return Padding(
      key: ValueKey(tool),
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Icon(_icons[tool], size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _label(s, tool),
                    style: const TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: shown,
                  onChanged: locked || (disabled && !shown)
                      ? null
                      : (_) => toggle(),
                ),
                if (shown && index != null)
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, right: 6),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 34),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
