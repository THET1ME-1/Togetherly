import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../dict_strings.dart';
import '../../models/doing.dart';
import '../../services/catalog_service.dart';
import '../../services/doing_service.dart';
import '../../services/offline/media_view_cache.dart';
import '../app_sheet.dart';

/// Готовые цвета стены. Те же, что в макете виджета.
const List<Color> kRoomColors = [
  Color(0xFFFFFFFF),
  Color(0xFFCFE3FB),
  Color(0xFF2F5FB3),
  Color(0xFFCDEEDD),
  Color(0xFFE2D6FA),
  Color(0xFFFDEEB5),
  Color(0xFF26262B),
];

/// Лист «Чем ты занят?»: восемнадцать занятий, своё слово и цвет своей
/// комнатки. Закрывается сам, когда занятие сохранилось.
Future<void> showDoingSheet(
  BuildContext context, {
  required String groupId,
  required ColorScheme scheme,
  Doing current = const Doing.none(),
  Color? wall,
}) {
  // Общая обёртка листов: не залезает под вырез и строку состояния.
  return showAppSheet<void>(
    context,
    background: scheme.surfaceContainerLow,
    builder: (_) => DoingSheet(groupId: groupId, scheme: scheme, current: current, wall: wall),
  );
}

class DoingSheet extends StatefulWidget {
  const DoingSheet({
    super.key,
    required this.groupId,
    required this.scheme,
    this.current = const Doing.none(),
    this.wall,
    this.saveDoing,
    this.saveColor,
  });

  final String groupId;
  final ColorScheme scheme;
  final Doing current;
  final Color? wall;

  /// Запись на сервер; в тесте подменяется, в приложении — [DoingService].
  final Future<bool> Function(Doing doing)? saveDoing;
  final Future<bool> Function(Color? wall)? saveColor;

  @override
  State<DoingSheet> createState() => _DoingSheetState();
}

class _DoingSheetState extends State<DoingSheet> {
  late final TextEditingController _own =
      TextEditingController(text: widget.current.isOwn ? widget.current.text : '');
  late Color? _wall = widget.wall;
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  Future<void> _pick(Doing doing) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    final save = widget.saveDoing ?? (d) => DoingService.instance.saveDoing(widget.groupId, d);
    final saved = await save(doing);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }

  Future<void> _paint(Color? wall) async {
    final before = _wall;
    setState(() {
      _wall = wall;
      _failed = false;
    });
    final save = widget.saveColor ?? (c) => DoingService.instance.saveRoomColor(widget.groupId, c);
    final saved = await save(wall);
    if (!mounted || saved) return;
    setState(() {
      _wall = before;
      _failed = true;
    });
  }

  Future<void> _anyColor() async {
    var chosen = _wall ?? kRoomColors[1];
    final picked = await showDialog<Color>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(trKey('doing.roomAny')),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: chosen,
            onColorChanged: (color) => chosen = color,
            enableAlpha: false,
            labelTypes: const [],
            pickerAreaBorderRadius: BorderRadius.circular(16),
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(dialog).pop(chosen), child: Text(trKey('doing.done'))),
        ],
      ),
    );
    if (picked != null) await _paint(Color(0xFF000000 | (picked.toARGB32() & 0xFFFFFF)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    final title = TextStyle(fontFamily: 'Unbounded', fontSize: 17, fontWeight: FontWeight.w700, color: cs.onSurface);
    final custom = _wall != null && !kRoomColors.contains(_wall);

    // Низ листа не уходит под полосу жестов и поднимается над клавиатурой.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 14),
            Text(trKey('doing.sheetTitle'), style: title),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.82,
              children: [for (final id in kDoingIds) _tile(cs, id)],
            ),
            const SizedBox(height: 12),
            // Кнопка «готово» стоит внутри поля: отдельной кнопкой она съедала
            // ширину, и подсказка обрезалась.
            TextField(
              key: const Key('doing_own'),
              controller: _own,
              enabled: !_saving,
              maxLength: kDoingTextMax,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _pick(Doing.own(_own.text, DateTime.now())),
              decoration: InputDecoration(
                hintText: trKey('doing.ownHint'),
                counterText: '',
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(4),
                  child: IconButton.filled(
                    key: const Key('doing_own_done'),
                    tooltip: trKey('doing.done'),
                    onPressed: _saving ? null : () => _pick(Doing.own(_own.text, DateTime.now())),
                    icon: const Icon(Icons.check_rounded),
                  ),
                ),
              ),
            ),
            if (_failed) ...[
              const SizedBox(height: 8),
              Text(trKey('doing.failed'), style: TextStyle(fontFamily: 'Onest', fontSize: 13, color: cs.error)),
            ],
            if (!widget.current.isNone)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('doing_clear'),
                  onPressed: _saving ? null : () => _pick(const Doing.none()),
                  child: Text(trKey('doing.clear')),
                ),
              ),
            const SizedBox(height: 14),
            Text(trKey('doing.roomTitle'), style: title.copyWith(fontSize: 15)),
            const SizedBox(height: 2),
            Text(
              trKey('doing.roomHint'),
              style: TextStyle(fontFamily: 'Onest', fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            // Девять кружков по 40 точек встают в один ряд на обычном телефоне.
            Wrap(
              spacing: 0,
              runSpacing: 4,
              children: [
                _swatch(cs, key: 'theme', color: cs.primaryContainer, selected: _wall == null, label: trKey('doing.roomTheme'), icon: Icons.palette_rounded, onTap: () => _paint(null)),
                for (final color in kRoomColors)
                  _swatch(cs, key: roomHex(color), color: color, selected: _wall == color, label: roomHex(color), onTap: () => _paint(color)),
                _swatch(cs, key: 'any', color: custom ? _wall! : cs.surface, selected: custom, label: trKey('doing.roomAny'), icon: custom ? null : Icons.add_rounded, onTap: _anyColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(ColorScheme cs, String id) {
    final selected = widget.current.id == id;
    final still = CatalogService.instance.giftArt('act_$id')?.stillUrl;
    return Material(
      key: Key('doing_tile_$id'),
      color: selected ? cs.primaryContainer : cs.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _saving ? null : () => _pick(Doing.of(id, DateTime.now())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
          child: Column(
            children: [
              Expanded(
                child: still == null
                    ? const SizedBox.expand()
                    : CachedNetworkImage(
                        imageUrl: still,
                        cacheManager: OfflineImageCacheManager.instance,
                        fit: BoxFit.contain,
                        fadeInDuration: Duration.zero,
                      ),
              ),
              Text(
                trKey('doing.$id'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(
    ColorScheme cs, {
    required String key,
    required Color color,
    required bool selected,
    required String label,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final ink = color.computeLuminance() > 0.5 ? const Color(0xFF4B2A31) : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        key: Key('doing_color_$key'),
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? cs.primary : Colors.transparent, width: 2.5),
          ),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: cs.outlineVariant, width: 1.5),
            ),
            child: icon == null ? null : Icon(icon, size: 18, color: ink),
          ),
        ),
      ),
    );
  }
}
