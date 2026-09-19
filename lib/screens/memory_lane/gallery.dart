part of '../memory_lane_screen.dart';

// ══════════════════════════════════════════════════════
//  Все кадры пары
// ══════════════════════════════════════════════════════

/// Все кадры и ролики пары по месяцам — вход из значка галереи в шапке ленты.
///
/// Экран был чёрной сеткой без единого действия. Теперь это место, откуда
/// медиа пары переезжает в галерею телефона целиком или по месяцу: так
/// переносят историю на новый телефон (жалоба 19.09.2026: «пережило смену
/// телефонов, было бы круто нормально сохранять»).
class _PhotoGalleryScreen extends StatefulWidget {
  final List<GalleryItem> items;
  final Color primary;
  final ColorScheme scheme;
  final Memory? Function(String memoryId) memoryOf;

  const _PhotoGalleryScreen({
    required this.items,
    required this.primary,
    required this.scheme,
    required this.memoryOf,
  });

  @override
  State<_PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _MonthGroup {
  final DateTime month;
  final List<int> indexes = [];
  _MonthGroup(this.month);
}

class _PhotoGalleryScreenState extends State<_PhotoGalleryScreen> {
  late final List<(Memory, MediaFile)?> _files = [
    for (final it in widget.items) _fileOf(it),
  ];
  late final List<_MonthGroup> _months = _group();

  @override
  void initState() {
    super.initState();
    SavedMediaLedger.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  (Memory, MediaFile)? _fileOf(GalleryItem item) {
    final m = widget.memoryOf(item.memoryId);
    if (m == null) return null;
    final key = mediaKey(item.isVideo ? item.videoUrl! : item.url);
    for (final f in memoryMediaFiles(m)) {
      if (f.key == key) return (m, f);
    }
    return null;
  }

  List<_MonthGroup> _group() {
    final out = <_MonthGroup>[];
    for (var i = 0; i < widget.items.length; i++) {
      final m = _files[i]?.$1;
      final d = m?.createdAt;
      final month = d == null ? DateTime(1970) : DateTime(d.year, d.month);
      if (out.isEmpty || out.last.month != month) out.add(_MonthGroup(month));
      out.last.indexes.add(i);
    }
    return out;
  }

  List<SaveItem> _itemsOf(Iterable<int> indexes) => [
        for (final i in indexes)
          if (_files[i] case (final m, final f)) SaveItem.of(m, f),
      ];

  String _monthLabel(DateTime d) {
    if (d.year == 1970) return '';
    return '${LocaleService.current.fullMonths[d.month - 1]} ${d.year}';
  }

  Future<void> _save(String title, List<int> indexes) async {
    final items = _itemsOf(indexes);
    if (items.isEmpty) return;
    final adult = {
      for (final i in indexes)
        if (_files[i]?.$1.isAdult ?? false) _files[i]!.$1.id,
    }.isNotEmpty;
    await saveToGallery(context, title: title, items: items, adult: adult);
  }

  Future<void> _open(int i) async {
    final memoryId = await Navigator.of(context).push<String>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => FullscreenGallery(
          items: widget.items,
          initialIndex: i,
          memoryOf: widget.memoryOf,
        ),
      ),
    );
    if (memoryId != null && mounted) Navigator.pop(context, memoryId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    final botPad = MediaQuery.of(context).padding.bottom;
    final ledger = SavedMediaLedger.instance;
    final all = [for (final f in _files) if (f != null) f.$2];
    final summary = summarizeMedia(all);
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            trKey('allSavedTitle'),
            style: const TextStyle(
                fontFamily: 'Unbounded', fontSize: 18, fontWeight: FontWeight.w700),
          ),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: Stack(
          children: [
            AnimatedBuilder(
              animation: ledger,
              builder: (context, _) {
                final saved = ledger.countSaved(all);
                return CustomScrollView(
                  cacheExtent: 600,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${all.length}',
                                  style: TextStyle(
                                    fontFamily: 'Unbounded',
                                    fontSize: 60,
                                    height: 0.95,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -2,
                                    color: cs.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      [
                                        trKey('allFilesLabel'),
                                        if (summary.videos > 0)
                                          trKey('saveCountVideos').replaceAll(
                                              '{n}', '${summary.videos}'),
                                      ].join('\n'),
                                      style: TextStyle(
                                        fontFamily: 'Onest',
                                        fontSize: 13.5,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              key: const ValueKey('all-media-save'),
                              onPressed: all.isEmpty
                                  ? null
                                  : () => _save(trKey('allSavedTitle'), [
                                        for (var i = 0; i < widget.items.length; i++) i,
                                      ]),
                              icon: const Icon(Icons.download_rounded),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(trKey('allSaveAll'), maxLines: 1),
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(56),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                trKey('allSaveSub')
                                    .replaceAll('{mb}', '${summary.megabytes}'),
                                if (saved > 0)
                                  trKey('saveAlreadyIn').replaceAll('{n}', '$saved'),
                              ].join(' · '),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 12.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    for (final g in _months) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 8, 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  [
                                    _monthLabel(g.month),
                                    '${g.indexes.length}',
                                  ].where((e) => e.isNotEmpty).join(' · ').toUpperCase(),
                                  style: ProfileTheme.sectionLabel(cs),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => _save(_monthLabel(g.month), g.indexes),
                                icon: const Icon(Icons.download_rounded, size: 18),
                                label: Text(trKey('allSaveMonth')),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 3,
                            crossAxisSpacing: 3,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (_, k) {
                              final i = g.indexes[k];
                              final item = widget.items[i];
                              final f = _files[i]?.$2;
                              final isSaved = f != null && ledger.containsFile(f);
                              return GestureDetector(
                                onTap: () => _open(i),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      StorageImage(
                                        imageUrl: item.url,
                                        fit: BoxFit.cover,
                                        // Только ширина: с высотой кадр
                                        // декодируется в квадрат и сплющивается.
                                        memCacheWidth: 300,
                                        errorWidget: (_, _, _) => ColoredBox(
                                          color: cs.surfaceContainerHigh,
                                          child: Icon(Icons.broken_image_rounded,
                                              color: cs.onSurfaceVariant),
                                        ),
                                      ),
                                      if (item.isVideo)
                                        const Center(
                                          child: Icon(Icons.play_circle_fill_rounded,
                                              color: Colors.white70, size: 34),
                                        ),
                                      if (isSaved)
                                        Positioned(
                                          left: 5,
                                          bottom: 5,
                                          child: Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              color: cs.inverseSurface
                                                  .withValues(alpha: 0.72),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(Icons.download_done_rounded,
                                                size: 15, color: cs.onInverseSurface),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            childCount: g.indexes.length,
                          ),
                        ),
                      ),
                    ],
                    SliverToBoxAdapter(child: SizedBox(height: botPad + 100)),
                  ],
                );
              },
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: botPad + 16,
              child: const SaveIsland(),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
//  Fullscreen Photo Gallery — cross-pin swipe
// ══════════════════════════════════════════════════════
class FullscreenGallery extends StatefulWidget {
  final List<GalleryItem> items;
  final int initialIndex;

  /// Запись кадра: без неё кадр не знает ни даты, ни места, и сохранения в
  /// полном экране нет.
  final Memory? Function(String memoryId)? memoryOf;

  const FullscreenGallery({
    super.key,
    required this.items,
    required this.initialIndex,
    this.memoryOf,
  });

  @override
  State<FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<FullscreenGallery> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  GalleryItem get _current => widget.items[_currentIndex];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Отметка «В галерее» читается из журнала на диске.
    SavedMediaLedger.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Файл кадра внутри его записи: по нему сохранение знает дату, место и
  /// номер кадра для имени файла.
  (Memory, MediaFile)? _fileOf(GalleryItem item) {
    final m = widget.memoryOf?.call(item.memoryId);
    if (m == null) return null;
    final key = mediaKey(item.isVideo ? item.videoUrl! : item.url);
    for (final f in memoryMediaFiles(m)) {
      if (f.key == key) return (m, f);
    }
    return null;
  }

  /// «Сохранить» и «Отправить» именно этот кадр. Кнопка помнит, что кадр уже в
  /// галерее, и не даёт сохранить его второй раз по ошибке.
  Widget _frameActions((Memory, MediaFile) hit) {
    final (m, f) = hit;
    final queue = MediaSaveQueue.instance;
    final ledger = SavedMediaLedger.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([queue, ledger]),
      builder: (context, _) {
        final saved = ledger.containsFile(f);
        final saving = !saved && queue.isQueued(f.key);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _viewerPill(
              key: const ValueKey('viewer-save'),
              icon: saved ? Icons.download_done_rounded : Icons.download_rounded,
              label: saved
                  ? trKey('viewerSaved')
                  : saving
                      ? trKey('viewerSaving')
                      : trKey('viewerSave'),
              ok: saved,
              busy: saving,
              onTap: saved || saving
                  ? null
                  : () => saveToGallery(
                        context,
                        title: memorySaveTitle(m),
                        items: [SaveItem.of(m, f)],
                        adult: m.isAdult,
                      ),
            ),
            const SizedBox(width: 8),
            _viewerPill(
              key: const ValueKey('viewer-share'),
              icon: Icons.ios_share_rounded,
              label: trKey('pickShare'),
              onTap: () => shareMemoryMedia(
                context,
                files: [f],
                takenAt: m.createdAt,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _viewerPill({
    required Key key,
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool ok = false,
    bool busy = false,
  }) {
    final bg = ok ? const Color(0xFFE9F6EE) : Colors.white.withValues(alpha: 0.14);
    final fg = ok ? const Color(0xFF1C4A2C) : Colors.white;
    return Material(
      key: key,
      color: bg,
      borderRadius: BorderRadius.circular(23),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
                  )
                else
                  Icon(icon, size: 20, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    final count = widget.items.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Photo / video pages
          PageView.builder(
            controller: _pageController,
            itemCount: count,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) {
              final item = widget.items[i];
              if (item.isVideo) {
                return GestureDetector(
                  // Свой плеер, а не система: ролик, снятый в приложении,
                  // открывался в браузере. Ссылку он разбирает сам
                  // (`resolvePlayable` внутри), поэтому её сюда тащить не надо.
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          InAppVideoPlayerPage(url: item.videoUrl!),
                      settings: const RouteSettings(name: '/video_player'),
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      StorageImage(
                        imageUrl: item.url,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.grey.shade900),
                      ),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: StorageImage(
                    imageUrl: item.url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white54,
                      ),
                    ),
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image_rounded,
                      color: Colors.white38,
                      size: 48,
                    ),
                  ),
                ),
              );
            },
          ),
          // Top bar: go-to-pin (left) + close (right)
          Positioned(
            top: topPad + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context, _current.memoryId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.push_pin_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          LocaleService.current.goToPin,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_fileOf(_current) case final hit?)
            Positioned(
              left: 16,
              right: 16,
              bottom: botPad + (count > 1 ? 58 : 22),
              child: _frameActions(hit),
            ),
          // Page indicator / counter
          if (count > 1)
            Positioned(
              bottom: botPad + 24,
              left: 0,
              right: 0,
              child: count <= 20
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        count,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _currentIndex ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _currentIndex
                                ? Colors.white
                                : Colors.white.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${_currentIndex + 1} / $count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// Isolated keyboard-inset padding widget
// Only this widget rebuilds on every frame of the keyboard animation,
// leaving the heavy modal sheet tree completely untouched.
// ══════════════════════════════════════════════════════
// ─── Map app tile for route picker ───────────────────────────────────────────
class _MapAppTile extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final String url;

  const _MapAppTile({
    required this.name,
    required this.icon,
    required this.color,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await safeLaunchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          // Fallback: try web URL for native-scheme apps
          final webFallback = Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${uri.host}',
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(LocaleService.current.appNotInstalled)),
            );
          }
          debugPrint('Cannot launch $url, fallback: $webFallback');
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Text(
              name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.appTheme.textPrimary,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: context.appTheme.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _KeyboardPaddingBox extends StatelessWidget {
  const _KeyboardPaddingBox();

  @override
  Widget build(BuildContext context) {
    final bottom =
        MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom +
        24;
    return SizedBox(height: bottom);
  }
}

// ─── Blur-until-tapped helper ───────────────────────────────────────────────
class _BlurAfterTap extends StatefulWidget {
  final Widget child;
  const _BlurAfterTap({required this.child});

  @override
  State<_BlurAfterTap> createState() => _BlurAfterTapState();
}

class _BlurAfterTapState extends State<_BlurAfterTap> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _revealed = !_revealed),
      // RepaintBoundary isolates the expensive BackdropFilter GPU pass so it
      // doesn't invalidate the surrounding layout on every frame.
      child: RepaintBoundary(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            widget.child,
            if (!_revealed)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    child: const Center(
                      child: Icon(
                        Icons.lock_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }
}

