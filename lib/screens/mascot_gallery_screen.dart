import 'dart:typed_data';

import '../widgets/storage_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;
import '../utils/share_origin.dart';
import 'dart:io';

import '../models/level.dart';
import '../models/mascot.dart';
import '../models/user_data.dart';
import '../widgets/common/app_dialog.dart';
import '../services/pb_media_service.dart';
import '../services/level_service.dart';
import '../services/mascot_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_scope.dart';
import '../models/mascot_anim.dart';
import '../models/mascot_sleep.dart';
import '../models/symbol_catalog.dart';
import '../theme/profile_theme.dart';
import '../widgets/app_sheet.dart';
import '../services/catalog_service.dart';
import '../widgets/active_mascot_widget.dart' show buildMascotAssetImage;
import '../widgets/mascot/pixel_mascot_view.dart';
import 'mascot_draw_screen.dart';

class MascotGalleryScreen extends StatefulWidget {
  final MascotService mascotService;
  final AppTheme theme;
  final String myUid;

  /// Кто смотрит: от него зависят окна сна персонажей, купленное и монеты.
  final UserData user;

  const MascotGalleryScreen({
    super.key,
    required this.mascotService,
    required this.theme,
    required this.myUid,
    required this.user,
  });

  @override
  State<MascotGalleryScreen> createState() => _MascotGalleryScreenState();
}

class _MascotGalleryScreenState extends State<MascotGalleryScreen> {
  AppTheme get _t => widget.theme;
  MascotService get _svc => widget.mascotService;

  bool _uploading = false;

  /// Поиск по названию. Пока строка непуста, папки раскрыты все: искать в
  /// свёрнутом списке бессмысленно.
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Свёрнутые папки. Решение человека переживает выход с экрана, поэтому
  /// живёт в prefs, а не в памяти состояния.
  static const String _kCollapsedKey = 'mascot_gallery_collapsed';
  Set<String> _collapsed = <String>{};

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChanged);
    _search.addListener(() {
      final q = _search.text.trim().toLowerCase();
      if (q != _query && mounted) setState(() => _query = q);
    });
    _loadCollapsed();
  }

  @override
  void dispose() {
    _svc.removeListener(_onChanged);
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCollapsed() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kCollapsedKey);
    if (saved != null && mounted) setState(() => _collapsed = saved.toSet());
  }

  Future<void> _toggleFolder(String key) async {
    setState(() {
      _collapsed.contains(key) ? _collapsed.remove(key) : _collapsed.add(key);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kCollapsedKey, _collapsed.toList());
  }

  bool _ru() => LocaleService.instance.isRussian;

  /// Раскладка по папкам. Пиксельные идут первыми — они анимированные и живее
  /// остальных; свои рисунки следом, потому что их заводили руками.
  List<_Folder> _folders() {
    final pixel = <Mascot>[];
    final own = <Mascot>[];
    final bundled = <Mascot>[];
    final catalog = <Mascot>[];

    for (final m in _svc.mascots) {
      if (CatalogService.instance.animById(m.id) != null) {
        pixel.add(m);
      } else if (m.catalogUrl != null) {
        catalog.add(m);
      } else if (m.isDefault) {
        bundled.add(m);
      } else {
        own.add(m);
      }
    }

    final ru = _ru();
    return [
      _Folder('pixel', ru ? 'Пиксельные' : 'Pixel', Icons.grid_view_rounded, pixel),
      _Folder('own', ru ? 'Наши рисунки' : 'Our drawings',
          Icons.brush_outlined, own),
      _Folder('bundled', ru ? 'Встроенные' : 'Built-in',
          Icons.auto_awesome_outlined, bundled),
      _Folder('catalog', ru ? 'Каталог' : 'Catalog',
          Icons.collections_bookmark_outlined, catalog),
    ];
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
        settings: const RouteSettings(name: '/mascot_draw'),
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
            SnackBar(
              content: Text(LocaleService.current.mascotSaveFailed),
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

    // Show one-time hint about transparent background requirement
    final prefs = await SharedPreferences.getInstance();
    const hintKey = 'mascot_import_hint_shown';
    if (prefs.getBool(hintKey) != true) {
      await prefs.setBool(hintKey, true);
      if (!mounted) return;
      final ok = await _showBgHintSheet();
      if (!ok || !mounted) return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final defaultName = file.name
        .replaceAll(RegExp(r'\.png$', caseSensitive: false), '')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');

    if (!mounted) return;
    final name = await _showImportNameDialog(defaultName);
    if (name == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final saved = await _svc.uploadAndSaveMascot(
        pngBytes: bytes,
        name: name,
        creatorUid: widget.myUid,
      );
      if (saved == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocaleService.current.mascotLoadFailed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<bool> _showBgHintSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: _t.cardSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          24, 20, 24, 20 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _t.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.layers_clear_rounded, color: _t.primary, size: 24),
            ),
            const SizedBox(height: 14),
            Text(
              LocaleService.current.transparentBgTitle,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              LocaleService.current.transparentBgBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _t.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _t.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  LocaleService.current.gotIt,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<String?> _showImportNameDialog(String defaultName) async {

    return AppDialog.prompt(
      context,
      title: LocaleService.current.mascotNameTitle,
      hint: LocaleService.current.enterNameHint,
      initial: defaultName,
      confirmLabel: LocaleService.current.add,
      maxLength: 30,
    );
  }

  void _showLimitSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LocaleService.current.mascotLimitReached),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Mascot actions ───────────────────────────────────────────────────────

  /// Открыт ли маскот этому человеку.
  ///
  /// Маскот общий, поэтому засчитывается и покупка партнёра: персонаж живёт на
  /// главной у обоих, серию они растят вдвоём, и требовать вторую оплату за то
  /// же самое было бы издевательством.
  bool _isUnlocked(Mascot mascot) => widget.user.unlocksCatalogItem(
        mascot.unlock,
        kMascotFeatureKind,
        mascot.id,
        LevelService.instance.level,
        boughtByPair: _svc.state.owns(
          Unlock.featureKey(kMascotFeatureKind, mascot.id),
        ),
      );

  /// Предложить купить платного маскота за монеты.
  ///
  /// Цену показываем из каталога, но списывает её сервер по своей же записи:
  /// клиентскому числу он не верит, подменить его в запросе нельзя.
  Future<void> _offerPurchase(Mascot mascot) async {
    final ru = LocaleService.instance.isRussian;
    final price = mascot.unlock.price;
    final coins = widget.user.coins;

    if (coins < price) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ru
              ? 'Не хватает монет: нужно $price, у вас $coins'
              : 'Not enough coins: $price needed, you have $coins'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final ok = await AppDialog.confirm(
      context,
      title: mascot.localizedName,
      message: ru
          ? 'Открыть этого персонажа навсегда за $price монет?'
          : 'Unlock this character forever for $price coins?',
      confirmLabel: ru ? 'Купить' : 'Buy',
      icon: Icons.pets_rounded,
    );
    if (!ok || !mounted) return;

    final bought =
        await widget.user.purchaseCatalogItem(kMascotFeatureKind, mascot.id);
    if (!mounted) return;

    if (!bought) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ru ? 'Покупка не прошла' : 'Purchase failed'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {});
    await _setActive(mascot);
  }

  Future<void> _setActive(Mascot mascot) async {
    // Гейт по разблокировке: каталожный маскот может быть «за уровень» или
    // платным. Платного тут же и предлагаем купить — за монеты, по цене из
    // каталога, поэтому новый персонаж продаётся без новой сборки.
    if (!_isUnlocked(mascot)) {
      final ru = LocaleService.instance.isRussian;
      if (mascot.unlock.isForSale) {
        await _offerPurchase(mascot);
        return;
      }
      final msg = mascot.unlock.isPremium
          ? (ru ? 'Пока не продаётся' : 'Not for sale yet')
          : (ru
              ? 'Откроется на уровне ${mascot.unlock.requiredLevel}'
              : 'Unlocks at level ${mascot.unlock.requiredLevel}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    final alreadyActive = _svc.state.activeMascotId == mascot.id;
    await _svc.setActive(alreadyActive ? null : mascot.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alreadyActive
                ? LocaleService.current.mascotDeactivated(mascot.localizedName)
                : LocaleService.current.mascotActivated(mascot.localizedName),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _rename(Mascot mascot) async {

    final newName = await AppDialog.prompt(
      context,
      title: LocaleService.current.rename,
      hint: LocaleService.current.mascotNameTitle,
      initial: mascot.localizedName,
      maxLength: 30,
    );
    if (newName != null && newName.isNotEmpty && newName != mascot.localizedName) {
      await _svc.renameMascot(mascot, newName);
    }
  }

  Future<void> _delete(Mascot mascot) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: LocaleService.current.deleteMascotTitle,
      message: LocaleService.current.deleteMascotBody(mascot.localizedName),
      confirmLabel: LocaleService.current.delete,
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (confirmed) {
      await _svc.deleteMascot(mascot);
    }
  }

  Future<void> _export(Mascot mascot) async {
    // iPad-поповер: origin считаем до async-gap, пока context жив.
    final origin = shareOriginFromContext(context);
    try {
      if (mascot.imageUrl != null) {
        final file = await fetchCachedImageFile(mascot.imageUrl!);
        final tmp = await getTemporaryDirectory();
        final dest = File(
          '${tmp.path}/${mascot.name.replaceAll(' ', '_')}.png',
        );
        await file.copy(dest.path);
        await Share.shareXFiles(
          [XFile(dest.path)],
          text: mascot.localizedName,
          sharePositionOrigin: origin,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(content: Text(LocaleService.current.exportError('$e'))),
        );
      }
    }
  }

  Future<void> _share(Mascot mascot) async {
    await _export(mascot);
  }

  /// Лист действий по маскоту.
  ///
  /// Открывается через [showAppSheet] — как остальные листы проекта: углы 28,
  /// хват, низ выше системных кнопок. Пункты крупные (высота 60), потому что
  /// в них целятся большим пальцем на весу; разделителя между шапкой и
  /// действиями нет — заголовок и так отделён отступом.
  void _showActions(Mascot mascot) {
    final isActive = _svc.state.activeMascotId == mascot.id;
    final canExport = mascot.imageUrl != null;
    final cs = ProfileTheme.themeFor(_t).colorScheme;
    final s = LocaleService.current;
    final ru = _ru();

    showAppSheet<void>(
      context,
      background: cs.surfaceContainer,
      builder: (ctx) => SheetScaffold(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: _MascotThumbnail(
                        mascot: mascot,
                        size: 60,
                        service: _svc,
                        sleep: widget.user.sleepOf(mascot.id)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mascot.localizedName,
                          style: TextStyle(
                            fontFamily: 'Unbounded',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mascot.recordStreak > 0
                              ? s.recordStreakDays(mascot.recordStreak)
                              : isActive
                                  ? (ru ? 'Сейчас на экране' : 'On screen now')
                                  : (ru ? 'Ждёт своей очереди' : 'Waiting'),
                          style: TextStyle(
                              fontSize: 13.5, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SheetAction(
                icon: isActive
                    ? Icons.do_not_disturb_on_outlined
                    : Icons.play_circle_outline_rounded,
                label: isActive ? s.deactivateLabel : s.makeActiveLabel,
                scheme: cs,
                primary: !isActive,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _setActive(mascot);
                },
              ),
              if (!mascot.isDefault) ...[
                const SizedBox(height: 8),
                _SheetAction(
                  icon: Icons.brush_outlined,
                  label: s.editLabel,
                  scheme: cs,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openDrawScreen(editMascot: mascot);
                  },
                ),
                const SizedBox(height: 8),
                _SheetAction(
                  icon: Icons.drive_file_rename_outline_rounded,
                  label: s.rename,
                  scheme: cs,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _rename(mascot);
                  },
                ),
              ],
              if (canExport) ...[
                const SizedBox(height: 8),
                _SheetAction(
                  icon: Icons.download_rounded,
                  label: s.exportPng,
                  scheme: cs,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _export(mascot);
                  },
                ),
                const SizedBox(height: 8),
                _SheetAction(
                  icon: Icons.ios_share_rounded,
                  label: s.share,
                  scheme: cs,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _share(mascot);
                  },
                ),
              ],
              if (!mascot.isDefault) ...[
                const SizedBox(height: 8),
                _SheetAction(
                  icon: Icons.delete_outline_rounded,
                  label: s.delete,
                  scheme: cs,
                  destructive: true,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _delete(mascot);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Список папок с сетками внутри.
  ///
  /// Пустые папки не показываем вовсе: пустой заголовок «Каталог · 0» ничего
  /// не объясняет и только удлиняет список.
  Widget _buildFolders() {
    final cs = ProfileTheme.themeFor(_t).colorScheme;
    final searching = _query.isNotEmpty;
    final folders = <Widget>[];

    for (final f in _folders()) {
      final items = searching
          ? f.items
              .where((m) => m.localizedName.toLowerCase().contains(_query))
              .toList()
          : f.items;
      if (items.isEmpty) continue;

      final open = searching || !_collapsed.contains(f.key);
      folders.add(_FolderHeader(
        title: f.title,
        icon: f.icon,
        count: items.length,
        open: open,
        scheme: cs,
        // Во время поиска сворачивать нечего: список и так отфильтрован.
        onTap: searching ? null : () => _toggleFolder(f.key),
      ));
      if (open) {
        folders.add(GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.82,
          ),
          itemCount: items.length,
          itemBuilder: (ctx, i) => _MascotCard(
            mascot: items[i],
            isActive: _svc.state.activeMascotId == items[i].id,
            theme: _t,
            service: _svc,
            sleep: widget.user.sleepOf(items[i].id),
            unlocked: _isUnlocked(items[i]),
            onTap: () => _showActions(items[i]),
          ),
        ));
      }
    }

    if (folders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _ru()
                ? 'Никого с таким именем. Попробуйте другое слово.'
                : 'Nobody with that name. Try another word.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
        ),
      );
    }

    // Подпись художницы — последним блоком прокрутки, а не в подвале: там она
    // отнимала место у кнопок и лезла в глаза на каждом экране.
    // Подписана псевдонимом и без ссылки на Телеграм — по просьбе самой
    // художницы (1 августа): аудитория выросла, и настоящая фамилия рядом с
    // переходом в личный аккаунт приводила к ней незнакомых людей.
    folders.add(_ArtistCredit(
      scheme: cs,
      text: _ru()
          ? 'Художница маскотов «От нас» — Meller1'
          : 'Mascots marked «От нас» drawn by Meller1',
    ));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: folders,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mascots = _svc.mascots;
    final streak = _svc.state.activeStreak;

    return Scaffold(
      backgroundColor: _t.surfaceMuted,
      appBar: AppBar(
        backgroundColor: _t.cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          LocaleService.current.groupMascots,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
                  LocaleService.current
                      .mascotsCount(_svc.mascotCount, MascotService.maxMascots),
                  style: TextStyle(fontSize: 13, color: _t.textSecondary),
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
                    child: Text(
                      LocaleService.current.limitLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _SearchField(
            controller: _search,
            hint: _ru() ? 'Найти маскота' : 'Find a mascot',
            onClear: () => _search.clear(),
          ),
          Expanded(
            child: _svc.isLoading
                ? const Center(child: CircularProgressIndicator())
                : mascots.isEmpty
                ? Center(
                    child: Text(
                      LocaleService.current.mascotsLoadFailedMultiline,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _t.textMuted),
                    ),
                  )
                : _buildFolders(),
          ),
          // Подвал: кто рисовал и что можно сделать. Раньше кнопки висели
          // плавающими с тенями поверх сетки и перекрывали нижний ряд;
          // теперь это обычная панель на surfaceContainer, тени не нужны —
          // в M3 слои разводит цвет контейнера, а не размытие под ним.
          _GalleryFooter(
            scheme: ProfileTheme.themeFor(_t).colorScheme,
            drawLabel: LocaleService.current.drawLabel,
            uploadTooltip: LocaleService.current.uploadPhotoTooltip,
            busy: _uploading,
            full: _svc.isGalleryFull,
            onDraw: () => _openDrawScreen(),
            onImport: _importPng,
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
    final cs = ProfileTheme.themeFor(theme).colorScheme;
    final s = LocaleService.current;
    final alive = streak > 0;

    // Огонь горит на primaryContainer, спящая серия — на приглушённом
    // контейнере. Эмодзи тут не годились: они рисуются системным шрифтом,
    // на разных телефонах выглядят по-разному и не красятся ролью схемы.
    final bg = alive ? cs.primaryContainer : cs.surfaceContainerHigh;
    final fg = alive ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: alive
                    ? cs.onPrimaryContainer.withValues(alpha: 0.12)
                    : cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: SymbolIcon(
                alive ? 'local_fire_department' : 'bedtime',
                size: 24,
                color: fg,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alive ? s.streakLabel(streak) : s.streakBroken,
                    style: TextStyle(
                      fontFamily: 'Unbounded',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: alive ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alive ? s.streakKeepHint : s.streakStartHint,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: fg.withValues(alpha: alive ? 0.85 : 1.0),
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

class _MascotCard extends StatelessWidget {
  final Mascot mascot;
  final bool isActive;
  final AppTheme theme;
  final MascotService service;
  final VoidCallback onTap;

  /// Когда этот персонаж уходит на ночную сцену.
  final SleepWindow sleep;

  /// Открыт ли он этому человеку: бесплатный, дорос уровнем, куплен или
  /// включён в Togetherly+.
  final bool unlocked;

  const _MascotCard({
    required this.mascot,
    required this.isActive,
    required this.theme,
    required this.service,
    required this.onTap,
    required this.unlocked,
    this.sleep = SleepWindow.standard,
  });

  @override
  Widget build(BuildContext context) {
    final locked = !unlocked;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          // Выбранная ячейка отличается тоном подложки и обводкой, а не
          // тенью: теней в проекте нет, глубину даёт тональная поверхность.
          color: isActive
              ? Color.alphaBlend(theme.primary.withValues(alpha: 0.10),
                  theme.cardSurface)
              : theme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? theme.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Opacity(
                      opacity: locked ? 0.35 : 1.0,
                      child: _MascotThumbnail(
                        mascot: mascot,
                        size: double.infinity,
                        service: service,
                        sleep: sleep,
                      ),
                    ),
                  ),
                  if (locked)
                    Positioned(
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          // Ценник тональной поверхностью и внизу карточки:
                          // чёрная плашка по центру закрывала самого персонажа
                          // и не жила ни в одной теме.
                          color: Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Цена — в тех же монетах, что и везде в приложении:
                            // абстрактный алмаз рядом с числом читался как
                            // вторая валюта, которой в проекте нет.
                            if (mascot.unlock.isPremium)
                              Image.asset('assets/images/icons/coin.webp',
                                  width: 13,
                                  height: 13,
                                  filterQuality: FilterQuality.medium)
                            else
                              Icon(Icons.lock_rounded,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                                  size: 12),
                            const SizedBox(width: 3),
                            Text(
                              // Цена прямо на плитке: замок без числа заставляет
                              // тыкать в каждого, чтобы узнать, сколько стоит.
                              mascot.unlock.isForSale
                                  ? '${mascot.unlock.price}'
                                  : mascot.unlock.isPremium
                                      ? (LocaleService.instance.isRussian
                                          ? 'платный'
                                          : 'paid')
                                      : (LocaleService.instance.isRussian
                                          ? 'Ур. ${mascot.unlock.requiredLevel}'
                                          : 'Lv ${mascot.unlock.requiredLevel}'),
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
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
                        child: Text(
                          LocaleService.current.fromUs,
                          style: const TextStyle(
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SymbolIcon('workspace_premium',
                            size: 12, color: theme.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          LocaleService.current
                              .recordStreakBadge(mascot.recordStreak),
                          style: TextStyle(fontSize: 10, color: theme.textMuted),
                        ),
                      ],
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
    this.sleep = SleepWindow.standard,
  });

  /// Когда этот персонаж уходит на ночную сцену.
  final SleepWindow sleep;

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
    // Пиксельный маскот каталога: его catalogUrl ведёт на атлас кадров,
    // поэтому в плитке крутим анимацию, а не показываем всю простыню.
    final animated = CatalogService.instance.animById(mascot.id);
    if (animated != null) {
      // Размер берём заданный, а если его нет — у родителя. Прежний вариант
      // всегда лез в LayoutBuilder, и в листе действий (строка без ограничений
      // по ширине) приходила бесконечность: лист раздувался и выглядел пустым.
      // В галерее показываем ступень, до которой пара дожила с этим маскотом:
      // взрослый вид у всех подряд обесценивал бы рост.
      final level = MascotAnim.levelForStreak(
          mascot.recordStreak > 0 ? mascot.recordStreak : service.state.activeStreak);
      if (size.isFinite) {
        return PixelMascotView(
          anim: animated,
          state: MascotAnimState.live,
          level: level,
          sleep: sleep,
          size: size,
        );
      }
      return LayoutBuilder(
        builder: (_, c) {
          final side = c.biggest.shortestSide;
          return PixelMascotView(
            anim: animated,
            state: MascotAnimState.live,
            level: level,
            sleep: sleep,
            size: side.isFinite ? side : 96,
          );
        },
      );
    }
    if (mascot.catalogUrl != null) {
      return CachedNetworkImage(
        imageUrl: mascot.catalogUrl!,
        width: size == double.infinity ? null : size,
        height: size == double.infinity ? null : size,
        fit: BoxFit.contain,
        placeholder: (_, __) => const _PlaceholderBox(),
        errorWidget: (_, __, ___) => const _PlaceholderBox(),
      );
    }
    if (mascot.imageUrl != null) {
      return StorageImage(
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
    final t = context.appTheme;
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.face, color: t.textMuted),
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
    final c = color ?? context.appTheme.textPrimary;
    return ListTile(
      leading: Icon(icon, color: c, size: 22),
      title: Text(label, style: TextStyle(color: c, fontSize: 15)),
      dense: true,
      onTap: onTap,
    );
  }
}

// ── Tiny helper: fetch cached image file ─────────────────────────────────────

Future<File> fetchCachedImageFile(String url) async {
  final tmp = await getTemporaryDirectory();
  final fileName = url.hashCode.toString();
  final cached = File('${tmp.path}/$fileName.png');
  if (await cached.exists()) return cached;

  // sb://media/... (и gs://) — приватные пути: резолвим в подписанный https URL.
  final resolved = await PbMediaService().resolvePlayable(url);
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(resolved));
  final res = await req.close();
  final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
  await cached.writeAsBytes(bytes);
  client.close();
  return cached;
}


/// Папка галереи: название, значок и её маскоты.
class _Folder {
  const _Folder(this.key, this.title, this.icon, this.items);

  final String key;
  final String title;
  final IconData icon;
  final List<Mascot> items;
}

/// Заголовок папки: значок, название, счётчик и стрелка раскрытия.
class _FolderHeader extends StatelessWidget {
  const _FolderHeader({
    required this.title,
    required this.icon,
    required this.count,
    required this.open,
    required this.scheme,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final int count;
  final bool open;
  final ColorScheme scheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Unbounded',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 22, color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Поиск по названию — поле M3 с заливкой и крестиком очистки.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, value, _) => TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          style: TextStyle(fontSize: 15, color: cs.onSurface),
          cursorColor: cs.primary,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
            prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                    onPressed: onClear,
                  ),
            filled: true,
            fillColor: cs.surfaceContainerHigh,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}


/// Пункт листа действий: крупная строка со значком, заливкой и радиусом 20.
///
/// Главное действие красится primaryContainer, опасное — errorContainer:
/// цвет отличает их лучше, чем красный текст в общем ряду.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.scheme,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final bg = destructive
        ? scheme.errorContainer
        : primary
            ? scheme.primaryContainer
            : scheme.surfaceContainerHigh;
    final fg = destructive
        ? scheme.onErrorContainer
        : primary
            ? scheme.onPrimaryContainer
            : scheme.onSurface;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              const SizedBox(width: 18),
              Icon(icon, size: 22, color: fg),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}


/// Подвал галереи: подпись художницы и кнопки «загрузить» и «нарисовать».
class _GalleryFooter extends StatelessWidget {
  const _GalleryFooter({
    required this.scheme,
    required this.drawLabel,
    required this.uploadTooltip,
    required this.busy,
    required this.full,
    required this.onDraw,
    required this.onImport,
  });

  final ColorScheme scheme;
  final String drawLabel;
  final String uploadTooltip;
  final bool busy;
  final bool full;
  final VoidCallback onDraw;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!full)
                Row(
                  children: [
                    // Загрузка своей картинки — действие редкое, поэтому
                    // тональная кнопка рядом с главной, а не своя плавающая.
                    SizedBox(
                      height: 56,
                      width: 56,
                      child: IconButton.filledTonal(
                        onPressed: busy ? null : onImport,
                        tooltip: uploadTooltip,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.surfaceContainerHighest,
                          foregroundColor: scheme.onSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: busy ? null : onDraw,
                          icon: busy
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.brush_rounded, size: 20),
                          label: Text(drawLabel),
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Подпись художницы — последний блок списка.
///
/// Стоит именно в прокрутке, а не в подвале: в подвале она соперничала с
/// кнопками за место и мозолила глаза, хотя нужна раз в жизни.
class _ArtistCredit extends StatelessWidget {
  const _ArtistCredit({
    required this.scheme,
    required this.text,
  });

  final ColorScheme scheme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SymbolIcon('palette', size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
