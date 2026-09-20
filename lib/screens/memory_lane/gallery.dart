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

  /// Плёнка кадров под снимком — она же переключатель.
  late final ScrollController _stripCtrl;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _stripCtrl = ScrollController(
        initialScrollOffset: (widget.initialIndex * 64.0 - 140).clamp(0, 1e6));
  }

  @override
  void dispose() {
    _pageController.dispose();
    _stripCtrl.dispose();
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
  /// Низ просмотрщика: именная реакция записи слева, справа кнопка
  /// сохранения — она качает ОДИН кадр, тот что на экране, а стрелка даёт
  /// выбор: все кадры записи, все кадры ленты, отметить вручную.
  Widget _frameActions((Memory, MediaFile) hit) {
    final (m, f) = hit;
    final queue = MediaSaveQueue.instance;
    final ledger = SavedMediaLedger.instance;
    final theme = context.appTheme;
    final uid = PocketBaseService().userId ?? '';
    final repo = MemoryRepository();
    return AnimatedBuilder(
      animation: Listenable.merge([queue, ledger]),
      builder: (context, _) {
        final chips = <Widget>[];
        m.reactions.forEach((who, key) {
          chips.add(ReactionChip(
            uid: who,
            name: who == m.authorUid ? m.authorName : '',
            avatarUrl: who == m.authorUid ? m.authorAvatar : '',
            reactionKey: key,
            theme: theme,
            isMine: who == uid,
            onTap: who == uid
                ? () => repo.setReaction(
                    groupId: m.groupId, memoryId: m.id, reaction: key)
                : null,
          ));
        });
        final saved = ledger.containsFile(f);
        final saving = !saved && queue.isQueued(f.key);
        return Row(
          children: [
            for (final c in chips) ...[c, const SizedBox(width: 2)],
            if (m.reactionOf(uid).isEmpty)
              AddReactionButton(
                theme: theme,
                onPick: (key) => repo.setReaction(
                    groupId: m.groupId, memoryId: m.id, reaction: key),
              ),
            const Spacer(),
            SaveSplitButton(
              height: 44,
              state: saveButtonState(
                total: 1,
                saved: saved ? 1 : 0,
                done: saving ? 0 : null,
                jobTotal: saving ? 1 : null,
              ),
              onSaveAll: () => saveToGallery(
                context,
                title: memorySaveTitle(m),
                items: [SaveItem.of(m, f)],
                adult: m.isAdult,
              ),
              onChoose: () => _chooseFromViewer(m, f),
              onCancel: () => queue.cancel(m.id),
            ),
          ],
        );
      },
    );
  }

  /// Лист «Что сохранить» из просмотрщика: этот кадр, вся запись, вся лента
  /// или выбрать вручную.
  Future<void> _chooseFromViewer(Memory m, MediaFile f) async {
    final scheme = Theme.of(context).colorScheme;
    final memFiles = memoryMediaFiles(m);
    final allFiles = <MediaFile>[
      for (final it in widget.items)
        if (_fileOf(it) case final hit?) hit.$2,
    ];
    final choice = await showViewerSaveSheet(
      context,
      scheme: scheme,
      current: f,
      memoryFiles: memFiles,
      feedCount: allFiles.length,
      takenAt: m.createdAt,
      title: memorySaveTitle(m),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case ViewerSaveChoice.frame:
        await saveToGallery(context,
            title: memorySaveTitle(m),
            items: [SaveItem.of(m, f)],
            adult: m.isAdult);
      case ViewerSaveChoice.memory:
        await saveToGallery(context,
            title: memorySaveTitle(m),
            items: [for (final x in memFiles) SaveItem.of(m, x)],
            adult: m.isAdult);
      case ViewerSaveChoice.feed:
        await saveToGallery(
          context,
          title: LocaleService.current.memoryLane,
          items: [
            for (final it in widget.items)
              if (_fileOf(it) case final hit?) SaveItem.of(hit.$1, hit.$2),
          ],
        );
      case ViewerSaveChoice.pick:
        final picked =
            await showFramePicker(context, files: memFiles, scheme: scheme);
        if (picked == null || picked.files.isEmpty || !mounted) return;
        if (picked.share) {
          await shareMemoryMedia(context,
              files: picked.files, takenAt: m.createdAt);
        } else {
          await saveToGallery(context,
              title: memorySaveTitle(m),
              items: [for (final x in picked.files) SaveItem.of(m, x)],
              adult: m.isAdult);
        }
    }
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


  /// Круглая кнопка поверх кадра: стекло, чтобы читалась и на светлом.
  /// Плёнка едет за кадром: текущий всегда виден, а не остаётся за краем.
  void _scrollStripTo(int index) {
    if (!_stripCtrl.hasClients) return;
    final target = (index * 64.0) - 140;
    _stripCtrl.animateTo(
      target.clamp(0, _stripCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _viewerRound({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  /// Пилюля шапки: номер кадра, название записи и шеврон — переход к
  /// воспоминанию. Она же говорит, из какой записи кадр, когда листаешь
  /// дальше по сквозной ленте.
  Widget _viewerTitlePill(int count) {
    final memory = widget.memoryOf?.call(_current.memoryId);
    final title = (memory?.title?.trim().isNotEmpty == true)
        ? memory!.title!.trim()
        : (_current.caption?.trim().isNotEmpty == true
            ? _current.caption!.trim()
            : LocaleService.current.memoryLane);
    // Номер внутри записи, а не в общей ленте: «3/7» понятнее, чем «118/412».
    final sameMemory = [
      for (final it in widget.items)
        if (it.memoryId == _current.memoryId) it,
    ];
    final inMemory = sameMemory.indexOf(_current) + 1;
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop(context, _current.memoryId),
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(left: 14, right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$inMemory/${sameMemory.length}',
                style: const TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white70, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// «Ещё» у кадра: сведения и переход к записи.
  /// «Ещё» у кадра: перейти к записи или отправить сам кадр.
  Future<void> _openFrameMenu() async {
    final hit = _fileOf(_current);
    final cs = Theme.of(context).colorScheme;
    await showAppSheet<void>(
      context,
      builder: (ctx) => SheetScaffold(
        title: LocaleService.current.moreActions,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _frameMenuRow(
                cs,
                icon: Icons.collections_bookmark_rounded,
                title: LocaleService.current.goToPin,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context, _current.memoryId);
                },
              ),
              if (hit != null) ...[
                const SizedBox(height: 4),
                _frameMenuRow(
                  cs,
                  icon: Icons.ios_share_rounded,
                  title: trKey('pickShare'),
                  onTap: () {
                    Navigator.pop(ctx);
                    shareMemoryMedia(context,
                        files: [hit.$2], takenAt: hit.$1.createdAt);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _frameMenuRow(ColorScheme cs,
      {required IconData icon,
      required String title,
      required VoidCallback onTap}) {
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(color: cs.surface, shape: BoxShape.circle),
                child: Icon(icon, size: 22, color: cs.onSurface),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                    style: AppFonts.onest(
                        size: 16, weight: 600, color: cs.onSurface)),
              ),
            ],
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
          // Поля у широкого кадра занимает он сам — увеличенный и размытый.
          // Экран остаётся про кадр, и чёрных дыр сверху и снизу больше нет.
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                  child: Opacity(
                    opacity: 0.5,
                    child: StorageImage(
                      imageUrl: _current.url,
                      fit: BoxFit.cover,
                      memCacheWidth: 200,
                      errorWidget: (_, __, ___) =>
                          const ColoredBox(color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Photo / video pages
          PageView.builder(
            controller: _pageController,
            itemCount: count,
            onPageChanged: (i) {
              setState(() => _currentIndex = i);
              _scrollStripTo(i);
            },
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
          // Шапка: крестик, пилюля с номером кадра и названием записи —
          // она же переход к воспоминанию, и она же отвечает, из какой
          // записи кадр, когда листаешь дальше по ленте.
          Positioned(
            top: topPad + 8,
            left: 8,
            right: 8,
            child: Row(
              children: [
                _viewerRound(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 6),
                Flexible(child: _viewerTitlePill(count)),
                const Spacer(),
                _viewerRound(
                  icon: Icons.more_vert_rounded,
                  onTap: () => _openFrameMenu(),
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
          // Плёнка снизу: кадры идут сквозь все записи, текущий обведён.
          if (count > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: botPad + 78,
              child: SizedBox(
                height: 56,
                child: ListView.separated(
                  controller: _stripCtrl,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: count,
                  separatorBuilder: (_, _) => const SizedBox(width: 2),
                  itemBuilder: (_, i) => FilmFrame(
                    url: widget.items[i].url,
                    height: 56,
                    selected: i == _currentIndex,
                    onTap: () => _pageController.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
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

