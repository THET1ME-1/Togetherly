import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/firebase_service.dart';

/// Unified avatar widget used everywhere a user picture is displayed.
///
/// Resolution order:
///   1. For the current user → FirebaseService.avatarUrl (in-memory, always fresh)
///   2. [liveUrl] — caller-supplied live URL (e.g. from group memberAvatars)
///   3. [fallbackUrl] — snapshot stored inside the memory/comment document
///   4. Initials placeholder built from [name]
///
/// Always uses CachedNetworkImage with an errorWidget — never shows a red cross.
class AvatarWidget extends StatelessWidget {
  final String uid;
  final String? liveUrl;
  final String? fallbackUrl;
  final String? name;
  final double size;
  final Color primary;

  const AvatarWidget({
    super.key,
    required this.uid,
    this.liveUrl,
    this.fallbackUrl,
    this.name,
    required this.size,
    required this.primary,
  });

  String _resolveUrl() {
    final fb = FirebaseService();
    if (uid == fb.uid) {
      final cached = fb.avatarUrl;
      if (cached.isNotEmpty) return cached;
    }
    if (liveUrl?.isNotEmpty == true) return liveUrl!;
    if (fallbackUrl?.isNotEmpty == true) return fallbackUrl!;
    return '';
  }

  Widget _placeholder() {
    final initial = (name?.isNotEmpty == true) ? name![0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      color: primary.withValues(alpha: 0.15),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
            color: primary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = _resolveUrl();
    return ClipOval(
      child: url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: (size * 2).toInt(),
              memCacheHeight: (size * 2).toInt(),
              errorWidget: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }
}
