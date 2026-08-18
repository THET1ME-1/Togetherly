import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/custom_theme.dart';
import '../../services/locale_service.dart';
import '../../services/photo_palette_service.dart';
import '../../theme/app_palettes.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../app_sheet.dart';
import '../seed_swatch.dart';

/// Лист своей темы: цвет берётся из фотографии или из пикера.
///
/// Отдельного экрана у этого нет намеренно — «Внешний вид» и так плотный,
/// а решение здесь одно: какой цвет. Лист живёт выше экрана, поэтому тема
/// задаётся явно (см. `plus_promo_sheet.dart`).
///
/// Возвращает собранную тему; `null` — человек закрыл лист.
Future<CustomTheme?> showCustomThemeSheet(
  BuildContext context, {
  CustomTheme? initial,
}) {
  final cs = ProfileTheme.schemeFor(context.appTheme);
  return showAppSheet<CustomTheme>(
    context,
    background: cs.surfaceContainerHigh,
    builder: (ctx) => Theme(
      data: ProfileTheme.data(cs),
      child: _CustomThemeSheet(initial: initial),
    ),
  );
}

class _CustomThemeSheet extends StatefulWidget {
  final CustomTheme? initial;

  const _CustomThemeSheet({this.initial});

  @override
  State<_CustomThemeSheet> createState() => _CustomThemeSheetState();
}

enum _Source { photo, picker }

class _CustomThemeSheetState extends State<_CustomThemeSheet> {
  late Color _seed = widget.initial?.seed ?? kPalettes.first.accent;
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  _Source _source = _Source.photo;
  List<Color> _fromPhoto = const [];
  bool _reading = false;
  bool _photoEmpty = false;

  AppStrings get _s => LocaleService.current;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _reading = true;
      _photoEmpty = false;
    });
    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1200);
      if (picked == null) {
        if (mounted) setState(() => _reading = false);
        return;
      }
      final colors = await seedColorsFromImage(await picked.readAsBytes());
      if (!mounted) return;
      setState(() {
        _fromPhoto = colors;
        _photoEmpty = colors.isEmpty;
        _reading = false;
        if (colors.isNotEmpty) _seed = colors.first;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _reading = false;
          _photoEmpty = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SheetScaffold(
      title: _s.customThemeTitle,
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(
              context,
              CustomTheme(seed: _seed, name: _name.text.trim()),
            ),
            child: Text(_s.save),
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _preview(cs),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Source>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _Source.photo,
                    icon: const Icon(Icons.photo_camera_back_rounded),
                    label: Text(_s.customThemeFromPhoto),
                  ),
                  ButtonSegment(
                    value: _Source.picker,
                    icon: const Icon(Icons.palette_rounded),
                    label: Text(_s.customThemeFromPicker),
                  ),
                ],
                selected: {_source},
                onSelectionChanged: (v) => setState(() => _source = v.first),
              ),
            ),
            const SizedBox(height: 16),
            if (_source == _Source.photo) _photoTab(cs) else _pickerTab(),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 24,
              decoration: InputDecoration(
                labelText: _s.customThemeNameLabel,
                hintText: _s.customThemeNameHint,
                counterText: '',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Кружок будущей темы и подпись. Показывает ровно ту схему, что достанется
  /// экранам: палитра собирается тем же [customPalette], что и при сохранении.
  Widget _preview(ColorScheme cs) {
    final palette = customPalette(_seed, slot: 0);
    return Row(
      children: [
        SeedSwatch(palette: palette, size: 56, selected: true),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _s.customThemePreview,
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(paletteFill(palette, Theme.of(context).brightness)),
                  _chip(cs.surfaceContainerHighest, wide: true),
                  _chip(paletteInk(palette, Theme.of(context).brightness)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(Color color, {bool wide = false}) => Container(
        width: wide ? 54 : 34,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
      );

  Widget _photoTab(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.tonalIcon(
          onPressed: _reading ? null : _pickPhoto,
          icon: const Icon(Icons.image_rounded),
          label: Text(_fromPhoto.isEmpty
              ? _s.customThemePickPhoto
              : _s.customThemeAnotherPhoto),
        ),
        if (_reading)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: LinearProgressIndicator(),
          ),
        if (_fromPhoto.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in _fromPhoto)
                SeedSwatch(
                  palette: customPalette(color, slot: 0),
                  selected: color == _seed,
                  size: 44,
                  onTap: () => setState(() => _seed = color),
                ),
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _photoEmpty ? _s.customThemeNoColors : _s.customThemePhotoHint,
            style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontSize: 12.5,
              color: _photoEmpty ? cs.error : cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _pickerTab() => ColorPicker(
        pickerColor: _seed,
        onColorChanged: (c) => setState(() => _seed = c),
        enableAlpha: false,
        displayThumbColor: true,
        paletteType: PaletteType.hueWheel,
        labelTypes: const [],
        hexInputBar: true,
        portraitOnly: true,
        pickerAreaBorderRadius: BorderRadius.circular(16),
      );
}
