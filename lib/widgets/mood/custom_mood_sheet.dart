import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/custom_mood.dart';
import '../../services/custom_mood_service.dart';
import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../../utils/emoji_image.dart';
import '../../utils/photo_crop.dart';
import '../app_sheet.dart';
import 'mood_draw_sheet.dart';

/// Форма своего настроения (Togetherly+).
///
/// Источника три — эмодзи, фотография, рисунок, — но на выходе всегда одна
/// картинка 512×512: так своё настроение работает и в сетке, и в календаре, и
/// на виджете рабочего стола, где нативная разметка рисует файл.
///
/// Возвращает true, если настроение завелось.
Future<bool?> showCustomMoodSheet(BuildContext context, String groupId) {
  return showAppSheet<bool>(
    context,
    builder: (_) => _CustomMoodSheet(groupId: groupId),
  );
}

class _CustomMoodSheet extends StatefulWidget {
  final String groupId;

  const _CustomMoodSheet({required this.groupId});

  @override
  State<_CustomMoodSheet> createState() => _CustomMoodSheetState();
}

class _CustomMoodSheetState extends State<_CustomMoodSheet> {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _emoji = TextEditingController();

  Uint8List? _picture; // готовая картинка: фото или рисунок
  int _score = 3;
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _label.dispose();
    _emoji.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final shot = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 90,
    );
    if (shot == null) return;
    // Обрезка обязательна: в сетке и в календаре настроение живёт в квадратной
    // плитке, а необрезанный кадр в ней сплющивается. Кроппер заодно снимает
    // EXIF-поворот, иначе снимок с камеры приезжает боком.
    final cropped = await cropPhoto(shot.path);
    final bytes = await File(cropped ?? shot.path).readAsBytes();
    if (!mounted) return;
    setState(() {
      _picture = bytes;
      _emoji.clear();
      _error = '';
    });
  }

  Future<void> _draw() async {
    final png = await showMoodDrawSheet(context);
    if (png == null || !mounted) return;
    setState(() {
      _picture = png;
      _emoji.clear();
      _error = '';
    });
  }

  Future<void> _save() async {
    final s = LocaleService.current;
    final label = _label.text.trim();
    final emoji = _emoji.text.trim();

    if (label.isEmpty) {
      setState(() => _error = s.customMoodNeedLabel);
      return;
    }
    if (_picture == null && emoji.isEmpty) {
      setState(() => _error = s.customMoodNeedPicture);
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });

    // Эмодзи превращается в такую же картинку, как фото и рисунок: партнёру со
    // сборкой постарше и виджету на рабочем столе всё равно, откуда она.
    final png = _picture ?? await renderEmojiPng(emoji);
    final made = await CustomMoodService.instance.create(
      groupId: widget.groupId,
      label: label,
      score: _score,
      png: png,
      emoji: _picture == null ? emoji : '',
    );

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
    final hasPicture = _picture != null;

    return SheetScaffold(
      title: s.customMoodTitle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.customMoodSubtitle,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _preview(cs, hasPicture),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _emoji,
                        maxLength: 4,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 26),
                        decoration: InputDecoration(
                          labelText: s.customMoodSourceEmoji,
                          helperText: s.customMoodEmojiHint,
                          counterText: '',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {
                          _picture = null;
                          _error = '';
                        }),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickPhoto,
                              icon: const Icon(Icons.photo_outlined, size: 18),
                              label: Text(s.customMoodSourcePhoto),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _draw,
                              icon: const Icon(Icons.brush_outlined, size: 18),
                              label: Text(s.customMoodSourceDraw),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _label,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: s.customMoodLabelHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = ''),
            ),
            const SizedBox(height: 6),
            Text(
              s.customMoodScoreTitle,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            _scalePills(cs),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error,
                  style: TextStyle(fontSize: 13, color: cs.onErrorContainer),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(s.customMoodSave),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Как настроение будет выглядеть в сетке.
  Widget _preview(ColorScheme cs, bool hasPicture) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPicture
          ? Image.memory(_picture!, fit: BoxFit.cover)
          : Center(
              child: Text(
                _emoji.text.isEmpty ? '🙂' : _emoji.text,
                style: TextStyle(
                  fontSize: 44,
                  color: _emoji.text.isEmpty ? cs.outline : null,
                ),
              ),
            ),
    );
  }

  /// Балл — таблетками, как фильтры достижений: пять штук делят строку и
  /// помещаются на 360 dp.
  Widget _scalePills(ColorScheme cs) {
    final s = LocaleService.current;
    final labels = [
      s.customMoodScore1,
      s.customMoodScore2,
      s.customMoodScore3,
      s.customMoodScore4,
      s.customMoodScore5,
    ];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 6),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _score = i + 1);
                },
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _score == i + 1
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _score == i + 1
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
