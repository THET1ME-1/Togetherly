part of '../memory_lane_screen.dart';

class _MemoryDetailSheet extends StatefulWidget {
  final Memory memory;
  final String groupId;
  final Color primary;
  final bool isOwner;
  final Color typeColor;
  final double? userLat;
  final double? userLng;
  final VoidCallback onTogglePin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSetLocation;
  /// Live-resolved author avatar URL (from group memberAvatars). If empty,
  /// AvatarWidget falls back to memory.authorAvatar.
  final String liveAuthorAvatar;

  const _MemoryDetailSheet({
    required this.memory,
    required this.groupId,
    required this.primary,
    required this.isOwner,
    required this.typeColor,
    this.userLat,
    this.userLng,
    required this.onTogglePin,
    required this.onEdit,
    required this.onDelete,
    this.onSetLocation,
    this.liveAuthorAvatar = '',
  });

  @override
  State<_MemoryDetailSheet> createState() => _MemoryDetailSheetState();
}

class _MemoryDetailSheetState extends State<_MemoryDetailSheet>
    with SingleTickerProviderStateMixin {
  AudioPlayer? _audioPlayer;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  /// Файлы записи, которые можно положить в галерею (см. memory_media.dart).
  late final List<MediaFile> _files = memoryMediaFiles(widget.memory);

  /// Какой кадр показан крупно. Плёнка под обложкой — переключатель:
  /// нажал кадр, он встал главным, прежний ушёл на его место.
  int _coverIndex = 0;

  @override
  void initState() {
    super.initState();
    // Журнал «уже в галерее» читается с диска: пока он не прочитан, кнопка
    // показала бы все 94 файла как несохранённые.
    SavedMediaLedger.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  /// Схема M3 экрана — тот же язык, что у формы новой записи.
  ColorScheme get _cs => ProfileTheme.themeFor(context.appTheme).colorScheme;

  /// У фотографии и видео кадр становится героем экрана; у книги, музыки,
  /// фильма и заметки такого кадра нет — там контент рисуется внутри листа.
  bool get _hasHero {
    final t = widget.memory.type;
    return t == MemoryType.photo ||
        t == MemoryType.video ||
        t == MemoryType.videoLink;
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    final cs = _cs;
    if (_isMoment) {
      return Theme(
        data: ProfileTheme.data(cs),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.94,
          maxChildSize: 0.96,
          builder: (_, sc) => _momentLayout(memory, cs, sc),
        ),
      );
    }
    return Theme(
      data: ProfileTheme.data(cs),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: _hasHero ? 0.92 : 0.8,
        maxChildSize: 0.96,
        builder: (_, sc) => LayoutBuilder(
          builder: (context, box) {
            final heroHeight = _hasHero ? box.maxHeight * 0.46 : 0.0;
            return ColoredBox(
              color: cs.surface,
              child: Stack(
                children: [
                  if (_hasHero)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: heroHeight + 26,
                      child: RepaintBoundary(
                        child: _buildHero(memory, cs),
                      ),
                    ),
                  Positioned(
                    top: _hasHero ? heroHeight : 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildSheetBody(memory, cs, sc),
                  ),
                  // Кнопки поверх кадра: подложка нужна, чтобы они читались и
                  // на светлой фотографии, и на тёмной.
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _circleOverlay(
                      cs,
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context),
                      glass: _hasHero,
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Row(
                      children: [
                        _typePill(memory, cs, glass: _hasHero),
                        if (_menuActions(memory).isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _circleOverlay(
                            cs,
                            icon: Icons.more_vert_rounded,
                            onTap: () => _showMoreMenu(memory, cs),
                            glass: _hasHero,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildActionBar(memory, cs),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Кадр ──────────────────────────────────────────────────────────────────


  /// Фото-видео пин: у него свой каркас по макету — шапка с автором,
  /// обложка целиком и плёнка остальных кадров. Книге, музыке и фильму он
  /// не подходит: там кадра нет вовсе.
  bool get _isMoment {
    final t = widget.memory.type;
    if (t != MemoryType.photo && t != MemoryType.video) return false;
    return _momentPhotos.isNotEmpty;
  }

  /// Кадры записи в порядке показа.
  List<String> get _momentPhotos {
    final m = widget.memory;
    if (m.imageUrls?.isNotEmpty == true) return m.imageUrls!;
    if (m.imageUrl?.isNotEmpty == true) return [m.imageUrl!];
    return const [];
  }

  String get _myUidHere => PocketBaseService().userId ?? '';

  Widget _momentLayout(Memory memory, ColorScheme cs, ScrollController sc) {
    return ColoredBox(
      color: cs.surface,
      child: Stack(
        children: [
          Column(
            children: [
              _momentBar(memory, cs),
              Expanded(
                child: SingleChildScrollView(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _momentCover(memory, cs),
                      const SizedBox(height: 14),
                      _momentTitle(memory, cs),
                      if (memory.locationName?.isNotEmpty == true ||
                          memory.latitude != null) ...[
                        const SizedBox(height: 12),
                        _placeBlock(memory, cs),
                      ],
                      const SizedBox(height: 12),
                      _momentReactions(memory, cs),
                      const SizedBox(height: 14),
                      RepaintBoundary(
                        child: _CommentsSection(
                          groupId: widget.groupId,
                          memoryId: widget.memory.id,
                          primary: cs.primary,
                        ),
                      ),
                      const _KeyboardPaddingBox(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _momentDock(memory, cs)),
        ],
      ),
    );
  }

  /// Шапка: назад, пилюля с автором и датой, справа связанная группа —
  /// карандаш автору и «⋯». Слова «Воспоминание» тут нет: и так понятно,
  /// что открыто, а место лучше занять тем, кто и когда это снял.
  Widget _momentBar(Memory memory, ColorScheme cs) {
    final total = _momentPhotos.length +
        (memory.videoUrl?.isNotEmpty == true && _momentPhotos.isEmpty ? 1 : 0);
    final sub = '${_fmtDate(memory.createdAt)} · '
        '${total} ${LocaleService.current.photosUnit(total)}';
    Widget btn(IconData icon, VoidCallback onTap,
        {BorderRadius? radius, String? tooltip}) {
      final b = Material(
        color: cs.surfaceContainerHigh,
        borderRadius: radius ?? BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
              width: 48, height: 48, child: Icon(icon, size: 22, color: cs.onSurface)),
        ),
      );
      return tooltip == null ? b : Tooltip(message: tooltip, child: b);
    }

    final canEdit = widget.isOwner;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Row(
        children: [
          btn(Icons.arrow_back_rounded, () => Navigator.pop(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.only(left: 4, right: 14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  AvatarWidget(
                    uid: memory.authorUid,
                    liveUrl: widget.liveAuthorAvatar,
                    fallbackUrl: memory.authorAvatar,
                    name: memory.authorName,
                    size: 40,
                    primary: cs.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          memory.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.onest(
                              size: 14, weight: 700, color: cs.onSurface),
                        ),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.onest(
                              size: 11.5,
                              weight: 500,
                              color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (canEdit) ...[
            btn(
              Icons.edit_outlined,
              () {
                Navigator.pop(context);
                widget.onEdit();
              },
              radius: const BorderRadius.horizontal(
                  left: Radius.circular(24), right: Radius.circular(8)),
              tooltip: LocaleService.current.editMemory,
            ),
            const SizedBox(width: 2),
            btn(
              Icons.more_vert_rounded,
              () => _showMoreMenu(memory, cs),
              radius: const BorderRadius.horizontal(
                  left: Radius.circular(8), right: Radius.circular(24)),
            ),
          ] else
            btn(Icons.more_vert_rounded, () => _showMoreMenu(memory, cs)),
        ],
      ),
    );
  }

  /// Обложка целиком и плёнка остальных кадров под ней.
  Widget _momentCover(Memory memory, ColorScheme cs) {
    final photos = _momentPhotos;
    final idx = _coverIndex.clamp(0, photos.length - 1);
    final hasVideo = memory.videoUrl?.isNotEmpty == true;
    Widget cover = AspectCover(
      url: photos[idx],
      radius: 22,
      maxHeight: 460,
      overlay: hasVideo && idx == 0
          ? const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  color: Colors.white, size: 54),
            )
          : null,
    );
    if (memory.isAdult) cover = _BlurAfterTap(child: cover);

    final others = <int>[
      for (var i = 0; i < photos.length; i++)
        if (i != idx) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openFrameFromDetail(memory, idx),
          child: cover,
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 2),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              itemCount: others.length,
              separatorBuilder: (_, _) => const SizedBox(width: 2),
              itemBuilder: (_, i) => FilmFrame(
                url: photos[others[i]],
                height: 76,
                onTap: () => setState(() => _coverIndex = others[i]),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Название крупно, подпись под ним обычным шрифтом.
  Widget _momentTitle(Memory memory, ColorScheme cs) {
    final title = memory.title?.trim() ?? '';
    final caption = normalizeMemoryCaption(memory.caption)?.trim() ?? '';
    if (title.isEmpty && caption.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.2,
                color: cs.onSurface,
              ),
            ),
          if (caption.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: title.isEmpty ? 0 : 6),
              child: Text(
                caption,
                style: AppFonts.onest(
                    size: 15.5, weight: 400, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  /// Место и время съёмки тёмным блоком — он заметен и не спорит с кадром.
  Widget _placeBlock(Memory memory, ColorScheme cs) {
    final name = memory.locationName?.trim().isNotEmpty == true
        ? memory.locationName!.trim()
        : '${memory.latitude?.toStringAsFixed(2)}, '
            '${memory.longitude?.toStringAsFixed(2)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(Icons.place_rounded, size: 22, color: cs.onInverseSurface),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.onest(
                        size: 15, weight: 700, color: cs.onInverseSurface)),
                Text(_fmtDate(memory.createdAt),
                    style: AppFonts.onest(
                        size: 12.5,
                        weight: 500,
                        color: cs.onInverseSurface.withValues(alpha: 0.85))),
              ],
            ),
          ),
          if (memory.latitude != null && memory.longitude != null)
            Material(
              color: cs.onInverseSurface.withValues(alpha: 0.14),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _showMapsPickerSheet(context, memory.latitude!,
                    memory.longitude!, memory.locationName),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.near_me_rounded,
                      size: 20, color: cs.onInverseSurface),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Именные реакции и вход в комментарии.
  Widget _momentReactions(Memory memory, ColorScheme cs) {
    final theme = context.appTheme;
    final uid = _myUidHere;
    final repo = MemoryRepository();
    final chips = <Widget>[];
    memory.reactions.forEach((who, key) {
      chips.add(ReactionChip(
        uid: who,
        name: who == memory.authorUid ? memory.authorName : '',
        avatarUrl: who == memory.authorUid ? (memory.authorAvatar) : '',
        reactionKey: key,
        theme: theme,
        isMine: who == uid,
        onTap: who == uid
            ? () => repo.setReaction(
                groupId: widget.groupId, memoryId: memory.id, reaction: key)
            : null,
      ));
    });
    return Row(
      children: [
        for (final c in chips) ...[c, const SizedBox(width: 2)],
        if (memory.reactionOf(uid).isEmpty)
          AddReactionButton(
            theme: theme,
            onPick: (key) => repo.setReaction(
                groupId: widget.groupId, memoryId: memory.id, reaction: key),
          ),
        const Spacer(),
        // Комментарии числом: у них счёт осмыслен — их бывает много.
        Material(
          color: theme.bgGradient[0],
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {},
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 18, color: theme.textSecondary),
                  if (memory.commentsCount > 0) ...[
                    const SizedBox(width: 6),
                    Text('${memory.commentsCount}',
                        style: AppFonts.onest(
                            size: 14, weight: 700, color: theme.textPrimary)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Низ экрана: плавающий тулбар с действиями и отдельная кнопка
  /// сохранения — так их разделяет M3 Expressive.
  Widget _momentDock(Memory memory, ColorScheme cs) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final saved = memory.isSavedBy(_myUidHere);
    Widget ib(IconData icon, VoidCallback onTap, {bool active = false}) =>
        Material(
          color: active ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 56,
              child: Icon(icon,
                  size: 24,
                  color: active ? cs.onSecondaryContainer : cs.onSurface),
            ),
          ),
        );
    final repo = MemoryRepository();
    final myReaction = memory.reactionOf(_myUidHere);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + bottom),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 72,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(36),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  ib(
                    myReaction.isEmpty
                        ? Icons.favorite_border_rounded
                        : reactionByKey(myReaction).icon,
                    () => repo.setReaction(
                        groupId: widget.groupId,
                        memoryId: memory.id,
                        reaction: myReaction.isEmpty ? 'heart' : myReaction),
                    active: myReaction.isNotEmpty,
                  ),
                  ib(Icons.reply_rounded, () => _shareFiles(memory)),
                  ib(
                    saved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    () => MemoryRepository()
                        .toggleSaved(groupId: widget.groupId, memoryId: memory.id),
                    active: saved,
                  ),
                  ib(Icons.push_pin_outlined, () => widget.onTogglePin(),
                      active: memory.isPinned),
                ],
              ),
            ),
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(width: 10),
            _saveButton(memory),
          ],
        ],
      ),
    );
  }

  /// Открыть кадр на весь экран из пина.
  void _openFrameFromDetail(Memory memory, int index) {
    final items = [
      for (var i = 0; i < _momentPhotos.length; i++)
        GalleryItem(
          url: _momentPhotos[i],
          videoUrl: i == 0 ? memory.videoUrl : null,
          memoryId: memory.id,
          caption: memory.title ?? memory.caption ?? '',
        ),
    ];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenGallery(
          items: items,
          initialIndex: index,
          memoryOf: (_) => memory,
        ),
        settings: const RouteSettings(name: '/memory_frame'),
      ),
    );
  }

  Widget _buildHero(Memory memory, ColorScheme cs) {
    final url = memory.imageUrl ?? memory.imageUrls?.firstOrNull ?? '';
    if (url.isEmpty) {
      return ColoredBox(
        color: cs.surfaceContainerHigh,
        child: Center(
          child: Icon(memoryTypeIcon(memory.type),
              size: 44, color: cs.onSurfaceVariant),
        ),
      );
    }
    return GestureDetector(
      onTap: () => _openHeroGallery(memory),
      child: Stack(
        fit: StackFit.expand,
        children: [
          StorageImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => ColoredBox(color: cs.surfaceContainerHigh),
            errorWidget: (_, __, ___) => ColoredBox(
              color: cs.surfaceContainerHigh,
              child: Icon(Icons.image_not_supported_rounded,
                  size: 40, color: cs.onSurfaceVariant),
            ),
          ),
          if (memory.type == MemoryType.video ||
              memory.type == MemoryType.videoLink)
            const Center(
              child: Icon(Icons.play_circle_filled_rounded,
                  color: Colors.white, size: 60),
            ),
          // Счётчик кадров: сколько фотографий в записи.
          if ((memory.imageUrls?.length ?? 0) > 1)
            Positioned(
              right: 14,
              bottom: 40,
              child: _glassPill(
                cs,
                LocaleService.current.itemsShort(memory.imageUrls!.length),
              ),
            ),
        ],
      ),
    );
  }

  /// Полноэкранный просмотр кадра — тот же, что открывается из ленты.
  void _openHeroGallery(Memory memory) {
    final photos = <String>[
      if (memory.imageUrls?.isNotEmpty == true)
        ...memory.imageUrls!
      else if (memory.imageUrl?.isNotEmpty == true)
        memory.imageUrl!,
    ];
    if (photos.isEmpty) return;
    Navigator.of(context).push<String>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => FullscreenGallery(
          items: photos
              .map((url) => GalleryItem(url: url, memoryId: memory.id))
              .toList(),
          initialIndex: 0,
          memoryOf: (_) => memory,
        ),
      ),
    );
  }

  Widget _circleOverlay(
    ColorScheme cs, {
    required IconData icon,
    required VoidCallback onTap,
    required bool glass,
  }) {
    return Material(
      color: glass
          ? cs.inverseSurface.withValues(alpha: 0.55)
          : cs.surfaceContainerHigh,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon,
              size: 22,
              color: glass ? cs.onInverseSurface : cs.onSurface),
        ),
      ),
    );
  }

  Widget _typePill(Memory memory, ColorScheme cs, {required bool glass}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 13, 8),
      decoration: BoxDecoration(
        color: glass
            ? cs.inverseSurface.withValues(alpha: 0.55)
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(memoryTypeIcon(memory.type),
              size: 16,
              color: glass ? cs.onInverseSurface : cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            LocaleService.current.memoryTypeName(memory.type.name),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: glass ? cs.onInverseSurface : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassPill(ColorScheme cs, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: cs.inverseSurface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onInverseSurface,
          ),
        ),
      );

  // ── Лист ──────────────────────────────────────────────────────────────────

  Widget _buildSheetBody(Memory memory, ColorScheme cs, ScrollController sc) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: _hasHero
            ? const BorderRadius.vertical(top: Radius.circular(28))
            : BorderRadius.zero,
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: RepaintBoundary(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: SingleChildScrollView(
                    controller: sc,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAuthorRow(memory, cs),
                        if (memory.title?.isNotEmpty == true) ...[
                          const SizedBox(height: 16),
                          Text(
                            memory.title!,
                            style: TextStyle(
                              fontFamily: ProfileTheme.displayFont,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.2,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                        _buildCaption(memory),
                        // У фото кадр уже показан героем; остальные типы рисуют
                        // свой контент здесь — плеер, обложку, карту.
                        if (!_hasHero) ...[
                          const SizedBox(height: 16),
                          RepaintBoundary(
                            child: _buildMedia(memory, cs.primary),
                          ),
                        ],
                        _buildMetaChips(memory, cs),
                        const SizedBox(height: 20),
                        RepaintBoundary(
                          child: _CommentsSection(
                            groupId: widget.groupId,
                            memoryId: widget.memory.id,
                            primary: cs.primary,
                          ),
                        ),
                        const _KeyboardPaddingBox(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorRow(Memory memory, ColorScheme cs) {
    return Row(
      children: [
        AvatarWidget(
          uid: memory.authorUid,
          liveUrl: widget.liveAuthorAvatar,
          fallbackUrl: memory.authorAvatar,
          name: memory.authorName,
          size: 40,
          primary: cs.primary,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                memory.authorName,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              Text(
                _fmtDate(memory.createdAt),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Место и «закреплено» — чипами, как в форме записи.
  Widget _buildMetaChips(Memory memory, ColorScheme cs) {
    final place = (memory.locationName?.isNotEmpty ?? false)
        ? memory.locationName!
        : (memory.latitude != null && memory.longitude != null
            ? '${memory.latitude!.toStringAsFixed(3)}, ${memory.longitude!.toStringAsFixed(3)}'
            : null);
    if (place == null && !memory.isPinned) return const SizedBox.shrink();
    // Расстояние до места жило отдельной строкой с цветной пилюлей; теперь оно
    // просто дописывается к чипу — строка ради одной цифры экран не стоила.
    String? placeLabel = place;
    if (place != null &&
        memory.latitude != null &&
        memory.longitude != null &&
        widget.userLat != null &&
        widget.userLng != null) {
      final meters = Geolocator.distanceBetween(
        widget.userLat!, widget.userLng!,
        memory.latitude!, memory.longitude!,
      );
      placeLabel = '$place · ${LocaleService.current.distanceLabel(meters)}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (place != null)
            _metaChip(
              cs: cs,
              icon: Icons.location_on_rounded,
              label: placeLabel!,
              accent: true,
            ),
          if (memory.isPinned)
            _metaChip(
              cs: cs,
              icon: Icons.push_pin_rounded,
              label: LocaleService.current.pinned,
              accent: false,
            ),
        ],
      ),
    );
  }

  Widget _metaChip({
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required bool accent,
    VoidCallback? onTap,
  }) {
    final bg = accent ? cs.primaryContainer : cs.secondaryContainer;
    final fg = accent ? cs.onPrimaryContainer : cs.onSecondaryContainer;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Действия ──────────────────────────────────────────────────────────────

  /// Панель внизу: «Закрепить» таблеткой и разделённая кнопка сохранения.
  /// Удаление сюда не входит — оно живёт в меню: раньше оно стояло вплотную к
  /// «Редактировать» и отличалось только цветом слова. «Изменить» остаётся
  /// в панели только на широком экране: рядом с разделённой кнопкой на 360 dp
  /// ему нет места, а в меню «три точки» он есть всегда.
  Widget _buildActionBar(Memory memory, ColorScheme cs) {
    final media = MediaQuery.of(context);
    final link = memoryExternalLink(memory);
    return Container(
      decoration: BoxDecoration(color: cs.surfaceContainerLow),
      padding: EdgeInsets.fromLTRB(16, 12, 16, media.padding.bottom + 16),
      child: LayoutBuilder(builder: (context, box) {
        final roomForEdit = widget.isOwner && box.maxWidth >= 400;
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onTogglePin();
                },
                icon: Icon(
                  memory.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  size: 21,
                ),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    memory.isPinned
                        ? LocaleService.current.unpinMemory
                        : LocaleService.current.pinMemory,
                    maxLines: 1,
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
            if (_files.isNotEmpty) ...[
              const SizedBox(width: 10),
              _saveButton(memory),
            ] else if (link != null) ...[
              const SizedBox(width: 10),
              _roundAction(
                cs,
                icon: Icons.open_in_new_rounded,
                tooltip: trKey('menuOpenLink'),
                onTap: () => safeLaunchUrl(Uri.parse(link),
                    mode: LaunchMode.externalApplication),
              ),
            ],
            if (roomForEdit) ...[
              const SizedBox(width: 10),
              _roundAction(
                cs,
                icon: Icons.edit_rounded,
                tooltip: LocaleService.current.editMemory,
                onTap: () {
                  Navigator.pop(context);
                  widget.onEdit();
                },
              ),
            ],
          ],
        );
      }),
    );
  }

  /// Разделённая кнопка: слушает очередь и журнал, поэтому ход сохранения и
  /// «уже в галерее» видны сразу, даже если сохранение начато из меню.
  Widget _saveButton(Memory memory) {
    final queue = MediaSaveQueue.instance;
    final ledger = SavedMediaLedger.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([queue, ledger]),
      builder: (context, _) {
        final job = queue.activeFor(memory.id);
        final progress = queue.progressFor(memory.id);
        return SaveSplitButton(
          state: saveButtonState(
            total: _files.length,
            saved: ledger.countSaved(_files),
            done: progress?.$1,
            jobTotal: progress?.$2,
          ),
          onSaveAll: () => _saveFiles(memory, _files),
          onChoose: () => _chooseWhatToSave(memory),
          onCancel: () {
            if (job != null) queue.cancel(job.id);
          },
        );
      },
    );
  }

  Future<void> _saveFiles(Memory memory, List<MediaFile> files) async {
    if (files.isEmpty) return;
    await saveToGallery(
      context,
      title: memorySaveTitle(memory),
      items: [for (final f in files) SaveItem.of(memory, f)],
      adult: memory.isAdult,
    );
  }

  Future<void> _chooseWhatToSave(Memory memory) async {
    final choice = await showSaveOptionsSheet(
      context,
      scheme: _cs,
      files: _files,
      title: memorySaveTitle(memory),
      takenAt: memory.createdAt,
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case SaveChoice.all:
        await _saveFiles(memory, _files);
      case SaveChoice.photos:
        await _saveFiles(
            memory, [for (final f in _files) if (f.kind == SaveKind.photo) f]);
      case SaveChoice.videos:
        await _saveFiles(
            memory, [for (final f in _files) if (f.kind == SaveKind.video) f]);
      case SaveChoice.cover:
        await _saveFiles(memory, [
          _files.firstWhere((f) => f.kind == SaveKind.photo,
              orElse: () => _files.first),
        ]);
      case SaveChoice.pick:
        await _pickFrames(memory);
    }
  }

  Future<void> _pickFrames(Memory memory) async {
    final picked = await showFramePicker(context, files: _files, scheme: _cs);
    if (picked == null || picked.files.isEmpty || !mounted) return;
    if (picked.share) {
      await shareMemoryMedia(
        context,
        files: picked.files,
        takenAt: memory.createdAt,
      );
    } else {
      await _saveFiles(memory, picked.files);
    }
  }

  /// «Отправить»: до десяти файлов уходят сразу, больше — через выбор кадров,
  /// иначе в мессенджер поехали бы все 94 и 35 мегабайт разом.
  Future<void> _shareFiles(Memory memory) async {
    if (_files.length > 10) {
      await _pickFrames(memory);
      return;
    }
    final caption = memory.caption?.trim();
    await shareMemoryMedia(
      context,
      files: _files,
      takenAt: memory.createdAt,
      text: (caption == null || caption.isEmpty) ? null : caption,
    );
  }

  Widget _roundAction(
    ColorScheme cs, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: cs.surfaceContainerHigh,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 54,
            height: 54,
            child: Icon(icon, size: 22, color: cs.onSurface),
          ),
        ),
      ),
    );
  }

  bool get _canSetPlace {
    final m = widget.memory;
    return widget.onSetLocation != null &&
        m.type != MemoryType.location &&
        m.latitude == null &&
        m.longitude == null &&
        (m.locationName?.isEmpty ?? true);
  }

  List<MemoryMenuAction> _menuActions(Memory memory) => memoryMenuActions(
        memory,
        isOwner: widget.isOwner,
        canSetPlace: _canSetPlace,
      );

  /// Меню «три точки». До 19.09.2026 в нём было два пункта, и у чужой записи
  /// с отмеченным местом оно не открывалось вовсе — «декорация». Теперь пункты
  /// считает [memoryMenuActions], а кнопку без пунктов лист не показывает.
  void _showMoreMenu(Memory memory, ColorScheme cs) {
    final actions = _menuActions(memory);
    if (actions.isEmpty) return;
    final summary = summarizeMedia(_files);
    final counts = [
      if (summary.photos > 0)
        trKey('saveCountPhotos').replaceAll('{n}', '${summary.photos}'),
      if (summary.videos > 0)
        trKey('saveCountVideos').replaceAll('{n}', '${summary.videos}'),
      if (summary.audio > 0)
        trKey('saveCountAudio').replaceAll('{n}', '${summary.audio}'),
      if (summary.total > 0)
        trKey('saveApproxMb').replaceAll('{n}', '${summary.megabytes}'),
    ].join(' · ');
    final thumb = _files.isNotEmpty ? (_files.first.thumb ?? _files.first.ref) : null;

    showAppSheet<void>(
      context,
      background: cs.surfaceContainerLow,
      builder: (ctx) {
        void close() => Navigator.pop(ctx);
        Widget tile(MemoryMenuAction a) {
          switch (a) {
            case MemoryMenuAction.saveAll:
              return _menuTile(cs,
                  icon: Icons.download_rounded,
                  title: trKey('menuSaveAll'),
                  sub: counts,
                  accent: true,
                  trailing: '${_files.length}', onTap: () {
                close();
                _saveFiles(memory, _files);
              });
            case MemoryMenuAction.pick:
              return _menuTile(cs,
                  icon: Icons.checklist_rounded,
                  title: trKey('saveOptPick'),
                  sub: trKey('menuPickSub'), onTap: () {
                close();
                _pickFrames(memory);
              });
            case MemoryMenuAction.share:
              return _menuTile(cs,
                  icon: Icons.ios_share_rounded,
                  title: trKey('menuShare'),
                  sub: trKey('menuShareSub'), onTap: () {
                close();
                _shareFiles(memory);
              });
            case MemoryMenuAction.openLink:
              return _menuTile(cs,
                  icon: Icons.open_in_new_rounded,
                  title: trKey('menuOpenLink'), onTap: () {
                close();
                safeLaunchUrl(Uri.parse(memoryExternalLink(memory)!),
                    mode: LaunchMode.externalApplication);
              });
            case MemoryMenuAction.copyCaption:
              final caption = memory.caption!.trim();
              return _menuTile(cs,
                  icon: Icons.content_copy_rounded,
                  title: trKey('menuCopyCaption'),
                  sub: caption.length > 40
                      ? '«${caption.substring(0, 39)}…»'
                      : '«$caption»', onTap: () {
                close();
                Clipboard.setData(ClipboardData(text: caption));
                showFloatingNote(context, trKey('menuCaptionCopied'));
              });
            case MemoryMenuAction.openMap:
              return _menuTile(cs,
                  icon: Icons.map_rounded,
                  title: trKey('menuOpenMap'),
                  sub: memory.locationName ?? '', onTap: () {
                close();
                _showMapsPickerSheet(context, memory.latitude!,
                    memory.longitude!, memory.locationName);
              });
            case MemoryMenuAction.setPlace:
              return _menuTile(cs,
                  icon: Icons.add_location_alt_rounded,
                  title: LocaleService.current.selectLocation, onTap: () {
                close();
                Navigator.pop(context);
                widget.onSetLocation!();
              });
            case MemoryMenuAction.edit:
              return _menuTile(cs,
                  icon: Icons.edit_rounded,
                  title: LocaleService.current.editMemory, onTap: () {
                close();
                Navigator.pop(context);
                widget.onEdit();
              });
            case MemoryMenuAction.delete:
              return _menuTile(cs,
                  icon: Icons.delete_outline_rounded,
                  title: LocaleService.current.deleteMemory,
                  danger: true, onTap: () {
                close();
                Navigator.pop(context);
                widget.onDelete();
              });
          }
        }

        final tiles = [for (final a in actions) tile(a)];
        return Theme(
          data: ProfileTheme.data(cs),
          child: SheetScaffold(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (thumb != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: StorageImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              memCacheWidth: 160,
                              errorWidget: (_, _, _) =>
                                  ColoredBox(color: cs.surfaceContainerHigh),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              memorySaveTitle(memory),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Unbounded',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              '${memory.authorName} · ${memoryDateLabel(memory.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 12.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(i == 0 ? 18 : 6),
                        bottom: Radius.circular(i == tiles.length - 1 ? 18 : 6),
                      ),
                      child: tiles[i],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _menuTile(
    ColorScheme cs, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String sub = '',
    String? trailing,
    bool accent = false,
    bool danger = false,
  }) {
    final chipBg = danger
        ? cs.errorContainer
        : accent
            ? cs.primary
            : cs.secondaryContainer;
    final chipFg = danger
        ? cs.onErrorContainer
        : accent
            ? cs.onPrimary
            : cs.onSecondaryContainer;
    return Material(
      color: accent ? cs.primaryContainer : cs.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 16, 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: chipBg, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: chipFg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: danger ? cs.error : cs.onSurface,
                      ),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                Text(
                  trailing,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── MEDIA ────────────────────────────────────────────────────────────────────
  Widget _buildMedia(Memory memory, Color p) {
    switch (memory.type) {
      case MemoryType.photo:
        // Смешанный пин: фото + видео — показываем оба блока.
        if (memory.videoUrl?.isNotEmpty == true) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPhotoMedia(memory),
              const SizedBox(height: 12),
              _buildVideoMedia(memory, p),
            ],
          );
        }
        return _buildPhotoMedia(memory);
      case MemoryType.video:
        return _buildVideoMedia(memory, p);
      case MemoryType.location:
        return _buildLocationMedia(memory, p);
      case MemoryType.music:
        return _MusicPlayerWidget(
          memory: memory,
          player: _audioPlayer,
          onPlayerCreated: (pl) => setState(() => _audioPlayer = pl),
          primary: p,
          typeColor: widget.typeColor,
        );
      case MemoryType.text:
        return _buildTextMedia(memory, p);
      case MemoryType.videoLink:
        return _buildVideoLinkMedia(memory, p);
      case MemoryType.book:
        return _buildBookMedia(memory, p);
      case MemoryType.movie:
        return _buildMovieMedia(memory, p);
    }
  }

  Widget _buildPhotoMedia(Memory memory) {
    final allPhotos = <String>[
      if (memory.imageUrls?.isNotEmpty == true)
        ...memory.imageUrls!
      else if (memory.imageUrl?.isNotEmpty == true)
        memory.imageUrl!,
    ];
    if (allPhotos.isEmpty) return _noImgBox(200);
    void openGallery(int i) {
      final galleryItems = allPhotos
          .map((url) => GalleryItem(url: url, memoryId: memory.id))
          .toList();
      Navigator.of(context).push<String>(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black,
          pageBuilder: (_, __, ___) => FullscreenGallery(
            items: galleryItems,
            initialIndex: i,
            memoryOf: (_) => memory,
          ),
        ),
      );
    }

    Widget photoWidget;
    if (allPhotos.length == 1) {
      photoWidget = GestureDetector(
        onTap: () => openGallery(0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: StorageImage(
              imageUrl: allPhotos.first,
              fit: BoxFit.cover,
              memCacheWidth: 800,
              memCacheHeight: 800,
              errorWidget: (_, __, ___) => _noImgBox(200),
            ),
          ),
        ),
      );
    } else {
      photoWidget = _buildPhotoGrid(allPhotos, openGallery);
    }

    if (memory.isAdult) {
      return _BlurAfterTap(child: photoWidget);
    }
    return photoWidget;
  }

  // ── SMART PHOTO GRID ─────────────────────────────────────────────────────────
  // Adapts layout to photo count: 1→square, 2→side-by-side, 3→big+two,
  // 4→2×2, 5→2+3, 6→3+3, 7-8→3+3 with +N badge, 9→3×3, 10+→3×3 with badge.
  Widget _buildPhotoGrid(List<String> photos, void Function(int) onTap) {
    final n = photos.length;
    const gap = 3.0;
    const innerR = BorderRadius.all(Radius.circular(8));
    const outerR = BorderRadius.all(Radius.circular(18));

    Widget cell(int index, {double? aspect, int? extraCount}) {
      return GestureDetector(
        onTap: () => onTap(index),
        child: ClipRRect(
          borderRadius: innerR,
          child: AspectRatio(
            aspectRatio: aspect ?? 1.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                StorageImage(
                  imageUrl: photos[index],
                  fit: BoxFit.cover,
                  memCacheWidth: 600,
                  memCacheHeight: 600,
                  fadeInDuration: const Duration(milliseconds: 180),
                  errorWidget: (_, __, ___) => Container(
                    color: context.appTheme.surfaceMuted,
                    child: Icon(Icons.image_not_supported_rounded,
                        color: context.appTheme.textMuted, size: 28),
                  ),
                ),
                if (extraCount != null && extraCount > 0)
                  Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: Text(
                      '+$extraCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget photoRow(List<int> indices, {int? moreCount}) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int k = 0; k < indices.length; k++) ...[
            if (k > 0) const SizedBox(width: gap),
            Expanded(
              child: cell(
                indices[k],
                extraCount: k == indices.length - 1 ? moreCount : null,
              ),
            ),
          ],
        ],
      );
    }

    late Widget body;
    if (n == 1) {
      body = cell(0, aspect: 1.0);
    } else if (n == 2) {
      body = photoRow([0, 1]);
    } else if (n == 3) {
      body = Column(
        children: [
          cell(0, aspect: 1.0),
          const SizedBox(height: gap),
          photoRow([1, 2]),
        ],
      );
    } else if (n == 4) {
      body = Column(
        children: [
          photoRow([0, 1]),
          const SizedBox(height: gap),
          photoRow([2, 3]),
        ],
      );
    } else if (n == 5) {
      body = Column(
        children: [
          photoRow([0, 1]),
          const SizedBox(height: gap),
          photoRow([2, 3, 4]),
        ],
      );
    } else if (n == 6) {
      body = Column(
        children: [
          photoRow([0, 1, 2]),
          const SizedBox(height: gap),
          photoRow([3, 4, 5]),
        ],
      );
    } else if (n <= 8) {
      body = Column(
        children: [
          photoRow([0, 1, 2]),
          const SizedBox(height: gap),
          photoRow([3, 4, 5], moreCount: n - 6),
        ],
      );
    } else {
      // 9+: 3×3, last cell shows +N if more than 9
      body = Column(
        children: [
          photoRow([0, 1, 2]),
          const SizedBox(height: gap),
          photoRow([3, 4, 5]),
          const SizedBox(height: gap),
          photoRow([6, 7, 8], moreCount: n > 9 ? n - 9 : null),
        ],
      );
    }

    return ClipRRect(
      borderRadius: outerR,
      child: body,
    );
  }

  Widget _buildVideoMedia(Memory memory, Color p) {
    final hasThumb = memory.imageUrl?.isNotEmpty == true;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          if (hasThumb)
            StorageImage(
              imageUrl: memory.imageUrl!,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
            )
          else
            Container(
                height: 220,
                color: context.appTheme.isDark
                    ? context.appTheme.surfaceMuted
                    : Colors.grey.shade900),
          Container(
            height: 220,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.1),
                  Colors.black.withOpacity(0.45),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 220,
            width: double.infinity,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  final url = memory.videoUrl;
                  if (url != null && url.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InAppVideoPlayerPage(
                          url: url,
                          title: memory.title,
                        ),
                        settings: const RouteSettings(name: '/video_player'),
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.play_arrow_rounded, size: 42, color: p),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    LocaleService.current.videoBadge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoLinkMedia(Memory memory, Color p) {
    final platform = _MemoryLaneScreenState._detectVideoPlatform(
      memory.videoUrl ?? '',
    );
    final platformColor = platform['color'] as Color;
    final platformName = platform['name'] as String;
    final hasThumb = memory.imageUrl?.isNotEmpty == true;

    return Container(
      decoration: BoxDecoration(
        color: platformColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: platformColor.withOpacity(0.18), width: 1),
      ),
      child: Column(
        children: [
          // Thumbnail strip
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasThumb)
                    StorageImage(
                      imageUrl: memory.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          _buildThumbFallback(platformColor, platformName),
                    )
                  else
                    _buildThumbFallback(platformColor, platformName),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.55),
                        ],
                      ),
                    ),
                  ),
                  // Play button
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        final url = memory.videoUrl;
                        if (url != null && url.isNotEmpty) {
                          safeLaunchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 42,
                          color: platformColor,
                        ),
                      ),
                    ),
                  ),
                  // Platform badge
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _MemoryLaneScreenState._videoPlatformIcon(
                              platformName,
                            ),
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            platformName.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom row: author + open button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                if (memory.musicArtist?.isNotEmpty == true)
                  Expanded(
                    child: Text(
                      memory.musicArtist!,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                ElevatedButton.icon(
                  onPressed: () {
                    final url = memory.videoUrl;
                    if (url != null && url.isNotEmpty) {
                      safeLaunchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                  label: Text(
                    LocaleService.current.openIn(platformName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: platformColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbFallback(Color platformColor, String platformName) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            platformColor.withOpacity(0.75),
            platformColor.withOpacity(0.45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_circle_outline_rounded,
              color: Colors.white.withOpacity(0.9),
              size: 52,
            ),
            const SizedBox(height: 6),
            Text(
              platformName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationMedia(Memory memory, Color p) {
    final hasCoords = memory.latitude != null && memory.longitude != null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.withOpacity(0.07), p.withOpacity(0.02)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.withOpacity(0.18), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [p, p.withOpacity(0.75)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memory.locationName ??
                          LocaleService.current.unknownLocation,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: context.appTheme.textPrimary,
                      ),
                    ),
                    if (memory.latitude != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${memory.latitude!.toStringAsFixed(5)}, '
                        '${memory.longitude?.toStringAsFixed(5) ?? ""}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (hasCoords) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showMapsPickerSheet(
                  context,
                  memory.latitude!,
                  memory.longitude!,
                  memory.locationName,
                ),
                icon: const Icon(Icons.map_rounded, size: 18),
                label: Text(LocaleService.current.openInGoogleMaps),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextMedia(Memory memory, Color p) {
    final text = memory.caption ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.withOpacity(0.07), p.withOpacity(0.02)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.withOpacity(0.15), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: p.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.format_quote_rounded, color: p, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                LocaleService.current.noteBadge,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: p,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SpoilerRichText(
            text: text,
            style: TextStyle(
              fontSize: 16,
              color: context.appTheme.textPrimary,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }

  // ── BOOK MEDIA (full detail card with 3D cover) ──────────────────────────────
  Widget _buildBookMedia(Memory memory, Color p) {
    final title = memory.title?.isNotEmpty == true
        ? memory.title!
        : LocaleService.current.books;
    final author = memory.bookAuthor ?? '';
    final hasYear = memory.bookYear?.isNotEmpty == true;
    final hasPublisher = memory.bookPublisher?.isNotEmpty == true;
    final hasInfo = memory.bookInfoUrl?.isNotEmpty == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.withOpacity(0.07), p.withOpacity(0.02)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.withOpacity(0.15), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Badge ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: p.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.menu_book_rounded, color: p, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                LocaleService.current.books.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: p,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── 3D cover + meta side by side ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniBookCover(
                accent: p,
                coverUrl: memory.bookCoverUrl,
                title: title,
                author: author,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: context.appTheme.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        author,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (hasYear || hasPublisher)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (hasYear)
                            _detailChip(
                              Icons.calendar_today_rounded,
                              memory.bookYear!,
                              p,
                            ),
                          if (hasPublisher)
                            _detailChip(
                              Icons.business_rounded,
                              memory.bookPublisher!,
                              p,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          // ── Rating ──
          if (memory.rating != null) ...[
            const SizedBox(height: 16),
            _ratingRow(memory.rating!),
          ],
          // ── Review (caption) ──
          if (memory.caption?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            _reviewHeader(p),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.appTheme.cardSurface.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.withOpacity(0.10)),
              ),
              child: _SpoilerRichText(
                text: memory.caption!,
                style: TextStyle(
                  fontSize: 14.5,
                  color: context.appTheme.textPrimary,
                  height: 1.55,
                ),
              ),
            ),
          ],
          // ── "Read more" link ──
          if (hasInfo) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => safeLaunchUrl(
                  Uri.parse(memory.bookInfoUrl!),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  LocaleService.current.bookReadMore,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ratingRow(int rating) {
    return Row(
      children: [
        Text(
          LocaleService.current.yourRating,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.appTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        RatingBadge(rating: rating, fontSize: 14),
      ],
    );
  }

  Widget _reviewHeader(Color p) {
    return Row(
      children: [
        Icon(Icons.rate_review_rounded, size: 14, color: p),
        const SizedBox(width: 6),
        Text(
          LocaleService.current.yourReview.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: p,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  // ── MOVIE / SERIES DETAIL ──
  Widget _buildMovieMedia(Memory memory, Color p) {
    final s = LocaleService.current;
    final isRu = LocaleService.instance.isRussian;
    final title = memory.title?.isNotEmpty == true ? memory.title! : s.movies;
    final original = memory.movieOriginalTitle ?? '';
    final hasOriginal = original.isNotEmpty && original != title;
    final hasYear = memory.movieYear?.isNotEmpty == true;
    final hasGenres = memory.movieGenres?.isNotEmpty == true;
    final hasCountry = memory.movieCountry?.isNotEmpty == true;
    final hasKp = memory.movieRatingKp?.isNotEmpty == true;
    final hasInfo = memory.movieInfoUrl?.isNotEmpty == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.withOpacity(0.07), p.withOpacity(0.02)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.withOpacity(0.15), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Badge ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: p.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.local_movies_rounded, color: p, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                movieKindLabel(memory.movieKind, isRu: isRu).toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: p,
                  letterSpacing: 1.2,
                ),
              ),
              if (hasKp) ...[
                const Spacer(),
                Icon(Icons.star_rounded, size: 15, color: Colors.amber.shade600),
                const SizedBox(width: 3),
                Text(
                  LocaleService.current.kpRating(memory.movieRatingKp!),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.amber.shade800,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // ── Poster + meta ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniMoviePoster(
                accent: p,
                posterUrl: memory.moviePosterUrl,
                title: title,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: context.appTheme.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    if (hasOriginal) ...[
                      const SizedBox(height: 6),
                      Text(
                        original,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (hasYear || hasGenres || hasCountry)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (hasYear)
                            _detailChip(
                              Icons.calendar_today_rounded,
                              memory.movieYear!,
                              p,
                            ),
                          if (hasGenres)
                            _detailChip(
                              Icons.theaters_rounded,
                              memory.movieGenres!,
                              p,
                            ),
                          if (hasCountry)
                            _detailChip(
                              Icons.public_rounded,
                              memory.movieCountry!,
                              p,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          // ── Rating ──
          if (memory.rating != null) ...[
            const SizedBox(height: 16),
            _ratingRow(memory.rating!),
          ],
          // ── Review (caption) ──
          if (memory.caption?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            _reviewHeader(p),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.appTheme.cardSurface.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.withOpacity(0.10)),
              ),
              child: _SpoilerRichText(
                text: memory.caption!,
                style: TextStyle(
                  fontSize: 14.5,
                  color: context.appTheme.textPrimary,
                  height: 1.55,
                ),
              ),
            ),
          ],
          // ── Open on Kinopoisk ──
          if (hasInfo) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => safeLaunchUrl(
                  Uri.parse(memory.movieInfoUrl!),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  s.movieReadMore,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailChip(IconData icon, String label, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _showMapsPickerSheet(
    BuildContext context,
    double lat,
    double lng,
    String? label,
  ) async {
    final t = context.appTheme;
    final encodedLabel = label != null ? Uri.encodeComponent(label) : '';

    final apps = [
      (
        name: 'Google Maps',
        icon: Icons.map_rounded,
        color: const Color(0xFF4285F4),
        url: 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      ),
      (
        name: 'Яндекс Карты',
        icon: Icons.directions_rounded,
        color: const Color(0xFFFC3F1D),
        url: 'yandexmaps://maps.yandex.ru/?rtext=~$lat,$lng&rtt=auto',
      ),
      (
        name: '2GIS',
        icon: Icons.location_city_rounded,
        color: const Color(0xFF00AF43),
        url: 'dgis://2gis.ru/routeSearch/rsType/car/to/$lng,$lat',
      ),
      (
        name: 'Waze',
        icon: Icons.navigation_rounded,
        color: const Color(0xFF09D3AC),
        url: 'https://waze.com/ul?ll=$lat,$lng&navigate=yes',
      ),
      (
        name: 'Apple Maps',
        icon: Icons.map_outlined,
        color: const Color(0xFF007AFF),
        url: 'https://maps.apple.com/?daddr=$lat,$lng&q=$encodedLabel',
      ),
    ];

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: t.cardSurface,
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: t.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_rounded,
                          size: 16, color: t.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ...apps.map((app) => _MapAppTile(
                    name: app.name,
                    icon: app.icon,
                    color: app.color,
                    url: app.url,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // ── CAPTION ──────────────────────────────────────────────────────────────────
  Widget _buildCaption(Memory memory) {
    if (memory.type == MemoryType.text) return const SizedBox.shrink();
    final caption = memory.caption;
    if (caption == null || caption.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        caption,
        style: TextStyle(
          fontSize: 15.5,
          color: context.appTheme.textPrimary,
          height: 1.55,
        ),
      ),
    );
  }

  Widget _noImgBox(double h) => Container(
    height: h,
    decoration: BoxDecoration(
      color: context.appTheme.surfaceMuted,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Center(
      child: Icon(
        Icons.image_not_supported_rounded,
        color: context.appTheme.textMuted,
        size: 48,
      ),
    ),
  );

  /// Дата записи по-русски: «Сегодня, 0:03», «Вчера, 21:40», «12 мая, 23:40».
  /// Раньше здесь стоял английский формат «Jul 29, 2026 at 00:03» — он не
  /// переводился и не совпадал с лентой.
  static String _fmtDate(DateTime dt) {
    final s = LocaleService.current;
    final now = DateTime.now();
    final hh = dt.hour.toString();
    final mm = dt.minute.toString().padLeft(2, '0');
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return '${s.todayLabel}, $hh:$mm';
    if (diff == 1) return '${s.yesterday}, $hh:$mm';
    final months = s.shortMonths;
    final date = '${dt.day} ${months[dt.month - 1]}';
    return dt.year == now.year
        ? '$date, $hh:$mm'
        : '$date ${dt.year}, $hh:$mm';
  }

}

// ══════════════════════════════════════════════════════
//  Comments Section Widget
// ══════════════════════════════════════════════════════

class _CommentsSection extends StatefulWidget {
  final String groupId;
  final String memoryId;
  final Color primary;

  const _CommentsSection({
    required this.groupId,
    required this.memoryId,
    required this.primary,
  });

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final TextEditingController _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      // Rate-limit раньше жил внутри FirebaseService.addComment; репозиторий PB
      // его не делает, поэтому проверяем здесь (бросает RateLimitException ниже).
      await RateLimiterService().checkAndRecordComment();
      await MemoryRepository().addComment(
        groupId: widget.groupId,
        memoryId: widget.memoryId,
        text: text,
      );
      _ctrl.clear();
    } on RateLimitException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 18,
              color: t.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              LocaleService.current.comments,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Comment list (real-time)
        StableStreamBuilder<List<MemoryComment>>(
          create: () =>
              MemoryRepository().watchComments(widget.groupId, widget.memoryId),
          keys: [widget.groupId, widget.memoryId],
          builder: (context, snap) {
            final comments = snap.data ?? [];
            if (comments.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  LocaleService.current.noCommentsYet,
                  style: TextStyle(
                    fontSize: 13,
                    color: t.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              );
            }
            // Column is faster than shrinkWrap ListView inside a ScrollView:
            // shrinkWrap forces a full second-pass layout on every rebuild.
            return Column(
              children: [
                for (int i = 0; i < comments.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _commentBubble(comments[i]),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        // Input field
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: LocaleService.current.writeAComment,
                  hintStyle: TextStyle(color: t.textMuted),
                  filled: true,
                  fillColor: t.surfaceMuted,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: t.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: t.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: widget.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.primary,
                  shape: BoxShape.circle,
                ),
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _commentBubble(MemoryComment comment) {
    final isMe = comment.authorUid == PocketBaseService().userId;
    final t = context.appTheme;
    return GestureDetector(
      onLongPress: isMe ? () => _confirmDeleteComment(comment) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarWidget(
            uid: comment.authorUid,
            fallbackUrl: comment.authorAvatar,
            name: comment.authorName,
            size: 28,
            primary: widget.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe
                    ? widget.primary.withOpacity(0.06)
                    : t.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isMe
                      ? widget.primary.withOpacity(0.15)
                      : t.divider,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        comment.authorName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isMe ? widget.primary : t.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _timeAgo(comment.createdAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    comment.text,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: t.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteComment(MemoryComment comment) {
    AppDialog.confirm(
      context,
      title: LocaleService.current.deleteCommentQuestion,
      message: LocaleService.current.actionCannotBeUndone,
      confirmLabel: LocaleService.current.delete,
      destructive: true,
      icon: Icons.delete_outline_rounded,
    ).then((ok) {
      if (ok) MemoryRepository().deleteComment(comment.id);
    });
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }
}

// ══════════════════════════════════════════════════════
//  GalleryItem — a single photo or video entry
// ══════════════════════════════════════════════════════
class GalleryItem {
  final String url;       // photo URL or video thumbnail
  final String? videoUrl; // non-null for video items
  final String memoryId;
  final String? caption;

  const GalleryItem({
    required this.url,
    this.videoUrl,
    required this.memoryId,
    this.caption,
  });

  bool get isVideo => videoUrl != null;
}

