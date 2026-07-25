import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/canvas_meta.dart';
import '../models/pair_data.dart';
import '../models/user_data.dart';
import '../services/canvas_storage_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/m3_loading.dart';
import 'draw_screen.dart';
import 'pixel_size_screen.dart';

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
    if (mounted) {
      setState(() {
        _canvases = list;
        _loading = false;
      });
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _openCanvas(CanvasMeta meta) async {
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
          sheetRatio: meta.effectiveRatio,
        ),
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/draw'),
      ),
    );
    // Reload after returning so thumbnails are refreshed.
    _load();
  }

  Future<void> _createNewCanvas() async {
    final s = LocaleService.current;
    // Prompt for a name.
    final name = await _showNameDialog(
      title: s.newCanvas,
      initial: '${s.untitledCanvas} ${_canvases.length + 1}',
    );
    if (name == null || !mounted) return;

    // Обычный холст или пиксель-арт; сетка выбирается на своём экране.
    final grid = await _askPixelGrid();
    if (!mounted) return;

    final meta = await _storage.createCanvas(
      _uid,
      name: name.trim().isEmpty
          ? '${s.untitledCanvas} ${_canvases.length + 1}'
          : name.trim(),
      groupId: _groupId,
      pixelW: grid?.$1,
      pixelH: grid?.$2,
    );

    if (!mounted) return;
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
          sheetRatio: meta.effectiveRatio,
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

  Future<void> _deleteCanvas(CanvasMeta meta) async {
    final s = LocaleService.current;
    final confirmed = await AppDialog.confirm(
      context,
      title: s.deleteCanvas,
      message: s.deleteCanvasConfirm,
      confirmLabel: s.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _storage.deleteCanvas(_uid, meta.id, groupId: _groupId);
    _load();
  }

  /// Спрашиваем режим: обычный холст или пиксель-арт. Сетка выбирается на
  /// отдельном экране [PixelSizeScreen] — так же, как в макете.
  Future<(int, int)?> _askPixelGrid() async {
    final s = LocaleService.current;
    final t = widget.theme;

    final wantPixel = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: t.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                s.newCanvas,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              _modeTile(
                t,
                icon: Icons.brush_rounded,
                title: s.plainCanvas,
                subtitle: s.plainCanvasSubtitle,
                onTap: () => Navigator.pop(ctx, false),
              ),
              const SizedBox(height: 10),
              _modeTile(
                t,
                icon: Icons.grid_on_rounded,
                title: s.pixelCanvasCreate,
                subtitle: s.pixelCanvasSubtitle,
                onTap: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );

    if (wantPixel != true || !mounted) return null;

    return Navigator.push<(int, int)>(
      context,
      MaterialPageRoute(
        builder: (_) => PixelSizeScreen(theme: t),
        settings: const RouteSettings(name: '/pixel_size'),
      ),
    );
  }

  Widget _modeTile(
    AppTheme t, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: t.surfaceMuted,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: t.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: t.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _showNameDialog({
    required String title,
    required String initial,
  }) async {
    final s = LocaleService.current;
    final controller = TextEditingController(text: initial);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: initial.length,
    );

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: s.canvasNameLabel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(s.done),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext ctx, CanvasMeta meta) {
    final s = LocaleService.current;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: widget.theme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: widget.theme.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: Text(s.renameCanvas),
              onTap: () {
                Navigator.pop(ctx);
                _renameCanvas(meta);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Colors.red.shade400,
              ),
              title: Text(
                s.deleteCanvas,
                style: TextStyle(color: Colors.red.shade400),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteCanvas(meta);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

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
              _roundBack(t),
              const SizedBox(height: 6),
              Text(
                s.canvasesTitle,
                style: TextStyle(
                  fontFamily: 'Unbounded',
                  fontSize: 62,
                  height: 0.86,
                  letterSpacing: -3,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              if (!_loading && _canvases.isNotEmpty)
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
                    ? Center(child: M3LoadingDots(color: t.primaryLight))
                    : _canvases.isEmpty
                        ? _buildEmpty(s, t)
                        : _buildGrid(s, t),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
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
    return GestureDetector(
      onTap: () => _openCanvas(meta),
      onLongPress: () => _showContextMenu(ctx, meta),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
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
    );
  }

  Widget _buildThumbnail(CanvasMeta meta, AppTheme t) {
    if (meta.previewBase64 != null) {
      try {
        final bytes = base64Decode(meta.previewBase64!);
        return Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.cover,
          width: double.infinity,
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
