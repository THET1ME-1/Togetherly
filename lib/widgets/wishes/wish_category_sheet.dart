import 'package:flutter/material.dart';

import '../../models/symbol_catalog.dart';
import '../../models/wish_category.dart';
import '../../screens/symbol_picker_screen.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';

/// Что вернул лист своей категории.
class WishKindDraft {
  const WishKindDraft({
    required this.title,
    required this.symbol,
    required this.note,
  });

  final String title;
  final String symbol;
  final String note;
}

/// Лист «Своя категория»: значок из полного набора, название и примечание.
///
/// Значок выбирается на общем экране символов — том же, что у таймеров, с
/// поиском по русским словам и по английским именам. Своих картинок не
/// заводим: 4381 значок покрывает всё, что пары придумывают, и весит один
/// подшитый шрифт.
Future<WishKindDraft?> showWishCategorySheet(
  BuildContext context, {
  required AppTheme theme,
  WishKind? existing,
}) {
  final scheme = ProfileTheme.themeFor(theme).colorScheme;
  final ru = LocaleService.instance.isRussian;

  return showAppSheet<WishKindDraft>(
    context,
    background: scheme.surfaceContainer,
    builder: (_) => _CategoryForm(
      theme: theme,
      scheme: scheme,
      ru: ru,
      existing: existing,
    ),
  );
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({
    required this.theme,
    required this.scheme,
    required this.ru,
    this.existing,
  });

  final AppTheme theme;
  final ColorScheme scheme;
  final bool ru;
  final WishKind? existing;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.titleRu ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  late String _symbol = widget.existing?.symbol ?? 'star';

  ColorScheme get _cs => widget.scheme;

  String _tr(String r, String e) => widget.ru ? r : e;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickSymbol() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => SymbolPickerScreen(theme: widget.theme, selected: _symbol),
      ),
    );
    if (picked != null && picked.isNotEmpty && mounted) {
      setState(() => _symbol = picked);
    }
  }

  void _submit() {
    final text = _title.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(WishKindDraft(
      title: text,
      symbol: _symbol,
      note: _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return SheetScaffold(
      title: editing
          ? _tr('Правим категорию', 'Edit category')
          : _tr('Своя категория', 'Your own category'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            // Значок и название стоят в строке: сначала выбирают картинку,
            // потом дописывают слово — так это и делают в жизни.
            Row(
              children: [
                Material(
                  color: _cs.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _pickSymbol,
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: Center(
                        child: SymbolIcon(_symbol,
                            size: 30, color: _cs.onPrimaryContainer),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    controller: _title,
                    label: _tr('Название', 'Name'),
                    hint: _tr('Концерты', 'Concerts'),
                    maxLength: 40,
                    autofocus: !editing,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _pickSymbol,
              icon: Icon(Icons.search_rounded, size: 18, color: _cs.primary),
              label: Text(
                _tr('Выбрать значок из 4381', 'Pick from 4381 icons'),
                style: AppFonts.onest(size: 13.5, weight: 600, color: _cs.primary),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(height: 6),
            _field(
              controller: _note,
              label: _tr('Примечание', 'Note'),
              hint: _tr('не обязательно', 'optional'),
              maxLength: 200,
            ),
            const SizedBox(height: 18),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _title,
              builder: (_, value, _) => SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: value.text.trim().isEmpty ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _cs.primary,
                    foregroundColor: _cs.onPrimary,
                    disabledBackgroundColor:
                        _cs.onSurface.withValues(alpha: .12),
                    disabledForegroundColor:
                        _cs.onSurface.withValues(alpha: .38),
                    shape: const StadiumBorder(),
                    textStyle: AppFonts.onest(size: 16, weight: 700),
                  ),
                  child: Text(editing
                      ? _tr('Сохранить', 'Save')
                      : _tr('Создать', 'Create')),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 48,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: _cs.primary,
                  textStyle: AppFonts.onest(size: 16, weight: 700),
                ),
                child: Text(_tr('Отмена', 'Cancel')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLength = 60,
    bool autofocus = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLength: maxLength,
      textInputAction:
          onSubmitted == null ? TextInputAction.done : TextInputAction.go,
      onSubmitted: onSubmitted,
      textCapitalization: TextCapitalization.sentences,
      style: AppFonts.onest(size: 16, color: _cs.onSurface),
      cursorColor: _cs.primary,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        filled: true,
        fillColor: _cs.surfaceContainerHighest,
        labelStyle: AppFonts.onest(size: 12, weight: 600, color: _cs.primary),
        floatingLabelStyle:
            AppFonts.onest(size: 12, weight: 600, color: _cs.primary),
        hintStyle: AppFonts.onest(size: 16, color: _cs.onSurfaceVariant),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: _cs.primary, width: 2),
        ),
      ),
    );
  }
}
