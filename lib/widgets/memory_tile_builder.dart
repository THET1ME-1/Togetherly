import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
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
    case MemoryType.videoLink:
      return 'assets/icons/ic_photo.svg';
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
      case MemoryType.videoLink:
        content = _videoLinkContent(memory);
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
      case MemoryType.videoLink:
        subtitle = memory.title?.isNotEmpty == true
            ? memory.title!
            : s.sharedAVideoLink;
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

    final content = Column(
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
                  // Square thumbnail (blurred individually for 18+)
                  Builder(
                    builder: (_) {
                      final thumb = Container(
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
                      );
                      if (memory.isAdult)
                        return _AdultBlurWrapper(child: thumb);
                      return thumb;
                    },
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
              itemBuilder: (_, i) {
                final img = ClipRRect(
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
                );
                return GestureDetector(
                  onTap: onOpenGallery != null
                      ? () => onOpenGallery(allPhotos, i)
                      : null,
                  child: memory.isAdult ? _AdultBlurWrapper(child: img) : img,
                );
              },
            ),
          ),
        ],
      ],
    );
    return content;
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
                          child: _SpoilerText(
                            text: memory.caption!,
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

  // ═══════════════════════════════════════════════════
  //  VIDEO LINK CONTENT  (YouTube / Vimeo / etc.)
  // ═══════════════════════════════════════════════════
  Widget _videoLinkContent(Memory memory) {
    final url = memory.videoUrl ?? '';
    final platform = _detectVideoPlatform(url);
    final platformName = platform['name'] as String;
    final platformColor = platform['color'] as Color;
    final hasThumb = memory.imageUrl?.isNotEmpty == true;
    final author = memory.musicArtist;
    final isAdult = _isAdultPlatform(platformName);

    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: thumbnail + text
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail with play overlay
              Container(
                width: 80,
                height: 56,
                decoration: BoxDecoration(
                  color: platformColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasThumb)
                        CachedNetworkImage(
                          imageUrl: memory.imageUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          memCacheHeight: 112,
                          errorWidget: (_, __, ___) =>
                              _thumbFallback(platformColor),
                        )
                      else
                        _thumbFallback(platformColor),
                      Container(color: Colors.black.withOpacity(0.20)),
                      Center(
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.90),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 16,
                            color: platformColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Title + author + platform badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memory.title?.isNotEmpty == true
                          ? memory.title!
                          : platformName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade900,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (author?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          author!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 6),
                    // Platform badge — music-style chip (no border)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: platformColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _platformIcon(platformName),
                            size: 10,
                            color: platformColor,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            platformName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: platformColor,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Caption
          if (memory.caption?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                memory.caption!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 10),
          // Open button — solid platform color, no border, white text
          if (url.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                label: Text(
                  'Открыть в $platformName',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: platformColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                ),
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: isAdult ? _AdultBlurWrapper(child: card) : card,
    );
  }

  Widget _thumbFallback(Color color) {
    return Container(
      color: color.withOpacity(0.08),
      child: Icon(
        Icons.smart_display_rounded,
        color: color.withOpacity(0.4),
        size: 22,
      ),
    );
  }

  static Map<String, dynamic> _detectVideoPlatform(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      return {'name': 'YouTube', 'color': const Color(0xFFFF0000)};
    } else if (lower.contains('vimeo.com')) {
      return {'name': 'Vimeo', 'color': const Color(0xFF1AB7EA)};
    } else if (lower.contains('dailymotion.com')) {
      return {'name': 'Dailymotion', 'color': const Color(0xFF0066DC)};
    } else if (lower.contains('pornhub.com')) {
      return {'name': 'PornHub', 'color': const Color(0xFFFF9000)};
    } else if (lower.contains('xvideos.com')) {
      return {'name': 'xVideos', 'color': const Color(0xFF1A1A1A)};
    } else if (lower.contains('xhamster.com')) {
      return {'name': 'xHamster', 'color': const Color(0xFFFF7900)};
    } else if (lower.contains('redtube.com')) {
      return {'name': 'RedTube', 'color': const Color(0xFFCC0000)};
    } else if (lower.contains('twitch.tv')) {
      return {'name': 'Twitch', 'color': const Color(0xFF9146FF)};
    } else if (lower.contains('tiktok.com')) {
      return {'name': 'TikTok', 'color': const Color(0xFF010101)};
    } else if (lower.contains('instagram.com')) {
      return {'name': 'Instagram', 'color': const Color(0xFFE1306C)};
    } else if (lower.contains('facebook.com') || lower.contains('fb.watch')) {
      return {'name': 'Facebook', 'color': const Color(0xFF1877F2)};
    } else if (lower.contains('twitter.com') || lower.contains('x.com')) {
      return {'name': 'X', 'color': const Color(0xFF000000)};
    } else if (lower.contains('rutube.ru')) {
      return {'name': 'Rutube', 'color': const Color(0xFF1C77FD)};
    } else if (lower.contains('vk.com')) {
      return {'name': 'VK', 'color': const Color(0xFF0077FF)};
    } else {
      return {'name': 'Video', 'color': const Color(0xFFEC4899)};
    }
  }

  static IconData _platformIcon(String platformName) {
    switch (platformName) {
      case 'YouTube':
        return Icons.smart_display_rounded;
      case 'Twitch':
        return Icons.videocam_rounded;
      case 'TikTok':
      case 'Instagram':
        return Icons.music_video_rounded;
      default:
        return Icons.play_circle_outline_rounded;
    }
  }

  static bool _isAdultPlatform(String name) {
    const adultPlatforms = {'PornHub', 'xVideos', 'xHamster', 'RedTube'};
    return adultPlatforms.contains(name);
  }
}

// ─── 18+ Blur Wrapper ───────────────────────────────────────────────────────
class _AdultBlurWrapper extends StatefulWidget {
  final Widget child;
  const _AdultBlurWrapper({required this.child});

  @override
  State<_AdultBlurWrapper> createState() => _AdultBlurWrapperState();
}

class _AdultBlurWrapperState extends State<_AdultBlurWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _ac.isDismissed ? () => _ac.forward() : null,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          widget.child,
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ac,
              builder: (_, __) {
                if (_ac.isCompleted) return const SizedBox.shrink();
                final t = _ac.value;
                final sigma = (14.0 * (1.0 - t)).clamp(0.1, 14.0);
                final opacity = (1.0 - t).clamp(0.0, 1.0);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.lock_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Spoiler Text ────────────────────────────────────────────────────────────
/// Renders plain text with optional `||spoiler||` segments hidden until tapped.
class _SpoilerText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const _SpoilerText({
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
  });

  List<({String text, bool isSpoiler})> _parse() {
    final result = <({String text, bool isSpoiler})>[];
    final parts = text.split('||');
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      result.add((text: parts[i], isSpoiler: i.isOdd));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final segments = _parse();
    final hasSpoiler = segments.any((s) => s.isSpoiler);
    if (!hasSpoiler) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    return Text.rich(
      TextSpan(
        children: segments.map((seg) {
          if (!seg.isSpoiler) {
            return TextSpan(text: seg.text, style: style);
          }
          return WidgetSpan(
            alignment: ui.PlaceholderAlignment.middle,
            child: _InlineSpoiler(
              text: seg.text,
              style: style ?? const TextStyle(fontSize: 12),
            ),
          );
        }).toList(),
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// A single inline spoiler chip — hidden until tapped.
class _InlineSpoiler extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _InlineSpoiler({required this.text, required this.style});

  @override
  State<_InlineSpoiler> createState() => _InlineSpoilerState();
}

class _InlineSpoilerState extends State<_InlineSpoiler>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _ac.isCompleted ? null : () => _ac.forward(),
      child: Stack(
        children: [
          // Transparent text for layout sizing
          Text(widget.text, style: widget.style),
          // Cover overlay that animates away on reveal
          AnimatedBuilder(
            animation: _ac,
            builder: (_, __) {
              if (_ac.isCompleted) return const SizedBox.shrink();
              return Opacity(
                opacity: 1.0 - Curves.easeOut.transform(_ac.value),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    widget.text,
                    style: widget.style.copyWith(color: Colors.grey.shade800),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
