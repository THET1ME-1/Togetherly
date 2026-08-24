import 'package:flutter/material.dart';
import '../utils/safe_text.dart';
import 'storage_image.dart';
import 'widget_content_view.dart';
import '../services/pocketbase_service.dart';
import '../services/pb_auth_service.dart';

/// Unified avatar widget used everywhere a user picture is displayed.
///
/// Resolution order:
///   1. For the current user → PocketBase profile avatarUrl (in-memory, always fresh)
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

  /// Открывать ли фотографию на весь экран по нажатию.
  ///
  /// Просьба из поддержки: лицо партнёра видно кружком в 40 точек, и
  /// разглядеть его негде. Включается не везде: в списках и строках, где
  /// нажатие уже что-то делает, тап по аватару перехватывал бы действие
  /// строки. Кружок с буквой не открывается вовсе — показывать нечего.
  final bool tapToView;

  const AvatarWidget({
    super.key,
    required this.uid,
    this.liveUrl,
    this.fallbackUrl,
    this.name,
    required this.size,
    required this.primary,
    this.tapToView = false,
  });

  String _resolveUrl() {
    if (uid == PocketBaseService().userId) {
      final cached =
          (PbAuthService().currentProfile()?['avatarUrl'] as String?) ?? '';
      if (cached.isNotEmpty) return cached;
    }
    if (liveUrl?.isNotEmpty == true) return liveUrl!;
    if (fallbackUrl?.isNotEmpty == true) return fallbackUrl!;
    return '';
  }

  Widget _placeholder() {
    final initial = (name ?? '').firstGraphemeUpper();
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
    final picture = _picture(url);
    if (!tapToView || url.isEmpty) return picture;
    return GestureDetector(
      onTap: () => openWidgetPhotoView(
        context,
        imageUrl: url,
        authorName: name,
      ),
      child: picture,
    );
  }

  Widget _picture(String url) {
    return ClipOval(
      child: url.isNotEmpty
          ? StorageImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Предел ставится по одной стороне. С обоими разом снимок
              // декодировался в квадрат, и вытянутый кадр приезжал в кружок
              // сплющенным — лицо на аватаре становилось шире, чем на самом
              // фото. Вторую сторону досчитает сам декодер, пропорции целы.
              memCacheWidth: (size * 2).toInt(),
              placeholder: (_, __) => _placeholder(),
              errorWidget: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }
}
