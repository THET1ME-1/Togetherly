import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/common/plus_badge.dart';
import '../../widgets/avatar_widget.dart';
import 'profile_banner.dart';

/// Шапка профиля (приём Kadr): баннер со скруглённым низом + аватар, свисающий
/// в кольце поверхности, справа имя и чип. Общая для СВОЕГО профиля
/// (редактируемая: заданы [onEdit]/[onPickBanner]/[onTapAvatar]) и профиля
/// ПАРТНЁРА (только показ — колбэки null: нет карандаша и кнопок камеры).
class ProfileHero extends StatelessWidget {
  final ColorScheme cs;
  final String uid;
  final String avatarUrl;
  final String name;

  /// Показывать ли значок Togetherly+ рядом с именем.
  final bool plus;

  /// Тема приложения — значок Плюса красится её основным цветом.
  final AppTheme? theme;
  final String bannerUrl;
  final String? localBannerPath;
  final String subtitle;
  final VoidCallback? onEdit;
  final VoidCallback? onPickBanner;
  final VoidCallback? onTapAvatar;

  /// Вход в настройки прямо из шапки. Задан только у своего профиля: у
  /// партнёрского настраивать нечего.
  final VoidCallback? onSettings;

  const ProfileHero({
    super.key,
    required this.cs,
    required this.uid,
    required this.avatarUrl,
    required this.name,
    this.plus = false,
    this.theme,
    required this.bannerUrl,
    this.localBannerPath,
    this.subtitle = '',
    this.onEdit,
    this.onPickBanner,
    this.onTapAvatar,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ProfileBanner(
              bannerUrl: bannerUrl,
              localPath: localBannerPath,
              background: cs.primaryContainer,
              onPick: onPickBanner,
            ),
            // Шестерёнка стоит слева от кнопки баннера. Тёмная подложка тут не
            // для красоты: под ней бывает светлая фотография, и белый значок
            // без неё пропадает.
            if (onSettings != null)
              Positioned(
                top: 4,
                right: onPickBanner != null ? 48 : 4,
                child: Semantics(
                  button: true,
                  label: LocaleService.current.settingsOpen,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSettings,
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.30),
                          ),
                          child: const Icon(Icons.settings_rounded,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 20,
              bottom: -40,
              child: GestureDetector(
                onTap: onTapAvatar,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: cs.surface),
                      child: AvatarWidget(
                        uid: uid,
                        liveUrl: avatarUrl,
                        name: name,
                        size: 84,
                        primary: cs.primary,
                      ),
                    ),
                    if (onTapAvatar != null)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.primary,
                            border: Border.all(color: cs.surface, width: 2),
                          ),
                          child: Icon(Icons.photo_camera_rounded,
                              size: 14, color: cs.onPrimary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(122, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: ProfileTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (plus && theme != null) ...[
                    const SizedBox(width: 8),
                    PlusBadge(theme: theme!),
                  ],
                  if (onEdit != null) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onEdit,
                      child: Icon(Icons.edit_rounded,
                          size: 18, color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 9),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
