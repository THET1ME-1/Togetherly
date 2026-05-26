import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img_lib;
import 'package:url_launcher/url_launcher.dart';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;
import 'dart:io';

import '../models/mascot.dart';
import '../services/mascot_service.dart';
import '../theme/app_theme.dart';
import '../widgets/active_mascot_widget.dart' show buildMascotAssetImage;
import 'mascot_draw_screen.dart';

// ─── Background removal — top-level so compute() can reach it ────────────────

class _BgArgs {
  final Uint8List bytes;
  final double seedFx;
  final double seedFy;
  final int tolerance;
  const _BgArgs(this.bytes, this.seedFx, this.seedFy, this.tolerance);
}

Uint8List _bgRemoveInIsolate(_BgArgs a) {
  final src = img_lib.decodeImage(a.bytes);
  if (src == null) return a.bytes;

  var image = src.convert(numChannels: 4);
  var w = image.width;
  var h = image.height;

  // Resize to max 1024 px on the long side so BFS stays fast on any device
  if (w > 1024 || h > 1024) {
    final scale = 1024 / (w > h ? w : h);
    image = img_lib.copyResize(
      image,
      width: (w * scale).round(),
      height: (h * scale).round(),
    );
    w = image.width;
    h = image.height;
  }

  final sx = (a.seedFx * (w - 1)).round().clamp(0, w - 1);
  final sy = (a.seedFy * (h - 1)).round().clamp(0, h - 1);

  final seedPx = image.getPixel(sx, sy);
  final bgR = seedPx.r.toInt();
  final bgG = seedPx.g.toInt();
  final bgB = seedPx.b.toInt();
  final thresh = a.tolerance * 3;

  // BFS flood-fill from seed point using a plain List as a queue (O(1) amortised)
  final visited = List<bool>.filled(w * h, false);
  final queue = <int>[];
  int qHead = 0;

  void tryEnqueue(int x, int y) {
    if (x < 0 || x >= w || y < 0 || y >= h) return;
    final idx = y * w + x;
    if (visited[idx]) return;
    visited[idx] = true;
    final px = image.getPixel(x, y);
    if ((px.r.toInt() - bgR).abs() +
            (px.g.toInt() - bgG).abs() +
            (px.b.toInt() - bgB).abs() <=
        thresh) { queue.add(idx); }
  }

  tryEnqueue(sx, sy);

  while (qHead < queue.length) {
    final i = queue[qHead++];
    final x = i % w;
    final y = i ~/ w;
    image.setPixelRgba(x, y, 0, 0, 0, 0);
    tryEnqueue(x - 1, y);
    tryEnqueue(x + 1, y);
    tryEnqueue(x, y - 1);
    tryEnqueue(x, y + 1);
  }

  return Uint8List.fromList(img_lib.encodePng(image));
}

class MascotGalleryScreen extends StatefulWidget {
  final MascotService mascotService;
  final AppTheme theme;
  final String myUid;

  const MascotGalleryScreen({
    super.key,
    required this.mascotService,
    required this.theme,
    required this.myUid,
  });

  @override
  State<MascotGalleryScreen> createState() => _MascotGalleryScreenState();
}

class _MascotGalleryScreenState extends State<MascotGalleryScreen> {
  static final Uri _authorTelegramUri = Uri.parse('https://t.me/oke_y_y');

  AppTheme get _t => widget.theme;
  MascotService get _svc => widget.mascotService;

  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChanged);
  }

  @override
  void dispose() {
    _svc.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  // ── Navigation helpers ───────────────────────────────────────────────────

  Future<void> _openDrawScreen({Mascot? editMascot}) async {
    if (_svc.isGalleryFull && editMascot == null) {
      _showLimitSnack();
      return;
    }

    Uint8List? initialBytes;
    if (editMascot?.imageUrl != null) {
      // Load existing image for re-editing
      try {
        final file = await fetchCachedImageFile(editMascot!.imageUrl!);
        initialBytes = await file.readAsBytes();
      } catch (_) {}
    }

    if (!mounted) return;
    final result = await Navigator.of(context).push<MascotDrawResult>(
      MaterialPageRoute(
        builder: (_) => MascotDrawScreen(
          theme: _t,
          initialName: editMascot?.name,
          initialPngBytes: initialBytes,
          isGalleryFull: _svc.isGalleryFull && editMascot == null,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      if (editMascot != null && !editMascot.isDefault) {
        await _svc.updateMascotImage(
          mascot: editMascot,
          pngBytes: result.pngBytes,
        );
        await _svc.renameMascot(editMascot, result.name);
      } else {
        final saved = await _svc.uploadAndSaveMascot(
          pngBytes: result.pngBytes,
          name: result.name,
          creatorUid: widget.myUid,
        );
        if (saved == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Не удалось сохранить маскота. Проверьте соединение.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _importPng() async {
    if (_svc.isGalleryFull) {
      _showLimitSnack();
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;

    if (!mounted) return;
    // Open background-removal preview; returns processed PNG bytes or null (cancel)
    final processedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => _BgRemovePage(originalBytes: bytes, theme: _t),
        fullscreenDialog: true,
      ),
    );
    if (processedBytes == null || !mounted) return;

    final defaultName = file.name
        .replaceAll(
          RegExp(r'\.(png|jpg|jpeg|webp)$', caseSensitive: false),
          '',
        )
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');

    final name = await _showImportNameDialog(defaultName);
    if (name == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final saved = await _svc.uploadAndSaveMascot(
        pngBytes: processedBytes,
        name: name,
        creatorUid: widget.myUid,
      );
      if (saved == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось загрузить. Проверьте соединение.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<String?> _showImportNameDialog(String defaultName) async {
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Имя маскота'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 30,
              decoration: const InputDecoration(hintText: 'Введите имя'),
              onSubmitted: (_) {
                final n = controller.text.trim();
                if (n.isNotEmpty) Navigator.of(ctx).pop(n);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final n = controller.text.trim();
              if (n.isNotEmpty) Navigator.of(ctx).pop(n);
            },
            child: Text('Добавить', style: TextStyle(color: _t.primary)),
          ),
        ],
      ),
    );
  }

  void _showLimitSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Достигнут лимит. Удалите маскота из галереи.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Mascot actions ───────────────────────────────────────────────────────

  Future<void> _setActive(Mascot mascot) async {
    final alreadyActive = _svc.state.activeMascotId == mascot.id;
    await _svc.setActive(alreadyActive ? null : mascot.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alreadyActive
                ? '${mascot.localizedName} деактивирован'
                : '${mascot.localizedName} теперь активен',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _rename(Mascot mascot) async {
    final controller = TextEditingController(text: mascot.localizedName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(hintText: 'Имя маскота'),
          onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('OK', style: TextStyle(color: _t.primary)),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != mascot.localizedName) {
      await _svc.renameMascot(mascot, newName);
    }
  }

  Future<void> _delete(Mascot mascot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить маскота?'),
        content: Text('«${mascot.localizedName}» будет удалён навсегда.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _svc.deleteMascot(mascot);
    }
  }

  Future<void> _export(Mascot mascot) async {
    try {
      if (mascot.imageUrl != null) {
        final file = await fetchCachedImageFile(mascot.imageUrl!);
        final tmp = await getTemporaryDirectory();
        final dest = File(
          '${tmp.path}/${mascot.name.replaceAll(' ', '_')}.png',
        );
        await file.copy(dest.path);
        await Share.shareXFiles([XFile(dest.path)], text: mascot.localizedName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
      }
    }
  }

  Future<void> _share(Mascot mascot) async {
    await _export(mascot);
  }

  Future<void> _openAuthorLink() async {
    await launchUrl(_authorTelegramUri, mode: LaunchMode.externalApplication);
  }

  void _showActions(Mascot mascot) {
    final isActive = _svc.state.activeMascotId == mascot.id;
    final canExport = mascot.imageUrl != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  _MascotThumbnail(mascot: mascot, size: 48, service: _svc),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mascot.localizedName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (mascot.recordStreak > 0)
                          Text(
                            'Рекорд: ${mascot.recordStreak} дн.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            _ActionTile(
              icon: isActive
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              label: isActive ? 'Деактивировать' : 'Сделать активным',
              color: isActive ? Colors.green : _t.primary,
              onTap: () {
                Navigator.of(ctx).pop();
                _setActive(mascot);
              },
            ),
            if (!mascot.isDefault)
              _ActionTile(
                icon: Icons.edit_outlined,
                label: 'Редактировать',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openDrawScreen(editMascot: mascot);
                },
              ),
            _ActionTile(
              icon: Icons.drive_file_rename_outline,
              label: 'Переименовать',
              onTap: () {
                Navigator.of(ctx).pop();
                _rename(mascot);
              },
            ),
            if (canExport) ...[
              _ActionTile(
                icon: Icons.download_outlined,
                label: 'Экспортировать PNG',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _export(mascot);
                },
              ),
              _ActionTile(
                icon: Icons.share_outlined,
                label: 'Поделиться',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _share(mascot);
                },
              ),
            ],
            if (!mascot.isDefault)
              _ActionTile(
                icon: Icons.delete_outline,
                label: 'Удалить',
                color: Colors.red,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _delete(mascot);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mascots = _svc.mascots;
    final streak = _svc.state.streakDays;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Маскоты группы',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_uploading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Streak banner
          _StreakBanner(streak: streak, theme: _t),
          // Gallery count info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${mascots.length} / ${MascotService.maxMascots} маскотов',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                if (_svc.isGalleryFull)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Лимит',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Grid
          Expanded(
            child: _svc.isLoading
                ? const Center(child: CircularProgressIndicator())
                : mascots.isEmpty
                ? Center(
                    child: Text(
                      'Маскоты не загрузились.\nПроверьте соединение.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.82,
                        ),
                    itemCount: mascots.length,
                    itemBuilder: (ctx, i) {
                      final m = mascots[i];
                      final isActive = _svc.state.activeMascotId == m.id;
                      return _MascotCard(
                        mascot: m,
                        isActive: isActive,
                        theme: _t,
                        service: _svc,
                        onTap: () => _showActions(m),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: InkWell(
                  onTap: _openAuthorLink,
                  borderRadius: BorderRadius.circular(999),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _t.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _t.primary.withOpacity(0.18)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.palette_outlined,
                          size: 15,
                          color: _t.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Художница - Алёна Гребенева',
                          style: TextStyle(
                            fontSize: 9,
                            color: _t.primary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _svc.isGalleryFull
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'import_png',
                  onPressed: _uploading ? null : _importPng,
                  backgroundColor: Colors.white,
                  foregroundColor: _t.primary,
                  tooltip: 'Загрузить фото',
                  child: const Icon(Icons.add_photo_alternate_outlined),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'draw_mascot',
                  onPressed: _uploading ? null : () => _openDrawScreen(),
                  backgroundColor: _t.primary,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add),
                  label: const Text('Нарисовать'),
                ),
              ],
            ),
    );
  }
}

// ── Streak banner ─────────────────────────────────────────────────────────────

class _StreakBanner extends StatelessWidget {
  final int streak;
  final AppTheme theme;

  const _StreakBanner({required this.streak, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(streak > 0 ? '🔥' : '💤', style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                streak > 0
                    ? 'Серия: $streak ${_dayLabel(streak)}'
                    : 'Серия прервана',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              Text(
                streak > 0
                    ? 'Заходите каждый день, чтобы не прерывать серию'
                    : 'Зайдите сегодня, чтобы начать новую серию',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _dayLabel(int n) {
    if (n % 100 >= 11 && n % 100 <= 14) return 'дней';
    switch (n % 10) {
      case 1:
        return 'день';
      case 2:
      case 3:
      case 4:
        return 'дня';
      default:
        return 'дней';
    }
  }
}

// ── Mascot card ───────────────────────────────────────────────────────────────

class _MascotCard extends StatelessWidget {
  final Mascot mascot;
  final bool isActive;
  final AppTheme theme;
  final MascotService service;
  final VoidCallback onTap;

  const _MascotCard({
    required this.mascot,
    required this.isActive,
    required this.theme,
    required this.service,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? theme.primary : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? theme.primary.withAlpha(40)
                  : Colors.black.withAlpha(12),
              blurRadius: isActive ? 10 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _MascotThumbnail(
                      mascot: mascot,
                      size: double.infinity,
                      service: service,
                    ),
                  ),
                  if (isActive)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: theme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    ),
                  if (mascot.isDefault)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.purple.withAlpha(200),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'От нас',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  Text(
                    mascot.localizedName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (mascot.recordStreak > 0)
                    Text(
                      '🏅 ${mascot.recordStreak} дн.',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mascot thumbnail (shared helper) ─────────────────────────────────────────

class _MascotThumbnail extends StatelessWidget {
  final Mascot mascot;
  final double size;
  final MascotService service;

  const _MascotThumbnail({
    required this.mascot,
    required this.size,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    // Resolve asset path considering mood state for default mascots
    final asset = service.resolvedAssetForMood(mascot);

    if (asset != null) {
      return buildMascotAssetImage(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    if (mascot.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: mascot.imageUrl!,
        width: size == double.infinity ? null : size,
        height: size == double.infinity ? null : size,
        fit: BoxFit.contain,
        placeholder: (_, __) => const _PlaceholderBox(),
        errorWidget: (_, __, ___) => const _PlaceholderBox(),
      );
    }
    return const _PlaceholderBox();
  }
}

class _PlaceholderBox extends StatelessWidget {
  const _PlaceholderBox();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.face, color: Colors.grey),
    );
  }
}

// ── Action tile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade800;
    return ListTile(
      leading: Icon(icon, color: c, size: 22),
      title: Text(label, style: TextStyle(color: c, fontSize: 15)),
      dense: true,
      onTap: onTap,
    );
  }
}

// ─── Background removal preview page ─────────────────────────────────────────

class _BgRemovePage extends StatefulWidget {
  final Uint8List originalBytes;
  final AppTheme theme;
  const _BgRemovePage({required this.originalBytes, required this.theme});

  @override
  State<_BgRemovePage> createState() => _BgRemovePageState();
}

class _BgRemovePageState extends State<_BgRemovePage> {
  Uint8List? _result;
  bool _processing = true;
  double _tolerance = 30;
  double _seedFx = 0.0;
  double _seedFy = 0.0;

  @override
  void initState() {
    super.initState();
    _process();
  }

  Future<void> _process() async {
    setState(() => _processing = true);
    try {
      final out = await compute(
        _bgRemoveInIsolate,
        _BgArgs(widget.originalBytes, _seedFx, _seedFy, _tolerance.round()),
      );
      if (mounted) setState(() { _result = out; _processing = false; });
    } catch (_) {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _onTap(TapDownDetails d, BoxConstraints c) {
    _seedFx = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0);
    _seedFy = (d.localPosition.dy / c.maxHeight).clamp(0.0, 1.0);
    _process();
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.theme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1C),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop<Uint8List>(null),
        ),
        title: const Text(
          'Убрать фон',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: (_processing || _result == null)
                ? null
                : () => Navigator.of(context).pop<Uint8List>(_result),
            child: Text(
              'Готово',
              style: TextStyle(
                color: (_processing || _result == null) ? Colors.white30 : primary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Image preview area ──────────────────────────────────────────────
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) => GestureDetector(
                onTapDown: (d) => _onTap(d, constraints),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const _Checkerboard(),
                    if (_result != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Image.memory(
                          _result!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    // Loading overlay
                    if (_processing)
                      Container(
                        color: Colors.black54,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: primary, strokeWidth: 2.5),
                              const SizedBox(height: 14),
                              const Text(
                                'Обрабатываю…',
                                style: TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Seed-point crosshair
                    if (!_processing)
                      Positioned(
                        left: _seedFx * constraints.maxWidth - 11,
                        top: _seedFy * constraints.maxHeight - 11,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
                          ),
                          child: const Center(
                            child: Icon(Icons.add, size: 10, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Controls panel ──────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.fromLTRB(
              20, 16, 20, 16 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.touch_app_rounded, size: 15, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(
                      'Нажмите на фото, чтобы выбрать цвет фона',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 15, color: Colors.grey.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Чувствительность',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_tolerance.round()}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: primary,
                    thumbColor: primary,
                    inactiveTrackColor: primary.withOpacity(0.15),
                    overlayColor: primary.withOpacity(0.08),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: _tolerance,
                    min: 5,
                    max: 80,
                    divisions: 15,
                    onChanged: (v) => setState(() => _tolerance = v),
                    onChangeEnd: (_) => _process(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Checkerboard background ──────────────────────────────────────────────────

class _Checkerboard extends StatelessWidget {
  const _Checkerboard();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _CheckerPainter(),
    child: const SizedBox.expand(),
  );
}

class _CheckerPainter extends CustomPainter {
  static const _cell = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = const Color(0xFFD8D8D8);
    final dark  = Paint()..color = const Color(0xFFAAAAAA);
    final cols = (size.width  / _cell).ceil() + 1;
    final rows = (size.height / _cell).ceil() + 1;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        canvas.drawRect(
          Rect.fromLTWH(c * _cell, r * _cell, _cell, _cell),
          (r + c).isEven ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter o) => false;
}

// ── Tiny helper: fetch cached image file ─────────────────────────────────────

Future<File> fetchCachedImageFile(String url) async {
  final tmp = await getTemporaryDirectory();
  final fileName = url.hashCode.toString();
  final cached = File('${tmp.path}/$fileName.png');
  if (await cached.exists()) return cached;

  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(url));
  final res = await req.close();
  final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
  await cached.writeAsBytes(bytes);
  client.close();
  return cached;
}
