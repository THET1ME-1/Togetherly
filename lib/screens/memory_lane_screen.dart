import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:exif/exif.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import '../models/memory.dart';
import '../models/comment.dart';
import '../models/pair_data.dart';
import '../services/firebase_service.dart';
import '../services/home_widget_service.dart';
import '../services/rate_limiter_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/common/m3_loading.dart';
import 'map_picker_screen.dart';
import 'memories_map_screen.dart';

/// Returns SVG asset path for a given memory type
String _svgAssetForType(MemoryType type) {
  switch (type) {
    case MemoryType.photo:
      return 'assets/icons/ic_photo.svg';
    case MemoryType.video:
      return 'assets/icons/ic_photo.svg';
    case MemoryType.videoLink:
      return 'assets/icons/ic_photo.svg';
    case MemoryType.location:
      return 'assets/icons/ic_location.svg';
    case MemoryType.music:
      return 'assets/icons/ic_music_note.svg';
    case MemoryType.text:
      return 'assets/icons/ic_edit.svg';
  }
}

/// Filter mode for Memory Lane pinned memories.
enum MemoryFilterMode { none, day, month }

/// Memory Lane — Google Calendar Schedule-style view
/// Grouped by date, pinned at top, full CRUD
class MemoryLaneScreen extends StatefulWidget {
  final PairData pairData;
  final AppTheme theme;
  final MemoryFilterMode filterMode;
  const MemoryLaneScreen({
    super.key,
    required this.pairData,
    required this.theme,
    this.filterMode = MemoryFilterMode.none,
  });

  @override
  State<MemoryLaneScreen> createState() => _MemoryLaneScreenState();
}

class _MemoryLaneScreenState extends State<MemoryLaneScreen> {
  Color get primary => widget.theme.primary;

  final FirebaseService _fb = FirebaseService();

  /// Live avatar for a memory author — falls back to the stored snapshot.
  String _liveAvatar(Memory memory) {
    // Current user: in-memory cache is always the freshest source.
    if (memory.authorUid == _fb.uid) {
      final cached = _fb.avatarUrl;
      if (cached.isNotEmpty) return cached;
    }
    for (final m in pair.members) {
      if (m.uid == memory.authorUid && m.avatar.isNotEmpty) return m.avatar;
    }
    return memory.authorAvatar;
  }

  /// Live display name for a memory author — falls back to the stored snapshot.
  String _liveName(Memory memory) {
    for (final m in pair.members) {
      if (m.uid == memory.authorUid && m.name.isNotEmpty) return m.name;
    }
    return memory.authorName;
  }
  List<Memory> _memories = [];
  StreamSubscription? _memorySub;
  bool _loading = true;



  // User location for distance display
  double? _userLat;
  double? _userLng;

  PairData get pair => widget.pairData;
  String get _groupId => pair.pairId;

  @override
  void initState() {
    super.initState();
    _loadAndListen();
    _fetchUserLocation();
    widget.pairData.addListener(_onPairChanged);
  }

  void _onPairChanged() {
    if (mounted) setState(() {});
  }

  void _loadAndListen() {
    if (_groupId.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    _memorySub = _fb.listenToMemories(
      groupId: _groupId,
      onData: (memories) {
        if (mounted) {
          setState(() {
            _memories = memories;
            _loading = false;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    widget.pairData.removeListener(_onPairChanged);
    _memorySub?.cancel();
    super.dispose();
  }

  // ── Organize memories ──
  List<Memory> get _pinnedMemories {
    final pinned = _memories.where((m) => m.isPinned).toList();
    if (widget.filterMode != MemoryFilterMode.none) return [];
    return pinned;
  }

  /// Memories filtered by current day/month across all years, grouped by year
  Map<String, List<Memory>> get _filteredByDateAcrossYears {
    final now = DateTime.now();
    List<Memory> filtered;
    if (widget.filterMode == MemoryFilterMode.day) {
      filtered = _memories
          .where(
            (m) => m.createdAt.month == now.month && m.createdAt.day == now.day,
          )
          .toList();
    } else if (widget.filterMode == MemoryFilterMode.month) {
      filtered = _memories
          .where((m) => m.createdAt.month == now.month)
          .toList();
    } else {
      return {};
    }
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final Map<String, List<Memory>> grouped = {};
    for (var m in filtered) {
      final key = '${m.createdAt.year}';
      grouped.putIfAbsent(key, () => []).add(m);
    }
    return grouped;
  }

  /// Group non-pinned memories by date, newest first
  Map<String, List<Memory>> get _groupedByDate {
    if (widget.filterMode != MemoryFilterMode.none) return {};
    final nonPinned = _memories.where((m) => !m.isPinned).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final Map<String, List<Memory>> grouped = {};
    for (var m in nonPinned) {
      final key = _dateKey(m.createdAt);
      grouped.putIfAbsent(key, () => []).add(m);
    }
    return grouped;
  }

  String _dateKey(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;

    final s = LocaleService.current;
    if (diff == 0) return s.todayDate;
    if (diff == 1) return s.yesterday;
    if (diff < 7) return s.shortWeekdays[dt.weekday - 1];

    final months = s.shortMonths;
    if (dt.year == now.year) {
      return '${months[dt.month - 1]} ${dt.day}';
    }
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _fmtToday() {
    final n = DateTime.now();
    final m = LocaleService.current.shortMonths;
    return '${m[n.month - 1]} ${n.day}';
  }

  String _fmtMonth() {
    return LocaleService.current.fullMonths[DateTime.now().month];
  }

  String _timeStr(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ══════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: widget.theme.bgGradient[0],
      body: Stack(
        children: [
          // -- Background --
          Positioned.fill(
            child: RepaintBoundary(
              child: widget.theme.bgImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: widget.theme.bgImageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (_, __) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: widget.theme.bgGradient,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: widget.theme.bgGradient,
                          ),
                        ),
                      ),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: widget.theme.bgGradient,
                        ),
                      ),
                    ),
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              _buildAppBar(),
              if (_loading)
                SliverFillRemaining(child: M3PageLoading(color: primary))
              else if (_memories.isEmpty)
                _buildEmpty()
              else ...[
                const SliverToBoxAdapter(child: SizedBox(height: 6)),
                // Pinned section (only in normal mode)
                if (_pinnedMemories.isNotEmpty) ...[
                  _sectionHeader('📌  ${LocaleService.current.pinned}'),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _memoryTile(_pinnedMemories[i]),
                        childCount: _pinnedMemories.length,
                      ),
                    ),
                  ),
                ],
                // Day/Month filter — grouped by year across all years
                if (widget.filterMode != MemoryFilterMode.none) ...[
                  if (_filteredByDateAcrossYears.isEmpty)
                    _buildEmpty()
                  else
                    ..._filteredByDateAcrossYears.entries.expand((entry) {
                      return [
                        _sectionHeader(entry.key),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => _memoryTile(entry.value[i]),
                              childCount: entry.value.length,
                            ),
                          ),
                        ),
                      ];
                    }),
                ],
                // Date-grouped sections (normal mode)
                ..._groupedByDate.entries.expand((entry) {
                  return [
                    _sectionHeader(entry.key),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _memoryTile(entry.value[i]),
                          childCount: entry.value.length,
                        ),
                      ),
                    ),
                  ];
                }),
              ],
              SliverToBoxAdapter(child: SizedBox(height: 90 + bottomPad)),
            ],
          ),
          // FAB
          Positioned(
            bottom: bottomPad + 24,
            left: 24,
            right: 24,
            child: Center(
              child: GestureDetector(
                onTap: _showAddMemorySheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        LocaleService.current.addMemoryBtn,
                        style: GoogleFonts.rubik(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── App Bar ──
  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: widget.theme.bgGradient[0].withOpacity(0.95),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.8),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.black87,
            size: 20,
          ),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocaleService.current.memoryLane,
            style: GoogleFonts.rubik(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          if (widget.filterMode != MemoryFilterMode.none)
            Text(
              widget.filterMode == MemoryFilterMode.day
                  ? '📌 ${LocaleService.current.pinned} • ${_fmtToday()}'
                  : '📌 ${LocaleService.current.pinned} • ${_fmtMonth()}',
              style: GoogleFonts.rubik(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: primary.withOpacity(0.8),
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _openPhotoGalleryScreen,
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.photo_library_rounded, color: primary, size: 18),
          ),
          tooltip: LocaleService.current.openPhotoGallery,
        ),
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MemoriesMapScreen(
                memories: _memories,
                theme: widget.theme,
                currentUserUid: _fb.uid,
              ),
            ),
          ),
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.map_rounded, color: primary, size: 18),
          ),
          tooltip: 'Карта воспоминаний',
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.group_rounded, size: 14, color: primary),
                  const SizedBox(width: 4),
                  Text(
                    '${pair.members.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Empty state ──
  SliverFillRemaining _buildEmpty() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 56,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              LocaleService.current.noMemoriesYet,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LocaleService.current.noMemoriesYetDesc,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  SECTION HEADER
  // ═══════════════════════════════════════════════════
  SliverToBoxAdapter _sectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Text(
          title,
          style: GoogleFonts.rubik(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  MEMORY TILE (type-specific cards)
  // ═══════════════════════════════════════════════════
  Widget _memoryTile(Memory memory) {
    switch (memory.type) {
      case MemoryType.photo:
        return _photoTile(memory);
      case MemoryType.video:
        return _videoTile(memory);
      case MemoryType.videoLink:
        return _videoLinkTile(memory);
      case MemoryType.location:
        return _locationTile(memory);
      case MemoryType.music:
        return _musicTile(memory);
      case MemoryType.text:
        return _textTile(memory);
    }
  }

  // ═══════════════════════════════════════════════════
  //  Helper: SVG icon path per memory type
  // ═══════════════════════════════════════════════════
  String _typeSvgAsset(MemoryType type) => _svgAssetForType(type);

  // ═══════════════════════════════════════════════════
  //  SHARED CARD HEADER (avatar · name · time · subtitle)
  // ═══════════════════════════════════════════════════
  Widget _cardHeader(
    Memory memory, {
    required String subtitle,
    Widget? trailing,
    Color? badgeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        children: [
          // Avatar with accent ring + optional badge dot
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
                  child: _liveAvatar(memory).isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: _liveAvatar(memory),
                          fit: BoxFit.cover,
                          memCacheWidth: 120,
                          memCacheHeight: 120,
                          errorWidget: (_, __, ___) =>
                              _avatarFallback(_liveName(memory)),
                        )
                      : _avatarFallback(_liveName(memory)),
                ),
              ),
              if (badgeColor != null)
                Positioned(
                  bottom: -2,
                  left: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        _typeSvgAsset(memory.type),
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
                        _liveName(memory),
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
          if (trailing != null) trailing,
          if (memory.isPinned && trailing == null)
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
  //  PHOTO TILE — social-style photo card
  // ═══════════════════════════════════════════════════
  Widget _photoTile(Memory memory) {
    final s = LocaleService.current;
    // Support both legacy imageUrl and new imageUrls array
    final allPhotos = <String>[
      if (memory.imageUrls?.isNotEmpty == true)
        ...memory.imageUrls!
      else if (memory.imageUrl?.isNotEmpty == true)
        memory.imageUrl!,
    ];
    final hasPhotos = allPhotos.isNotEmpty;

    return _baseTile(
      memory: memory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            memory,
            subtitle: memory.title?.isNotEmpty == true
                ? memory.title!
                : s.sharedAPicture,
            badgeColor: primary,
          ),
          const SizedBox(height: 10),
          // ── Photo sub-card (same style as music tile) ──
          GestureDetector(
            onTap: hasPhotos
                ? () async {
                    final items = _allGalleryItems;
                    final idx =
                        items.indexWhere((it) => it.memoryId == memory.id);
                    final result = await _openFullscreenGallery(
                      context,
                      items,
                      idx >= 0 ? idx : 0,
                    );
                    if (result != null && mounted) {
                      final mem = _memories.firstWhere(
                        (m) => m.id == result,
                        orElse: () => memory,
                      );
                      _showMemoryDetail(mem);
                    }
                  }
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
                    // Left: text content
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
                                LocaleService.current.noPhotoAttached,
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
                                  LocaleService.current.nPhotos(
                                    allPhotos.length,
                                  ),
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
                    // Right: stacked deck preview (up to 3 photos)
                    Builder(
                      builder: (_) {
                        if (!hasPhotos) {
                          return Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.image_rounded,
                              color: primary.withValues(alpha: 0.4),
                              size: 22,
                            ),
                          );
                        }
                        final deckPhotos = allPhotos.take(3).toList();
                        const cardSize = 48.0;
                        const offset = 7.0;
                        final totalWidth =
                            cardSize + (deckPhotos.length - 1) * offset;
                        return SizedBox(
                          width: totalWidth,
                          height: cardSize,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (int i = deckPhotos.length - 1; i >= 0; i--)
                                Positioned(
                                  left: i * offset,
                                  top: 0,
                                  child: Transform.rotate(
                                    angle: i * 0.07,
                                    alignment: Alignment.bottomLeft,
                                    child: Builder(builder: (_) {
                                      final card = Container(
                                        width: cardSize,
                                        height: cardSize,
                                        decoration: BoxDecoration(
                                          color: primary.withValues(
                                            alpha: 0.08,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.12),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: CachedNetworkImage(
                                            imageUrl: deckPhotos[i],
                                            fit: BoxFit.cover,
                                            memCacheWidth: 96,
                                            memCacheHeight: 96,
                                            errorWidget: (ctx, err, w) => Icon(
                                              Icons.broken_image_rounded,
                                              color: Colors.grey.shade300,
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                      );
                                      if (memory.isAdult) {
                                        return _BlurAfterTap(child: card);
                                      }
                                      return card;
                                    }),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          _locationDistancePill(memory),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  VIDEO TILE — cinematic preview card
  // ═══════════════════════════════════════════════════
  Widget _videoTile(Memory memory) {
    final hasThumb = memory.imageUrl != null && memory.imageUrl!.isNotEmpty;
    final s = LocaleService.current;

    return _baseTile(
      memory: memory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            memory,
            subtitle: memory.title?.isNotEmpty == true
                ? memory.title!
                : s.sharedAVideo,
            badgeColor: primary,
          ),
          const SizedBox(height: 10),
          // Video preview with play button
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
                  // Duration/type badge
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
          _locationDistancePill(memory),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  LOCATION TILE — check-in card with route button
  // ═══════════════════════════════════════════════════
  Widget _locationTile(Memory memory) {
    final s = LocaleService.current;
    final hasCoords = memory.latitude != null && memory.longitude != null;

    return _baseTile(
      memory: memory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(memory, subtitle: s.sharedALocation, badgeColor: primary),
          const SizedBox(height: 10),
          // Location card body
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
                          memory.locationName ?? LocaleService.current.location,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (hasCoords && _userLat != null)
                          Text(
                            s.kmFromYou(
                              _distanceKm(memory.latitude!, memory.longitude!),
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (hasCoords)
                    GestureDetector(
                      onTap: () => _openLocationInMaps(
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
          // Caption / thought text
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
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  MUSIC TILE — streaming-style card
  // ═══════════════════════════════════════════════════
  Widget _musicTile(Memory memory) {
    return _baseTile(
      memory: memory,
      enableTap: false,
      child: MemoryMusicPlayer(
        key: ValueKey(memory.id),
        memory: memory,
        theme: widget.theme,
        onHeaderTap: () => _showMemoryDetail(memory),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  TEXT / NOTE TILE — thought bubble card
  // ═══════════════════════════════════════════════════
  Widget _textTile(Memory memory) {
    final s = LocaleService.current;
    final hasLocation =
        memory.locationName != null && memory.locationName!.isNotEmpty;
    final hasCoords = memory.latitude != null && memory.longitude != null;

    return _baseTile(
      memory: memory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(memory, subtitle: s.sharedAThought, badgeColor: primary),
          const SizedBox(height: 10),
          // ── Note sub-card (same style as music/location tiles) ──
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
                  // Left icon
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
                  // Text content
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
                            child: _SpoilerRichText(
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
          // Location sub-card (if available)
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
                          if (hasCoords && _userLat != null)
                            Text(
                              s.kmFromYou(
                                _distanceKm(
                                  memory.latitude!,
                                  memory.longitude!,
                                ),
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (hasCoords)
                      GestureDetector(
                        onTap: () => _openLocationInMaps(
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
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  VIDEO LINK TILE — card for shared web video link
  // ═══════════════════════════════════════════════════
  Widget _videoLinkTile(Memory memory) {
    final s = LocaleService.current;
    final platform = _detectVideoPlatform(memory.videoUrl ?? '');
    final platformColor = platform['color'] as Color;
    final platformName = platform['name'] as String;
    final hasThumb = memory.imageUrl?.isNotEmpty == true;

    Widget buildSubCard() => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail with play overlay
              GestureDetector(
                onTap: () {
                  final url = memory.videoUrl;
                  if (url != null && url.isNotEmpty) {
                    launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 80,
                    height: 56,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Thumbnail or platform-colored fallback
                        if (hasThumb)
                          CachedNetworkImage(
                            imageUrl: memory.imageUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 160,
                            memCacheHeight: 112,
                            errorWidget: (_, __, ___) =>
                                _videoLinkThumbFallback(platformColor),
                          )
                        else
                          _videoLinkThumbFallback(platformColor),
                        // Dark overlay
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.35),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                        // Play button
                        Center(
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.92),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.20),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                              color: platformColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Title, author, platform badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memory.title?.isNotEmpty == true
                          ? memory.title!
                          : LocaleService.current.video,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade900,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    // Platform badge — music-style chip (no border)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: platformColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _videoPlatformIcon(platformName),
                            size: 11,
                            color: platformColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              platformName,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: platformColor,
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Author/channel if in musicArtist field
                    if (memory.musicArtist?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          memory.musicArtist!,
                          style: TextStyle(
                            fontSize: 11,
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
          // Caption
          if (memory.caption?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              memory.caption!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          // Open button — solid platform color, no border, white text
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final url = memory.videoUrl;
                if (url != null && url.isNotEmpty) {
                  launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
              icon: const Icon(
                Icons.open_in_new_rounded,
                size: 14,
                color: Colors.white,
              ),
              label: Text(
                LocaleService.current.openIn(platformName),
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
    return _baseTile(
      memory: memory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            memory,
            subtitle: memory.title?.isNotEmpty == true
                ? memory.title!
                : s.sharedAVideoLink,
            badgeColor: platformColor,
          ),
          const SizedBox(height: 10),
          // ── Video link sub-card ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: platformName == 'YouTube'
                ? _YouTubeInlineCard(
                    memory: memory,
                    platformColor: platformColor,
                    platformName: platformName,
                  )
                : buildSubCard(),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _videoLinkThumbFallback(Color platformColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            platformColor.withOpacity(0.85),
            platformColor.withOpacity(0.55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(
        Icons.play_circle_outline_rounded,
        color: Colors.white,
        size: 28,
      ),
    );
  }

  // ── Platform detection for video URLs ──
  static Map<String, dynamic> _detectVideoPlatform(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      return {'name': 'YouTube', 'color': const Color(0xFFFF0000)};
    } else if (lower.contains('vimeo.com')) {
      return {'name': 'Vimeo', 'color': const Color(0xFF1AB7EA)};
    } else if (lower.contains('dailymotion.com')) {
      return {'name': 'Dailymotion', 'color': const Color(0xFF0066DC)};
    } else if (lower.contains('twitch.tv')) {
      return {'name': 'Twitch', 'color': const Color(0xFF9146FF)};
    } else if (lower.contains('tiktok.com')) {
      return {'name': 'TikTok', 'color': const Color(0xFF010101)};
    } else if (lower.contains('instagram.com')) {
      return {'name': 'Instagram', 'color': const Color(0xFFE1306C)};
    } else if (lower.contains('facebook.com') || lower.contains('fb.watch')) {
      return {'name': 'Facebook', 'color': const Color(0xFF1877F2)};
    } else if (lower.contains('twitter.com') || lower.contains('x.com')) {
      return {'name': 'Twitter/X', 'color': const Color(0xFF000000)};
    } else if (lower.contains('rutube.ru')) {
      return {'name': 'Rutube', 'color': const Color(0xFF1482C8)};
    } else if (lower.contains('vk.com') || lower.contains('vkvideo.ru')) {
      return {'name': 'VK Video', 'color': const Color(0xFF0077FF)};
    } else {
      return {
        'name': LocaleService.current.video,
        'color': const Color(0xFF6B7280),
      };
    }
  }

  static IconData _videoPlatformIcon(String platformName) {
    switch (platformName) {
      case 'YouTube':
        return Icons.smart_display_rounded;
      case 'Twitch':
        return Icons.live_tv_rounded;
      case 'TikTok':
        return Icons.music_video_rounded;
      case 'Instagram':
        return Icons.camera_alt_rounded;
      case 'Facebook':
        return Icons.facebook_rounded;
      case 'Vimeo':
      case 'Dailymotion':
        return Icons.play_circle_rounded;
      case 'Rutube':
      case 'VK Video':
        return Icons.play_circle_outline_rounded;
      default:
        return Icons.videocam_rounded;
    }
  }

  /// Fetch video metadata (title, channel, thumbnail) from a URL
  Future<Map<String, String?>> _fetchVideoMeta(String url) async {
    final lower = url.toLowerCase();

    // ── YouTube (official oEmbed — no API key required) ──
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      try {
        final resp = await http.get(
          Uri.parse(
            'https://www.youtube.com/oembed?url=${Uri.encodeComponent(url)}&format=json',
          ),
        );
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          return {
            'title': data['title'] as String?,
            'author': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      } catch (e) {
        debugPrint('YouTube video meta error: $e');
      }
      return {};
    }

    // ── Vimeo via oEmbed ──
    if (lower.contains('vimeo.com')) {
      try {
        final resp = await http.get(
          Uri.parse(
            'https://vimeo.com/api/oembed.json?url=${Uri.encodeComponent(url)}',
          ),
        );
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          return {
            'title': data['title'] as String?,
            'author': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      } catch (e) {
        debugPrint('Vimeo meta error: $e');
      }
    }

    // ── Dailymotion via oEmbed ──
    if (lower.contains('dailymotion.com')) {
      try {
        final resp = await http.get(
          Uri.parse(
            'https://www.dailymotion.com/services/oembed?url=${Uri.encodeComponent(url)}&format=json',
          ),
        );
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          return {
            'title': data['title'] as String?,
            'author': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      } catch (e) {
        debugPrint('Dailymotion meta error: $e');
      }
    }

    // ── Generic noembed.com fallback ──
    try {
      final resp = await http.get(
        Uri.parse('https://noembed.com/embed?url=${Uri.encodeComponent(url)}'),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (data['error'] == null) {
          return {
            'title': data['title'] as String?,
            'author': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      }
    } catch (_) {}

    // ── OG tags fallback ──
    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (compatible; Twitterbot/1.0)'},
      );
      if (resp.statusCode == 200) {
        final body = resp.body;
        final titleMatch = RegExp(
          r'property="og:title"\s+content="([^"]+)"',
          caseSensitive: false,
        ).firstMatch(body);
        final imageMatch = RegExp(
          r'property="og:image"\s+content="([^"]+)"',
          caseSensitive: false,
        ).firstMatch(body);
        final authorMatch = RegExp(
          r'name="author"\s+content="([^"]+)"',
          caseSensitive: false,
        ).firstMatch(body);
        if (titleMatch != null) {
          return {
            'title': _decodeHtmlEntities(titleMatch.group(1) ?? ''),
            'author': authorMatch?.group(1),
            'cover': imageMatch?.group(1),
          };
        }
      }
    } catch (_) {}

    return {};
  }

  // ═══════════════════════════════════════════════════
  //  BASE TILE WRAPPER
  // ═══════════════════════════════════════════════════
  Widget _baseTile({
    required Memory memory,
    required Widget child,
    bool enableTap = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: enableTap ? () => _showMemoryDetail(memory) : null,
        onLongPress: () => _showMemoryActions(memory),
        child: Container(
          decoration: BoxDecoration(
            color: widget.theme.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: memory.isPinned
                ? Border.all(color: primary.withOpacity(0.25), width: 1.5)
                : Border.all(
                    color: widget.theme.cardBorder.withOpacity(0.5),
                    width: 0.5,
                  ),
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

  Color _memoryTypeColor(MemoryType type) => primary;

  // ═══════════════════════════════════════════════════
  //  MEMORY DETAIL — full screen
  // ═══════════════════════════════════════════════════
  void _showMemoryDetail(Memory memory) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => _MemoryDetailSheet(
        memory: memory,
        groupId: _groupId,
        fb: _fb,
        primary: primary,
        isOwner: memory.authorUid == _fb.uid,
        canDownload: _canDownload(memory),
        typeColor: _memoryTypeColor(memory.type),
        userLat: _userLat,
        userLng: _userLng,
        liveAuthorAvatar: _liveAvatar(memory),
        onTogglePin: () => _togglePin(memory),
        onDownload: () => _downloadMemoryMedia(memory),
        onEdit: () => _editMemory(memory),
        onDelete: () => _confirmDelete(memory),
        onSetLocation: () => _setLocationOnMemory(memory),
      ),
    );
  }

  // ignore: unused_element
  void _showMemoryDetailLEGACY(Memory memory) {
    AudioPlayer? audioPlayer;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize:
                  memory.type == MemoryType.photo ||
                      memory.type == MemoryType.video
                  ? 0.85
                  : 0.7,
              maxChildSize: 0.95,
              builder: (_, scrollController) => SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Type badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _memoryTypeColor(memory.type).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            _typeSvgAsset(memory.type),
                            width: 14,
                            height: 14,
                            colorFilter: ColorFilter.mode(
                              _memoryTypeColor(memory.type),
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            memory.typeLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _memoryTypeColor(memory.type),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── PHOTO detail ──
                    if (memory.type == MemoryType.photo) ...[
                      if (memory.imageUrl != null &&
                          memory.imageUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: CachedNetworkImage(
                              imageUrl: memory.imageUrl!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey.shade200,
                                child: Center(
                                  child: Icon(
                                    Icons.broken_image_rounded,
                                    color: Colors.grey.shade400,
                                    size: 48,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.image_not_supported_rounded,
                                  color: Colors.grey.shade400,
                                  size: 48,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  LocaleService.current.photoNotUploaded,
                                  style: TextStyle(color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],

                    // ── VIDEO detail ──
                    if (memory.type == MemoryType.video) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            if (memory.imageUrl != null &&
                                memory.imageUrl!.isNotEmpty)
                              CachedNetworkImage(
                                imageUrl: memory.imageUrl!,
                                width: double.infinity,
                                height: 220,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  height: 220,
                                  color: Colors.grey.shade900,
                                ),
                              )
                            else
                              Container(
                                height: 220,
                                color: Colors.grey.shade900,
                              ),
                            Container(
                              height: 220,
                              color: Colors.black.withOpacity(0.4),
                            ),
                            SizedBox(
                              height: 220,
                              width: double.infinity,
                              child: Center(
                                child: GestureDetector(
                                  onTap: () {
                                    final url = memory.videoUrl;
                                    if (url != null && url.isNotEmpty) {
                                      launchUrl(
                                        Uri.parse(url),
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 40,
                                      color: Color(0xFFEC4899),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── LOCATION detail ──
                    if (memory.type == MemoryType.location) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FAF4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFD1F0DE)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF22C55E,
                                    ).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.location_on_rounded,
                                    color: Color(0xFF22C55E),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        memory.locationName ??
                                            LocaleService
                                                .current
                                                .unknownLocation,
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.grey.shade900,
                                        ),
                                      ),
                                      if (memory.latitude != null)
                                        Text(
                                          '${memory.latitude!.toStringAsFixed(5)}, ${memory.longitude?.toStringAsFixed(5) ?? ""}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (memory.latitude != null &&
                                memory.longitude != null) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    final url =
                                        'https://www.google.com/maps?q=${memory.latitude},${memory.longitude}';
                                    launchUrl(
                                      Uri.parse(url),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                  icon: const Icon(Icons.map_rounded, size: 18),
                                  label: Text(
                                    LocaleService.current.openInGoogleMaps,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF22C55E),
                                    side: const BorderSide(
                                      color: Color(0xFF22C55E),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // ── MUSIC detail with playback ──
                    if (memory.type == MemoryType.music) ...[
                      _buildMusicDetailWidget(memory, audioPlayer, (player) {
                        setState(() => audioPlayer = player);
                      }),
                    ],

                    // ── TEXT / NOTE detail ──
                    if (memory.type == MemoryType.text) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFEF3C7)),
                        ),
                        child: Text(
                          memory.caption ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade800,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],

                    // Caption (for non-text types)
                    if (memory.type != MemoryType.text &&
                        memory.caption != null &&
                        memory.caption!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        memory.caption!,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade800,
                          height: 1.5,
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    // Author + time
                    Row(
                      children: [
                        AvatarWidget(
                          uid: memory.authorUid,
                          liveUrl: _liveAvatar(memory),
                          fallbackUrl: memory.authorAvatar,
                          name: _liveName(memory),
                          size: 28,
                          primary: primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _liveName(memory),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatFullDate(memory.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Action buttons — две строки по 2 кнопки
                    Column(
                      children: [
                        // Строка 1: Pin + Save
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  audioPlayer?.dispose();
                                  Navigator.pop(context);
                                  _togglePin(memory);
                                },
                                icon: Icon(
                                  memory.isPinned
                                      ? Icons.push_pin_rounded
                                      : Icons.push_pin_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  memory.isPinned
                                      ? LocaleService.current.unpinMemory
                                      : LocaleService.current.pinMemory,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primary,
                                  side: BorderSide(
                                    color: primary.withOpacity(0.3),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            if (_canDownload(memory)) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    audioPlayer?.dispose();
                                    Navigator.pop(context);
                                    _downloadMemoryMedia(memory);
                                  },
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    LocaleService.current.saveToDevice,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.blue.shade600,
                                    side: BorderSide(
                                      color: Colors.blue.shade200,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Строка 2: Edit + Delete (только для своих записей)
                        if (memory.authorUid == _fb.uid) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    audioPlayer?.dispose();
                                    Navigator.pop(context);
                                    _editMemory(memory);
                                  },
                                  icon: const Icon(
                                    Icons.edit_rounded,
                                    size: 16,
                                  ),
                                  label: Text(LocaleService.current.editMemory),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.grey.shade700,
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    audioPlayer?.dispose();
                                    Navigator.pop(context);
                                    _confirmDelete(memory);
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    LocaleService.current.deleteMemory,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade400,
                                    side: BorderSide(
                                      color: Colors.red.shade200,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),

                    // ── Comments section ──
                    const SizedBox(height: 24),
                    _CommentsSection(
                      groupId: _groupId,
                      memoryId: memory.id,
                      fb: _fb,
                      primary: primary,
                    ),

                    const _KeyboardPaddingBox(),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      audioPlayer?.dispose();
    });
  }

  // ── Music player widget for detail view ──
  Widget _buildMusicDetailWidget(
    Memory memory,
    AudioPlayer? player,
    void Function(AudioPlayer) onPlayer,
  ) {
    return _MusicPlayerWidget(
      memory: memory,
      player: player,
      onPlayerCreated: onPlayer,
      primary: primary,
      typeColor: _memoryTypeColor(MemoryType.music),
    );
  }

  String _formatFullDate(DateTime dt) {
    final s = LocaleService.current;
    return s.formatDateAt(
      s.shortMonths[dt.month],
      dt.day,
      dt.year,
      _timeStr(dt),
    );
  }

  // ═══════════════════════════════════════════════════
  //  MEMORY ACTIONS (long press)
  // ═══════════════════════════════════════════════════
  void _showMemoryActions(Memory memory) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
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
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                memory.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                color: primary,
              ),
              title: Text(
                memory.isPinned
                    ? LocaleService.current.unpinMemory
                    : LocaleService.current.pinMemory,
              ),
              onTap: () {
                Navigator.pop(context);
                _togglePin(memory);
              },
            ),
            ListTile(
              leading: Icon(
                memory.latitude != null
                    ? Icons.location_on_rounded
                    : Icons.add_location_alt_rounded,
                color: Colors.teal,
              ),
              title: Text(
                memory.latitude != null
                    ? 'Изменить геолокацию'
                    : 'Добавить геолокацию',
              ),
              onTap: () {
                Navigator.pop(context);
                _setLocationOnMemory(memory);
              },
            ),
            if (_canDownload(memory))
              ListTile(
                leading: Icon(
                  Icons.download_rounded,
                  color: Colors.blue.shade600,
                ),
                title: Text(LocaleService.current.saveToDevice),
                onTap: () {
                  Navigator.pop(context);
                  _downloadMemoryMedia(memory);
                },
              ),
            if (memory.authorUid == _fb.uid) ...[
              ListTile(
                leading: Icon(Icons.edit_rounded, color: Colors.grey.shade700),
                title: Text(LocaleService.current.editMemory),
                onTap: () {
                  Navigator.pop(context);
                  _editMemory(memory);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red.shade400,
                ),
                title: Text(
                  LocaleService.current.deleteMemory,
                  style: TextStyle(color: Colors.red.shade400),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(memory);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  DOWNLOAD
  // ═══════════════════════════════════════════════════

  bool _canDownload(Memory memory) {
    return memory.type == MemoryType.photo ||
        memory.type == MemoryType.video ||
        memory.type == MemoryType.music;
  }

  /// Extracts the file extension from a Firebase Storage URL.
  /// e.g. ".../memory_123.webp?alt=media&token=..." → "webp"
  String _extFromUrl(String url, String fallback) {
    try {
      final decoded = Uri.decodeFull(url);
      final path = Uri.parse(decoded).path;
      final name = path.split('/').last.split('?').first;
      final dot = name.lastIndexOf('.');
      if (dot != -1) return name.substring(dot + 1).toLowerCase();
    } catch (_) {}
    return fallback;
  }

  Future<void> _downloadMemoryMedia(Memory memory) async {
    String? url;
    String extension;
    String prefix;

    switch (memory.type) {
      case MemoryType.photo:
        url = memory.imageUrl;
        extension = url != null ? _extFromUrl(url, 'webp') : 'webp';
        prefix = 'photo';
        break;
      case MemoryType.video:
        url = memory.videoUrl;
        extension = url != null ? _extFromUrl(url, 'mp4') : 'mp4';
        prefix = 'video';
        break;
      case MemoryType.music:
        url = memory.musicUrl;
        extension = url != null ? _extFromUrl(url, 'mp3') : 'mp3';
        prefix = 'music';
        break;
      default:
        return;
    }

    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocaleService.current.noMediaUrl),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // For external links (Spotify, YouTube etc.) just open them
    if (!url.contains('firebasestorage') && !url.contains('firebase')) {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    }

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocaleService.current.downloading),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode}');
      }

      // Write to a temp file first, then hand off to gal (images/video)
      // or Downloads folder (audio). gal inserts into Android MediaStore so
      // the system Gallery app sees it immediately.
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${prefix}_$timestamp.$extension';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(response.bodyBytes);

      if (memory.type == MemoryType.photo) {
        await Gal.putImage(tempFile.path, album: 'Togetherly');
      } else if (memory.type == MemoryType.video) {
        await Gal.putVideo(tempFile.path, album: 'Togetherly');
      } else {
        // Audio — save to Downloads (Files app sees it without MediaStore)
        Directory saveDir;
        if (Platform.isAndroid) {
          saveDir = Directory('/storage/emulated/0/Download');
          if (!saveDir.existsSync()) saveDir = await getApplicationDocumentsDirectory();
        } else {
          saveDir = await getApplicationDocumentsDirectory();
        }
        final destFile = File('${saveDir.path}/$fileName');
        await tempFile.copy(destFile.path);
      }

      await tempFile.delete().catchError((_) => tempFile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocaleService.current.savedToGallery),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocaleService.current.downloadFailed(e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════
  //  CRUD
  // ═══════════════════════════════════════════════════
  Future<void> _togglePin(Memory memory) async {
    await _fb.togglePinMemory(
      groupId: _groupId,
      memoryId: memory.id,
      isPinned: !memory.isPinned,
    );
  }

  void _confirmDelete(Memory memory) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(LocaleService.current.deleteMemoryQuestion),
        content: Text(LocaleService.current.actionCannotBeUndone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LocaleService.current.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _fb.deleteMemory(
                groupId: _groupId,
                memoryId: memory.id,
                imageUrl: memory.imageUrl,
                videoUrl: memory.videoUrl,
                musicUrl: memory.musicUrl,
                musicCoverUrl: memory.musicCoverUrl,
              );

              // Обновляем виджет, если удалили фото дня
              if (memory.type == MemoryType.photo) {
                await HomeWidgetService.instance.handleMemoryDeleted(
                  _groupId,
                  memory.id,
                );
              }
            },
            child: Text(
              LocaleService.current.delete,
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
        ],
      ),
    );
  }

  void _editMemory(Memory memory) {
    final titleCtrl = TextEditingController(text: memory.title ?? '');
    final captionCtrl = TextEditingController(text: memory.caption ?? '');
    final locationCtrl = TextEditingController(text: memory.locationName ?? '');
    double? editLat = memory.latitude;
    double? editLng = memory.longitude;
    bool isAdultEdit = memory.isAdult;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  LocaleService.current.editMemoryTitle,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: titleCtrl,
                  maxLines: 1,
                  decoration: InputDecoration(
                    hintText: LocaleService.current.titleOptional,
                    prefixIcon: const Icon(Icons.title_rounded, size: 20),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: captionCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: LocaleService.current.description,
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
                // Spoiler toolbar for text pins in edit form
                if (memory.type == MemoryType.text) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          final sel = captionCtrl.selection;
                          if (!sel.isValid) return;
                          final text = captionCtrl.text;
                          if (sel.isCollapsed) {
                            final pos = sel.start;
                            final newText =
                                '${text.substring(0, pos)}||||${text.substring(pos)}';
                            captionCtrl.value = TextEditingValue(
                              text: newText,
                              selection: TextSelection.collapsed(
                                offset: pos + 2,
                              ),
                            );
                          } else {
                            final selected = text.substring(sel.start, sel.end);
                            final newText = text.replaceRange(
                              sel.start,
                              sel.end,
                              '||$selected||',
                            );
                            captionCtrl.value = TextEditingValue(
                              text: newText,
                              selection: TextSelection.collapsed(
                                offset: sel.start + selected.length + 4,
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.visibility_off_rounded,
                                size: 14,
                                color: primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                LocaleService.current.spoiler,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        LocaleService.current.selectTextAndPress,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (memory.type == MemoryType.location) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationCtrl,
                    decoration: InputDecoration(
                      hintText: LocaleService.current.locationNameHint,
                      prefixIcon: const Icon(Icons.location_on_rounded),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapPickerScreen(
                              initialLatitude: editLat,
                              initialLongitude: editLng,
                            ),
                          ),
                        );

                        if (result != null && mounted) {
                          setState(() {
                            editLat = result['latitude'];
                            editLng = result['longitude'];
                            locationCtrl.text = result['address'] ?? '';
                          });
                        }
                      },
                      icon: const Icon(Icons.map_rounded),
                      label: Text(
                        editLat != null && editLng != null
                            ? LocaleService.current.changeLocationOnMap
                            : LocaleService.current.pickLocationOnMap,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF22C55E),
                        side: const BorderSide(color: Color(0xFF22C55E)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                // 18+ toggle for photo edits
                if (memory.type == MemoryType.photo) ...[
                  GestureDetector(
                    onTap: () => setState(() => isAdultEdit = !isAdultEdit),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isAdultEdit
                            ? Colors.red.shade50
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isAdultEdit
                              ? Colors.red.shade200
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isAdultEdit
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            size: 18,
                            color: isAdultEdit
                                ? Colors.red.shade400
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  LocaleService.current.adultContent,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isAdultEdit
                                        ? Colors.red.shade600
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                Text(
                                  LocaleService.current.photoBlurred,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isAdultEdit
                                        ? Colors.red.shade400
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: isAdultEdit,
                            onChanged: (v) => setState(() => isAdultEdit = v),
                            activeColor: Colors.red.shade400,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _fb.updateMemory(
                        groupId: _groupId,
                        memoryId: memory.id,
                        title: titleCtrl.text.trim().isNotEmpty
                            ? titleCtrl.text.trim()
                            : '',
                        caption: captionCtrl.text.trim(),
                        locationName: memory.type == MemoryType.location
                            ? locationCtrl.text.trim()
                            : null,
                        latitude: editLat,
                        longitude: editLng,
                        isAdult: memory.type == MemoryType.photo
                            ? isAdultEdit
                            : null,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      LocaleService.current.saveChanges,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  ADD MEMORY
  // ═══════════════════════════════════════════════════
  void _showAddMemorySheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                LocaleService.current.addMemoryTitle,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                LocaleService.current.chooseWhatToShare,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),
              _addMemoryOption(
                icon: Icons.photo_rounded,
                label: LocaleService.current.photo,
                color: const Color(0xFF3B82F6),
                type: MemoryType.photo,
              ),
              _addMemoryOption(
                icon: Icons.videocam_rounded,
                label: LocaleService.current.video,
                color: const Color(0xFFEC4899),
                type: MemoryType.video,
              ),
              _addMemoryOption(
                icon: Icons.location_on_rounded,
                label: LocaleService.current.location,
                color: const Color(0xFF22C55E),
                type: MemoryType.location,
              ),
              _addMemoryOption(
                icon: Icons.music_note_rounded,
                label: LocaleService.current.music,
                color: const Color(0xFF8B5CF6),
                type: MemoryType.music,
              ),
              _addMemoryOption(
                icon: Icons.edit_note_rounded,
                label: LocaleService.current.note,
                color: const Color(0xFFFBBF24),
                type: MemoryType.text,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addMemoryOption({
    required IconData icon,
    required String label,
    required Color color,
    required MemoryType type,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade800,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      onTap: () {
        Navigator.pop(context);
        _showCreateMemoryForm(type);
      },
    );
  }

  /// Fetch track metadata from YouTube (stream-based) or Spotify (oEmbed).
  /// Supported music services list for the info dialog
  static const List<Map<String, dynamic>> _supportedMusicServices = [
    {
      'name': 'Spotify',
      'supported': true,
      'color': Color(0xFF1DB954),
      'icon': Icons.music_note_rounded,
    },
    {
      'name': 'YouTube Music',
      'supported': true,
      'color': Color(0xFFFF0000),
      'icon': Icons.play_circle_rounded,
    },
    {
      'name': 'Apple Music',
      'supported': true,
      'color': Color(0xFFFC3C44),
      'icon': Icons.apple_rounded,
    },
    {
      'name': 'Deezer',
      'supported': true,
      'color': Color(0xFFA238FF),
      'icon': Icons.album_rounded,
    },
    {
      'name': 'SoundCloud',
      'supported': true,
      'color': Color(0xFFFF5500),
      'icon': Icons.cloud_rounded,
    },
    {
      'name': 'Яндекс Музыка',
      'supported': true,
      'color': Color(0xFFFFCC00),
      'icon': Icons.library_music_rounded,
    },
    {
      'name': 'Tidal',
      'supported': true,
      'color': Color(0xFF000000),
      'icon': Icons.waves_rounded,
    },
    {
      'name': 'YouTube Music',

      'supported': true,
      'color': Color(0xFFFF0000),
      'icon': Icons.smart_display_rounded,
    },
    {
      'name': 'Audio file',
      'supported': true,
      'color': Color(0xFF8B5CF6),
      'icon': Icons.audio_file_rounded,
    },
    {
      'name': 'Amazon Music',
      'supported': false,
      'color': Color(0xFF25D1DA),
      'icon': Icons.shopping_bag_rounded,
    },
    {
      'name': 'Pandora',
      'supported': false,
      'color': Color(0xFF005483),
      'icon': Icons.radio_rounded,
    },
  ];



  static const List<Map<String, dynamic>> _supportedVideoServices = [
    {
      'name': 'YouTube',
      'supported': true,
      'color': Color(0xFFFF0000),
      'icon': Icons.smart_display_rounded,
    },
    {
      'name': 'Vimeo',
      'supported': true,
      'color': Color(0xFF1AB7EA),
      'icon': Icons.play_circle_rounded,
    },
    {
      'name': 'Dailymotion',
      'supported': true,
      'color': Color(0xFF0066DC),
      'icon': Icons.play_circle_outline_rounded,
    },
    {
      'name': 'Twitch',
      'supported': true,
      'color': Color(0xFF9146FF),
      'icon': Icons.live_tv_rounded,
    },
    {
      'name': 'TikTok',
      'supported': true,
      'color': Color(0xFF010101),
      'icon': Icons.music_video_rounded,
    },
    {
      'name': 'Instagram',
      'supported': true,
      'color': Color(0xFFE1306C),
      'icon': Icons.camera_alt_rounded,
    },
    {
      'name': 'Facebook',
      'supported': true,
      'color': Color(0xFF1877F2),
      'icon': Icons.facebook_rounded,
    },
    {
      'name': 'Twitter / X',
      'supported': true,
      'color': Color(0xFF000000),
      'icon': Icons.alternate_email_rounded,
    },
    {
      'name': 'Rutube',
      'supported': true,
      'color': Color(0xFF1482C8),
      'icon': Icons.play_circle_outline_rounded,
    },
    {
      'name': 'VK Video',
      'supported': true,
      'color': Color(0xFF0077FF),
      'icon': Icons.play_circle_outline_rounded,
    },
  ];

  void _showSupportedVideoServicesDialog() {
    final primary = widget.theme.primary;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primary.withOpacity(0.15),
                      const Color(0xFFFF0000).withOpacity(0.1),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.smart_display_rounded,
                  color: primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                LocaleService.current.supportedPlatforms,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                LocaleService.current.pasteLinkSupported,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: SingleChildScrollView(
                  child: Column(
                    children: _supportedVideoServices.map((svc) {
                      final svcColor = svc['color'] as Color;
                      final row = Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: svcColor.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: svcColor.withOpacity(0.12),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                svc['icon'] as IconData,
                                size: 20,
                                color: svcColor,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  svc['name'] as String,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.check_circle_rounded,
                                size: 20,
                                color: const Color(0xFF22C55E),
                              ),
                            ],
                          ),
                        ),
                      );
                      return row;
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    LocaleService.current.gotIt,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSupportedServicesDialog() {
    final primary = widget.theme.primary;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primary.withOpacity(0.15),
                      const Color(0xFFEC4899).withOpacity(0.1),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.music_note_rounded, color: primary, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                LocaleService.current.supportedServices,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                LocaleService.current.pasteLinkFromService,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 18),
              ..._supportedMusicServices.map(
                (svc) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: (svc['color'] as Color).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (svc['color'] as Color).withOpacity(0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          svc['icon'] as IconData,
                          size: 20,
                          color: svc['color'] as Color,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            svc['name'] as String,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        Icon(
                          svc['supported'] == true
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 20,
                          color: svc['supported'] == true
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    LocaleService.current.gotIt,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  Future<Map<String, String?>> _fetchMusicMeta(String url) async {
    final lower = url.toLowerCase();

    // ── YouTube / YouTube Music (official oEmbed — no API key required) ──
    if (lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('music.youtube.com')) {
      try {
        final resp = await http.get(
          Uri.parse(
            'https://www.youtube.com/oembed?url=${Uri.encodeComponent(url)}&format=json',
          ),
        );
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          return {
            'title': data['title'] as String?,
            'artist': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      } catch (e) {
        debugPrint('YouTube meta fetch error: $e');
      }
      return {};
    }

    // ── Spotify ──
    if (lower.contains('spotify.com')) {
      try {
        final oembedResp = await http.get(
          Uri.parse(
            'https://open.spotify.com/oembed?url=${Uri.encodeComponent(url)}',
          ),
          headers: {'User-Agent': 'Mozilla/5.0'},
        );
        String? parsedTitle;
        String? parsedArtist;
        String? cover;

        if (oembedResp.statusCode == 200) {
          final data = json.decode(oembedResp.body) as Map<String, dynamic>;
          parsedTitle = data['title'] as String?;
          cover = data['thumbnail_url'] as String?;
        }

        try {
          final pageResp = await http.get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          );
          if (pageResp.statusCode == 200) {
            final body = pageResp.body;
            final titleMatch = RegExp(
              r'<title[^>]*>(.+?)</title>',
              caseSensitive: false,
            ).firstMatch(body);
            if (titleMatch != null) {
              final pageTitle = titleMatch.group(1) ?? '';
              final byMatch = RegExp(
                r'(?:song and lyrics|[Aa]lbum|single)\s+by\s+(.+?)\s*\|\s*Spotify',
              ).firstMatch(pageTitle);
              if (byMatch != null) {
                parsedArtist = byMatch.group(1)?.trim();
              }
            }
          }
        } catch (_) {}

        return {'title': parsedTitle, 'artist': parsedArtist, 'cover': cover};
      } catch (e) {
        debugPrint('Spotify meta fetch error: $e');
      }
    }

    // ── Deezer ──
    final isDeezer =
        lower.contains('deezer.com') ||
        lower.contains('deezer.page.link') ||
        lower.contains('link.deezer.com');
    if (isDeezer) {
      try {
        // Resolve short/dynamic links → actual deezer.com/track/ URL
        String resolvedUrl = url;
        final isShortLink =
            lower.contains('deezer.page.link') ||
            lower.contains('link.deezer.com');
        if (isShortLink) {
          try {
            String current = url;
            for (int i = 0; i < 5; i++) {
              final httpClient = HttpClient();
              httpClient.connectionTimeout = const Duration(seconds: 6);
              final req = await httpClient.getUrl(Uri.parse(current));
              req.followRedirects = false;
              final resp = await req.close();
              final location = resp.headers.value('location');
              httpClient.close();
              if (location == null || location.isEmpty) break;
              current = location;
              if (current.toLowerCase().contains('deezer.com/') &&
                  current.toLowerCase().contains('/track/')) {
                resolvedUrl = current;
                break;
              }
              resolvedUrl = current;
            }
          } catch (_) {}
        }
        final resolvedLower = resolvedUrl.toLowerCase();

        final trackMatch = RegExp(
          r'deezer\.com/(?:[^/?#]+/)*track/(\d+)',
        ).firstMatch(resolvedLower);
        if (trackMatch != null) {
          final trackId = trackMatch.group(1);
          final apiResp = await http.get(
            Uri.parse('https://api.deezer.com/track/$trackId'),
            headers: {'Accept': 'application/json'},
          );
          if (apiResp.statusCode == 200) {
            final data = json.decode(apiResp.body) as Map<String, dynamic>;
            if (data['error'] == null) {
              return {
                'title': data['title'] as String?,
                'artist':
                    (data['artist'] as Map<String, dynamic>?)?['name']
                        as String?,
                'cover':
                    (data['album'] as Map<String, dynamic>?)?['cover_big']
                        as String?,
              };
            }
          }
        }
        // Fallback to oEmbed (works with both full and resolved URLs)
        final oembedResp = await http.get(
          Uri.parse(
            'https://noembed.com/embed?url=${Uri.encodeComponent(resolvedUrl)}',
          ),
        );
        if (oembedResp.statusCode == 200) {
          final data = json.decode(oembedResp.body) as Map<String, dynamic>;
          if (data['error'] == null && data['title'] != null) {
            return {
              'title': data['title'] as String?,
              'artist': data['author_name'] as String?,
              'cover': data['thumbnail_url'] as String?,
            };
          }
        }
      } catch (e) {
        debugPrint('Deezer meta fetch error: $e');
      }
    }

    // ── SoundCloud ──
    if (lower.contains('soundcloud.com')) {
      try {
        final oembedResp = await http.get(
          Uri.parse(
            'https://soundcloud.com/oembed?url=${Uri.encodeComponent(url)}&format=json',
          ),
        );
        if (oembedResp.statusCode == 200) {
          final data = json.decode(oembedResp.body) as Map<String, dynamic>;
          return {
            'title': data['title'] as String?,
            'artist': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      } catch (e) {
        debugPrint('SoundCloud meta fetch error: $e');
      }
    }

    // ── Яндекс Музыка ──
    if (lower.contains('music.yandex.') || lower.contains('music.yandex.com')) {
      try {
        final pageResp = await http.get(
          Uri.parse(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        );
        if (pageResp.statusCode == 200) {
          final body = pageResp.body;
          final titleMatch = RegExp(
            r'<title[^>]*>(.+?)</title>',
            caseSensitive: false,
          ).firstMatch(body);
          if (titleMatch != null) {
            final pageTitle = titleMatch.group(1) ?? '';
            // Format: "Song Name — Artist слушать онлайн на Яндекс Музыке"
            final parts = pageTitle.split('—');
            if (parts.length >= 2) {
              final title = parts[0].trim();
              final artistPart = parts[1]
                  .split(RegExp(r'слушать|listen'))
                  .first
                  .trim();
              return {'title': title, 'artist': artistPart, 'cover': null};
            }
          }
        }
      } catch (e) {
        debugPrint('Yandex Music meta fetch error: $e');
      }
    }

    // ── Apple Music ──
    if (lower.contains('music.apple.com')) {
      try {
        // Extract track ID from ?i= parameter (highest priority)
        final trackIdMatch = RegExp(r'[?&]i=(\d+)').firstMatch(url);
        // Fallback: last numeric segment in the path (album/song ID)
        final pathIdMatch = RegExp(
          r'/(\d+)(?:[?#/]|$)',
        ).allMatches(url).lastOrNull;
        final lookupId = trackIdMatch?.group(1) ?? pathIdMatch?.group(1);
        if (lookupId != null) {
          final resp = await http.get(
            Uri.parse(
              'https://itunes.apple.com/lookup?id=$lookupId&entity=song',
            ),
          );
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body) as Map<String, dynamic>;
            final results = data['results'] as List?;
            if (results != null && results.isNotEmpty) {
              final track =
                  results.firstWhere(
                        (r) => r['wrapperType'] == 'track',
                        orElse: () => results.first,
                      )
                      as Map<String, dynamic>;
              return {
                'title': track['trackName'] as String?,
                'artist': track['artistName'] as String?,
                'cover': track['artworkUrl100'] as String?,
              };
            }
          }
        }
      } catch (e) {
        debugPrint('Apple Music meta fetch error: $e');
      }
    }

    // ── Tidal ──
    if (lower.contains('tidal.com')) {
      try {
        // Tidal serves pre-rendered OG tags to social media bots
        final pageResp = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'Twitterbot/1.0'},
        );
        if (pageResp.statusCode == 200) {
          final body = pageResp.body;
          final ogTitleMatch = RegExp(
            r'property="og:title"\s+content="([^"]+)"',
            caseSensitive: false,
          ).firstMatch(body);
          final ogImageMatch = RegExp(
            r'property="og:image"\s+content="([^"]+)"',
            caseSensitive: false,
          ).firstMatch(body);
          if (ogTitleMatch != null) {
            // Format: "Artist - Title"
            final raw = _decodeHtmlEntities(ogTitleMatch.group(1) ?? '');
            final sepIdx = raw.indexOf(' - ');
            if (sepIdx != -1) {
              return {
                'title': raw.substring(sepIdx + 3).trim(),
                'artist': raw.substring(0, sepIdx).trim(),
                'cover': ogImageMatch?.group(1),
              };
            }
            return {
              'title': raw.isNotEmpty ? raw : null,
              'artist': null,
              'cover': ogImageMatch?.group(1),
            };
          }
        }
      } catch (e) {
        debugPrint('Tidal meta fetch error: $e');
      }
    }

    // ── Generic fallback — noembed.com (works for many services) ──
    try {
      final oembedResp = await http.get(
        Uri.parse('https://noembed.com/embed?url=${Uri.encodeComponent(url)}'),
      );
      if (oembedResp.statusCode == 200) {
        final data = json.decode(oembedResp.body) as Map<String, dynamic>;
        if (data['error'] == null) {
          return {
            'title': data['title'] as String?,
            'artist': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      }
    } catch (_) {}

    return {};
  }

  void _showCreateMemoryForm(MemoryType type) {
    final titleCtrl = TextEditingController();
    final captionCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final musicTitleCtrl = TextEditingController();
    final musicArtistCtrl = TextEditingController();
    final musicUrlCtrl = TextEditingController();
    final videoLinkCtrl = TextEditingController();

    // Local state for file selections
    List<XFile> selectedPhotos = [];
    XFile? selectedMedia; // video only
    Uint8List? videoThumbnailBytes;
    bool isGeneratingThumbnail = false;
    String? selectedMusicPath;
    double? lat;
    double? lng;
    bool isLoadingLocation = false;
    bool isFetchingMeta = false;
    String? fetchedCoverUrl;
    bool isFetchingVideoMeta = false;
    String? fetchedVideoThumb;
    String? fetchedVideoAuthor;
    bool useVideoUrl = false;
    bool isAdultPhoto = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        LocaleService.current.newMemory(_typeName(type)),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ),
                    if (type == MemoryType.music)
                      GestureDetector(
                        onTap: _showSupportedServicesDialog,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 20,
                            color: primary,
                          ),
                        ),
                      ),
                    if (type == MemoryType.video)
                      GestureDetector(
                        onTap: _showSupportedVideoServicesDialog,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 20,
                            color: primary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Photo/Video picker ──
                if (type == MemoryType.photo) ...[
                  // Thumbnails of already selected photos
                  if (selectedPhotos.isNotEmpty) ...[
                    SizedBox(
                      height: 88,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: selectedPhotos.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          if (i == selectedPhotos.length) {
                            return GestureDetector(
                              onTap: () async {
                                try {
                                  final picker = ImagePicker();
                                  final picked = await picker.pickMultiImage(
                                    maxWidth: 1920,
                                    maxHeight: 1920,
                                    imageQuality: 85,
                                  );
                                  if (picked.isNotEmpty) {
                                    setState(() => selectedPhotos.addAll(picked));
                                    if (lat == null) {
                                      _extractExifGps(picked.first.path).then((coords) async {
                                        if (coords == null) return;
                                        String addr = '';
                                        try {
                                          final ps = await placemarkFromCoordinates(coords.$1, coords.$2);
                                          if (ps.isNotEmpty) {
                                            final place = ps.first;
                                            final name = place.name ?? place.subLocality ?? '';
                                            final locality = place.locality ?? '';
                                            addr = name.isNotEmpty ? '$name, $locality' : locality;
                                          }
                                        } catch (_) {}
                                        if (context.mounted) {
                                          setState(() {
                                            lat = coords.$1;
                                            lng = coords.$2;
                                            locationCtrl.text = addr;
                                          });
                                        }
                                      });
                                    }
                                  }
                                } catch (e) {
                                  debugPrint('Pick photos failed: $e');
                                }
                              },
                              child: Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: primary.withOpacity(0.35),
                                  ),
                                ),
                                child: Icon(
                                  Icons.add_rounded,
                                  color: primary,
                                  size: 28,
                                ),
                              ),
                            );
                          }
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(selectedPhotos[i].path),
                                  width: 88,
                                  height: 88,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => selectedPhotos.removeAt(i),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                      size: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Empty state — tap to pick photos
                  if (selectedPhotos.isEmpty)
                    GestureDetector(
                      onTap: () async {
                        try {
                          final picker = ImagePicker();
                          final picked = await picker.pickMultiImage(
                            maxWidth: 1920,
                            maxHeight: 1920,
                            imageQuality: 85,
                          );
                          if (picked.isNotEmpty) {
                            setState(() => selectedPhotos = picked);
                            if (lat == null) {
                              _extractExifGps(picked.first.path).then((coords) async {
                                if (coords == null) return;
                                String addr = '';
                                try {
                                  final ps = await placemarkFromCoordinates(coords.$1, coords.$2);
                                  if (ps.isNotEmpty) {
                                    final place = ps.first;
                                    final name = place.name ?? place.subLocality ?? '';
                                    final locality = place.locality ?? '';
                                    addr = name.isNotEmpty ? '$name, $locality' : locality;
                                  }
                                } catch (_) {}
                                if (context.mounted) {
                                  setState(() {
                                    lat = coords.$1;
                                    lng = coords.$2;
                                    locationCtrl.text = addr;
                                  });
                                }
                              });
                            }
                          }
                        } catch (e) {
                          debugPrint('Pick photos failed: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  LocaleService.current.failedSelectPhotos(
                                    e.toString(),
                                  ),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_rounded,
                                size: 28,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                LocaleService.current.tapToSelectPhotos,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // 18+ toggle for photo pins
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setState(() => isAdultPhoto = !isAdultPhoto),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isAdultPhoto
                            ? Colors.red.shade50
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isAdultPhoto
                              ? Colors.red.shade200
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isAdultPhoto
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            size: 18,
                            color: isAdultPhoto
                                ? Colors.red.shade400
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  LocaleService.current.adultContent,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isAdultPhoto
                                        ? Colors.red.shade600
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                Text(
                                  LocaleService.current.photoBlurred,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isAdultPhoto
                                        ? Colors.red.shade400
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: isAdultPhoto,
                            onChanged: (v) => setState(() => isAdultPhoto = v),
                            activeColor: Colors.red.shade400,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── Location for photo ──
                  const SizedBox(height: 8),
                  if (lat != null && lng != null) ...[
                    GestureDetector(
                      onTap: () => setState(() {
                        lat = null;
                        lng = null;
                        locationCtrl.clear();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withOpacity(0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF22C55E).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 14,
                              color: Color(0xFF22C55E),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                locationCtrl.text.isNotEmpty
                                    ? locationCtrl.text
                                    : '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF22C55E),
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.close_rounded, size: 14, color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isLoadingLocation
                                ? null
                                : () async {
                                    setState(() => isLoadingLocation = true);
                                    try {
                                      if (!await Geolocator.isLocationServiceEnabled()) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(LocaleService.current.locationServicesDisabled),
                                            ),
                                          );
                                        }
                                        setState(() => isLoadingLocation = false);
                                        return;
                                      }
                                      LocationPermission perm = await Geolocator.checkPermission();
                                      if (perm == LocationPermission.denied) {
                                        perm = await Geolocator.requestPermission();
                                      }
                                      if (perm == LocationPermission.denied ||
                                          perm == LocationPermission.deniedForever) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(LocaleService.current.locationPermissionDenied),
                                            ),
                                          );
                                        }
                                        setState(() => isLoadingLocation = false);
                                        return;
                                      }
                                      final pos = await Geolocator.getCurrentPosition();
                                      lat = pos.latitude;
                                      lng = pos.longitude;
                                      try {
                                        final ps = await placemarkFromCoordinates(lat!, lng!);
                                        if (ps.isNotEmpty) {
                                          final place = ps.first;
                                          final name = place.name ?? place.subLocality ?? '';
                                          final locality = place.locality ?? '';
                                          locationCtrl.text = name.isNotEmpty
                                              ? '$name, $locality'
                                              : locality;
                                        }
                                      } catch (_) {}
                                    } catch (e) {
                                      debugPrint('Get location error: $e');
                                    }
                                    setState(() => isLoadingLocation = false);
                                  },
                            icon: isLoadingLocation
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: primary,
                                    ),
                                  )
                                : const Icon(Icons.my_location_rounded),
                            label: Text(
                              LocaleService.current.useCurrent,
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primary,
                              side: BorderSide(color: primary),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final result = await Navigator.push<Map<String, dynamic>>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MapPickerScreen(
                                    initialLatitude: lat,
                                    initialLongitude: lng,
                                  ),
                                ),
                              );
                              if (result != null && context.mounted) {
                                setState(() {
                                  lat = result['latitude'] as double?;
                                  lng = result['longitude'] as double?;
                                  locationCtrl.text = result['address'] as String? ?? '';
                                });
                              }
                            },
                            icon: const Icon(Icons.map_rounded),
                            label: Text(
                              LocaleService.current.pickOnMap,
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF22C55E),
                              side: const BorderSide(color: Color(0xFF22C55E)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                ] else if (type == MemoryType.video) ...[
                  // ── Toggle: Из галереи / По ссылке ──
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            useVideoUrl = false;
                            selectedMedia = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !useVideoUrl
                                  ? primary.withOpacity(0.10)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: !useVideoUrl
                                    ? primary.withOpacity(0.30)
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.video_library_rounded,
                                  size: 16,
                                  color: !useVideoUrl
                                      ? primary
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  LocaleService.current.fromGallery,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: !useVideoUrl
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: !useVideoUrl
                                        ? primary
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            useVideoUrl = true;
                            selectedMedia = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: useVideoUrl
                                  ? const Color(0xFFEC4899).withOpacity(0.10)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: useVideoUrl
                                    ? const Color(0xFFEC4899).withOpacity(0.30)
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.link_rounded,
                                  size: 16,
                                  color: useVideoUrl
                                      ? const Color(0xFFEC4899)
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  LocaleService.current.byLink,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: useVideoUrl
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: useVideoUrl
                                        ? const Color(0xFFEC4899)
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!useVideoUrl) ...[
                    // ── File picker ──
                    GestureDetector(
                      onTap: () async {
                        try {
                          final picker = ImagePicker();
                          final picked = await picker.pickVideo(
                            source: ImageSource.gallery,
                          );
                          if (picked != null) {
                            setState(() {
                              selectedMedia = picked;
                              videoThumbnailBytes = null;
                              isGeneratingThumbnail = true;
                            });
                            try {
                              final thumb =
                                  await VideoCompress.getByteThumbnail(
                                picked.path,
                                quality: 60,
                                position: -1,
                              );
                              setState(() {
                                videoThumbnailBytes = thumb;
                                isGeneratingThumbnail = false;
                              });
                            } catch (e) {
                              debugPrint('Thumbnail preview failed: $e');
                              setState(() => isGeneratingThumbnail = false);
                            }
                          }
                        } catch (e) {
                          debugPrint('Pick video failed: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  LocaleService.current.failedSelectVideo(
                                    e.toString(),
                                  ),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: selectedMedia != null ? 200 : 100,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: selectedMedia != null
                              ? Colors.grey.shade900
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                          image: videoThumbnailBytes != null
                              ? DecorationImage(
                                  image: MemoryImage(videoThumbnailBytes!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: selectedMedia == null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.videocam_rounded,
                                      size: 28,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      LocaleService.current.tapToSelectVideo,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : isGeneratingThumbnail
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (videoThumbnailBytes != null)
                                        Container(
                                          color: Colors.black38,
                                        ),
                                      const Center(
                                        child: Icon(
                                          Icons.play_circle_filled_rounded,
                                          color: Colors.white,
                                          size: 48,
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: CircleAvatar(
                                          backgroundColor: Colors.black54,
                                          radius: 16,
                                          child: const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    // ── URL input ──
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEC4899).withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFEC4899).withOpacity(0.18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFEC4899,
                                  ).withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.link_rounded,
                                  size: 16,
                                  color: Color(0xFFEC4899),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                LocaleService.current.videoLink,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: videoLinkCtrl,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            onChanged: (_) {},
                            decoration: InputDecoration(
                              hintText: 'YouTube, Vimeo, TikTok, Twitch...',
                              prefixIcon: const Icon(
                                Icons.play_circle_outline_rounded,
                                size: 20,
                              ),
                              suffixIcon: isFetchingVideoMeta
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.search_rounded),
                                      tooltip: LocaleService.current.fetchData,
                                      onPressed: () async {
                                        final url = videoLinkCtrl.text.trim();
                                        if (url.isEmpty) return;
                                        setState(
                                          () => isFetchingVideoMeta = true,
                                        );
                                        final meta = await _fetchVideoMeta(url);
                                        setState(() {
                                          isFetchingVideoMeta = false;
                                          if (meta['title'] != null &&
                                              meta['title']!.isNotEmpty) {
                                            titleCtrl.text = meta['title']!;
                                          }
                                          fetchedVideoThumb = meta['cover'];
                                          fetchedVideoAuthor = meta['author'];
                                          if (meta['author'] != null) {
                                            musicArtistCtrl.text =
                                                meta['author']!;
                                          }
                                        });
                                      },
                                    ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                            ),
                          ),
                          // Preview thumbnail if fetched
                          if (fetchedVideoThumb != null) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: fetchedVideoThumb!,
                                    width: 72,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 144,
                                    memCacheHeight: 96,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (titleCtrl.text.isNotEmpty)
                                        Text(
                                          titleCtrl.text,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade800,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      if (fetchedVideoAuthor != null)
                                        Text(
                                          fetchedVideoAuthor!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                          maxLines: 1,
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            LocaleService.current.supportedPlatformsHint,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ] else if (type == MemoryType.videoLink) ...[
                  // legacy — existing videoLink memories; form handled via video toggle
                  const SizedBox(height: 0),
                ],
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primary.withOpacity(0.04),
                        const Color(0xFFEC4899).withOpacity(0.03),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: primary.withOpacity(0.12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.edit_note_rounded,
                              size: 16,
                              color: primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            LocaleService.current.memoryDetails,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: titleCtrl,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: LocaleService.current.titleOptional,
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          prefixIcon: Icon(
                            Icons.title_rounded,
                            color: primary,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: primary, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: captionCtrl,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: type == MemoryType.text
                              ? LocaleService.current.writeYourNote
                              : LocaleService.current.descriptionOptional,
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(bottom: 40),
                            child: Icon(
                              Icons.notes_rounded,
                              color: primary,
                              size: 20,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: primary, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                      // Spoiler toolbar — shown only for text pins
                      if (type == MemoryType.text) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                final sel = captionCtrl.selection;
                                if (!sel.isValid) return;
                                final text = captionCtrl.text;
                                if (sel.isCollapsed) {
                                  // Insert empty spoiler at cursor
                                  final pos = sel.start;
                                  final newText =
                                      '${text.substring(0, pos)}||||${text.substring(pos)}';
                                  captionCtrl.value = TextEditingValue(
                                    text: newText,
                                    selection: TextSelection.collapsed(
                                      offset: pos + 2,
                                    ),
                                  );
                                } else {
                                  final selected = text.substring(
                                    sel.start,
                                    sel.end,
                                  );
                                  final newText = text.replaceRange(
                                    sel.start,
                                    sel.end,
                                    '||$selected||',
                                  );
                                  captionCtrl.value = TextEditingValue(
                                    text: newText,
                                    selection: TextSelection.collapsed(
                                      offset: sel.start + selected.length + 4,
                                    ),
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.visibility_off_rounded,
                                      size: 14,
                                      color: primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      LocaleService.current.spoiler,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              LocaleService.current.selectTextAndPress,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Location fields ──
                if (type == MemoryType.location) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationCtrl,
                    decoration: InputDecoration(
                      hintText: LocaleService.current.locationNameHint,
                      prefixIcon: const Icon(Icons.location_on_rounded),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isLoadingLocation
                              ? null
                              : () async {
                                  setState(() => isLoadingLocation = true);
                                  try {
                                    bool serviceEnabled =
                                        await Geolocator.isLocationServiceEnabled();
                                    if (!serviceEnabled) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              LocaleService
                                                  .current
                                                  .locationServicesDisabled,
                                            ),
                                          ),
                                        );
                                      }
                                      setState(() => isLoadingLocation = false);
                                      return;
                                    }

                                    LocationPermission permission =
                                        await Geolocator.checkPermission();
                                    if (permission ==
                                        LocationPermission.denied) {
                                      permission =
                                          await Geolocator.requestPermission();
                                    }
                                    if (permission ==
                                            LocationPermission.denied ||
                                        permission ==
                                            LocationPermission.deniedForever) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              LocaleService
                                                  .current
                                                  .locationPermissionDenied,
                                            ),
                                          ),
                                        );
                                      }
                                      setState(() => isLoadingLocation = false);
                                      return;
                                    }

                                    final position =
                                        await Geolocator.getCurrentPosition();
                                    lat = position.latitude;
                                    lng = position.longitude;

                                    // Try to get address
                                    try {
                                      final placemarks =
                                          await placemarkFromCoordinates(
                                            lat!,
                                            lng!,
                                          );
                                      if (placemarks.isNotEmpty) {
                                        final place = placemarks.first;
                                        final name =
                                            place.name ??
                                            place.subLocality ??
                                            '';
                                        final locality = place.locality ?? '';
                                        locationCtrl.text = name.isNotEmpty
                                            ? '$name, $locality'
                                            : locality;
                                      }
                                    } catch (e) {
                                      debugPrint('Geocoding failed: $e');
                                    }
                                  } catch (e) {
                                    debugPrint('Get location failed: $e');
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            LocaleService
                                                .current
                                                .failedGetLocation,
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                  setState(() => isLoadingLocation = false);
                                },
                          icon: isLoadingLocation
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: M3LoadingDots(
                                    color: primary,
                                    dotSize: 4,
                                    gap: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location_rounded),
                          label: Text(
                            lat != null && lng != null
                                ? LocaleService.current.locationSet
                                : LocaleService.current.useCurrent,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primary,
                            side: BorderSide(color: primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MapPickerScreen(
                                  initialLatitude: lat,
                                  initialLongitude: lng,
                                ),
                              ),
                            );

                            if (result != null && mounted) {
                              setState(() {
                                lat = result['latitude'];
                                lng = result['longitude'];
                                locationCtrl.text = result['address'] ?? '';
                              });
                            }
                          },
                          icon: const Icon(Icons.map_rounded),
                          label: Text(
                            LocaleService.current.pickOnMap,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF22C55E),
                            side: const BorderSide(color: Color(0xFF22C55E)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // ── Music fields ──
                if (type == MemoryType.music) ...[
                  // ─── Section: Song Details ───
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          primary.withOpacity(0.04),
                          const Color(0xFFEC4899).withOpacity(0.03),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: primary.withOpacity(0.12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.music_note_rounded,
                                size: 16,
                                color: primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              LocaleService.current.songDetails,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: musicTitleCtrl,
                          style: const TextStyle(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: LocaleService.current.songName,
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            prefixIcon: Icon(
                              Icons.audiotrack_rounded,
                              color: primary,
                              size: 20,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: primary,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: musicArtistCtrl,
                          style: const TextStyle(fontSize: 15),
                          decoration: InputDecoration(
                            hintText:
                                LocaleService.current.artistsCommaSeparated,
                            helperText: LocaleService.current.egArtists,
                            helperStyle: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            prefixIcon: Icon(
                              Icons.person_rounded,
                              color: primary,
                              size: 20,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: primary,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ─── Divider ───
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Colors.grey.shade200,
                            height: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.link_rounded,
                                  size: 14,
                                  color: primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  LocaleService.current.source,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Colors.grey.shade200,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ─── Section: Link / Upload ───
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.link_rounded,
                                size: 16,
                                color: Color(0xFF22C55E),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                LocaleService.current.streamingLink,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                            if (fetchedCoverUrl != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF22C55E,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      size: 12,
                                      color: Color(0xFF22C55E),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      LocaleService.current.fetched,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF22C55E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: musicUrlCtrl,
                          style: const TextStyle(fontSize: 14),
                          onSubmitted: (v) async {
                            final url = v.trim();
                            if (url.isEmpty) return;
                            setState(() => isFetchingMeta = true);
                            final meta = await _fetchMusicMeta(url);
                            setState(() {
                              isFetchingMeta = false;
                              if ((meta['title']?.isNotEmpty ?? false) &&
                                  musicTitleCtrl.text.isEmpty) {
                                musicTitleCtrl.text = meta['title']!;
                              }
                              if ((meta['artist']?.isNotEmpty ?? false) &&
                                  musicArtistCtrl.text.isEmpty) {
                                musicArtistCtrl.text = meta['artist']!;
                              }
                              if (meta['cover']?.isNotEmpty ?? false) {
                                fetchedCoverUrl = meta['cover'];
                              }
                            });
                          },
                          decoration: InputDecoration(
                            hintText:
                                LocaleService.current.pasteLinkFromService,
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.link_rounded,
                              color: primary,
                              size: 20,
                            ),
                            suffixIcon: isFetchingMeta
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: M3LoadingDots(
                                        color: Colors.grey,
                                        dotSize: 4,
                                        gap: 2,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    icon: Icon(
                                      Icons.manage_search_rounded,
                                      color: primary,
                                    ),
                                    tooltip:
                                        LocaleService.current.autoFetchSongInfo,
                                    onPressed: () async {
                                      final url = musicUrlCtrl.text.trim();
                                      if (url.isEmpty) return;
                                      setState(() => isFetchingMeta = true);
                                      final meta = await _fetchMusicMeta(url);
                                      setState(() {
                                        isFetchingMeta = false;
                                        if ((meta['title']?.isNotEmpty ??
                                                false) &&
                                            musicTitleCtrl.text.isEmpty) {
                                          musicTitleCtrl.text = meta['title']!;
                                        }
                                        if ((meta['artist']?.isNotEmpty ??
                                                false) &&
                                            musicArtistCtrl.text.isEmpty) {
                                          musicArtistCtrl.text =
                                              meta['artist']!;
                                        }
                                        if (meta['cover']?.isNotEmpty ??
                                            false) {
                                          fetchedCoverUrl = meta['cover'];
                                        }
                                      });
                                    },
                                  ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: primary,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // ── OR divider ──
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: Colors.grey.shade300,
                                height: 1,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                LocaleService.current.orDivider,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: Colors.grey.shade300,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // ── File picker ──
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final result = await FilePicker.platform
                                  .pickFiles(type: FileType.audio);
                              if (result != null && result.files.isNotEmpty) {
                                setState(
                                  () => selectedMusicPath =
                                      result.files.first.path,
                                );
                                if (musicTitleCtrl.text.isEmpty) {
                                  musicTitleCtrl.text = result.files.first.name
                                      .split('.')
                                      .first;
                                }
                              }
                            },
                            icon: Icon(
                              selectedMusicPath != null
                                  ? Icons.check_circle_rounded
                                  : Icons.upload_file_rounded,
                              size: 18,
                            ),
                            label: Text(
                              selectedMusicPath != null
                                  ? '${LocaleService.current.fileSelected} ✓'
                                  : LocaleService.current.pickAudioFromDevice,
                              style: const TextStyle(fontSize: 13),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: selectedMusicPath != null
                                  ? const Color(0xFF22C55E)
                                  : primary,
                              side: BorderSide(
                                color: selectedMusicPath != null
                                    ? const Color(0xFF22C55E)
                                    : primary,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      // When video form is in "by link" mode — treat as videoLink
                      final effectiveType =
                          (type == MemoryType.video && useVideoUrl)
                          ? MemoryType.videoLink
                          : type;
                      await _saveNewMemory(
                        type: effectiveType,
                        title: titleCtrl.text.trim(),
                        caption: captionCtrl.text.trim(),
                        locationName: locationCtrl.text.trim(),
                        latitude: lat,
                        longitude: lng,
                        musicTitle: musicTitleCtrl.text.trim(),
                        musicArtist: musicArtistCtrl.text.trim(),
                        musicUrl: musicUrlCtrl.text.trim(),
                        musicCoverUrl: fetchedCoverUrl,
                        mediaPaths: selectedPhotos.isNotEmpty
                            ? selectedPhotos.map((f) => f.path).toList()
                            : null,
                        mediaPath: selectedMedia?.path,
                        musicPath: selectedMusicPath,
                        // videoLink-specific
                        videoLinkUrl: effectiveType == MemoryType.videoLink
                            ? videoLinkCtrl.text.trim()
                            : null,
                        videoLinkThumb: fetchedVideoThumb,
                        videoLinkAuthor: musicArtistCtrl.text.trim(),
                        isAdult: isAdultPhoto,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 8,
                      shadowColor: primary.withOpacity(0.3),
                    ),
                    child: Text(
                      LocaleService.current.addMemoryTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _typeName(MemoryType type) {
    final s = LocaleService.current;
    switch (type) {
      case MemoryType.photo:
        return s.photo;
      case MemoryType.video:
        return s.video;
      case MemoryType.videoLink:
        return s.video;
      case MemoryType.location:
        return s.location;
      case MemoryType.music:
        return s.music;
      case MemoryType.text:
        return s.note;
    }
  }

  Future<void> _saveNewMemory({
    required MemoryType type,
    String title = '',
    String caption = '',
    String locationName = '',
    double? latitude,
    double? longitude,
    String musicTitle = '',
    String musicArtist = '',
    String musicUrl = '',
    String? musicCoverUrl,
    List<String>? mediaPaths, // multiple photos
    String? mediaPath, // single video
    String? musicPath,
    // videoLink
    String? videoLinkUrl,
    String? videoLinkThumb,
    String? videoLinkAuthor,
    bool isAdult = false,
  }) async {
    final user = _fb.currentUser;
    if (user == null || _groupId.isEmpty) return;

    // Check rate limit before uploading to avoid wasting bandwidth
    try {
      await RateLimiterService().checkMemory();
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
      return;
    }

    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: M3LoadingDots(color: Colors.white, dotSize: 5, gap: 2),
              ),
              const SizedBox(width: 12),
              Text(LocaleService.current.uploadingMemory),
            ],
          ),
          duration: const Duration(seconds: 30),
        ),
      );
    }

    String? uploadedImageUrl;
    List<String> uploadedImageUrls = [];
    String? uploadedVideoUrl;
    String? uploadedMusicUrl;

    try {
      // Upload multiple photos if selected
      if (type == MemoryType.photo &&
          mediaPaths != null &&
          mediaPaths.isNotEmpty) {
        for (final path in mediaPaths) {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final ext = path.split('.').last;
          final fileName = 'memory_$timestamp.$ext';
          final destination = 'memories/$_groupId/$fileName';
          final url = await _fb.uploadFile(path, destination);
          if (url != null) uploadedImageUrls.add(url);
        }
        if (uploadedImageUrls.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(LocaleService.current.failedUploadPhotos),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
        uploadedImageUrl = uploadedImageUrls.first;
      }

      // Upload video if selected
      if (type == MemoryType.video && mediaPath != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final ext = mediaPath.split('.').last;
        final fileName = 'memory_$timestamp.$ext';
        final destination = 'memories/$_groupId/$fileName';

        // Generate and upload thumbnail so the preview card has an image
        try {
          final thumbBytes = await VideoCompress.getByteThumbnail(
            mediaPath,
            quality: 80,
            position: -1,
          );
          if (thumbBytes != null) {
            final tempDir = await getTemporaryDirectory();
            final thumbFile =
                File('${tempDir.path}/thumb_$timestamp.jpg');
            await thumbFile.writeAsBytes(thumbBytes);
            final thumbUrl = await _fb.uploadFile(
              thumbFile.path,
              'memories/$_groupId/thumb_$timestamp.jpg',
            );
            thumbFile.delete().catchError((_) => thumbFile);
            if (thumbUrl != null) uploadedImageUrl = thumbUrl;
          }
        } catch (e) {
          debugPrint('Video thumbnail upload failed: $e');
        }

        final url = await _fb.uploadFile(mediaPath, destination);
        if (url != null) {
          uploadedVideoUrl = url;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(LocaleService.current.failedUploadVideo),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      }

      // Upload music file if selected
      if (musicPath != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final ext = musicPath.split('.').last;
        final fileName = 'music_$timestamp.$ext';
        final destination = 'music/$_groupId/$fileName';

        uploadedMusicUrl = await _fb.uploadFile(musicPath, destination);
      }

      // Use provided musicUrl if no file uploaded
      final finalMusicUrl =
          uploadedMusicUrl ?? (musicUrl.isNotEmpty ? musicUrl : null);

      // For videoLink type — resolve fields
      final finalVideoUrl = type == MemoryType.videoLink
          ? (videoLinkUrl?.isNotEmpty == true ? videoLinkUrl : null)
          : uploadedVideoUrl;
      final finalImageUrl = type == MemoryType.videoLink
          ? videoLinkThumb
          : uploadedImageUrl;
      final finalMusicArtist = type == MemoryType.videoLink
          ? (videoLinkAuthor?.isNotEmpty == true ? videoLinkAuthor : null)
          : (musicArtist.isNotEmpty ? musicArtist : null);

      await _fb.addMemory(
        groupId: _groupId,
        type: type,
        title: title.isNotEmpty ? title : null,
        caption: caption.isNotEmpty ? caption : null,
        locationName: locationName.isNotEmpty ? locationName : null,
        latitude: latitude,
        longitude: longitude,
        musicTitle: musicTitle.isNotEmpty ? musicTitle : null,
        musicArtist: finalMusicArtist,
        musicUrl: finalMusicUrl,
        musicCoverUrl: musicCoverUrl,
        imageUrl: finalImageUrl,
        imageUrls: uploadedImageUrls.isNotEmpty ? uploadedImageUrls : null,
        videoUrl: finalVideoUrl,
        isAdult: isAdult,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocaleService.current.memoryAddedSuccess),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Save memory failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocaleService.current.failedAddMemory(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // =============================================
  // HELPER METHODS: Location, Distance, Time, Avatar
  // =============================================

  /// Fetch user location for distance display on photo cards
  /// Extract GPS (lat, lng) from a photo file's EXIF data.
  /// Returns null if no GPS tag found or parsing fails.
  static Future<(double, double)?> _extractExifGps(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final tags = await readExifFromBytes(bytes);
      if (!tags.containsKey('GPS GPSLatitude') ||
          !tags.containsKey('GPS GPSLongitude')) return null;
      final latRef = tags['GPS GPSLatitudeRef']?.printable.trim() ?? 'N';
      final lngRef = tags['GPS GPSLongitudeRef']?.printable.trim() ?? 'E';
      double? toDeg(String raw) {
        final clean = raw.replaceAll(RegExp(r'[\[\]\s]'), '');
        final parts = clean.split(',');
        if (parts.length < 3) return null;
        double p(String s) {
          if (s.contains('/')) {
            final f = s.split('/');
            final n = double.tryParse(f[0]);
            final d = double.tryParse(f[1]);
            if (n == null || d == null || d == 0) return 0;
            return n / d;
          }
          return double.tryParse(s) ?? 0;
        }
        return p(parts[0]) + p(parts[1]) / 60.0 + p(parts[2]) / 3600.0;
      }
      final latVal = toDeg(tags['GPS GPSLatitude']!.printable);
      final lngVal = toDeg(tags['GPS GPSLongitude']!.printable);
      if (latVal == null || lngVal == null || (latVal == 0.0 && lngVal == 0.0)) {
        return null;
      }
      return (latRef == 'S' ? -latVal : latVal, lngRef == 'W' ? -lngVal : lngVal);
    } catch (e) {
      debugPrint('EXIF GPS extraction failed: $e');
      return null;
    }
  }

  Future<void> _fetchUserLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return;
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) { return; }

      // Use last known position instantly so pills show right away
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() {
          _userLat = last.latitude;
          _userLng = last.longitude;
        });
      }

      // Then get a fresh fix and update
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) {
        setState(() {
          _userLat = pos.latitude;
          _userLng = pos.longitude;
        });
      }
    } catch (e) {
      debugPrint('Failed to get user location: $e');
    }
  }

  /// Calculate distance in km between user and a point
  String _distanceKm(double lat, double lng) {
    if (_userLat == null || _userLng == null) return '';
    final d = Geolocator.distanceBetween(_userLat!, _userLng!, lat, lng);
    if (d < 1000) return '${d.round()}m';
    return '${(d / 1000).toStringAsFixed(1)}km';
  }

  /// Color for distance pill based on proximity
  Color _distanceColor(double lat, double lng) {
    if (_userLat == null || _userLng == null) return Colors.grey;
    final km = Geolocator.distanceBetween(_userLat!, _userLng!, lat, lng) / 1000;
    if (km < 1) return const Color(0xFF22C55E);
    if (km < 10) return const Color(0xFF16A34A);
    if (km < 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  /// Colored location distance pill shown on photo/video tiles.
  /// Shows distance + color when user GPS is known; falls back to
  /// location name (grey) when user GPS is unavailable.
  Widget _locationDistancePill(Memory memory) {
    final hasCoords = memory.latitude != null && memory.longitude != null;
    final hasName = memory.locationName?.isNotEmpty == true;
    if (!hasCoords && !hasName) return const SizedBox.shrink();

    Widget pill;
    if (hasCoords) {
      final dist = _distanceKm(memory.latitude!, memory.longitude!);
      if (dist.isNotEmpty) {
        // User GPS known → colored distance pill
        final color = _distanceColor(memory.latitude!, memory.longitude!);
        pill = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.35), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_rounded, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                dist,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        );
      } else {
        // No user GPS → grey pin icon only (no name on closed tiles)
        pill = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Icon(Icons.location_on_rounded, size: 12, color: Colors.grey.shade500),
        );
      }
    } else {
      // locationName only, no coords — grey pin icon
      pill = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        child: Icon(Icons.location_on_rounded, size: 12, color: Colors.grey.shade500),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Row(children: [pill]),
    );
  }

  /// Open MapPickerScreen to set/change location on any memory type
  Future<void> _setLocationOnMemory(Memory memory) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLatitude: memory.latitude,
          initialLongitude: memory.longitude,
        ),
      ),
    );
    if (result == null) return;
    final lat = result['latitude'] as double?;
    final lng = result['longitude'] as double?;
    final address = result['address'] as String?;
    if (lat == null || lng == null) return;
    await _fb.updateMemory(
      groupId: _groupId,
      memoryId: memory.id,
      latitude: lat,
      longitude: lng,
      locationName: memory.locationName?.isNotEmpty == true
          ? memory.locationName
          : address,
    );
  }

  // ── Global gallery helpers ─────────────────────────────────────────────────

  /// Flattens all photo/video memories into a single ordered list for cross-pin swiping.
  List<GalleryItem> get _allGalleryItems {
    final items = <GalleryItem>[];
    final sorted = [..._memories]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final m in sorted) {
      if (m.type == MemoryType.photo) {
        final urls = <String>[
          if (m.imageUrls?.isNotEmpty == true)
            ...m.imageUrls!
          else if (m.imageUrl?.isNotEmpty == true)
            m.imageUrl!,
        ];
        for (final url in urls) {
          items.add(GalleryItem(url: url, memoryId: m.id, caption: m.caption));
        }
      } else if (m.type == MemoryType.video &&
          m.videoUrl?.isNotEmpty == true) {
        items.add(GalleryItem(
          url: m.imageUrl?.isNotEmpty == true ? m.imageUrl! : m.videoUrl!,
          videoUrl: m.videoUrl,
          memoryId: m.id,
          caption: m.caption,
        ));
      }
    }
    return items;
  }

  void _openPhotoGalleryScreen() async {
    final items = _allGalleryItems;
    if (items.isEmpty) return;
    final memoryId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _PhotoGalleryScreen(items: items, primary: primary),
      ),
    );
    if (memoryId != null && mounted) {
      final mem = _memories.firstWhere(
        (m) => m.id == memoryId,
        orElse: () => _memories.first,
      );
      _showMemoryDetail(mem);
    }
  }

  /// Format time ago from DateTime using localized strings
  String _formatTimeAgo(DateTime dt) {
    final s = LocaleService.current;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return s.justNow;
    if (diff.inMinutes < 60) return s.minutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return s.hoursAgo(diff.inHours);
    if (diff.inDays < 30) return s.daysAgo(diff.inDays);
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  /// Open fullscreen cross-pin gallery, returns memoryId if "go to pin" tapped.
  Future<String?> _openFullscreenGallery(
    BuildContext ctx,
    List<GalleryItem> items,
    int initialIndex,
  ) {
    return Navigator.of(ctx).push<String>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) =>
            FullscreenGallery(items: items, initialIndex: initialIndex),
      ),
    );
  }

  /// Open location in external maps app
  Future<void> _openLocationInMaps(
    double lat,
    double lng,
    String? label,
  ) async {
    final query = label != null ? Uri.encodeComponent(label) : '$lat,$lng';
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($query)');
    final appleMapsUri = Uri.parse(
      'https://maps.apple.com/?q=$query&ll=$lat,$lng',
    );

    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
    } else if (await canLaunchUrl(appleMapsUri)) {
      await launchUrl(appleMapsUri, mode: LaunchMode.externalApplication);
    } else {
      final webUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  /// Avatar fallback with initial letter
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
}

// ── Standalone music player widget for detail sheet ──
class _MusicPlayerWidget extends StatefulWidget {
  final Memory memory;
  final AudioPlayer? player;
  final void Function(AudioPlayer) onPlayerCreated;
  final Color primary;
  final Color typeColor;

  const _MusicPlayerWidget({
    required this.memory,
    required this.player,
    required this.onPlayerCreated,
    required this.primary,
    required this.typeColor,
  });

  @override
  State<_MusicPlayerWidget> createState() => _MusicPlayerWidgetState();
}

class _MusicPlayerWidgetState extends State<_MusicPlayerWidget> {
  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _loading = false;
  String? _error;

  bool _isExternalLink = false;
  String? _sourceName;
  Color? _sourceColor;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    _player = widget.player;
    _detectSource();
  }

  @override
  void didUpdateWidget(_MusicPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memory.musicUrl != widget.memory.musicUrl) {
      _sourceName = null;
      _sourceColor = null;
      _isExternalLink = false;
      _detectSource();
    }
  }

  void _detectSource() {
    final url = widget.memory.musicUrl;
    if (url == null || url.isEmpty) return;
    final lower = url.toLowerCase();

    if (lower.contains('spotify')) {
      _sourceName = 'Spotify';
      _sourceColor = const Color(0xFF1DB954);
      _isExternalLink = true;
    } else if (lower.contains('music.youtube.com')) {
      _sourceName = 'YouTube Music';
      _sourceColor = const Color(0xFFFF0000);
      _isExternalLink = true;
    } else if (lower.contains('youtube') || lower.contains('youtu.be')) {
      _sourceName = 'YouTube';
      _sourceColor = const Color(0xFFFF0000);
      _isExternalLink = true;
    } else if (lower.contains('music.apple.com')) {
      _sourceName = 'Apple Music';
      _sourceColor = const Color(0xFFFC3C44);
      _isExternalLink = true;
    } else if (lower.contains('deezer')) {
      _sourceName = 'Deezer';
      _sourceColor = const Color(0xFFA238FF);
      _isExternalLink = true;
    } else if (lower.contains('soundcloud')) {
      _sourceName = 'SoundCloud';
      _sourceColor = const Color(0xFFFF5500);
      _isExternalLink = true;
    } else if (lower.contains('music.yandex') ||
        lower.contains('yandex.ru/music')) {
      _sourceName = 'Яндекс Музыка';
      _sourceColor = const Color(0xFFFFCC00);
      _isExternalLink = true;
    } else if (lower.contains('tidal.com')) {
      _sourceName = 'Tidal';
      _sourceColor = const Color(0xFF000000);
      _isExternalLink = true;
    } else if (lower.startsWith('http') &&
        !lower.contains('firebasestorage') &&
        !lower.contains('firebase')) {
      _sourceName = null;
      _isExternalLink = true;
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _initAndPlay() async {
    final url = widget.memory.musicUrl;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _error = 'No audio URL');
      return;
    }

    // If it's an external streaming link open externally
    final lower = url.toLowerCase();
    if (lower.contains('spotify') ||
        lower.contains('youtube') ||
        lower.contains('youtu.be') ||
        lower.contains('music.apple.com') ||
        lower.contains('deezer') ||
        lower.contains('soundcloud') ||
        lower.contains('music.yandex') ||
        lower.contains('tidal.com') ||
        (!lower.contains('firebasestorage') &&
            !lower.contains('firebase') &&
            lower.startsWith('http'))) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) return;
    setState(() => _loading = true);
    try {
      _player ??= AudioPlayer();
      widget.onPlayerCreated(_player!);

      _posSub = _player!.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _durSub = _player!.durationStream.listen((dur) {
        if (dur != null && mounted) setState(() => _duration = dur);
      });
      _stateSub = _player!.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
            if (state.processingState == ProcessingState.completed) {
              _isPlaying = false;
              _position = Duration.zero;
              _player?.seek(Duration.zero);
              _player?.pause();
            }
          });
        }
      });

      await _player!.setUrl(url);
      if (mounted) setState(() => _loading = false);
      await _player!.play();
    } catch (e) {
      debugPrint('Audio player error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Cannot play this audio';
        });
      }
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4D9FC)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Album art / cover
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child:
                    memory.musicCoverUrl != null &&
                        memory.musicCoverUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: memory.musicCoverUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            _defaultMusicCover(),
                      )
                    : _defaultMusicCover(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memory.musicTitle ?? LocaleService.current.audioFile,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade900,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (memory.musicArtist != null &&
                        memory.musicArtist!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: memory.musicArtist!
                              .split(',')
                              .map((a) => a.trim())
                              .where((a) => a.isNotEmpty)
                              .map(
                                (a) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: widget.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    a,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: widget.primary,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
              // Play / Pause button — only for local audio files
              if (!_isExternalLink)
                GestureDetector(
                  onTap: _loading
                      ? null
                      : () {
                          if (_player == null ||
                              !_isPlaying && _position == Duration.zero) {
                            _initAndPlay();
                          } else if (_isPlaying) {
                            _player?.pause();
                          } else {
                            _player?.play();
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF8B5CF6),
                      shape: BoxShape.circle,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: M3LoadingDots(
                              color: Colors.white,
                              dotSize: 5,
                              gap: 2,
                            ),
                          )
                        : Icon(
                            _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                  ),
                ),
            ],
          ),
          // Progress bar — only for local audio
          if (!_isExternalLink && _duration > Duration.zero) ...[
            const SizedBox(height: 12),
            WaveProgressBar(
              value: _duration.inMilliseconds > 0
                  ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(
                      0.0,
                      1.0,
                    )
                  : 0.0,
              color: const Color(0xFF8B5CF6),
              isPlaying: _isPlaying,
              onChanged: (v) {
                _player?.seek(
                  Duration(
                    milliseconds: (v * _duration.inMilliseconds).toInt(),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_position),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(fontSize: 12, color: Colors.red.shade400),
            ),
          ],
          // Branded link button for external streaming services
          if (_isExternalLink && memory.musicUrl != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  launchUrl(
                    Uri.parse(memory.musicUrl!),
                    mode: LaunchMode.externalApplication,
                  );
                },
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  LocaleService.current.openIn(
                    _sourceName ?? LocaleService.current.audioFile,
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _sourceColor ?? const Color(0xFF8B5CF6),
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

  Widget _defaultMusicCover() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
//  Music Mini Player — feed card with real playback
// ══════════════════════════════════════════════════════

class MemoryMusicPlayer extends StatefulWidget {
  final Memory memory;
  final AppTheme theme;
  final VoidCallback? onHeaderTap;

  const MemoryMusicPlayer({
    super.key,
    required this.memory,
    required this.theme,
    this.onHeaderTap,
  });

  @override
  State<MemoryMusicPlayer> createState() => _MemoryMusicPlayerState();
}

class _MemoryMusicPlayerState extends State<MemoryMusicPlayer> {
  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _loading = false;
  bool _isExternalLink = false;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  String? _sourceName;
  Color? _sourceColor;
  Color get primary => widget.theme.primary;
  Memory get memory => widget.memory;

  @override
  void initState() {
    super.initState();
    _detectSource();
  }

  @override
  void didUpdateWidget(MemoryMusicPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memory.musicUrl != widget.memory.musicUrl) {
      _sourceName = null;
      _sourceColor = null;
      _isExternalLink = false;
      _detectSource();
    }
  }

  void _detectSource() {
    final url = memory.musicUrl;
    if (url == null || url.isEmpty) return;
    final lower = url.toLowerCase();

    if (lower.contains('spotify')) {
      _sourceName = 'Spotify';
      _sourceColor = const Color(0xFF1DB954);
      _isExternalLink = true;
    } else if (lower.contains('music.youtube.com')) {
      _sourceName = 'YouTube Music';
      _sourceColor = const Color(0xFFFF0000);
      _isExternalLink = true;
    } else if (lower.contains('youtube') || lower.contains('youtu.be')) {
      _sourceName = 'YouTube';
      _sourceColor = const Color(0xFFFF0000);
      _isExternalLink = true;
    } else if (lower.contains('music.apple.com')) {
      _sourceName = 'Apple Music';
      _sourceColor = const Color(0xFFFC3C44);
      _isExternalLink = true;
    } else if (lower.contains('deezer')) {
      // covers deezer.com, deezer.page.link, link.deezer.com
      _sourceName = 'Deezer';
      _sourceColor = const Color(0xFFA238FF);
      _isExternalLink = true;
    } else if (lower.contains('soundcloud')) {
      // covers soundcloud.com, on.soundcloud.com, soundcloud.app.goo.gl
      _sourceName = 'SoundCloud';
      _sourceColor = const Color(0xFFFF5500);
      _isExternalLink = true;
    } else if (lower.contains('music.yandex.') ||
        lower.contains('yandex.ru/music') ||
        lower.contains('music.yandex')) {
      _sourceName = 'Яндекс Музыка';
      _sourceColor = const Color(0xFFFFCC00);
      _isExternalLink = true;
    } else if (lower.contains('tidal.com')) {
      _sourceName = 'Tidal';
      _sourceColor = const Color(0xFF000000);
      _isExternalLink = true;
    } else if (lower.startsWith('http') &&
        !lower.contains('firebasestorage') &&
        !lower.contains('firebase')) {
      // Any other http link that's not firebase storage
      _sourceName = null;
      _isExternalLink = true;
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final url = memory.musicUrl;
    if (url == null || url.isEmpty) return;

    if (_isExternalLink) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }

    if (_isPlaying) {
      _player?.pause();
      return;
    }

    if (_player != null && _position > Duration.zero) {
      _player?.play();
      return;
    }

    if (!mounted) return;
    setState(() => _loading = true);
    try {
      _player ??= AudioPlayer();

      // Cancel any previous subscriptions before re-subscribing
      await _posSub?.cancel();
      await _durSub?.cancel();
      await _stateSub?.cancel();

      _posSub = _player!.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _durSub = _player!.durationStream.listen((dur) {
        if (dur != null && mounted) setState(() => _duration = dur);
      });
      _stateSub = _player!.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
            if (state.processingState == ProcessingState.completed) {
              _isPlaying = false;
              _position = Duration.zero;
              _player?.seek(Duration.zero);
              _player?.pause();
            }
          });
        }
      });

      if (!mounted) return;
      await _player!.setUrl(url);
      if (mounted) setState(() => _loading = false);
      await _player!.play();
    } catch (e) {
      debugPrint('Mini player error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString();
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  String _timeAgo(DateTime dt) {
    final s = LocaleService.current;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return s.justNow;
    if (diff.inMinutes < 60) return s.minutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return s.hoursAgo(diff.inHours);
    if (diff.inDays < 30) return s.daysAgo(diff.inDays);
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasCover =
        memory.musicCoverUrl != null && memory.musicCoverUrl!.isNotEmpty;
    final hasUrl = memory.musicUrl != null && memory.musicUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header with streaming source (tap → open detail) ──
        GestureDetector(
          onTap: widget.onHeaderTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
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
                      child: AvatarWidget(
                        uid: memory.authorUid,
                        fallbackUrl: memory.authorAvatar,
                        name: memory.authorName,
                        size: 40,
                        primary: primary,
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      left: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: primary, // Music type color is primary
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: SvgPicture.asset(
                            _svgAssetForType(memory.type),
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
                          if (_sourceName != null) ...[
                            Text(
                              ' via ',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            Text(
                              _sourceName!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _sourceColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: _sourceColor,
                            ),
                          ],
                          Text(
                            '  ·  ${_timeAgo(memory.createdAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        [
                          if (memory.title?.isNotEmpty == true) memory.title!,
                          if (memory.caption?.isNotEmpty == true)
                            memory.caption!,
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: primary),
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
          ),
        ),
        const SizedBox(height: 10),

        // ── Music player sub-card (absorbs taps — не открывает деталь) ──
        GestureDetector(
          onTap: () {}, // поглощаем тап, чтобы не всплывал к _baseTile
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200, width: 1),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Album cover with M3 Expressive wave overlay when playing
                      Stack(
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
                                      colorFilter: ColorFilter.mode(
                                        primary,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                  ),
                          ),
                          // M3 Expressive wave bars overlay — fades in when playing
                          Positioned.fill(
                            child: AnimatedOpacity(
                              opacity: _isPlaying ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 300),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: primary.withOpacity(0.72),
                                  ),
                                  child: Center(
                                    child: _M3WaveBars(
                                      isPlaying: _isPlaying,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              memory.musicTitle ??
                                  LocaleService.current.unknownTrack,
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
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 2,
                                  children: memory.musicArtist!
                                      .split(',')
                                      .map((a) => a.trim())
                                      .where((a) => a.isNotEmpty)
                                      .map(
                                        (a) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: primary.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            a,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: primary,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Play / Pause button — only for local audio files
                      if (hasUrl && !_isExternalLink)
                        GestureDetector(
                          onTap: _togglePlayback,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: _loading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: M3LoadingDots(
                                      color: primary,
                                      dotSize: 5,
                                      gap: 2,
                                    ),
                                  )
                                : SvgPicture.asset(
                                    _isPlaying
                                        ? 'assets/icons/ic_stop.svg'
                                        : 'assets/icons/ic_play.svg',
                                    width: 20,
                                    height: 20,
                                    colorFilter: ColorFilter.mode(
                                      primary,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),

                  // ── Branded link button for external streaming services ──
                  if (_isExternalLink && hasUrl) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _togglePlayback,
                        icon: const Icon(
                          Icons.open_in_new_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                        label: Text(
                          LocaleService.current.openIn(
                            _sourceName ?? LocaleService.current.audioFile,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _sourceColor ?? primary,
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

                  // ── Progress slider + time labels (only for local audio) ──
                  if (!_isExternalLink) ...[
                    const SizedBox(height: 6),
                    WaveProgressBar(
                      value: _duration.inMilliseconds > 0
                          ? (_position.inMilliseconds /
                                    _duration.inMilliseconds)
                                .clamp(0.0, 1.0)
                          : 0.0,
                      color: primary,
                      isPlaying: _isPlaying,
                      height: 22,
                      onChanged: _duration > Duration.zero
                          ? (v) => _player?.seek(
                              Duration(
                                milliseconds: (v * _duration.inMilliseconds)
                                    .toInt(),
                              ),
                            )
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _fmt(_position),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          Text(
                            _duration > Duration.zero
                                ? _fmt(_duration)
                                : '--:--',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════
//  Memory Detail Sheet Widget
//  Extracted StatefulWidget — keyboard animation only
//  rebuilds this isolated subtree, not the whole page.
// ══════════════════════════════════════════════════════

class _MemoryDetailSheet extends StatefulWidget {
  final Memory memory;
  final String groupId;
  final FirebaseService fb;
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
    required this.fb,
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
  // Cached to avoid recomputing Color.lerp on every build frame
  late final List<Color> _bannerGradient;

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
    _bannerGradient = [
      widget.primary,
      Color.lerp(widget.primary, Colors.white, 0.30)!,
    ];
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    final p = widget.primary;
    final isLarge =
        memory.type == MemoryType.photo ||
        memory.type == MemoryType.video ||
        memory.type == MemoryType.videoLink;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: isLarge ? 0.88 : 0.75,
      maxChildSize: 0.95,
      builder: (_, sc) => Container(
        color: Colors.white,
        child: Column(
            children: [
              _buildHeader(memory, p),
              Expanded(
                // RepaintBoundary isolates the animated entry from the static
                // header so the header layer doesn't repaint every animation frame.
                child: RepaintBoundary(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: SingleChildScrollView(
                        controller: sc,
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Images/video are GPU-heavy; isolate them so that
                            // caption/location/action repaints don't touch them.
                            RepaintBoundary(child: _buildMedia(memory, p)),
                            _buildCaption(memory),
                            _buildLocationRow(memory, p),
                            const SizedBox(height: 20),
                            // Action buttons are static after build; isolate them
                            // so comments StreamBuilder repaints don't cascade up.
                            RepaintBoundary(child: _buildActions(memory, p)),
                            const SizedBox(height: 24),
                            RepaintBoundary(
                              child: _CommentsSection(
                                groupId: widget.groupId,
                                memoryId: widget.memory.id,
                                fb: widget.fb,
                                primary: p,
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
        ),
    );
  }

  // ── HEADER ───────────────────────────────────────────────────────────────────
  Widget _buildHeader(Memory memory, Color p) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _bannerGradient,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.7),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: AvatarWidget(
                  uid: memory.authorUid,
                  liveUrl: widget.liveAuthorAvatar,
                  fallbackUrl: memory.authorAvatar,
                  name: memory.authorName,
                  size: 44,
                  primary: widget.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memory.authorName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _fmtDate(memory.createdAt),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.35),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      _svgAssetForType(memory.type),
                      width: 12,
                      height: 12,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      memory.typeLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              if (memory.isPinned) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.35),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.push_pin_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
          if (memory.title?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              memory.title!,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── MEDIA ────────────────────────────────────────────────────────────────────
  Widget _buildMedia(Memory memory, Color p) {
    switch (memory.type) {
      case MemoryType.photo:
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
            child: CachedNetworkImage(
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
                CachedNetworkImage(
                  imageUrl: photos[index],
                  fit: BoxFit.cover,
                  memCacheWidth: 600,
                  memCacheHeight: 600,
                  fadeInDuration: const Duration(milliseconds: 180),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey.shade100,
                    child: Icon(Icons.image_not_supported_rounded,
                        color: Colors.grey.shade400, size: 28),
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
          cell(0, aspect: 16 / 9),
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
            CachedNetworkImage(
              imageUrl: memory.imageUrl!,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
            )
          else
            Container(height: 220, color: Colors.grey.shade900),
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
                    CachedNetworkImage(
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
                          launchUrl(
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
                        color: Colors.grey.shade600,
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
                      launchUrl(
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
                  boxShadow: [
                    BoxShadow(
                      color: p.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
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
                        color: Colors.grey.shade900,
                      ),
                    ),
                    if (memory.latitude != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${memory.latitude!.toStringAsFixed(5)}, '
                        '${memory.longitude?.toStringAsFixed(5) ?? ""}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
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
              color: Colors.grey.shade800,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }

  // ── LOCATION ROW (shown for all memory types that have coords/name) ──────────
  Widget _buildLocationRow(Memory memory, Color p) {
    final hasCoords = memory.latitude != null && memory.longitude != null;
    final hasName = memory.locationName?.isNotEmpty == true;
    if (!hasCoords && !hasName) return const SizedBox.shrink();
    // Don't duplicate — location type already shows full card via _buildLocationMedia
    if (memory.type == MemoryType.location) return const SizedBox.shrink();

    String? distLabel;
    Color pillColor = Colors.grey.shade500;
    if (hasCoords && widget.userLat != null && widget.userLng != null) {
      final m = Geolocator.distanceBetween(
        widget.userLat!, widget.userLng!,
        memory.latitude!, memory.longitude!,
      );
      final km = m / 1000;
      distLabel = m < 1000 ? '${m.round()} м' : '${km.toStringAsFixed(1)} км';
      if (km < 1) {
        pillColor = const Color(0xFF22C55E);
      } else if (km < 10) {
        pillColor = const Color(0xFF16A34A);
      } else if (km < 50) {
        pillColor = const Color(0xFFF59E0B);
      } else {
        pillColor = const Color(0xFFEF4444);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: GestureDetector(
        onTap: hasCoords
            ? () => _showMapsPickerSheet(
                context, memory.latitude!, memory.longitude!, memory.locationName)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: hasCoords ? pillColor.withOpacity(0.06) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasCoords ? pillColor.withOpacity(0.25) : Colors.grey.shade200,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: hasCoords ? pillColor.withOpacity(0.12) : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: hasCoords ? pillColor : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasName)
                      Text(
                        memory.locationName!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (distLabel != null)
                      Text(
                        distLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: pillColor,
                        ),
                      )
                    else if (!hasName)
                      Text(
                        '${memory.latitude!.toStringAsFixed(5)}, ${memory.longitude!.toStringAsFixed(5)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                  ],
                ),
              ),
              if (hasCoords) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, size: 18, color: pillColor),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Shows a bottom sheet with map app choices to build a route.
  static Future<void> _showMapsPickerSheet(
    BuildContext context,
    double lat,
    double lng,
    String? label,
  ) async {
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
      backgroundColor: Colors.white,
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
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_rounded,
                          size: 16, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
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
          color: Colors.grey.shade800,
          height: 1.55,
        ),
      ),
    );
  }

  // ── ACTIONS ───────────────────────────────────────────────────────────────────
  Widget _buildActions(Memory memory, Color p) {
    return Column(
      children: [
        Container(height: 1, color: Colors.grey.shade100),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _actionBtn(
                icon: memory.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                label: memory.isPinned
                    ? LocaleService.current.unpinMemory
                    : LocaleService.current.pinMemory,
                color: p,
                onTap: () {
                  Navigator.pop(context);
                  widget.onTogglePin();
                },
              ),
            ),
            if (widget.canDownload) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.download_rounded,
                  label: LocaleService.current.saveToDevice,
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onDownload();
                  },
                ),
              ),
            ],
          ],
        ),
        if (widget.isOwner) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.edit_rounded,
                  label: LocaleService.current.editMemory,
                  color: Colors.grey.shade700,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onEdit();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.delete_outline_rounded,
                  label: LocaleService.current.deleteMemory,
                  color: const Color(0xFFEF4444),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onDelete();
                  },
                ),
              ),
            ],
          ),
          // Show "Set Location" only when the memory has no location yet
          if (widget.onSetLocation != null &&
              widget.memory.type != MemoryType.location &&
              widget.memory.latitude == null &&
              widget.memory.longitude == null &&
              (widget.memory.locationName?.isEmpty ?? true)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _actionBtn(
                icon: Icons.add_location_alt_rounded,
                label: LocaleService.current.selectLocation,
                color: const Color(0xFF10B981),
                onTap: () {
                  Navigator.pop(context);
                  widget.onSetLocation!();
                },
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    // Compute withOpacity values once instead of on every build call
    final bgColor = color.withValues(alpha: 0.08);
    final borderColor = color.withValues(alpha: 0.22);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noImgBox(double h) => Container(
    height: h,
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Center(
      child: Icon(
        Icons.image_not_supported_rounded,
        color: Colors.grey.shade400,
        size: 48,
      ),
    ),
  );

  static String _fmtDate(DateTime dt) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month]} ${dt.day}, ${dt.year} at $h:$m';
  }
}

// ══════════════════════════════════════════════════════
//  Comments Section Widget
// ══════════════════════════════════════════════════════

class _CommentsSection extends StatefulWidget {
  final String groupId;
  final String memoryId;
  final FirebaseService fb;
  final Color primary;

  const _CommentsSection({
    required this.groupId,
    required this.memoryId,
    required this.fb,
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
      await widget.fb.addComment(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 18,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              LocaleService.current.comments,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Comment list (real-time)
        StreamBuilder<List<MemoryComment>>(
          stream: widget.fb.commentsStream(
            groupId: widget.groupId,
            memoryId: widget.memoryId,
          ),
          builder: (context, snap) {
            final comments = snap.data ?? [];
            if (comments.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  LocaleService.current.noCommentsYet,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
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
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.grey.shade200),
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
                        child: M3LoadingDots(
                          color: Colors.white,
                          dotSize: 4,
                          gap: 2,
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
    final isMe = comment.authorUid == widget.fb.uid;
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
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isMe
                      ? widget.primary.withOpacity(0.15)
                      : Colors.grey.shade200,
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
                          color: isMe ? widget.primary : Colors.grey.shade700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _timeAgo(comment.createdAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    comment.text,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade800,
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
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(LocaleService.current.deleteCommentQuestion),
        content: Text(LocaleService.current.actionCannotBeUndone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LocaleService.current.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.fb.deleteComment(
                groupId: widget.groupId,
                memoryId: widget.memoryId,
                commentId: comment.id,
              );
            },
            child: Text(
              LocaleService.current.delete,
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
        ],
      ),
    );
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

// ══════════════════════════════════════════════════════
//  Photo Grid Gallery Screen
// ══════════════════════════════════════════════════════
class _PhotoGalleryScreen extends StatelessWidget {
  final List<GalleryItem> items;
  final Color primary;

  const _PhotoGalleryScreen({required this.items, required this.primary});

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final botPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          s.allMediaGallery,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: GridView.builder(
        padding: EdgeInsets.only(bottom: botPad + 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          return GestureDetector(
            onTap: () async {
              final memoryId = await Navigator.of(context).push<String>(
                PageRouteBuilder(
                  opaque: false,
                  barrierColor: Colors.black,
                  pageBuilder: (_, __, ___) =>
                      FullscreenGallery(items: items, initialIndex: i),
                ),
              );
              if (memoryId != null && context.mounted) {
                Navigator.pop(context, memoryId);
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: item.url,
                  fit: BoxFit.cover,
                  memCacheWidth: 300,
                  memCacheHeight: 300,
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey.shade900,
                    child: const Icon(
                      Icons.broken_image_rounded,
                      color: Colors.white38,
                      size: 28,
                    ),
                  ),
                ),
                if (item.isVideo)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white70,
                      size: 36,
                    ),
                  ),
              ],
            ),
          );
        },
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

  const FullscreenGallery({
    super.key,
    required this.items,
    required this.initialIndex,
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
                  onTap: () => launchUrl(
                    Uri.parse(item.videoUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CachedNetworkImage(
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
                  child: CachedNetworkImage(
                    imageUrl: item.url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: M3LoadingDots(
                        color: Colors.white54,
                        dotSize: 6,
                        gap: 4,
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
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          // Fallback: try web URL for native-scheme apps
          final webFallback = Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${uri.host}',
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Приложение не установлено')),
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
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
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

// ─── Spoiler rich text for detail view ───────────────────────────────────────

class _SpoilerRichText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;
  const _SpoilerRichText({
    required this.text,
    required this.style,
    this.maxLines,
    this.overflow,
  });
  @override
  State<_SpoilerRichText> createState() => _SpoilerRichTextState();
}

class _SpoilerRichTextState extends State<_SpoilerRichText> {
  final Set<int> _revealed = {};

  List<({String text, bool isSpoiler})> _parse() {
    final result = <({String text, bool isSpoiler})>[];
    final parts = widget.text.split('||');
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      result.add((text: parts[i], isSpoiler: i.isOdd));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final segments = _parse();
    if (!segments.any((s) => s.isSpoiler)) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }
    int spoilerIndex = 0;
    return Text.rich(
      TextSpan(
        children: segments.map((seg) {
          if (!seg.isSpoiler)
            return TextSpan(text: seg.text, style: widget.style);
          final idx = spoilerIndex++;
          final isRevealed = _revealed.contains(idx);
          return WidgetSpan(
            alignment: ui.PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: isRevealed
                  ? null
                  : () => setState(() => _revealed.add(idx)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: isRevealed ? Colors.transparent : Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  seg.text,
                  style: widget.style.copyWith(
                    color: isRevealed
                        ? widget.style.color
                        : Colors.grey.shade800,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
//  WaveProgressBar — Material You animated wave progress bar for music player
//  Active portion: animated sine wave. Inactive portion: flat line.
// ──────────────────────────────────────────────────────────────────────────────

class WaveProgressBar extends StatefulWidget {
  /// Progress from 0.0 to 1.0
  final double value;
  final Color color;

  /// Controls wave animation: starts/stops based on playback state
  final bool isPlaying;

  /// Called with new value (0.0–1.0) when user seeks
  final ValueChanged<double>? onChanged;

  final double height;

  const WaveProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.isPlaying = false,
    this.onChanged,
    this.height = 28,
  });

  @override
  State<WaveProgressBar> createState() => _WaveProgressBarState();
}

class _WaveProgressBarState extends State<WaveProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (widget.isPlaying) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(WaveProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.isPlaying && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            if (widget.onChanged == null) return;
            final r = (d.localPosition.dx / constraints.maxWidth).clamp(
              0.0,
              1.0,
            );
            widget.onChanged!(r);
          },
          onHorizontalDragUpdate: (d) {
            if (widget.onChanged == null) return;
            final r = (d.localPosition.dx / constraints.maxWidth).clamp(
              0.0,
              1.0,
            );
            widget.onChanged!(r);
          },
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                painter: _WaveProgressPainter(
                  value: widget.value,
                  color: widget.color,
                  phase: _ctrl.value * 2 * pi,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveProgressPainter extends CustomPainter {
  final double value; // 0.0 – 1.0
  final Color color;
  final double phase;

  static const double _amplitude = 2.0;
  static const int _wavesVisible = 2;

  const _WaveProgressPainter({
    required this.value,
    required this.color,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final activeWidth = (size.width * value).clamp(0.0, size.width);
    const strokeWidth = 2.5;

    final activePaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final inactivePaint = Paint()
      ..color = color.withOpacity(0.22)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Inactive flat line from activeWidth to end
    if (activeWidth < size.width) {
      canvas.drawLine(
        Offset(activeWidth, cy),
        Offset(size.width, cy),
        inactivePaint,
      );
    }

    // Active wavy line from 0 to activeWidth
    if (activeWidth > 1) {
      final wavelength = size.width / _wavesVisible;
      final path = Path();
      const steps = 200;
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = activeWidth * t;
        final y = cy + _amplitude * sin((x / wavelength) * 2 * pi - phase);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, activePaint);
    }

    // Thumb circle at current position
    if (value > 0.005 && value < 0.995) {
      final thumbPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(activeWidth, cy), 5.5, thumbPaint);
    }
  }

  @override
  bool shouldRepaint(_WaveProgressPainter old) =>
      old.value != value || old.phase != phase || old.color != color;
}

// ──────────────────────────────────────────────────────────────────────────────
//  _M3WaveBars — M3 Expressive animated equalizer bars (now-playing indicator)
//  4 vertical rounded bars that bounce with wave-like offset phases, giving a
//  fluid, spring-like feel characteristic of Material 3 Expressive motion.
// ──────────────────────────────────────────────────────────────────────────────

class _M3WaveBars extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const _M3WaveBars({required this.isPlaying, required this.color});

  @override
  State<_M3WaveBars> createState() => _M3WaveBarsState();
}

class _M3WaveBarsState extends State<_M3WaveBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.isPlaying) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_M3WaveBars old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.isPlaying && _ctrl.isAnimating) {
      _ctrl.animateTo(
        0.5,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        size: const Size(28, 18),
        painter: _WaveBarsPainter(
          phase: _ctrl.value * 2 * pi,
          color: widget.color,
          isPlaying: widget.isPlaying,
        ),
      ),
    );
  }
}

/// Inline YouTube player card — shows thumbnail initially,
/// then plays the video inline when the user taps the play button.
class _YouTubeInlineCard extends StatefulWidget {
  final Memory memory;
  final Color platformColor;
  final String platformName;

  const _YouTubeInlineCard({
    required this.memory,
    required this.platformColor,
    required this.platformName,
  });

  @override
  State<_YouTubeInlineCard> createState() => _YouTubeInlineCardState();
}

class _YouTubeInlineCardState extends State<_YouTubeInlineCard> {
  YoutubePlayerController? _controller;
  bool _isPlaying = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _startInlinePlay() {
    final videoId = YoutubePlayer.convertUrlToId(widget.memory.videoUrl ?? '');
    if (videoId == null) {
      final url = widget.memory.videoUrl;
      if (url != null && url.isNotEmpty) {
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    }
    setState(() {
      _controller = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          enableCaption: false,
          hideControls: false,
        ),
      );
      _isPlaying = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    final platformColor = widget.platformColor;
    final platformName = widget.platformName;
    final hasThumb = memory.imageUrl?.isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Inline player or thumbnail preview ──
          if (_isPlaying && _controller != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: YoutubePlayer(
                controller: _controller!,
                showVideoProgressIndicator: true,
                progressIndicatorColor: platformColor,
                progressColors: ProgressBarColors(
                  playedColor: platformColor,
                  handleColor: platformColor,
                ),
              ),
            )
          else
            GestureDetector(
              onTap: _startInlinePlay,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasThumb)
                        CachedNetworkImage(
                          imageUrl: memory.imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  platformColor.withValues(alpha: 0.85),
                                  platformColor.withValues(alpha: 0.55),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                platformColor.withValues(alpha: 0.85),
                                platformColor.withValues(alpha: 0.55),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.4),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 34,
                            color: platformColor,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: platformColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.smart_display_rounded,
                                size: 10,
                                color: Colors.white,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'YouTube',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
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
            ),
          const SizedBox(height: 10),
          // ── Title ──
          Text(
            memory.title?.isNotEmpty == true
                ? memory.title!
                : LocaleService.current.video,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade900,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (memory.musicArtist?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                memory.musicArtist!,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (memory.caption?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              memory.caption!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final url = memory.videoUrl;
                if (url != null && url.isNotEmpty) {
                  launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
              icon: const Icon(
                Icons.open_in_new_rounded,
                size: 14,
                color: Colors.white,
              ),
              label: Text(
                LocaleService.current.openIn(platformName),
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
  }
}

class _WaveBarsPainter extends CustomPainter {
  final double phase;
  final Color color;
  final bool isPlaying;

  // Quarter-period offsets → adjacent bars peak at different times (wave effect)
  static const List<double> _phaseOffsets = [0.0, pi * 0.5, pi * 1.0, pi * 1.5];

  // Slightly different frequencies per bar for organic, non-robotic feel
  static const List<double> _freqs = [1.0, 1.25, 0.85, 1.15];

  const _WaveBarsPainter({
    required this.phase,
    required this.color,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 4;
    const gap = 3.0;
    final barW = (size.width - gap * (barCount - 1)) / barCount;
    final maxH = size.height;
    const minH = 3.0;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      double h;
      if (isPlaying) {
        // Primary wave + subtle harmonic for spring-like feel
        final t1 = sin(phase * _freqs[i] + _phaseOffsets[i]);
        final t2 = sin(phase * _freqs[i] * 1.8 + _phaseOffsets[i] * 0.4) * 0.25;
        final combined = ((t1 + t2) / 1.25).clamp(-1.0, 1.0);
        h = (minH + (maxH - minH) * (combined * 0.5 + 0.5)).clamp(minH, maxH);
      } else {
        h = minH;
      }
      final x = i * (barW + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, barW, h),
          const Radius.circular(2.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveBarsPainter old) =>
      old.phase != phase || old.color != color || old.isPlaying != isPlaying;
}

// ─────────────────────────────────────────────────────────────
// In-app video player for uploaded video memories
// ─────────────────────────────────────────────────────────────

class _InAppVideoPlayerPage extends StatefulWidget {
  final String url;
  final String? title;

  const _InAppVideoPlayerPage({required this.url, this.title});

  @override
  State<_InAppVideoPlayerPage> createState() => _InAppVideoPlayerPageState();
}

class _InAppVideoPlayerPageState extends State<_InAppVideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  Timer? _hideTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
          _duration = _controller.value.duration;
        });
        _controller.play();
        _scheduleHide();
      });
    _controller.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {
      _position = _controller.value.position;
    });
    // Auto-restart when finished
    if (_controller.value.position >= _controller.value.duration &&
        _controller.value.duration > Duration.zero) {
      _controller.seekTo(Duration.zero);
      _controller.pause();
      setState(() => _showControls = true);
      _hideTimer?.cancel();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls && _controller.value.isPlaying) _scheduleHide();
  }

  void _togglePlay() {
    if (_controller.value.isPlaying) {
      _controller.pause();
      _hideTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      _controller.play();
      _scheduleHide();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_onUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _controller.value.isPlaying;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: _toggleControls,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Video ──
              Center(
                child: _isInitialized
                    ? AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      )
                    : const CircularProgressIndicator(color: Colors.white),
              ),

              // ── Controls overlay ──
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Stack(
                  children: [
                    // Top bar
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            if (widget.title != null) ...[
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.title!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Centre play/pause button
                    Center(
                      child: GestureDetector(
                        onTap: _togglePlay,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            key: ValueKey(isPlaying),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Bottom bar with progress + time
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.75),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VideoProgressIndicator(
                              _controller,
                              allowScrubbing: true,
                              padding: EdgeInsets.zero,
                              colors: const VideoProgressColors(
                                playedColor: Color(0xFFEC4899),
                                bufferedColor: Colors.white38,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  _fmt(_position),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _fmt(_duration),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
