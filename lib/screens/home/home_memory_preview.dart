import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/memory.dart';
import '../../models/pair_data.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/memory_tile_builder.dart';
import '../memory_lane_screen.dart';

/// Секция «Воспоминания» на главном экране: превью последних 3 記憶.
/// Если партнёр не подключён — заглушка.
class MemoryLanePreview extends StatelessWidget {
  final bool isPaired;
  final List<Memory> memories;
  final PairData pairData;
  final AppTheme theme;
  final double? userLat;
  final double? userLng;

  const MemoryLanePreview({
    super.key,
    required this.isPaired,
    required this.memories,
    required this.pairData,
    required this.theme,
    this.userLat,
    this.userLng,
  });

  @override
  Widget build(BuildContext context) {
    if (!isPaired) return _buildEmpty(context);
    return _buildPaired(context);
  }

  // ── Paired view ────────────────────────────────────────────────────────────

  Widget _buildPaired(BuildContext context) {
    final primary = theme.primary;
    final tileBuilder = MemoryTileBuilder(
      primary: primary,
      cardSurface: Colors.white,
      cardBorder: const Color(0xFFE5E5E5),
    );

    String? liveAvatarFor(String uid) {
      for (final m in pairData.members) {
        if (m.uid == uid && m.avatar.isNotEmpty) return m.avatar;
      }
      return null;
    }

    String? liveNameFor(String uid) {
      for (final m in pairData.members) {
        if (m.uid == uid && m.name.isNotEmpty) return m.name;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LocaleService.current.relationshipMemoryLane,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              GestureDetector(
                onTap: () => _openMemoryLane(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        LocaleService.current.viewAll,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (memories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE5E5E5), width: 0.5),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.photo_album_outlined,
                      size: 32,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      LocaleService.current.noMemoriesYet,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      LocaleService.current.addFirstMemory,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                for (int i = 0; i < memories.length && i < 3; i++)
                  _buildTile(context, tileBuilder, memories[i],
                      liveAvatarFor: liveAvatarFor,
                      liveNameFor: liveNameFor),
              ],
            ),
          ),
      ],
    );
  }

  // ── Empty (unpaired) view ──────────────────────────────────────────────────

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LocaleService.current.relationshipMemoryLane,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE5E5E5), width: 0.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 36,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                Text(
                  LocaleService.current.memoriesWillAppear,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  LocaleService.current.connectWithPartnerToStart,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Single tile ────────────────────────────────────────────────────────────

  Widget _buildTile(
    BuildContext context,
    MemoryTileBuilder tileBuilder,
    Memory memory, {
    String? Function(String uid)? liveAvatarFor,
    String? Function(String uid)? liveNameFor,
  }) {
    final distanceText = memory.latitude != null && memory.longitude != null
        ? _distanceKm(memory.latitude!, memory.longitude!)
        : null;

    if (memory.type == MemoryType.music) {
      return tileBuilder.buildTile(
        memory,
        liveAvatarFor: liveAvatarFor,
        liveNameFor: liveNameFor,
        musicPlayerWidget: MemoryMusicPlayer(
          key: ValueKey(memory.id),
          memory: memory,
          theme: theme,
        ),
      );
    }

    if (memory.type == MemoryType.text) {
      return tileBuilder.buildTile(
        memory,
        liveAvatarFor: liveAvatarFor,
        liveNameFor: liveNameFor,
        onTap: () => _showNoteDetail(context, memory),
        onOpenLocation: (lat, lng, label) =>
            _openLocationInMaps(lat, lng, label),
        distanceText: distanceText,
      );
    }

    return tileBuilder.buildTile(
      memory,
      liveAvatarFor: liveAvatarFor,
      liveNameFor: liveNameFor,
      onTap: () => _openMemoryLane(context),
      onOpenGallery: (urls, index) {
        final items = urls
            .map((url) => GalleryItem(url: url, memoryId: ''))
            .toList();
        Navigator.of(context).push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black,
            pageBuilder: (_, __, e) =>
                FullscreenGallery(items: items, initialIndex: index),
          ),
        );
      },
      onOpenLocation: (lat, lng, label) => _openLocationInMaps(lat, lng, label),
      distanceText: distanceText,
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _openMemoryLane(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryLaneScreen(pairData: pairData, theme: theme),
      ),
    );
  }

  // ── Note detail bottom-sheet ───────────────────────────────────────────────

  void _showNoteDetail(BuildContext context, Memory memory) {
    final primary = theme.primary;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (_) {
        final hasLocation =
            memory.locationName != null && memory.locationName!.isNotEmpty;
        final hasCoords = memory.latitude != null && memory.longitude != null;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.9,
          builder: (_, sc) => SingleChildScrollView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.sticky_note_2_rounded,
                        color: primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memory.authorName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade900,
                            ),
                          ),
                          Text(
                            LocaleService.current.sharedAThought,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (memory.title?.isNotEmpty == true) ...[
                  Text(
                    memory.title!,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (memory.caption?.isNotEmpty == true)
                  Text(
                    memory.caption!,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade700,
                      height: 1.6,
                    ),
                  ),
                if (hasLocation || hasCoords) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: hasCoords
                        ? () {
                            Navigator.pop(context);
                            _openLocationInMaps(
                              memory.latitude!,
                              memory.longitude!,
                              memory.locationName,
                            );
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: primary.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            color: primary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              memory.locationName ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasCoords)
                            Text(
                              LocaleService.current.setARoute,
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
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _distanceKm(double lat, double lng) {
    if (userLat == null || userLng == null) return '';
    final d = Geolocator.distanceBetween(userLat!, userLng!, lat, lng);
    if (d < 1000) return '${d.round()}m';
    return '${(d / 1000).toStringAsFixed(1)}km';
  }

  static Future<void> _openLocationInMaps(
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
}
