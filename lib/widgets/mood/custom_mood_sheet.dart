import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../dict_strings.dart';
import '../../models/custom_mood.dart';
import '../../services/custom_mood_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../../utils/emoji_image.dart';
import '../../utils/photo_crop.dart';
import '../../utils/safe_pick.dart';
import '../app_sheet.dart';
import '../connect_expressive.dart' show M3ShapeClipper;
import 'mood_canvas.dart';
import 'mood_form_parts.dart';

/// Лист «Новое настроение» (Togetherly+), вариант «Холст» из макета 14.10.2026.
///
/// Картинка настроения — главное на листе: источник выбирается прямо на
/// холсте, там же рисуют. Источника три — эмодзи, фото, рисунок, — но на
/// выходе всегда одна картинка 512×512: так своё настроение работает и в
/// сетке, и в календаре, и на виджете рабочего стола, где нативная разметка
/// рисует файл.
///
/// Возвращает true, если настроение завелось.
Future<bool?> showCustomMoodSheet(
  BuildContext context,
  String groupId, {
  CustomMoodStore? store,
  Future<Uint8List?> Function()? pickPhoto,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => _CustomMoodSheet(
      groupId: groupId,
      store: store ?? CustomMoodService.instance,
      pickPhoto: pickPhoto ?? _galleryPhoto,
    ),
  );
}

/// Правка своего настроения: название и место на шкале. Картинку не меняем —
/// прошлые отметки ссылаются на прежний файл.
///
/// Возвращает true, если правка сохранилась.
Future<bool?> showEditCustomMoodSheet(BuildContext context, CustomMood mood, {CustomMoodStore? store}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => _EditCustomMoodSheet(mood: mood, store: store ?? CustomMoodService.instance),
  );
}

/// Частые смайлики на холсте. Без новинок последних лет: на старых телефонах
/// системный шрифт их не знает и рисует пустой квадрат.
const List<String> kQuickMoodEmoji = ['😊', '🥰', '🤯', '😴', '🤒', '😤', '🥺', '😭', '🍕', '☕', '🎉', '💤'];

Future<Uint8List?> _galleryPhoto() async {
  final picker = ImagePicker();
  final shot = await safePick(
    () => picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 90),
  );
  if (shot == null) return null;
  // Обрезка обязательна: в сетке и в календаре настроение живёт в квадратной
  // плитке, а необрезанный кадр в ней сплющивается. Кроппер заодно снимает
  // EXIF-поворот, иначе снимок с камеры приезжает боком.
  final cropped = await cropPhoto(shot.path);
  return File(cropped ?? shot.path).readAsBytes();
}

/// Что сейчас на холсте.
enum _Stage { pick, emojiGrid, emoji, photo, draw }

class _CustomMoodSheet extends StatefulWidget {
  final String groupId;
  final CustomMoodStore store;
  final Future<Uint8List?> Function() pickPhoto;

  const _CustomMoodSheet({required this.groupId, required this.store, required this.pickPhoto});

  @override
  State<_CustomMoodSheet> createState() => _CustomMoodSheetState();
}

class _CustomMoodSheetState extends State<_CustomMoodSheet> {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _emoji = TextEditingController();
  final FocusNode _emojiFocus = FocusNode();

  _Stage _stage = _Stage.pick;
  Uint8List? _photo;
  final List<MoodStroke> _strokes = [];
  Color _ink = kMoodInks.first;
  bool _eraser = false;
  int _score = 3;
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _label.dispose();
    _emoji.dispose();
    _emojiFocus.dispose();
    super.dispose();
  }

  bool get _hasPicture => switch (_stage) {
        _Stage.emoji => _emoji.text.trim().isNotEmpty,
        _Stage.photo => _photo != null,
        _Stage.draw => _strokes.isNotEmpty,
        _ => false,
      };

  bool get _ready => _hasPicture && _label.text.trim().isNotEmpty;

  /// «Сменить»: назад к выбору источника, картинка снимается целиком.
  void _swap() {
    _emojiFocus.unfocus();
    setState(() {
      _stage = _Stage.pick;
      _emoji.clear();
      _photo = null;
      _strokes.clear();
      _eraser = false;
      _error = '';
    });
  }

  Future<void> _choosePhoto() async {
    final bytes = await widget.pickPhoto();
    if (bytes == null || !mounted) return;
    setState(() {
      _photo = bytes;
      _stage = _Stage.photo;
      _error = '';
    });
  }

  void _chooseEmoji(String emoji) {
    HapticFeedback.selectionClick();
    setState(() {
      _emoji.text = emoji;
      _stage = _Stage.emoji;
      _error = '';
    });
  }

  /// «Свой с клавиатуры»: холст становится полем для одного смайлика.
  void _typeEmoji() {
    setState(() {
      _emoji.clear();
      _stage = _Stage.emoji;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emojiFocus.requestFocus();
    });
  }

  Future<void> _save() async {
    if (!_ready || _saving) return;
    final s = LocaleService.current;
    setState(() {
      _saving = true;
      _error = '';
    });
    CustomMood? made;
    try {
      final emoji = _emoji.text.trim();
      final png = switch (_stage) {
        _Stage.photo => _photo!,
        _Stage.draw => await renderStrokesPng(_strokes),
        // Эмодзи превращается в такую же картинку, как фото и рисунок:
        // партнёру со сборкой постарше и виджету на столе всё равно, откуда она.
        _ => await renderEmojiPng(emoji),
      };
      made = await widget.store.create(
        groupId: widget.groupId,
        label: _label.text.trim(),
        score: _score,
        png: png,
        emoji: _stage == _Stage.emoji ? emoji : '',
      );
    } catch (_) {
      made = null;
    }
    if (!mounted) return;
    if (made == null) {
      setState(() {
        _saving = false;
        _error = s.customMoodFailed;
      });
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final t = context.appTheme;
    final cs = ProfileTheme.schemeFor(t);
    return SheetScaffold(
      title: s.customMoodTitle,
      bottom: MoodSheetButton(
        key: const Key('custom-mood-save'),
        label: s.customMoodSave,
        onPressed: _ready ? _save : null,
        busy: _saving,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.customMoodSubtitle,
              style: TextStyle(fontFamily: 'Onest', fontSize: 14, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Center(child: _stageBox(t, cs)),
            if (_stage == _Stage.draw) ...[
              const SizedBox(height: 10),
              _tools(t, cs),
            ],
            const SizedBox(height: 16),
            MoodNameField(controller: _label, onChanged: (_) => setState(() => _error = '')),
            const SizedBox(height: 14),
            MoodScoreScale(score: _score, onChanged: (v) => setState(() => _score = v)),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ErrorNote(text: _error),
            ],
          ],
        ),
      ),
    );
  }

  // ── Холст ────────────────────────────────────────────────────────────────

  Widget _stageBox(AppTheme t, ColorScheme cs) {
    return LayoutBuilder(builder: (context, box) {
      final side = math.min(264.0, box.maxWidth);
      final tinted = _stage == _Stage.emoji && _emoji.text.trim().isNotEmpty;
      final background = switch (_stage) {
        _Stage.draw => Colors.white,
        _ when tinted => moodScoreTint(_score, cs, alpha: 0.30),
        _ => cs.surfaceContainerHighest,
      };
      return SizedBox(
        key: const Key('custom-mood-stage'),
        width: side,
        height: side,
        child: ClipPath(
          clipper: ShapeBorderClipper(
            shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(side * 0.2)),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            color: background,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _stageContent(t, cs, side),
                if (_stage == _Stage.emoji || _stage == _Stage.photo)
                  Positioned(top: 12, right: 12, child: _SwapPill(onTap: _swap)),
                if (_stage == _Stage.draw)
                  Positioned(top: 10, right: 10, child: _SwapRound(onTap: _swap)),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _stageContent(AppTheme t, ColorScheme cs, double side) {
    final s = LocaleService.current;
    switch (_stage) {
      case _Stage.pick:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StageOption(
                key: const Key('custom-mood-src-emoji'),
                icon: Icons.emoji_emotions_rounded,
                label: s.customMoodSourceEmoji,
                onTap: () => setState(() => _stage = _Stage.emojiGrid),
              ),
              const SizedBox(height: 10),
              _StageOption(
                key: const Key('custom-mood-src-photo'),
                icon: Icons.photo_rounded,
                label: s.customMoodSourcePhoto,
                onTap: _choosePhoto,
              ),
              const SizedBox(height: 10),
              _StageOption(
                key: const Key('custom-mood-src-draw'),
                icon: Icons.brush_rounded,
                label: s.customMoodSourceDraw,
                onTap: () => setState(() {
                  _strokes.clear();
                  _stage = _Stage.draw;
                }),
              ),
            ],
          ),
        );
      case _Stage.emojiGrid:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  const gap = 4.0;
                  final cellW = (box.maxWidth - gap * 3) / 4;
                  final cellH = (box.maxHeight - gap * 2) / 3;
                  return GridView.count(
                    crossAxisCount: 4,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    childAspectRatio: cellH > 0 ? cellW / cellH : 1,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: [
                      for (final e in kQuickMoodEmoji)
                        _EmojiCell(
                          key: Key('custom-mood-emoji-$e'),
                          emoji: e,
                          size: math.min(cellW, cellH) * 0.62,
                          onTap: () => _chooseEmoji(e),
                        ),
                    ],
                  );
                }),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _KeyboardPill(label: trKey('customMoodOwnKeyboard'), onTap: _typeEmoji),
                  ),
                  const SizedBox(width: 6),
                  _SwapRound(onTap: _swap, size: 44, tonal: true),
                ],
              ),
            ],
          ),
        );
      case _Stage.emoji:
        final empty = _emoji.text.trim().isEmpty;
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MediaQuery.withNoTextScaling(
                  child: TextField(
                    key: const Key('custom-mood-emoji-field'),
                    controller: _emoji,
                    focusNode: _emojiFocus,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: side * 0.42, height: 1.15, color: cs.onSurface),
                    cursorColor: cs.primary,
                    buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                    decoration: const InputDecoration.collapsed(hintText: ''),
                    onChanged: (_) => setState(() => _error = ''),
                    onSubmitted: (_) => _emojiFocus.unfocus(),
                  ),
                ),
              ),
            ),
            if (empty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 18,
                child: Text(
                  trKey('customMoodTypeHint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Onest', fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        );
      case _Stage.photo:
        return Image.memory(_photo!, fit: BoxFit.cover, gaplessPlayback: true);
      case _Stage.draw:
        return MoodCanvas(
          key: const Key('custom-mood-canvas'),
          strokes: _strokes,
          color: _ink,
          eraser: _eraser,
          onChanged: () => setState(() => _error = ''),
        );
    }
  }

  // ── Кисть ────────────────────────────────────────────────────────────────

  Widget _tools(AppTheme t, ColorScheme cs) {
    final s = LocaleService.current;
    final onFill = AppThemes.onColor(t.fillColor, mode: t.brightness);
    return LayoutBuilder(builder: (context, box) {
      // Шесть красок делят остаток строки после двух кнопок; на 320 точках
      // кружок становится меньше, но не уезжает за край. Кнопка рисуется в 44,
      // а места занимает 48: столько Material отдаёт под касание.
      const button = 44.0, target = 48.0, gap = 6.0;
      final cell = ((box.maxWidth - target * 2 - gap * 3) / kMoodInks.length).clamp(26.0, 40.0);
      final dot = math.min(30.0, cell - 6);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < kMoodInks.length; i++)
            _InkDot(
              key: Key('custom-mood-ink-$i'),
              color: kMoodInks[i],
              cell: cell,
              dot: dot,
              selected: !_eraser && _ink == kMoodInks[i],
              onTap: () => setState(() {
                _ink = kMoodInks[i];
                _eraser = false;
              }),
            ),
          const SizedBox(width: gap),
          IconButton(
            key: const Key('custom-mood-eraser'),
            tooltip: s.customMoodEraser,
            onPressed: () => setState(() => _eraser = !_eraser),
            style: IconButton.styleFrom(
              fixedSize: const Size(button, button),
              backgroundColor: _eraser ? t.fillColor : cs.surfaceContainerHighest,
              foregroundColor: _eraser ? onFill : cs.onSurface,
            ),
            icon: const Icon(Icons.cleaning_services_rounded, size: 22),
          ),
          const SizedBox(width: gap),
          IconButton(
            key: const Key('custom-mood-undo'),
            tooltip: s.customMoodUndo,
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() {
                      _strokes.removeLast();
                    }),
            style: IconButton.styleFrom(
              fixedSize: const Size(button, button),
              backgroundColor: cs.surfaceContainerHighest,
              foregroundColor: cs.onSurface,
              disabledBackgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            ),
            icon: const Icon(Icons.undo_rounded, size: 22),
          ),
        ],
      );
    });
  }
}

class _StageOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _StageOption({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final cs = ProfileTheme.schemeFor(t);
    final onFill = AppThemes.onColor(t.fillColor, mode: t.brightness);
    return Material(
      color: cs.surfaceContainerHigh,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: t.fillColor, shape: BoxShape.circle),
                  child: Icon(icon, size: 22, color: onFill),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Onest', fontSize: 15, fontWeight: FontWeight.w600, height: 1.2, color: cs.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmojiCell extends StatelessWidget {
  final String emoji;
  final double size;
  final VoidCallback onTap;

  const _EmojiCell({super.key, required this.emoji, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: emoji,
      child: InkResponse(
        onTap: onTap,
        radius: size,
        child: Center(
          child: MediaQuery.withNoTextScaling(
            child: Text(emoji, style: TextStyle(fontSize: size, height: 1.0)),
          ),
        ),
      ),
    );
  }
}

class _KeyboardPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _KeyboardPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    return Material(
      key: const Key('custom-mood-kbd'),
      color: cs.surfaceContainerHigh,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.keyboard_rounded, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Onest', fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Сменить» на холсте с готовой картинкой.
class _SwapPill extends StatelessWidget {
  final VoidCallback onTap;

  const _SwapPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    return Material(
      key: const Key('custom-mood-swap'),
      color: cs.inverseSurface,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz_rounded, size: 18, color: cs.onInverseSurface),
              const SizedBox(width: 6),
              Text(
                trKey('customMoodSwap'),
                style: TextStyle(fontFamily: 'Onest', fontSize: 13, fontWeight: FontWeight.w600, color: cs.onInverseSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Сменить» кружком: на холсте рисунка и в сетке смайликов пилюля закрывала бы
/// место, где рисуют или выбирают.
class _SwapRound extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final bool tonal;

  const _SwapRound({required this.onTap, this.size = 40, this.tonal = false});

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    return Tooltip(
      message: trKey('customMoodSwap'),
      child: Material(
        key: const Key('custom-mood-swap'),
        color: tonal ? cs.surfaceContainerHigh : cs.inverseSurface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(Icons.swap_horiz_rounded, size: 20, color: tonal ? cs.onSurfaceVariant : cs.onInverseSurface),
          ),
        ),
      ),
    );
  }
}

class _InkDot extends StatelessWidget {
  final Color color;
  final double cell;
  final double dot;
  final bool selected;
  final VoidCallback onTap;

  const _InkDot({
    super.key,
    required this.color,
    required this.cell,
    required this.dot,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: cell,
          height: 48,
          child: Center(
            child: AnimatedScale(
              scale: selected ? 1.3 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: SizedBox(
                width: dot,
                height: dot,
                child: ClipPath(
                  clipper: selected
                      ? M3ShapeClipper(MaterialShapes.cookie9Sided)
                      : const ShapeBorderClipper(shape: CircleBorder()),
                  child: ColoredBox(color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final String text;

  const _ErrorNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(14)),
      child: Text(text, style: TextStyle(fontFamily: 'Onest', fontSize: 13, color: cs.onErrorContainer)),
    );
  }
}

// ── Правка ─────────────────────────────────────────────────────────────────

class _EditCustomMoodSheet extends StatefulWidget {
  final CustomMood mood;
  final CustomMoodStore store;

  const _EditCustomMoodSheet({required this.mood, required this.store});

  @override
  State<_EditCustomMoodSheet> createState() => _EditCustomMoodSheetState();
}

class _EditCustomMoodSheetState extends State<_EditCustomMoodSheet> {
  late final TextEditingController _label = TextEditingController(text: widget.mood.label);
  late int _score = widget.mood.score;
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  bool get _ready {
    final label = _label.text.trim();
    if (label.isEmpty) return false;
    return label != widget.mood.label || _score != widget.mood.score;
  }

  Future<void> _save() async {
    if (!_ready || _saving) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    final ok = await widget.store.rename(recordId: widget.mood.id, label: _label.text.trim(), score: _score);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = LocaleService.current.customMoodFailed;
      });
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = ProfileTheme.schemeFor(context.appTheme);
    final label = _label.text.trim();
    return SheetScaffold(
      title: trKey('customMoodEditTitle'),
      bottom: MoodSheetButton(
        key: const Key('custom-mood-save'),
        label: s.save,
        onPressed: _ready ? _save : null,
        busy: _saving,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: OwnMoodPicture(mood: widget.mood, size: 124, score: _score)),
            const SizedBox(height: 10),
            Text(
              label.isEmpty ? widget.mood.label : label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Onest', fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              trKey('customMoodEditHint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Onest', fontSize: 13, height: 1.4, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            MoodNameField(controller: _label, onChanged: (_) => setState(() => _error = '')),
            const SizedBox(height: 14),
            MoodScoreScale(score: _score, onChanged: (v) => setState(() => _score = v)),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ErrorNote(text: _error),
            ],
          ],
        ),
      ),
    );
  }
}
