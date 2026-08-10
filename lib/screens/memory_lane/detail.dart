part of '../memory_lane_screen.dart';

class _MemoryDetailSheet extends StatefulWidget {
  final Memory memory;
  final String groupId;
  final Color primary;
  final bool isOwner;
  final bool canDownload;
  final Color typeColor;
  final double? userLat;
  final double? userLng;
  final VoidCallback onTogglePin;
  final VoidCallback onDownload;
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
    required this.canDownload,
    required this.typeColor,
    this.userLat,
    this.userLng,
    required this.onTogglePin,
    required this.onDownload,
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

  @override
  void initState() {
    super.initState();
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
                        const SizedBox(width: 8),
                        _circleOverlay(
                          cs,
                          icon: Icons.more_vert_rounded,
                          onTap: () => _showMoreMenu(memory, cs),
                          glass: _hasHero,
                        ),
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

  /// Панель внизу: одно главное действие таблеткой и два круглых рядом.
  /// Удаление сюда не входит — оно живёт в меню: раньше оно стояло вплотную к
  /// «Редактировать» и отличалось только цветом слова.
  Widget _buildActionBar(Memory memory, ColorScheme cs) {
    final media = MediaQuery.of(context);
    return Container(
      decoration: BoxDecoration(color: cs.surfaceContainerLow),
      padding: EdgeInsets.fromLTRB(16, 12, 16, media.padding.bottom + 16),
      child: Row(
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
              label: Text(
                memory.isPinned
                    ? LocaleService.current.unpinMemory
                    : LocaleService.current.pinMemory,
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
          ),
          if (widget.canDownload) ...[
            const SizedBox(width: 10),
            _roundAction(
              cs,
              icon: Icons.download_rounded,
              tooltip: LocaleService.current.saveToDevice,
              onTap: () {
                Navigator.pop(context);
                widget.onDownload();
              },
            ),
          ],
          if (widget.isOwner) ...[
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
      ),
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

  /// Редкое и опасное: сменить место и удалить. У чужой записи меню не
  /// открывается вовсе — раньше «Редактировать» и «Удалить» показывались всем,
  /// а отказ приходил уже от сервера.
  void _showMoreMenu(Memory memory, ColorScheme cs) {
    final canSetPlace = widget.onSetLocation != null &&
        memory.type != MemoryType.location &&
        memory.latitude == null &&
        memory.longitude == null &&
        (memory.locationName?.isEmpty ?? true);
    if (!widget.isOwner && !canSetPlace) return;

    showAppSheet<void>(
      context,
      background: cs.surfaceContainer,
      builder: (ctx) => Theme(
        data: ProfileTheme.data(cs),
        child: SheetScaffold(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canSetPlace)
                  _menuRow(
                    cs,
                    icon: Icons.add_location_alt_rounded,
                    title: LocaleService.current.selectLocation,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                      widget.onSetLocation!();
                    },
                  ),
                if (widget.isOwner)
                  _menuRow(
                    cs,
                    icon: Icons.delete_outline_rounded,
                    title: LocaleService.current.deleteMemory,
                    danger: true,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                      widget.onDelete();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuRow(
    ColorScheme cs, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final fg = danger ? cs.error : cs.onSurface;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: danger ? cs.error : cs.onSurfaceVariant),
              const SizedBox(width: 14),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fg,
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
          pageBuilder: (_, __, ___) =>
              FullscreenGallery(items: galleryItems, initialIndex: i),
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
                        builder: (_) => _InAppVideoPlayerPage(
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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
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
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
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
                  boxShadow: context.appTheme.accentGlow(
                    p,
                    opacity: 0.3,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
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
        StreamBuilder<List<MemoryComment>>(
          stream: MemoryRepository().watchComments(widget.groupId, widget.memoryId),
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

