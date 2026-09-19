import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/memory_media.dart';
import '../../services/saved_media_ledger.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import '../storage_image.dart';

class FramePickResult {
  final List<MediaFile> files;

  /// `true` — человек нажал «Отправить», а не «Сохранить».
  final bool share;

  const FramePickResult(this.files, {this.share = false});
}

/// Лист «Выбрать кадры» поверх воспоминания.
Future<FramePickResult?> showFramePicker(
  BuildContext context, {
  required List<MediaFile> files,
  required ColorScheme scheme,
  String? title,
}) async {
  final ledger = SavedMediaLedger.instance;
  await ledger.load();
  if (!context.mounted) return null;
  final saved = {for (final f in files) if (ledger.containsFile(f)) f.key};
  return showAppSheet<FramePickResult>(
    context,
    expand: true,
    background: scheme.surfaceContainerLow,
    builder: (ctx) => Theme(
      data: ProfileTheme.data(scheme),
      child: SheetScaffold(
        title: title ?? trKey('pickTitle'),
        child: FramePicker(
          files: files,
          savedKeys: saved,
          onDone: (r) => Navigator.of(ctx).pop(r),
        ),
      ),
    ),
  );
}

/// Сетка кадров воспоминания с выбором.
///
/// Касание отмечает кадр. Удержание и протягивание отмечают подряд в любую
/// сторону — как в «Google Фото»; протянул лишнего и вернул палец — лишнее
/// снимается. Горизонтальный проход по ряду отмечает ряд без удержания.
/// Протягивание у верхнего и нижнего края прокручивает сетку.
///
/// Уже сохранённые на этом телефоне кадры помечены, но не заперты: человек
/// мог удалить кадр из галереи сам, и вернуть его должно быть можно.
class FramePicker extends StatefulWidget {
  const FramePicker({
    super.key,
    required this.files,
    required this.savedKeys,
    required this.onDone,
    this.columns = 4,
  });

  static const Key counterKey = ValueKey('frame-picker-counter');
  static const Key allKey = ValueKey('frame-picker-all');
  static const Key saveKey = ValueKey('frame-picker-save');
  static const Key shareKey = ValueKey('frame-picker-share');

  final List<MediaFile> files;
  final Set<String> savedKeys;
  final ValueChanged<FramePickResult> onDone;
  final int columns;

  @override
  State<FramePicker> createState() => _FramePickerState();
}

class _FramePickerState extends State<FramePicker> {
  static const double _gap = 4;
  static const double _edge = 56;

  final ScrollController _scroll = ScrollController();
  late List<bool> _sel = List<bool>.filled(widget.files.length, false);

  // Протягивание: откуда начали, отмечаем или снимаем, какой был выбор до.
  int? _dragFrom;
  bool _dragValue = true;
  List<bool>? _dragBase;
  double _width = 0;
  double _viewport = 0;

  int get _count => _sel.where((s) => s).length;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double get _tile => (_width - _gap * (widget.columns - 1)) / widget.columns;

  int? _indexAt(Offset local) {
    if (_width <= 0) return null;
    final y = local.dy + (_scroll.hasClients ? _scroll.offset : 0);
    final row = (y / (_tile + _gap)).floor();
    final col = (local.dx / (_tile + _gap)).floor().clamp(0, widget.columns - 1);
    if (row < 0) return null;
    final i = row * widget.columns + col;
    return i < widget.files.length ? i : null;
  }

  void _toggle(int i) => setState(() => _sel[i] = !_sel[i]);

  void _startRange(Offset local) {
    final i = _indexAt(local);
    if (i == null) return;
    _dragFrom = i;
    _dragValue = !_sel[i];
    _dragBase = List<bool>.of(_sel);
    _extendRange(local);
  }

  void _extendRange(Offset local) {
    final from = _dragFrom, base = _dragBase;
    if (from == null || base == null) return;
    _autoScroll(local);
    final to = _indexAt(local);
    if (to == null) return;
    final lo = math.min(from, to), hi = math.max(from, to);
    setState(() {
      _sel = List<bool>.of(base);
      for (var i = lo; i <= hi; i++) {
        _sel[i] = _dragValue;
      }
    });
  }

  void _endRange() {
    _dragFrom = null;
    _dragBase = null;
  }

  void _autoScroll(Offset local) {
    if (!_scroll.hasClients || _viewport <= 0) return;
    double delta = 0;
    if (local.dy < _edge) delta = -(_edge - local.dy) * 0.6;
    if (local.dy > _viewport - _edge) delta = (local.dy - (_viewport - _edge)) * 0.6;
    if (delta == 0) return;
    final pos = _scroll.position;
    _scroll.jumpTo((pos.pixels + delta).clamp(0, pos.maxScrollExtent));
  }

  void _toggleAll() {
    final all = _count < widget.files.length;
    setState(() => _sel = List<bool>.filled(widget.files.length, all));
  }

  List<MediaFile> get _picked =>
      [for (var i = 0; i < widget.files.length; i++) if (_sel[i]) widget.files[i]];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final summary = summarizeMedia(_picked);
    final allOn = _count == widget.files.length && _count > 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _count == 0
                      ? trKey('pickSelected').replaceAll('{n}', '0')
                      : '${trKey('pickSelected').replaceAll('{n}', '$_count')}'
                          ' · ${trKey('saveApproxMb').replaceAll('{n}', '${summary.megabytes}')}',
                  key: FramePicker.counterKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                key: FramePicker.allKey,
                onPressed: _toggleAll,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(allOn ? trKey('pickNone') : trKey('pickAll')),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swipe_rounded, size: 16, color: cs.onTertiaryContainer),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      trKey('pickHint'),
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(builder: (context, box) {
              _width = box.maxWidth;
              _viewport = box.maxHeight;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (d) => _startRange(d.localPosition),
                onLongPressMoveUpdate: (d) => _extendRange(d.localPosition),
                onLongPressEnd: (_) => _endRange(),
                onHorizontalDragStart: (d) => _startRange(d.localPosition),
                onHorizontalDragUpdate: (d) => _extendRange(d.localPosition),
                onHorizontalDragEnd: (_) => _endRange(),
                onHorizontalDragCancel: _endRange,
                child: GridView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.zero,
                  cacheExtent: 600,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: widget.columns,
                    mainAxisSpacing: _gap,
                    crossAxisSpacing: _gap,
                  ),
                  itemCount: widget.files.length,
                  itemBuilder: (_, i) => _FrameTile(
                    key: ValueKey('frame-$i'),
                    file: widget.files[i],
                    selected: _sel[i],
                    saved: widget.savedKeys.contains(widget.files[i].key),
                    onTap: () => _toggle(i),
                  ),
                ),
              );
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                key: FramePicker.shareKey,
                onPressed: _count == 0
                    ? null
                    : () => widget.onDone(FramePickResult(_picked, share: true)),
                icon: const Icon(Icons.ios_share_rounded, size: 20),
                label: Text(trKey('pickShare')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 54),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: FramePicker.saveKey,
                  onPressed: _count == 0
                      ? null
                      : () => widget.onDone(FramePickResult(_picked)),
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _count == 0
                          ? trKey('viewerSave')
                          : trKey('pickSave').replaceAll('{n}', '$_count'),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    super.key,
    required this.file,
    required this.selected,
    required this.saved,
    required this.onTap,
  });

  final MediaFile file;
  final bool selected;
  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final thumb = file.thumb ?? (file.kind == SaveKind.photo ? file.ref : null);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumb != null)
              StorageImage(
                imageUrl: thumb,
                fit: BoxFit.cover,
                memCacheWidth: 300,
                placeholder: (_, _) => ColoredBox(color: cs.surfaceContainerHigh),
                errorWidget: (_, _, _) => ColoredBox(
                  color: cs.surfaceContainerHigh,
                  child: Icon(Icons.image_rounded, color: cs.onSurfaceVariant),
                ),
              )
            else
              ColoredBox(
                color: cs.surfaceContainerHigh,
                child: Icon(
                  file.kind == SaveKind.audio
                      ? Icons.music_note_rounded
                      : Icons.movie_rounded,
                  color: cs.onSurfaceVariant,
                ),
              ),
            if (selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.16),
                  border: Border.all(color: cs.primary, width: 3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            if (file.kind == SaveKind.video)
              const Positioned(
                left: 5,
                bottom: 4,
                child: Icon(Icons.play_circle_rounded, color: Colors.white, size: 20),
              ),
            if (saved)
              Positioned(
                key: ValueKey('frame-saved-${file.index}'),
                right: 5,
                bottom: 5,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: cs.inverseSurface.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.download_done_rounded,
                      size: 15, color: cs.onInverseSurface),
                ),
              ),
            Positioned(
              right: 5,
              top: 5,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: selected ? cs.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: selected ? null : Border.all(color: Colors.white, width: 2),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, size: 17, color: cs.onPrimary)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
