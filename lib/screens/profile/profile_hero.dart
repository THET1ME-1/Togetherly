import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/common/plus_badge.dart';
import '../../models/profile_icon.dart';
import '../../widgets/avatar_widget.dart';
import 'profile_banner.dart';
import '../../widgets/common/badge_image.dart';

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

  /// Значок из профиля («badge» в users). В карточке пары он у имени стоял с
  /// самого начала, а в своём профиле его не было вовсе — просьба автора
  /// 17.08.2026 показать значок рядом с «Plus».
  final String badge;

  /// Тема приложения — значок Плюса красится её основным цветом.
  final AppTheme? theme;
  final String bannerUrl;
  final String? localBannerPath;
  final String subtitle;
  final VoidCallback? onEdit;
  final VoidCallback? onPickBanner;
  final VoidCallback? onTapAvatar;

  /// Нажатие на саму аватарку — магазин рамок. Смена фото тогда уходит на
  /// кнопку камеры в углу.
  final VoidCallback? onTapFrame;

  /// Нажатие на значок у ника — магазин значков.
  final VoidCallback? onTapBadge;

  /// Вход в настройки прямо из шапки. Задан только у своего профиля: у
  /// партнёрского настраивать нечего.
  final VoidCallback? onSettings;

  /// Справка «Как сделать» — кнопка «?» рядом с шестерёнкой.
  final VoidCallback? onHelp;

  const ProfileHero({
    super.key,
    required this.cs,
    required this.uid,
    required this.avatarUrl,
    required this.name,
    this.badge = '',
    this.plus = false,
    this.theme,
    required this.bannerUrl,
    this.localBannerPath,
    this.subtitle = '',
    this.onEdit,
    this.onPickBanner,
    this.onTapAvatar,
    this.onTapFrame,
    this.onTapBadge,
    this.onSettings,
    this.onHelp,
  });

  /// Круглая кнопка поверх баннера. Тёмная подложка тут не для красоты: под
  /// ней бывает светлая фотография, и белый значок без неё пропадает.
  Widget _bannerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
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
              child: Icon(icon, size: 18, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

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
            // Шестерёнка стоит слева от кнопки баннера, «?» — слева от неё.
            if (onSettings != null)
              Positioned(
                top: 4,
                right: onPickBanner != null ? 48 : 4,
                child: _bannerButton(
                  icon: Icons.settings_rounded,
                  label: LocaleService.current.settingsOpen,
                  onTap: onSettings!,
                ),
              ),
            if (onHelp != null)
              Positioned(
                top: 4,
                right: (onPickBanner != null ? 48 : 4) +
                    (onSettings != null ? 44 : 0),
                child: _bannerButton(
                  icon: Icons.help_rounded,
                  label: trKey('help.title'),
                  onTap: onHelp!,
                ),
              ),
            Positioned(
              left: 20,
              bottom: -40,
              child: GestureDetector(
                onTap: onTapFrame ?? onTapAvatar,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.surface,
                      ),
                      child: AvatarWidget(
                        uid: uid,
                        liveUrl: avatarUrl,
                        name: name,
                        size: 84,
                        primary: cs.primary,
                        // В своём профиле нажатие занято (рамки или смена
                        // фото), а в партнёрском не делало ничего — там и
                        // открываем фото.
                        tapToView: onTapAvatar == null && onTapFrame == null,
                      ),
                    ),
                    if (onTapAvatar != null)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onTapAvatar,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primary,
                              border: Border.all(color: cs.surface, width: 2),
                            ),
                            child: Icon(
                              Icons.photo_camera_rounded,
                              size: 14,
                              color: cs.onPrimary,
                            ),
                          ),
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
                  // Значок профиля — сразу за ником, «Plus» уже после него.
                  if (badge.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTapBadge,
                      child: BadgeImage(badge, side: 28),
                    ),
                  ] else if (onTapBadge != null) ...[
                    // Значка нет — кружок «добавить», чтобы было куда нажать.
                    const SizedBox(width: 6),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTapBadge,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add_reaction_outlined,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  if (plus && theme != null) ...[
                    const SizedBox(width: 8),
                    PlusBadge(theme: theme!),
                  ],
                  if (onEdit != null) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onEdit,
                      child: Icon(
                        Icons.edit_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
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
