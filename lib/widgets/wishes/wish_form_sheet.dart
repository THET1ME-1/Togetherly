import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/symbol_catalog.dart';
import '../../models/wish.dart';
import '../../models/wish_category.dart';
import '../../services/locale_service.dart';
import '../../services/pb_data_service.dart';
import '../../services/pb_media_service.dart';
import '../../services/plus_access.dart';
import '../../utils/safe_pick.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import '../storage_image.dart';

/// Что вернул лист: новое желание или правка старого.
class WishDraft {
  const WishDraft({
    required this.title,
    required this.note,
    required this.kind,
    this.isItem = false,
    this.price = 0,
    this.currency = '',
    this.url = '',
    this.image = '',
    this.shop = '',
  });

  final String title;
  final String note;
  final WishKind kind;

  // ── Вещь: цена, ссылка, картинка ──
  final bool isItem;
  final int price;
  final String currency;
  final String url;
  final String image;
  final String shop;
}

/// Лист «Новое желание»: категория чипами, название и необязательная заметка.
///
/// Кнопка подтверждения во всю ширину листа — как и остальные действия
/// проекта: до угла экрана большим пальцем не дотянуться.
Future<WishDraft?> showWishFormSheet(
  BuildContext context, {
  required AppTheme theme,
  required List<WishKind> customKinds,
  required PlusGate plusGate,
  required String groupId,
  required String uid,
  Wish? existing,
  String initialUrl = '',
  Future<WishKind?> Function()? onCreateCategory,
  Future<void> Function(WishKind kind)? onEditCategory,
  VoidCallback? onOfferPlus,
}) {
  // Тему и строки снимаем ДО открытия листа: он живёт в дереве навигатора и
  // переживает экран, а обращение к его состоянию из builder'а уже давало
  // сотни падений на мёртвом `State.context`.
  final scheme = ProfileTheme.themeFor(theme).colorScheme;
  final ru = LocaleService.instance.isRussian;

  return showAppSheet<WishDraft>(
    context,
    background: scheme.surfaceContainer,
    builder: (_) => _WishForm(
      scheme: scheme,
      ru: ru,
      groupId: groupId,
      uid: uid,
      initialUrl: initialUrl,
      existing: existing,
      customKinds: customKinds,
      plusGate: plusGate,
      onCreateCategory: onCreateCategory,
      onEditCategory: onEditCategory,
      onOfferPlus: onOfferPlus,
    ),
  );
}

class _WishForm extends StatefulWidget {
  const _WishForm({
    required this.scheme,
    required this.ru,
    required this.customKinds,
    required this.plusGate,
    required this.groupId,
    required this.uid,
    this.initialUrl = '',
    this.existing,
    this.onCreateCategory,
    this.onEditCategory,
    this.onOfferPlus,
  });

  final ColorScheme scheme;
  final bool ru;
  final List<WishKind> customKinds;
  final PlusGate plusGate;
  final String groupId;
  final String uid;

  /// Ссылка, пришедшая из «Поделиться»: форма открывается уже с ней.
  final String initialUrl;
  final Wish? existing;
  final Future<WishKind?> Function()? onCreateCategory;
  final Future<void> Function(WishKind kind)? onEditCategory;
  final VoidCallback? onOfferPlus;

  @override
  State<_WishForm> createState() => _WishFormState();
}

class _WishFormState extends State<_WishForm> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  late List<WishKind> _custom = List.of(widget.customKinds);
  late WishKind _kind = _initialKind();

  ColorScheme get _cs => widget.scheme;

  String _tr(String r, String e) => widget.ru ? r : e;

  @override
  void initState() {
    super.initState();
    // Ссылка пришла из «Поделиться» — карточку тянем сразу, человек нажал
    // «поделиться» именно ради неё.
    if (widget.existing == null && widget.initialUrl.isNotEmpty) {
      _isItem = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPreview());
    }
    if (widget.existing?.isItem ?? false) _isItem = true;
  }

  WishKind _initialKind() {
    final w = widget.existing;
    if (w == null) return kBuiltinWishKinds.first;
    return resolveWishKind(
      categoryId: w.categoryId,
      symbol: w.symbol,
      custom: widget.customKinds,
    );
  }

  List<WishKind> get _kinds => [...kBuiltinWishKinds, ..._custom];

  // ── Вещь ──
  /// Ссылка на товар: по ней сервер сам достаёт название, картинку и цену.
  late final TextEditingController _url =
      TextEditingController(text: widget.existing?.url ?? widget.initialUrl);
  final TextEditingController _price = TextEditingController();
  bool _fetching = false;
  bool _uploading = false;
  bool _isItem = false;
  late String _image = widget.existing?.image ?? '';
  late String _shop = widget.existing?.shop ?? '';
  late String _currency = widget.existing?.currency ?? '';

  /// Тянет карточку товара со страницы магазина. Что не нашлось — человек
  /// вписывает сам: у половины магазинов og-тегов нет вовсе, и пустая форма
  /// после «загрузки» выглядела бы поломкой.
  Future<void> _fetchPreview() async {
    final url = _url.text.trim();
    if (url.isEmpty || _fetching) return;
    setState(() => _fetching = true);
    final data = await PbDataService().linkPreview(url);
    if (!mounted) return;
    setState(() {
      _fetching = false;
      if (data == null) return;
      _isItem = true;
      final title = (data['title'] ?? '').toString();
      if (title.isNotEmpty && _title.text.trim().isEmpty) _title.text = title;
      _image = (data['image'] ?? '').toString();
      _shop = (data['shop'] ?? '').toString();
      final price = (data['price'] as num?)?.toInt() ?? 0;
      if (price > 0) _price.text = price.toString();
      _currency = (data['currency'] ?? '').toString();
    });
    if (data == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('Магазин не дал карточку — впишите руками',
              "The shop didn't share a card — fill it in")),
        ),
      );
    }
  }

  /// Своё фото вещи: снимок с полки магазина или скриншот из приложения.
  ///
  /// Ссылку на картинку дают не все магазины — половина закрыта антиботом, и
  /// без своей фотографии список превращается в одинаковые строки. Файл уходит
  /// в хранилище и возвращается ссылкой `pb://`, её же понимает карточка.
  Future<void> _pickPhoto(ImageSource source) async {
    if (_uploading) return;
    final x = await safePick(
      () => ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      ),
    );
    if (x == null || !mounted) return;
    setState(() => _uploading = true);
    final url = await PbMediaService.instance.uploadFile(
      x.path,
      uid: widget.uid,
      groupId: widget.groupId,
      kind: 'wish',
    );
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (url != null && url.isNotEmpty) {
        _image = url;
        _isItem = true;
      }
    });
    if (url == null && mounted) {
      // Очереди для файлов нет намеренно: желание сохранится и без картинки,
      // а фото добавится правкой, когда сеть вернётся.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('Фото не загрузилось — попробуйте позже',
              "The photo didn't upload — try later")),
        ),
      );
    }
  }

  Future<void> _choosePhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: _cs.primary),
              title: Text(_tr('Из галереи', 'From gallery'),
                  style: AppFonts.onest(size: 16, color: _cs.onSurface)),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_rounded, color: _cs.primary),
              title: Text(_tr('Снять', 'Take a photo'),
                  style: AppFonts.onest(size: 16, color: _cs.onSurface)),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source != null) await _pickPhoto(source);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _url.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _addCategory() async {
    // Стена Togetherly+: своих категорий нет у того, кто не покупал, а на iOS
    // Плюса не существует вовсе — там кнопки просто нет (см. PlusAccess.gate).
    if (widget.plusGate == PlusGate.locked) {
      widget.onOfferPlus?.call();
      return;
    }
    final created = await widget.onCreateCategory?.call();
    if (created == null || !mounted) return;
    setState(() {
      _custom = [..._custom, created];
      _kind = created;
    });
  }

  void _submit() {
    final text = _title.text.trim();
    if (text.isEmpty) return;
    final price = int.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    Navigator.of(context).pop(
      WishDraft(
        title: text,
        note: _note.text.trim(),
        kind: _kind,
        isItem: _isItem || _url.text.trim().isNotEmpty || price > 0,
        price: price,
        currency: _currency,
        url: _url.text.trim(),
        image: _image,
        shop: _shop,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final showPlusChip = widget.plusGate != PlusGate.hidden;

    return SheetScaffold(
      title: editing
          ? _tr('Правим желание', 'Edit wish')
          : _tr('Новое желание', 'New wish'),
      // SheetScaffold отступает только у заголовка, содержимое отдаёт во всю
      // ширину — без этой рамки поля и кнопки упирались в края экрана.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                // Лента чипов уходит за край сама: обрезать её рамкой значит
                // потерять подсказку, что список продолжается.
                clipBehavior: Clip.none,
                children: [
                  for (final k in _kinds) ...[
                    _CategoryChip(
                      kind: k,
                      label: k.title(widget.ru),
                      selected: k.id == _kind.id,
                      scheme: _cs,
                      onTap: () => setState(() => _kind = k),
                      onLongPress:
                          k.custom ? () => widget.onEditCategory?.call(k) : null,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (showPlusChip)
                    _AddChip(
                      scheme: _cs,
                      locked: widget.plusGate == PlusGate.locked,
                      label: _tr('Своя', 'Custom'),
                      onTap: _addCategory,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _field(
              controller: _title,
              label: _tr('Что хотим', 'What we want'),
              hint: _tr('«Дюна: Часть третья»', '"Dune: Part Three"'),
              maxLength: 120,
              autofocus: !editing,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            _field(
              controller: _note,
              label: _tr('Заметка', 'Note'),
              hint: _tr('не обязательно', 'optional'),
              maxLength: 200,
            ),
            const SizedBox(height: 10),
            _linkField(),
            const SizedBox(height: 10),
            _photoButton(),
            if (_isItem) ...[
              const SizedBox(height: 10),
              _itemPreview(),
            ],
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
                  child: Text(
                    editing ? _tr('Сохранить', 'Save') : _tr('Добавить', 'Add'),
                  ),
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

  /// Своя фотография вещи. Стоит рядом со ссылкой: половина магазинов
  /// закрыта антиботом и картинку не отдаёт, и это единственный способ
  /// оставить в списке не строку, а вещь.
  Widget _photoButton() {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _uploading ? null : _choosePhotoSource,
        icon: _uploading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: _cs.primary),
              )
            : Icon(_image.isEmpty
                ? Icons.add_a_photo_outlined
                : Icons.photo_rounded),
        label: Text(
          _image.isEmpty
              ? _tr('Своё фото', 'Own photo')
              : _tr('Заменить фото', 'Replace photo'),
          style: AppFonts.onest(size: 14.5, weight: 600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _cs.onSurfaceVariant,
          side: BorderSide(color: _cs.outlineVariant),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  /// Поле ссылки с кнопкой «подтянуть карточку».
  Widget _linkField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _fetchPreview(),
            style: AppFonts.onest(size: 15, color: _cs.onSurface),
            cursorColor: _cs.primary,
            decoration: InputDecoration(
              labelText: _tr('Ссылка на товар', 'Product link'),
              hintText: _tr('не обязательно', 'optional'),
              filled: true,
              fillColor: _cs.surfaceContainerHighest,
              labelStyle:
                  AppFonts.onest(size: 12, weight: 600, color: _cs.primary),
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
                borderSide: BorderSide(color: _cs.primary, width: 1.4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 52,
          width: 52,
          child: FilledButton(
            onPressed: _fetching ? null : _fetchPreview,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: const CircleBorder(),
              backgroundColor: _cs.secondaryContainer,
              foregroundColor: _cs.onSecondaryContainer,
            ),
            child: _fetching
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: _cs.onSecondaryContainer,
                    ),
                  )
                : const Icon(Icons.download_rounded, size: 20),
          ),
        ),
      ],
    );
  }

  /// Что удалось достать: картинка, магазин и цена (её можно поправить).
  Widget _itemPreview() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _image.isEmpty
                ? Container(
                    width: 56,
                    height: 56,
                    color: _cs.surfaceContainerHighest,
                    child: Icon(Icons.image_outlined,
                        color: _cs.onSurfaceVariant, size: 22),
                  )
                : StorageImage(
                    imageUrl: _image,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Container(
                      width: 56,
                      height: 56,
                      color: _cs.surfaceContainerHighest,
                      child: Icon(Icons.link_off_rounded,
                          color: _cs.onSurfaceVariant, size: 20),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_shop.isNotEmpty)
                  Text(
                    _shop,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.onest(
                        size: 12, weight: 600, color: _cs.onSurfaceVariant),
                  ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    style: AppFonts.onest(size: 15, color: _cs.onSurface),
                    cursorColor: _cs.primary,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _tr('Цена', 'Price'),
                      suffixText: _currency.isEmpty ? null : _currency,
                      filled: true,
                      fillColor: _cs.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLength = 120,
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.kind,
    required this.label,
    required this.selected,
    required this.scheme,
    required this.onTap,
    this.onLongPress,
  });

  final WishKind kind;
  final String label;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Material(
      // Ни у выбранного, ни у остальных обводки нет: разницу держит заливка.
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SymbolIcon(kind.symbol, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: AppFonts.onest(size: 13.5, weight: 600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Чип «Своя» — заводит категорию пары. У некупившего вместо плюса замок и
/// переход на экран Togetherly+.
class _AddChip extends StatelessWidget {
  const _AddChip({
    required this.scheme,
    required this.locked,
    required this.label,
    required this.onTap,
  });

  final ColorScheme scheme;
  final bool locked;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                locked ? Icons.lock_rounded : Icons.add_rounded,
                size: 18,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppFonts.onest(
                    size: 13.5, weight: 700, color: scheme.onPrimaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
