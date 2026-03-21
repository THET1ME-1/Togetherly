import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/memory.dart';
import '../models/comment.dart';
import '../models/pair_data.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';

/// Memory Lane — Google Calendar Schedule-style view
/// Grouped by date, pinned at top, full CRUD
class MemoryLaneScreen extends StatefulWidget {
  final PairData pairData;
  final AppTheme theme;
  const MemoryLaneScreen({
    super.key,
    required this.pairData,
    required this.theme,
  });

  @override
  State<MemoryLaneScreen> createState() => _MemoryLaneScreenState();
}

class _MemoryLaneScreenState extends State<MemoryLaneScreen> {
  Color get primary => widget.theme.primary;

  final FirebaseService _fb = FirebaseService();
  List<Memory> _memories = [];
  StreamSubscription? _memorySub;
  bool _loading = true;

  PairData get pair => widget.pairData;
  String get _groupId => pair.pairId;

  @override
  void initState() {
    super.initState();
    _loadAndListen();
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
    _memorySub?.cancel();
    super.dispose();
  }

  // ── Organize memories ──
  List<Memory> get _pinnedMemories =>
      _memories.where((m) => m.isPinned).toList();

  /// Group non-pinned memories by date, newest first
  Map<String, List<Memory>> get _groupedByDate {
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

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return _weekdayName(dt.weekday);

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
    if (dt.year == now.year) {
      return '${months[dt.month]} ${dt.day}';
    }
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  }

  String _weekdayName(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[weekday - 1];
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
    return Scaffold(
      backgroundColor: widget.theme.bgGradient[0],
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_memories.isEmpty)
                _buildEmpty()
              else ...[
                // Pinned section
                if (_pinnedMemories.isNotEmpty) ...[
                  _sectionHeader('📌  Pinned'),
                  SliverPadding(
                    padding: const EdgeInsets.only(left: 12, right: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _timelineMemoryRow(_pinnedMemories[i]),
                        childCount: _pinnedMemories.length,
                      ),
                    ),
                  ),
                  _timelineSpacer(8),
                ],
                // Date-grouped sections (Schedule view)
                ..._groupedByDate.entries.expand((entry) {
                  return [
                    _sectionHeader(entry.key),
                    SliverPadding(
                      padding: const EdgeInsets.only(left: 12, right: 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _timelineMemoryRow(entry.value[i]),
                          childCount: entry.value.length,
                        ),
                      ),
                    ),
                  ];
                }),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
          // FAB
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            right: 24,
            child: FloatingActionButton.extended(
              onPressed: _showAddMemorySheet,
              backgroundColor: primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add Memory',
                style: TextStyle(fontWeight: FontWeight.w700),
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
      backgroundColor: Colors.white.withOpacity(0.92),
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
      ),
      title: Text(
        'Memory Lane',
        style: GoogleFonts.rubik(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade900,
        ),
      ),
      actions: [
        // member count badge
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
              'No memories yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Add Memory" to create your first\nshared memory together',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  TIMELINE COMPONENTS
  // ═══════════════════════════════════════════════════
  static const double _timelineColumnWidth = 32.0;
  static const double _timelineLineWidth = 2.0;
  static const double _timelineMarkerSize = 12.0;

  /// Wraps a memory tile with a timeline marker + vertical line on the left
  Widget _timelineMemoryRow(Memory memory) {
    final typeColor = _memoryTypeColor(memory.type);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _timelineColumnWidth,
            child: Stack(
              children: [
                // Continuous vertical line
                Positioned(
                  left: (_timelineColumnWidth - _timelineLineWidth) / 2,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: _timelineLineWidth,
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                // Circle marker with fade + scale animation
                Positioned(
                  top: 18,
                  left: (_timelineColumnWidth - _timelineMarkerSize) / 2,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Opacity(
                          opacity: value.clamp(0.0, 1.0),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      width: _timelineMarkerSize,
                      height: _timelineMarkerSize,
                      decoration: BoxDecoration(
                        color: typeColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: typeColor.withOpacity(0.35),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: _memoryTile(memory)),
        ],
      ),
    );
  }

  /// Spacer that keeps the timeline line continuous between sections
  SliverToBoxAdapter _timelineSpacer(double height) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned(
                left: (_timelineColumnWidth - _timelineLineWidth) / 2,
                top: 0,
                bottom: 0,
                child: Container(
                  width: _timelineLineWidth,
                  color: primary.withOpacity(0.13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  SECTION HEADER (date label like Google Calendar)
  // ═══════════════════════════════════════════════════
  SliverToBoxAdapter _sectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 20, top: 16, bottom: 6),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Timeline line through header
              SizedBox(
                width: _timelineColumnWidth,
                child: Stack(
                  children: [
                    Positioned(
                      left: (_timelineColumnWidth - _timelineLineWidth) / 2,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: _timelineLineWidth,
                        color: primary.withOpacity(0.13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.rubik(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
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
      case MemoryType.location:
        return _locationTile(memory);
      case MemoryType.music:
        return _musicTile(memory);
      case MemoryType.text:
        return _textTile(memory);
    }
  }

  // ── PHOTO TILE ──
  Widget _photoTile(Memory memory) {
    final hasImage = memory.imageUrl != null && memory.imageUrl!.isNotEmpty;
    return _baseTile(
      memory: memory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImage)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Image.network(
                memory.imageUrl!,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                cacheWidth: 800,
                errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  color: Colors.grey.shade200,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      color: Colors.grey.shade400,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _tileFooter(memory),
          ),
        ],
      ),
    );
  }

  // ── VIDEO TILE ──
  Widget _videoTile(Memory memory) {
    final hasThumb = memory.imageUrl != null && memory.imageUrl!.isNotEmpty;
    final hasVideo = memory.videoUrl != null && memory.videoUrl!.isNotEmpty;
    return _baseTile(
      memory: memory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasThumb)
                    Image.network(
                      memory.imageUrl!,
                      fit: BoxFit.cover,
                      cacheWidth: 800,
                      cacheHeight: 500,
                      errorBuilder: (_, __, ___) =>
                          Container(color: Colors.grey.shade300),
                    )
                  else
                    Container(color: Colors.grey.shade900),
                  Container(color: Colors.black.withOpacity(0.3)),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 32,
                        color: const Color(0xFFEC4899),
                      ),
                    ),
                  ),
                  if (hasVideo)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'VIDEO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _tileFooter(memory),
          ),
        ],
      ),
    );
  }

  // ── LOCATION TILE ──
  Widget _locationTile(Memory memory) {
    return _baseTile(
      memory: memory,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF0FAF4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FAF4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFF22C55E),
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
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (memory.latitude != null && memory.longitude != null)
                          Text(
                            '${memory.latitude!.toStringAsFixed(4)}, ${memory.longitude!.toStringAsFixed(4)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (memory.isPinned)
                    Icon(
                      Icons.push_pin_rounded,
                      size: 14,
                      color: primary.withOpacity(0.6),
                    ),
                ],
              ),
              if (memory.caption != null && memory.caption!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  memory.caption!,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              _authorTimeRow(memory),
            ],
          ),
        ),
      ),
    );
  }

  // ── MUSIC TILE ──
  Widget _musicTile(Memory memory) {
    return _baseTile(
      memory: memory,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F0FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        memory.musicCoverUrl != null &&
                            memory.musicCoverUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              memory.musicCoverUrl!,
                              fit: BoxFit.cover,
                              cacheWidth: 96,
                              cacheHeight: 96,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.music_note_rounded,
                                color: Color(0xFF8B5CF6),
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.music_note_rounded,
                            color: Color(0xFF8B5CF6),
                            size: 24,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          memory.musicTitle ?? 'Music',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (memory.musicArtist != null)
                          Text(
                            memory.musicArtist!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // Play button indicator
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Color(0xFF8B5CF6),
                      size: 22,
                    ),
                  ),
                ],
              ),
              if (memory.caption != null && memory.caption!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  memory.caption!,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              // Fake waveform bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _authorTimeRow(memory),
            ],
          ),
        ),
      ),
    );
  }

  // ── TEXT / NOTE TILE ──
  Widget _textTile(Memory memory) {
    return _baseTile(
      memory: memory,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('📝', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    'Note',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const Spacer(),
                  if (memory.isPinned)
                    Icon(
                      Icons.push_pin_rounded,
                      size: 14,
                      color: primary.withOpacity(0.6),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (memory.title != null && memory.title!.isNotEmpty) ...[
                Text(
                  memory.title!,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (memory.caption != null && memory.caption!.isNotEmpty)
                  const SizedBox(height: 4),
              ],
              if (memory.caption != null && memory.caption!.isNotEmpty)
                Text(
                  memory.caption!,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade800,
                    height: 1.5,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              if (memory.title == null && memory.caption == null)
                Text(
                  'Note',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade400,
                  ),
                ),
              const SizedBox(height: 10),
              _authorTimeRow(memory),
            ],
          ),
        ),
      ),
    );
  }

  // ── Base tile wrapper ──
  Widget _baseTile({required Memory memory, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _showMemoryDetail(memory),
        onLongPress: () => _showMemoryActions(memory),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: memory.isPinned
                ? Border.all(color: primary.withOpacity(0.3), width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }

  // ── Tile footer (for photo/video) ──
  Widget _tileFooter(Memory memory) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(memory.typeEmoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _memoryTitle(memory),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (memory.isPinned)
              Icon(
                Icons.push_pin_rounded,
                size: 14,
                color: primary.withOpacity(0.6),
              ),
          ],
        ),
        if (memory.caption != null && memory.caption!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            memory.caption!,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 6),
        _authorTimeRow(memory),
      ],
    );
  }

  // ── Author + time row (reusable) ──
  Widget _authorTimeRow(Memory memory) {
    return Row(
      children: [
        if (memory.authorAvatar.isNotEmpty)
          Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: ClipOval(
              child: Image.network(
                memory.authorAvatar,
                fit: BoxFit.cover,
                cacheWidth: 48,
                cacheHeight: 48,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            ),
          ),
        if (memory.authorAvatar.isNotEmpty) const SizedBox(width: 4),
        Text(
          memory.authorName,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade500,
          ),
        ),
        const Spacer(),
        Text(
          _timeStr(memory.createdAt),
          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
        ),
      ],
    );
  }

  String _memoryTitle(Memory memory) {
    if (memory.title != null && memory.title!.isNotEmpty) {
      return memory.title!;
    }
    switch (memory.type) {
      case MemoryType.photo:
        return 'Photo';
      case MemoryType.video:
        return 'Video';
      case MemoryType.location:
        return memory.locationName ?? 'Location';
      case MemoryType.music:
        return memory.musicTitle ?? 'Music';
      case MemoryType.text:
        return memory.caption?.isNotEmpty == true ? memory.caption! : 'Note';
    }
  }

  Color _memoryTypeColor(MemoryType type) {
    switch (type) {
      case MemoryType.photo:
        return const Color(0xFF3B82F6);
      case MemoryType.video:
        return const Color(0xFFEC4899);
      case MemoryType.location:
        return const Color(0xFF22C55E);
      case MemoryType.music:
        return const Color(0xFF8B5CF6);
      case MemoryType.text:
        return const Color(0xFFFBBF24);
    }
  }

  // ═══════════════════════════════════════════════════
  //  MEMORY DETAIL — full screen
  // ═══════════════════════════════════════════════════
  void _showMemoryDetail(Memory memory) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
        onTogglePin: () => _togglePin(memory),
        onDownload: () => _downloadMemoryMedia(memory),
        onEdit: () => _editMemory(memory),
        onDelete: () => _confirmDelete(memory),
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
                          Text(
                            memory.typeEmoji,
                            style: const TextStyle(fontSize: 14),
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
                          child: Image.network(
                            memory.imageUrl!,
                            width: double.infinity,
                            fit: BoxFit.fitWidth,
                            errorBuilder: (_, __, ___) => Container(
                              height: 200,
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
                                  'Photo not uploaded yet',
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
                              Image.network(
                                memory.imageUrl!,
                                width: double.infinity,
                                height: 220,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
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
                                            'Unknown location',
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
                                  label: const Text('Open in Google Maps'),
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
                        if (memory.authorAvatar.isNotEmpty)
                          CircleAvatar(
                            radius: 14,
                            backgroundImage: NetworkImage(memory.authorAvatar),
                          ),
                        if (memory.authorAvatar.isNotEmpty)
                          const SizedBox(width: 8),
                        Text(
                          memory.authorName,
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
                                label: Text(memory.isPinned ? 'Unpin' : 'Pin'),
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
                                  label: const Text('Save'),
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
                                  label: const Text('Edit'),
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
                                  label: const Text('Delete'),
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
    return '${months[dt.month]} ${dt.day}, ${dt.year} at ${_timeStr(dt)}';
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
              title: Text(memory.isPinned ? 'Unpin memory' : 'Pin memory'),
              onTap: () {
                Navigator.pop(context);
                _togglePin(memory);
              },
            ),
            if (_canDownload(memory))
              ListTile(
                leading: Icon(
                  Icons.download_rounded,
                  color: Colors.blue.shade600,
                ),
                title: const Text('Save to device'),
                onTap: () {
                  Navigator.pop(context);
                  _downloadMemoryMedia(memory);
                },
              ),
            if (memory.authorUid == _fb.uid) ...[
              ListTile(
                leading: Icon(Icons.edit_rounded, color: Colors.grey.shade700),
                title: const Text('Edit memory'),
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
                  'Delete memory',
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

  Future<void> _downloadMemoryMedia(Memory memory) async {
    String? url;
    String extension;
    String prefix;

    switch (memory.type) {
      case MemoryType.photo:
        url = memory.imageUrl;
        extension = 'jpg';
        prefix = 'photo';
        break;
      case MemoryType.video:
        url = memory.videoUrl;
        extension = 'mp4';
        prefix = 'video';
        break;
      case MemoryType.music:
        url = memory.musicUrl;
        extension = 'mp3';
        prefix = 'music';
        break;
      default:
        return;
    }

    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No media URL available'),
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
          const SnackBar(
            content: Text('Downloading...'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode}');
      }

      // Save to Downloads / Pictures directory
      Directory saveDir;
      if (Platform.isAndroid) {
        // Use external storage Downloads
        saveDir = Directory('/storage/emulated/0/Download');
        if (!saveDir.existsSync()) {
          saveDir = await getApplicationDocumentsDirectory();
        }
      } else {
        saveDir = await getApplicationDocumentsDirectory();
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${prefix}_$timestamp.$extension';
      final file = File('${saveDir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${file.path}'),
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
            content: Text('Download failed: $e'),
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
        title: const Text('Delete memory?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
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
            },
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }

  void _editMemory(Memory memory) {
    final titleCtrl = TextEditingController(text: memory.title ?? '');
    final captionCtrl = TextEditingController(text: memory.caption ?? '');
    final locationCtrl = TextEditingController(text: memory.locationName ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => Padding(
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
              'Edit Memory',
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
                hintText: 'Title (optional)',
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
                hintText: 'Description...',
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
            if (memory.type == MemoryType.location) ...[
              const SizedBox(height: 12),
              TextField(
                controller: locationCtrl,
                decoration: InputDecoration(
                  hintText: 'Location name...',
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
            ],
            const SizedBox(height: 20),
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
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Save Changes',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
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
                'Add Memory',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose what you want to share',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),
              _addMemoryOption(
                icon: Icons.photo_rounded,
                label: 'Photo',
                color: const Color(0xFF3B82F6),
                type: MemoryType.photo,
              ),
              _addMemoryOption(
                icon: Icons.videocam_rounded,
                label: 'Video',
                color: const Color(0xFFEC4899),
                type: MemoryType.video,
              ),
              _addMemoryOption(
                icon: Icons.location_on_rounded,
                label: 'Location',
                color: const Color(0xFF22C55E),
                type: MemoryType.location,
              ),
              _addMemoryOption(
                icon: Icons.music_note_rounded,
                label: 'Music',
                color: const Color(0xFF8B5CF6),
                type: MemoryType.music,
              ),
              _addMemoryOption(
                icon: Icons.edit_note_rounded,
                label: 'Note',
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

  void _showCreateMemoryForm(MemoryType type) {
    final titleCtrl = TextEditingController();
    final captionCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final musicTitleCtrl = TextEditingController();
    final musicArtistCtrl = TextEditingController();
    final musicUrlCtrl = TextEditingController();

    // Local state for file selections
    XFile? selectedMedia;
    String? selectedMusicPath;
    double? lat;
    double? lng;
    bool isLoadingLocation = false;

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
                Text(
                  'New ${_typeName(type)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Photo/Video picker ──
                if (type == MemoryType.photo || type == MemoryType.video) ...[
                  GestureDetector(
                    onTap: () async {
                      try {
                        final picker = ImagePicker();
                        XFile? picked;

                        if (type == MemoryType.photo) {
                          picked = await picker.pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 1920,
                            maxHeight: 1920,
                            imageQuality: 85,
                          );
                        } else {
                          picked = await picker.pickVideo(
                            source: ImageSource.gallery,
                          );
                        }

                        if (picked != null) {
                          setState(() => selectedMedia = picked);
                        }
                      } catch (e) {
                        debugPrint('Pick media failed: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to select media: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: selectedMedia != null ? 200 : 100,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                        image: selectedMedia != null
                            ? DecorationImage(
                                image: FileImage(File(selectedMedia!.path)),
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
                                    type == MemoryType.photo
                                        ? Icons.add_photo_alternate_rounded
                                        : Icons.videocam_rounded,
                                    size: 28,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    type == MemoryType.photo
                                        ? 'Tap to select photo'
                                        : 'Tap to select video',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: CircleAvatar(
                                  backgroundColor: Colors.black54,
                                  radius: 16,
                                  child: Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Caption (always show)
                TextField(
                  controller: titleCtrl,
                  maxLines: 1,
                  decoration: InputDecoration(
                    hintText: type == MemoryType.text
                        ? 'Title (optional)'
                        : 'Title (optional)',
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
                    hintText: type == MemoryType.text
                        ? 'Write your note...'
                        : 'Description (optional)',
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

                // ── Location fields ──
                if (type == MemoryType.location) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationCtrl,
                    decoration: InputDecoration(
                      hintText: 'Location name (e.g. Central Park)',
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
                      onPressed: isLoadingLocation
                          ? null
                          : () async {
                              setState(() => isLoadingLocation = true);
                              try {
                                bool serviceEnabled =
                                    await Geolocator.isLocationServiceEnabled();
                                if (!serviceEnabled) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Location services are disabled',
                                        ),
                                      ),
                                    );
                                  }
                                  setState(() => isLoadingLocation = false);
                                  return;
                                }

                                LocationPermission permission =
                                    await Geolocator.checkPermission();
                                if (permission == LocationPermission.denied) {
                                  permission =
                                      await Geolocator.requestPermission();
                                }
                                if (permission == LocationPermission.denied ||
                                    permission ==
                                        LocationPermission.deniedForever) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Location permission denied',
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
                                        place.name ?? place.subLocality ?? '';
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to get location'),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded),
                      label: Text(
                        lat != null && lng != null
                            ? 'Location set ✓'
                            : 'Use Current Location',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        side: BorderSide(color: primary),
                      ),
                    ),
                  ),
                ],

                // ── Music fields ──
                if (type == MemoryType.music) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: musicTitleCtrl,
                    decoration: InputDecoration(
                      hintText: 'Song name',
                      prefixIcon: const Icon(Icons.music_note_rounded),
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: musicArtistCtrl,
                    decoration: InputDecoration(
                      hintText: 'Artist name',
                      prefixIcon: const Icon(Icons.person_rounded),
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: musicUrlCtrl,
                    decoration: InputDecoration(
                      hintText: 'Link (Spotify, YouTube, Apple Music, etc.)',
                      prefixIcon: const Icon(Icons.link_rounded),
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
                  Center(
                    child: Text(
                      'OR',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.audio,
                        );
                        if (result != null && result.files.isNotEmpty) {
                          setState(
                            () => selectedMusicPath = result.files.first.path,
                          );
                          if (musicTitleCtrl.text.isEmpty) {
                            musicTitleCtrl.text = result.files.first.name
                                .split('.')
                                .first;
                          }
                        }
                      },
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(
                        selectedMusicPath != null
                            ? 'File selected ✓'
                            : 'Pick from device',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        side: BorderSide(color: primary),
                      ),
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
                      await _saveNewMemory(
                        type: type,
                        title: titleCtrl.text.trim(),
                        caption: captionCtrl.text.trim(),
                        locationName: locationCtrl.text.trim(),
                        latitude: lat,
                        longitude: lng,
                        musicTitle: musicTitleCtrl.text.trim(),
                        musicArtist: musicArtistCtrl.text.trim(),
                        musicUrl: musicUrlCtrl.text.trim(),
                        mediaPath: selectedMedia?.path,
                        musicPath: selectedMusicPath,
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
                    child: const Text(
                      'Add Memory',
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

  String _typeName(MemoryType type) {
    switch (type) {
      case MemoryType.photo:
        return 'Photo';
      case MemoryType.video:
        return 'Video';
      case MemoryType.location:
        return 'Location';
      case MemoryType.music:
        return 'Music';
      case MemoryType.text:
        return 'Note';
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
    String? mediaPath,
    String? musicPath,
  }) async {
    final user = _fb.currentUser;
    if (user == null || _groupId.isEmpty) return;

    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Uploading memory...'),
            ],
          ),
          duration: const Duration(seconds: 30),
        ),
      );
    }

    String? uploadedImageUrl;
    String? uploadedVideoUrl;
    String? uploadedMusicUrl;

    try {
      // Upload photo or video if selected
      if (mediaPath != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final ext = mediaPath.split('.').last;
        final fileName = 'memory_$timestamp.$ext';
        final destination = 'memories/$_groupId/$fileName';

        final url = await _fb.uploadFile(mediaPath, destination);
        if (url != null) {
          if (type == MemoryType.photo) {
            uploadedImageUrl = url;
          } else if (type == MemoryType.video) {
            uploadedVideoUrl = url;
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Failed to upload file. Make sure Firebase Storage is enabled in your Firebase Console.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
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

      await _fb.addMemory(
        groupId: _groupId,
        type: type,
        title: title.isNotEmpty ? title : null,
        caption: caption.isNotEmpty ? caption : null,
        locationName: locationName.isNotEmpty ? locationName : null,
        latitude: latitude,
        longitude: longitude,
        musicTitle: musicTitle.isNotEmpty ? musicTitle : null,
        musicArtist: musicArtist.isNotEmpty ? musicArtist : null,
        musicUrl: finalMusicUrl,
        imageUrl: uploadedImageUrl,
        videoUrl: uploadedVideoUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Memory added successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Save memory failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add memory: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  @override
  void initState() {
    super.initState();
    _player = widget.player;
  }

  Future<void> _initAndPlay() async {
    final url = widget.memory.musicUrl;
    if (url == null || url.isEmpty) {
      setState(() => _error = 'No audio URL');
      return;
    }

    // If it's an external streaming link (spotify, youtube, etc) open externally
    if (url.contains('spotify.com') ||
        url.contains('youtube.com') ||
        url.contains('youtu.be') ||
        url.contains('music.apple.com') ||
        url.contains('deezer.com')) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }

    setState(() => _loading = true);
    try {
      _player ??= AudioPlayer();
      widget.onPlayerCreated(_player!);

      _player!.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _player!.durationStream.listen((dur) {
        if (dur != null && mounted) setState(() => _duration = dur);
      });
      _player!.playerStateStream.listen((state) {
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
      await _player!.play();
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Audio player error: $e');
      setState(() {
        _loading = false;
        _error = 'Cannot play this audio';
      });
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
                    ? Image.network(
                        memory.musicCoverUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _defaultMusicCover(),
                      )
                    : _defaultMusicCover(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memory.musicTitle ?? 'Audio file',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade900,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (memory.musicArtist != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          memory.musicArtist!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Play / Pause button
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
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
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
          // Progress bar
          if (_duration > Duration.zero) ...[
            const SizedBox(height: 12),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: const Color(0xFF8B5CF6),
                inactiveTrackColor: const Color(0xFF8B5CF6).withOpacity(0.15),
                thumbColor: const Color(0xFF8B5CF6),
                overlayColor: const Color(0xFF8B5CF6).withOpacity(0.1),
              ),
              child: Slider(
                value: _position.inMilliseconds.toDouble().clamp(
                  0,
                  _duration.inMilliseconds.toDouble(),
                ),
                max: _duration.inMilliseconds.toDouble(),
                onChanged: (v) {
                  _player?.seek(Duration(milliseconds: v.toInt()));
                },
              ),
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
          // Open in external service if musicUrl is a link
          if (memory.musicUrl != null &&
              memory.musicUrl!.startsWith('http')) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  launchUrl(
                    Uri.parse(memory.musicUrl!),
                    mode: LaunchMode.externalApplication,
                  );
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open link'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8B5CF6),
                  side: const BorderSide(color: Color(0xFF8B5CF6)),
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
        size: 28,
      ),
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
  final VoidCallback onTogglePin;
  final VoidCallback onDownload;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MemoryDetailSheet({
    required this.memory,
    required this.groupId,
    required this.fb,
    required this.primary,
    required this.isOwner,
    required this.canDownload,
    required this.typeColor,
    required this.onTogglePin,
    required this.onDownload,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_MemoryDetailSheet> createState() => _MemoryDetailSheetState();
}

class _MemoryDetailSheetState extends State<_MemoryDetailSheet> {
  AudioPlayer? _audioPlayer;

  @override
  void dispose() {
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize:
          memory.type == MemoryType.photo || memory.type == MemoryType.video
          ? 0.85
          : 0.7,
      maxChildSize: 0.95,
      builder: (_, sc) => SingleChildScrollView(
        controller: sc,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.typeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(memory.typeEmoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    memory.typeLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.typeColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (memory.type == MemoryType.photo)
              RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: memory.imageUrl?.isNotEmpty == true
                      ? Image.network(
                          memory.imageUrl!,
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                          errorBuilder: (_, __, ___) => _noImgBox(200),
                        )
                      : _noImgBox(200),
                ),
              ),
            if (memory.type == MemoryType.video)
              RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      if (memory.imageUrl?.isNotEmpty == true)
                        Image.network(
                          memory.imageUrl!,
                          width: double.infinity,
                          height: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 220,
                            color: Colors.grey.shade900,
                          ),
                        )
                      else
                        Container(height: 220, color: Colors.grey.shade900),
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
              ),
            if (memory.type == MemoryType.location)
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
                            color: const Color(0xFF22C55E).withOpacity(0.12),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                memory.locationName ?? 'Unknown location',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                              if (memory.latitude != null)
                                Text(
                                  '${memory.latitude!.toStringAsFixed(5)}, '
                                  '${memory.longitude?.toStringAsFixed(5) ?? ""}',
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
                          label: const Text('Open in Google Maps'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF22C55E),
                            side: const BorderSide(color: Color(0xFF22C55E)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (memory.type == MemoryType.music)
              _MusicPlayerWidget(
                memory: memory,
                player: _audioPlayer,
                onPlayerCreated: (p) => setState(() => _audioPlayer = p),
                primary: widget.primary,
                typeColor: widget.typeColor,
              ),
            if (memory.type == MemoryType.text)
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
            Row(
              children: [
                if (memory.authorAvatar.isNotEmpty)
                  CircleAvatar(
                    radius: 14,
                    backgroundImage: NetworkImage(memory.authorAvatar),
                  ),
                if (memory.authorAvatar.isNotEmpty) const SizedBox(width: 8),
                Text(
                  memory.authorName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                Text(
                  _fmtDate(memory.createdAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onTogglePin();
                        },
                        icon: Icon(
                          memory.isPinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          size: 16,
                        ),
                        label: Text(memory.isPinned ? 'Unpin' : 'Pin'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.primary,
                          side: BorderSide(
                            color: widget.primary.withOpacity(0.3),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    if (widget.canDownload) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onDownload();
                          },
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('Save'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue.shade600,
                            side: BorderSide(color: Colors.blue.shade200),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
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
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onEdit();
                          },
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            side: BorderSide(color: Colors.grey.shade300),
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
                            Navigator.pop(context);
                            widget.onDelete();
                          },
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                          ),
                          label: const Text('Delete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade400,
                            side: BorderSide(color: Colors.red.shade200),
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
            const SizedBox(height: 24),
            RepaintBoundary(
              child: _CommentsSection(
                groupId: widget.groupId,
                memoryId: widget.memory.id,
                fb: widget.fb,
                primary: widget.primary,
              ),
            ),
            const _KeyboardPaddingBox(),
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
    await widget.fb.addComment(
      groupId: widget.groupId,
      memoryId: widget.memoryId,
      text: text,
    );
    _ctrl.clear();
    setState(() => _sending = false);
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
              'Comments',
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
                  'No comments yet — be the first!',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: comments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _commentBubble(comments[i]),
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
                  hintText: 'Write a comment…',
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
    final isMe = comment.authorUid == widget.fb.uid;
    return GestureDetector(
      onLongPress: isMe ? () => _confirmDeleteComment(comment) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (comment.authorAvatar.isNotEmpty)
            CircleAvatar(
              radius: 14,
              backgroundImage: NetworkImage(comment.authorAvatar),
            )
          else
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey.shade200,
              child: Text(
                comment.authorName.isNotEmpty
                    ? comment.authorName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
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
        title: const Text('Delete comment?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
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
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
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
// Isolated keyboard-inset padding widget
// Only this widget rebuilds on every frame of the keyboard animation,
// leaving the heavy modal sheet tree completely untouched.
// ══════════════════════════════════════════════════════
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
