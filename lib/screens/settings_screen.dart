import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../theme/profile_theme.dart';
import '../widgets/app_icon_sheet.dart';
import '../widgets/settings_scaffold.dart';

/// Экран настроек.
///
/// Раньше настройки жили внутри профиля: девять сворачивающихся блоков вперемешку
/// с карточками пары и статистикой, каждый со своим набором плиток. Одни и те же
/// вещи попадались дважды, а стиль плыл от блока к блоку.
///
/// Здесь один каркас на весь экран ([SettingsGroup] + [SettingsRow]) и порядок
/// секций от «трогаешь каждый день» к «раз в полгода». Логика осталась в профиле:
/// экран получает готовые обработчики и ничего не знает про PocketBase.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.scheme,
    required this.onAppearance,
    required this.onNotifications,
    required this.onLanguage,
    required this.onCoinShop,
    required this.onPrivacyPolicy,
    required this.onExport,
    required this.onResetMissYou,
    required this.onTerms,
    required this.onSupport,
    required this.onAbout,
    required this.onLogout,
    required this.onDeleteAccount,
    required this.lockScreenMood,
    required this.onLockScreenMoodChanged,
    required this.sideActionIsArrow,
    required this.onToggleSideAction,
    this.appVersion = '',
    this.plusActive = false,
    this.plusVisible = true,
    this.onPlus,
    this.cycleAvailable = false,
    this.cycleShared = false,
    this.onCycleSharedChanged,
    this.onCycleWipe,
    this.onCycleConsentWithdraw,
    this.onExportMyData,
    this.mascotSleepAvailable = false,
    this.onMascotSleep,
    this.appIconId,
    this.onAppIcon,
  });

  final ColorScheme scheme;

  final VoidCallback onAppearance;
  final VoidCallback onNotifications;
  final VoidCallback onLanguage;
  final VoidCallback onCoinShop;
  final VoidCallback onPrivacyPolicy;
  final VoidCallback onExport;
  final VoidCallback onResetMissYou;
  final VoidCallback onTerms;
  final VoidCallback onSupport;
  final VoidCallback onAbout;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  final bool lockScreenMood;
  final ValueChanged<bool> onLockScreenMoodChanged;

  final bool sideActionIsArrow;
  final VoidCallback onToggleSideAction;

  final String appVersion;

  /// Есть ли у человека хоть один персонаж с ночной сценой. Нет такого — и
  /// строки нет: настраивать нечего, а пустой лист только сбивает с толку.
  final bool mascotSleepAvailable;
  final VoidCallback? onMascotSleep;

  /// Куплен ли Togetherly+ — от этого зависит подпись строки.
  final bool plusActive;

  /// Существует ли Togetherly+ на этой платформе. На iOS строки нет вовсе:
  /// продавать там нечего, а название без покупки только путает.
  final bool plusVisible;
  final VoidCallback? onPlus;

  /// Раздел цикла показывается только при женском поле в профиле: у остальных
  /// цикла не бывает, и пункт был бы шумом.
  final bool cycleAvailable;
  final bool cycleShared;
  final ValueChanged<bool>? onCycleSharedChanged;
  final VoidCallback? onCycleWipe;

  /// Отзыв согласия на обработку данных цикла: закрывает раздел и стирает
  /// отметки. Отзывать должно быть так же просто, как соглашаться.
  final VoidCallback? onCycleConsentWithdraw;

  /// Архив «мои данные» — право забрать копию по закону 133/2011 и GDPR.
  final VoidCallback? onExportMyData;

  /// Текущая иконка приложения; null — сменить её тут нельзя (iOS: alias'ы
  /// живут только в Android-манифесте).
  final String? appIconId;
  final VoidCallback? onAppIcon;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;

    return Theme(
      data: ProfileTheme.data(scheme),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            title: Text(
              s.settingsTitle,
              style: TextStyle(
                fontFamily: 'Unbounded',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation('wght', 600)],
                color: scheme.onSurface,
              ),
            ),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              MediaQuery.of(context).padding.bottom + 32,
            ),
            children: [
              // Togetherly+ первым: это главное, что можно тут сделать.
              if (plusVisible)
                SettingsGroup([
                  SettingsRow(
                    icon: Icons.workspace_premium_rounded,
                    title: s.plusTitle,
                    subtitle: plusActive ? s.plusActiveBody : s.plusHeroBody,
                    iconBg:
                        plusActive ? scheme.primary : scheme.primaryContainer,
                    iconFg: plusActive
                        ? scheme.onPrimary
                        : scheme.onPrimaryContainer,
                    trailing: const SettingsChevron(),
                    onTap: onPlus,
                  ),
                ]),

              SettingsSection(s.appearanceTitle),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.palette_rounded,
                  title: s.appearanceTitle,
                  subtitle: s.settingsAppearanceHint,
                  trailing: const SettingsChevron(),
                  onTap: onAppearance,
                ),
                if (appIconId != null) ...[
                  SettingsRow(
                    icon: Icons.apps_rounded,
                    title: s.appIconTitle,
                    subtitle: appIconNameOf(appIconId!),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIconBadge(option: appIconOptionOf(appIconId!)),
                        const SizedBox(width: 8),
                        const SettingsChevron(),
                      ],
                    ),
                    onTap: onAppIcon,
                  ),
                ],
                if (mascotSleepAvailable) ...[
                  SettingsRow(
                    icon: Icons.bedtime_rounded,
                    title: s.mascotSleepTitle,
                    subtitle: s.mascotSleepHint,
                    trailing: const SettingsChevron(),
                    onTap: onMascotSleep,
                  ),
                ],
                SettingsRow(
                  icon: Icons.translate_rounded,
                  title: s.language,
                  subtitle: LocaleService.instance.isRussian
                      ? 'Русский'
                      : 'English',
                  trailing: const SettingsChevron(),
                  onTap: onLanguage,
                ),
              ]),

              SettingsSection(s.notifications),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.notifications_rounded,
                  title: s.notifications,
                  subtitle: s.settingsNotificationsHint,
                  trailing: const SettingsChevron(),
                  onTap: onNotifications,
                ),
                SettingsRow(
                  icon: Icons.lock_clock_rounded,
                  title: s.lockScreenMoodToggle,
                  subtitle: s.settingsLockMoodHint,
                  trailing: Switch(
                    value: lockScreenMood,
                    onChanged: onLockScreenMoodChanged,
                  ),
                  onTap: () => onLockScreenMoodChanged(!lockScreenMood),
                ),
                SettingsRow(
                  icon: Icons.touch_app_rounded,
                  title: s.sideActionTitle,
                  subtitle: sideActionIsArrow
                      ? s.sideActionOpenFeed
                      : s.sideActionCreatePin,
                  trailing: Icon(
                    Icons.swap_horiz_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                  onTap: onToggleSideAction,
                ),
              ]),

              if (cycleAvailable) ...[
                SettingsSection(s.cycleTitle),
                SettingsGroup([
                  SettingsRow(
                    icon: Icons.visibility_rounded,
                    title: s.cycleShareWithPartner,
                    subtitle: s.cycleShareHint,
                    trailing: Switch(
                      value: cycleShared,
                      onChanged: onCycleSharedChanged,
                    ),
                    onTap: () => onCycleSharedChanged?.call(!cycleShared),
                  ),
                  SettingsRow(
                    icon: Icons.gpp_maybe_outlined,
                    title: s.cycleConsentWithdraw,
                    subtitle: s.cycleConsentWithdrawHint,
                    trailing: const SettingsChevron(),
                    onTap: onCycleConsentWithdraw,
                  ),
                  SettingsRow(
                    icon: Icons.delete_outline_rounded,
                    title: s.cycleWipe,
                    subtitle: s.cycleWipeHint,
                    iconBg: scheme.errorContainer,
                    iconFg: scheme.onErrorContainer,
                    titleColor: scheme.error,
                    onTap: onCycleWipe,
                  ),
                ]),
              ],

              SettingsSection(s.settingsDataSection),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.folder_zip_outlined,
                  title: s.exportMyData,
                  subtitle: s.exportMyDataHint,
                  trailing: const SettingsChevron(),
                  onTap: onExportMyData,
                ),
                SettingsRow(
                  icon: Icons.download_rounded,
                  title: s.exportMemories,
                  subtitle: s.settingsExportHint,
                  trailing: const SettingsChevron(),
                  onTap: onExport,
                ),
                SettingsRow(
                  icon: Icons.replay_rounded,
                  title: s.resetMissYouCount,
                  subtitle: s.settingsResetMissHint,
                  trailing: const SettingsChevron(),
                  onTap: onResetMissYou,
                ),
                SettingsRow(
                  icon: Icons.shield_rounded,
                  title: s.privacy,
                  subtitle: s.settingsPrivacyHint,
                  trailing: const SettingsChevron(),
                  onTap: onPrivacyPolicy,
                ),
              ]),

              SettingsSection(s.coinShopTitle),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.monetization_on_rounded,
                  title: s.coinShopTitle,
                  subtitle: s.settingsCoinsHint,
                  trailing: const SettingsChevron(),
                  onTap: onCoinShop,
                ),
              ]),

              SettingsSection(s.aboutApp),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.info_rounded,
                  title: s.aboutApp,
                  subtitle: appVersion.isEmpty ? null : appVersion,
                  trailing: const SettingsChevron(),
                  onTap: onAbout,
                ),
                SettingsRow(
                  icon: Icons.description_rounded,
                  title: s.termsOfUse,
                  trailing: const SettingsChevron(),
                  onTap: onTerms,
                ),
                SettingsRow(
                  icon: Icons.mail_rounded,
                  title: s.supportTitle,
                  subtitle: s.settingsSupportHint,
                  trailing: const SettingsChevron(),
                  onTap: onSupport,
                ),
              ]),

              SettingsSection(s.settingsAccountSection, color: scheme.error),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.logout_rounded,
                  title: s.logout,
                  iconBg: scheme.surfaceContainerHighest,
                  iconFg: scheme.onSurfaceVariant,
                  onTap: onLogout,
                ),
                SettingsRow(
                  icon: Icons.delete_forever_rounded,
                  title: s.deleteAccount,
                  subtitle: s.settingsDeleteHint,
                  iconBg: scheme.errorContainer,
                  iconFg: scheme.onErrorContainer,
                  titleColor: scheme.error,
                  onTap: onDeleteAccount,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
