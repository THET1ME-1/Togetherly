import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/canvas_meta.dart';
import '../models/pair_data.dart';
import '../models/user_data.dart';
import '../services/canvas_storage_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/m3_loading.dart';
import 'canvas_create_flow.dart';
import 'coloring_catalogue_screen.dart';
import 'draw_screen.dart';

/// Gallery of saved drawings.  Shows a 2-column card grid with thumbnail
/// preview, canvas name and date.  A prominent "New Canvas" card is always
/// pinned at the top-left.
class DrawGalleryScreen extends StatefulWidget {
  final UserData userData;
  final PairData pairData;
  final AppTheme theme;

  const DrawGalleryScreen({
    super.key,
    required this.userData,
    required this.pairData,
    required this.theme,
  });

  @override
  State<DrawGalleryScreen> createState() => _DrawGalleryScreenState();
}

class _DrawGalleryScreenState extends State<DrawGalleryScreen> {
  final CanvasStorageService _storage = CanvasStorageService.instance;
  List<CanvasMeta> _canvases = [];
  bool _loading = true;

  /// Отпечаток последнего показанного списка — см. [_load].
  String _fingerprint = '';

  /// Декодированные миниатюры по id холста.
  ///
  /// `Image.memory` сравнивает провайдеры по самому массиву байт, а не по его
  /// содержимому. Каждый билд декодировал base64 заново, получал новый
  /// `Uint8List`, и Flutter считал это другой картинкой: сбрасывал кадр,
  /// декодировал png и рисовал заново — отсюда и моргание всей сетки. Держим
  /// готовый провайдер и меняем его, только когда превью действительно новое.
  final Map<String, ({String source, MemoryImage image})> _thumbs = {};

  /// Отмеченные холсты. Пустое множество — обычный просмотр. Долгое нажатие
  /// включает выбор, дальше карточки отмечаются касанием.
  final Set<String> _selected = <String>{};
  bool get _selectionMode => _selected.isNotEmpty;

  String get _uid => widget.userData.uid;
  String get _groupId => widget.pairData.pairId;
  bool get _isPaired => _groupId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();

    // Start real-time sync for paired users
    if (_isPaired) {
      _storage.onRemoteChange = _onRemoteChange;
      _storage.startListening(uid: _uid, groupId: _groupId);
      // Push existing local canvases to Firebase (idempotent)
      _storage.pushAllToFirebase(_uid, _groupId);
    }
  }

  @override
  void dispose() {
    _storage.onRemoteChange = null;
    _storage.stopListening();
    super.dispose();
  }

  void _onRemoteChange() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final list = await _storage.getCanvases(_uid, groupId: _groupId);
    if (!mounted) return;
    // Перерисовываем, только если список правда изменился. Realtime-канал пары
    // несёт изменения всех холстов, и на каждое событие экран пересобирал сетку
    // целиком — миниатюры при этом моргали белым.
    final next = list.map((c) => c.fingerprint).join(';');
    if (next == _fingerprint && !_loading) return;
    _fingerprint = next;
    setState(() {
      _canvases = list;
      _loading = false;
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  /// Создание холста идёт общим путём — тем же, что и с главной
  /// ([CanvasCreateFlow]). Раньше выбор вида (включая раскраску) жил только
  /// здесь, и до него доходили не все.
  Future<void> _createNewCanvas() async {
    final created = await CanvasCreateFlow.start(
      context,
      userData: widget.userData,
      pairData: widget.pairData,
      theme: widget.theme,
      storage: _storage,
    );
    if (created && mounted) _load();
  }


  Future<void> _openCanvas(CanvasMeta meta, {ColoringChoice? coloring}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrawScreen(
          userData: widget.userData,
          pairData: widget.pairData,
          theme: widget.theme,
          canvasId: meta.id,
          canvasName: meta.name,
          pixelW: meta.pixelW,
          pixelH: meta.pixelH,
          sheetRatio: coloring != null ? 1.0 : meta.effectiveRatio,
          coloringId: coloring?.picture.id,
          coloringMode: coloring?.mode,
        ),
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/draw'),
      ),
    );
    _load();
  }

  Future<void> _renameCanvas(CanvasMeta meta) async {
    final s = LocaleService.current;
    final name = await _showNameDialog(
      title: s.renameCanvas,
      initial: meta.name,
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    await _storage.renameCanvas(_uid, meta.id, name.trim(), groupId: _groupId);
    _load();
  }

  void _toggleSelected(CanvasMeta meta) {
    setState(() {
      if (!_selected.remove(meta.id)) _selected.add(meta.id);
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _canvases.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_canvases.map((c) => c.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    final s = LocaleService.current;
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final confirmed = await AppDialog.confirm(
      context,
      title: s.deleteCanvasesTitle(ids.length),
      message: s.deleteCanvasesConfirm(ids.length),
      confirmLabel: s.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    for (final id in ids) {
      await _storage.deleteCanvas(_uid, id, groupId: _groupId);
    }
    if (!mounted) return;
    setState(_selected.clear);
    _load();
  }


  /// Имя холста спрашиваем нижним листом: диалог по центру не дотянуться
  /// большим пальцем, а на кнопочной навигации он ещё и лип к панели.
  Future<String?> _showNameDialog({
    required String title,
    required String initial,
  }) =>
      AppDialog.prompt(
        context,
        title: title,
        label: LocaleService.current.canvasNameLabel,
        initial: initial,
      );

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final t = widget.theme;

    // Экран по макету: имя раздела во весь верх, под ним счёт рисунков,
    // дальше сетка карточек, внизу пилюля нового холста. Без AppBar — назад
    // уводит круглая кнопка, чтобы заголовок начинался прямо с края.
    return Scaffold(
      backgroundColor: t.bgGradient.first,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectionMode) _selectionBar(s, t) else _roundBack(t),
              const SizedBox(height: 6),
              if (!_selectionMode)
                Text(
                  s.canvasesTitle,
                  style: AppFonts.unbounded(
                    size: 62,
                    weight: 800,
                    height: 0.86,
                    letterSpacing: -3,
                    color: t.textPrimary,
                  ),
                ),
              const SizedBox(height: 10),
              if (!_selectionMode && !_loading && _canvases.isNotEmpty)
                Text(
                  s.canvasesSubtitle(
                    _canvases.length,
                    _formatDate(_canvases.first.updatedAt),
                  ),
                  style: TextStyle(fontSize: 13.5, color: t.textSecondary),
                ),
              const SizedBox(height: 16),
              Expanded(
                child: _loading
                    ? Center(child: M3Loading(color: t.primaryLight))
                    : _canvases.isEmpty
                        ? _buildEmpty(s, t)
                        : _buildGrid(s, t),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _selectionMode
                    ? FilledButton.icon(
                        onPressed: _deleteSelected,
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        label: Text(
                          s.delete,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: t.isDark
                              ? const Color(0xFF93000A)
                              : const Color(0xFFFFDAD6),
                          foregroundColor: t.isDark
                              ? const Color(0xFFFFDAD6)
                              : const Color(0xFF410002),
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: const StadiumBorder(),
                        ),
                      )
                    : FilledButton(
                  onPressed: _createNewCanvas,
                  style: FilledButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: _onPrimary(t),
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    s.newCanvas,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Контрастный цвет поверх акцента: у светлых акцентов белый текст тонет.
  Color _onPrimary(AppTheme t) =>
      t.primary.computeLuminance() > 0.55 ? const Color(0xFF16161A) : Colors.white;

  /// Шапка режима выбора: выход, счётчик, переименование одного и «Все».
  Widget _selectionBar(AppStrings s, AppTheme t) {
    final one = _selected.length == 1;
    return Row(
      children: [
        Material(
          color: t.cardSurface,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(_selected.clear),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(Icons.close_rounded, size: 20, color: t.textPrimary),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            s.selectedCount(_selected.length),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
        ),
        if (one)
          IconButton(
            onPressed: () {
              final meta =
                  _canvases.firstWhere((c) => c.id == _selected.first);
              setState(_selected.clear);
              _renameCanvas(meta);
            },
            icon: Icon(Icons.drive_file_rename_outline_rounded,
                color: t.textPrimary),
            tooltip: s.renameCanvas,
          ),
        TextButton(
          onPressed: _selectAll,
          style: TextButton.styleFrom(
            shape: const StadiumBorder(),
            foregroundColor: t.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: Text(s.selectAll,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _roundBack(AppTheme t) => Material(
        color: t.cardSurface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pop(context),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(Icons.arrow_back_rounded,
                size: 20, color: t.textPrimary),
          ),
        ),
      );

  Widget _buildEmpty(AppStrings s, AppTheme t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: t.primaryLight,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(Icons.brush_rounded, size: 32, color: t.primary),
          ),
          const SizedBox(height: 18),
          Text(
            s.noDrawingsYet,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(AppStrings s, AppTheme t) {
    return GridView.builder(
      // Запас прогрева: без него ряд за краем экрана начинал готовиться
      // ровно тогда, когда его уже листают.
      cacheExtent: 600,
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.88,
      ),
      itemCount: _canvases.length,
      itemBuilder: (ctx, i) => _buildCard(ctx, _canvases[i], t),
    );
  }

  Widget _buildCard(BuildContext ctx, CanvasMeta meta, AppTheme t) {
    // Карточка из макета: превью на всю плитку, имя и дата поверх него в
    // нижнем углу. Без белой полосы снизу и без теней.
    final picked = _selected.contains(meta.id);
    return GestureDetector(
      // В режиме выбора касание отмечает холст, а не открывает его.
      onTap: () => _selectionMode ? _toggleSelected(meta) : _openCanvas(meta),
      onLongPress: () => _toggleSelected(meta),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: picked ? t.primary : Colors.transparent,
            width: 3,
          ),
        ),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildThumbnail(meta, t),
            // Затемнение снизу, чтобы подпись читалась на любом рисунке.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 88,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.62),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    meta.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(meta.updatedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            // Отметка выбора
            if (_selectionMode)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: picked
                        ? t.primary
                        : Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: picked ? t.primary : Colors.white70,
                      width: 2,
                    ),
                  ),
                  child: picked
                      ? Icon(Icons.check_rounded,
                          size: 16, color: _onPrimary(t))
                      : null,
                ),
              ),
            // Пиксельный холст помечаем: сетку потом не поменять, полезно
            // видеть заранее.
            if (meta.isPixel)
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${meta.pixelW}×${meta.pixelH}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(CanvasMeta meta, AppTheme t) {
    final preview = meta.previewBase64;
    if (preview != null) {
      final cached = _thumbs[meta.id];
      if (cached != null && cached.source == preview) {
        return Image(
          image: cached.image,
          fit: BoxFit.cover,
          width: double.infinity,
          gaplessPlayback: true,
        );
      }
      try {
        final image = MemoryImage(Uint8List.fromList(base64Decode(preview)));
        _thumbs[meta.id] = (source: preview, image: image);
        return Image(
          image: image,
          fit: BoxFit.cover,
          width: double.infinity,
          // Пока новое превью декодируется, держим прошлый кадр — иначе на
          // месте рисунка на мгновение появляется пустая карточка.
          gaplessPlayback: true,
        );
      } catch (_) {}
    }
    // Placeholder when no preview exists yet.
    return Container(
      width: double.infinity,
      color: t.surfaceMuted,
      child: Center(
        child: Icon(
          Icons.brush_rounded,
          size: 36,
          color: t.primary.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      // Today – show time
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (diff.inDays == 1) return LocaleService.current.yesterday;
    if (diff.inDays < 7) {
      final weekdays = LocaleService.current.shortWeekdays;
      return weekdays[dt.weekday - 1];
    }
    final months = LocaleService.current.shortMonths;
    return '${dt.day} ${months[dt.month - 1]}';
  }
}
