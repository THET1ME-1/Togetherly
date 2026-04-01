import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/memory.dart';
import '../services/locale_service.dart';

/// Returns SVG asset path for a given memory type
String svgAssetForMemoryType(MemoryType type) {
  switch (type) {
    case MemoryType.photo:
      return 'assets/icons/ic_photo.svg';
    case MemoryType.video:
      return 'assets/icons/ic_photo.svg';
    case MemoryType.location:
      return 'assets/icons/ic_location.svg';
    case MemoryType.music:
      return 'assets/icons/ic_music_note.svg';
    case MemoryType.text:
      return 'assets/icons/ic_edit.svg';
  }
}

/// Reusable memory tile builder that can be used in both
/// the full Memory Lane screen and the Home screen quick preview.
///
/// Pass [onTap], [onLongPress] for card actions.
/// Pass [onOpenGallery] to handle fullscreen photo viewer.
/// Pass [onOpenLocation] for map navigation.
/// [distanceText] is a pre-computed distance label (e.g. "2.3km").
class MemoryTileBuilder {
  final Color primary;
  final Color cardSurface;
  final Color cardBorder;

  const MemoryTileBuilder({
    required this.primary,
    this.cardSurface = Colors.white,
    this.cardBorder = const Color(0xFFE5E5E5),
  });

  // ═══════════════════════════════════════════════════
  //  MAIN ENTRY: build tile by type
  // ═══════════════════════════════════════════════════
  Widget buildTile(
    Memory memory, {
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    void Function(List<String> urls, int index)? onOpenGallery,
    void Function(double lat, double lng, String? label)? onOpenLocation,
    String? distanceText,

    /// If non-null, replaces the music content area with this widget
    /// (used in MemoryLaneScreen where _MusicMiniPlayer is used)
    Widget? musicPlayerWidget,
  }) {
    Widget content;
    bool enableTap = true;
    switch (memory.type) {
      case MemoryType.photo:
        content = _photoContent(memory, onOpenGallery: onOpenGallery);
        break;
      case MemoryType.video:
        content = _videoContent(memory);
        break;
      case MemoryType.location:
        content = _locationContent(
          memory,
          onOpenLocation: onOpenLocation,
          distanceText: distanceText,
        );
        break;
      case MemoryType.music:
        if (musicPlayerWidget != null) {
          return _baseTile(
            memory: memory,
            onTap: null,
            onLongPress: onLongPress,
            child: musicPlayerWidget,
          );
        }
        content = _musicContent(memory);
        enableTap = false;
        break;
      case MemoryType.text:
        content = _textContent(
          memory,
          onOpenLocation: onOpenLocation,
          distanceText: distanceText,
        );
        break;
    }

    return _baseTile(
      memory: memory,
      onTap: enableTap ? onTap : null,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(memory),
          const SizedBox(height: 10),
          content,
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  BASE TILE WRAPPER
  // ═══════════════════════════════════════════════════
  Widget _baseTile({
    required Memory memory,
    required Widget child,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: memory.isPinned
                ? Border.all(color: primary.withOpacity(0.25), width: 1.5)
                : Border.all(color: cardBorder.withOpacity(0.5), width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  CARD HEADER  (avatar · name · time · subtitle)
  // ═══════════════════════════════════════════════════
  Widget _cardHeader(Memory memory) {
    final s = LocaleService.current;
    String subtitle;
    switch (memory.type) {
      case MemoryType.photo:
        subtitle = memory.title?.isNotEmpty == true
            ? memory.title!
            : s.sharedAPicture;
        break;
      case MemoryType.video:
        subtitle = memory.title?.isNotEmpty == true
            ? memory.title!
            : s.sharedAVideo;
        break;
      case MemoryType.location:
        subtitle = s.sharedALocation;
        break;
      case MemoryType.music:
        subtitle = [
          if (memory.title?.isNotEmpty == true) memory.title!,
          if (memory.caption?.isNotEmpty == true) memory.caption!,
        ].join(' • ');
        break;
      case MemoryType.text:
        subtitle = s.sharedAThought;
        break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        children: [
          // Avatar with accent ring + type badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: primary.withOpacity(0.18),
                    width: 1.5,
                  ),
                ),
                child: ClipOval(
                  child: memory.authorAvatar.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: memory.authorAvatar,
                          fit: BoxFit.cover,
                          memCacheWidth: 120,
                          memCacheHeight: 120,
                          errorWidget: (_, __, ___) =>
                              _avatarFallback(memory.authorName),
                        )
                      : _avatarFallback(memory.authorName),
                ),
              ),
              Positioned(
                bottom: -2,
                left: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      svgAssetForMemoryType(memory.type),
                      width: 10,
                      height: 10,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        memory.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ),
                    Text(
                      '  ·  ${_formatTimeAgo(memory.createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          if (memory.isPinned)
            Icon(
              Icons.push_pin_rounded,
              size: 16,
              color: primary.withOpacity(0.45),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  PHOTO CONTENT
  // ═══════════════════════════════════════════════════
  Widget _photoContent(
    Memory memory, {
    void Function(List<String> urls, int index)? onOpenGallery,
  }) {
    final s = LocaleService.current;
    final allPhotos = <String>[
      if (memory.imageUrls?.isNotEmpty == true)
        ...memory.imageUrls!
      else if (memory.imageUrl?.isNotEmpty == true)
        memory.imageUrl!,
    ];
    final hasPhotos = allPhotos.isNotEmpty;

    return Column(
      children: [
        // Sub-card
        GestureDetector(
          onTap: hasPhotos && onOpenGallery != null
              ? () => onOpenGallery(allPhotos, 0)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200, width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          memory.title?.isNotEmpty == true
                              ? memory.title!
                              : s.sharedAPicture,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (memory.caption?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              memory.caption!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (!hasPhotos)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'No photo attached',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade400,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        if (allPhotos.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${allPhotos.length} photos',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Square thumbnail
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: hasPhotos
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: allPhotos.first,
                              fit: BoxFit.cover,
                              memCacheWidth: 96,
                              memCacheHeight: 96,
                              errorWidget: (_, __, ___) => Icon(
                                Icons.broken_image_rounded,
                                color: Colors.grey.shade300,
                                size: 22,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.image_rounded,
                            color: primary.withOpacity(0.4),
                            size: 22,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Multi-photo strip
        if (allPhotos.length > 1) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: allPhotos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: onOpenGallery != null
                    ? () => onOpenGallery(allPhotos, i)
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: allPhotos[i],
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    memCacheWidth: 144,
                    memCacheHeight: 144,
                    errorWidget: (_, __, ___) => Container(
                      width: 72,
                      height: 72,
                      color: Colors.grey.shade100,
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  VIDEO CONTENT
  // ═══════════════════════════════════════════════════
  Widget _videoContent(Memory memory) {
    final hasThumb = memory.imageUrl != null && memory.imageUrl!.isNotEmpty;
    final s = LocaleService.current;

    return Column(
      children: [
        ClipRRect(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasThumb)
                  CachedNetworkImage(
                    imageUrl: memory.imageUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 800,
                    memCacheHeight: 450,
                    errorWidget: (_, __, ___) =>
                        Container(color: Colors.grey.shade200),
                  )
                else
                  Container(color: Colors.grey.shade900),
                Container(color: Colors.black.withOpacity(0.25)),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 32,
                      color: Color(0xFFEC4899),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(6),
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
                          s.videoLabel.toUpperCase(),
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
        if (memory.caption?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(
              memory.caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  LOCATION CONTENT
  // ═══════════════════════════════════════════════════
  Widget _locationContent(
    Memory memory, {
    void Function(double lat, double lng, String? label)? onOpenLocation,
    String? distanceText,
  }) {
    final s = LocaleService.current;
    final hasCoords = memory.latitude != null && memory.longitude != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memory.locationName ?? 'Location',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (distanceText != null && distanceText.isNotEmpty)
                        Text(
                          s.kmFromYou(distanceText),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasCoords && onOpenLocation != null)
                  GestureDetector(
                    onTap: () => onOpenLocation(
                      memory.latitude!,
                      memory.longitude!,
                      memory.locationName,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s.setARoute,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (memory.caption?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(
              memory.caption!,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.grey.shade800,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  MUSIC CONTENT (simple, no playback)
  // ═══════════════════════════════════════════════════
  Widget _musicContent(Memory memory) {
    final hasCover =
        memory.musicCoverUrl != null && memory.musicCoverUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: hasCover
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: memory.musicCoverUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 96,
                        memCacheHeight: 96,
                        errorWidget: (_, __, ___) => Center(
                          child: SvgPicture.asset(
                            'assets/icons/ic_music_note.svg',
                            width: 20,
                            height: 20,
                            colorFilter: ColorFilter.mode(
                              primary,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: SvgPicture.asset(
                        'assets/icons/ic_music_note.svg',
                        width: 20,
                        height: 20,
                        colorFilter: ColorFilter.mode(primary, BlendMode.srcIn),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memory.musicTitle ?? 'Unknown Track',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (memory.musicArtist != null &&
                      memory.musicArtist!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        memory.musicArtist!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  // ═══════════════════════════════════════════════════
  //  TEXT / NOTE CONTENT
  // ═══════════════════════════════════════════════════
  Widget _textContent(
    Memory memory, {
    void Function(double lat, double lng, String? label)? onOpenLocation,
    String? distanceText,
  }) {
    final s = LocaleService.current;
    final hasLocation =
        memory.locationName != null && memory.locationName!.isNotEmpty;
    final hasCoords = memory.latitude != null && memory.longitude != null;

    return Column(
      children: [
        // Note sub-card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.sticky_note_2_rounded,
                    color: primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (memory.title?.isNotEmpty == true)
                        Text(
                          memory.title!,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (memory.caption?.isNotEmpty == true)
                        Padding(
                          padding: EdgeInsets.only(
                            top: memory.title?.isNotEmpty == true ? 3 : 0,
                          ),
                          child: Text(
                            memory.caption!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              height: 1.35,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (memory.title == null && memory.caption == null)
                        Text(
                          s.note,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Location sub-card
        if (hasLocation || hasCoords)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.location_on_rounded,
                      color: primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          memory.locationName ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (distanceText != null && distanceText.isNotEmpty)
                          Text(
                            s.kmFromYou(distanceText),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (hasCoords && onOpenLocation != null)
                    GestureDetector(
                      onTap: () => onOpenLocation(
                        memory.latitude!,
                        memory.longitude!,
                        memory.locationName,
                      ),
                      child: Text(
                        s.setARoute,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════

  Widget _avatarFallback(String? name) {
    final initial = (name != null && name.isNotEmpty)
        ? name[0].toUpperCase()
        : '?';
    return Container(
      color: primary.withOpacity(0.15),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: primary,
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final s = LocaleService.current;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return s.justNow;
    if (diff.inMinutes < 60) return s.minutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return s.hoursAgo(diff.inHours);
    if (diff.inDays < 30) return s.daysAgo(diff.inDays);
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }
}
