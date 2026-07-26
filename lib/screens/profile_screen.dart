import 'dart:async';
import 'package:flutter/material.dart';
import 'profile/profile_hero.dart';
import 'profile/miss_you_week_chart.dart';
import '../models/partner_profile.dart';
import 'package:flutter/services.dart';
import '../utils/safe_text.dart';
import '../utils/couple_days.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/level_avatar.dart';
import '../widgets/storage_image.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/safe_pick.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io' show Platform, File;
import '../services/media_service.dart';
import '../services/pocketbase_service.dart';
import '../services/pb_data_service.dart';
import '../services/miss_you_repository.dart';
import '../models/user_data.dart';
import '../models/pair_data.dart';
import '../models/connection.dart';
import '../models/profile_icon.dart';
import '../services/locale_service.dart';
import '../services/ui_prefs.dart';
import '../theme/app_theme.dart';
import '../theme/app_palettes.dart';
import '../theme/theme_scope.dart';
import '../theme/profile_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/morph_loader.dart';
import '../widgets/settings_scaffold.dart';
import '../services/cycle_service.dart';
import '../services/plus_service.dart';
import 'plus_screen.dart';
import 'settings_screen.dart';
import '../widgets/common/coin_reward_toast.dart';
import '../widgets/common/m3_loading.dart';
import 'welcome_screen.dart';
import 'gifts/gift_profile_body.dart';
import 'gifts/partner_profile_screen.dart';
import 'gifts/self_profile_screen.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/seed_swatch.dart';
import '../utils/share_origin.dart';
import '../services/export_service.dart';
import '../services/timer_service.dart';
import '../services/widget_service.dart';
import '../services/rewarded_ad_service.dart';
import '../services/app_icon_service.dart';
import '../services/coin_store.dart';
import '../services/celebration_notification_service.dart';
import '../services/days_together_notification_service.dart';
import 'date_time_picker_screen.dart';

/// Entry for a partner across all connections
class _PartnerEntry {
  final GroupMember member;
  final Connection connection;
  const _PartnerEntry({required this.member, required this.connection});
}

class ProfileScreen extends StatefulWidget {
  final UserData userData;
  final PairData pairData;
  final TimerService timerService;
  final WidgetService widgetService;
  final VoidCallback? onSwitchToHome;

  /// Раздел подарков включён на сервере (`app_config.gifts_enabled`). Личный
  /// профиль-«Открытка» и вход в профиль партнёра показываются только при нём —
  /// иначе не «протечём» фичу тем, у кого она выключена.
  final bool giftsEnabled;
  const ProfileScreen({
    super.key,
    required this.userData,
    required this.pairData,
    required this.timerService,
    required this.widgetService,
    this.onSwitchToHome,
    this.giftsEnabled = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final RewardedAdService _rewardedAd = RewardedAdService();
  final CoinStore _iap = createCoinStore();
  bool _iapLoading = false;


  // Политика и условия живут на PocketBase-VPS (Firebase Hosting гасится вместе
  // с проектом). Раздаются из pb_public, исходники — PRIVACY_POLICY.md и
  // TERMS_OF_USE.md в репо (регенерация: tool/gen_legal_html.py).
  static final Uri _privacyPolicyUri = Uri.parse(
    'https://togetherly.day/privacy-policy',
  );
  static final Uri _termsUri = Uri.parse(
    'https://togetherly.day/terms',
  );
  // Лендинг тоже переехал с Firebase Hosting на VPS (pb_public).
  static final Uri _aboutAppUri = Uri.parse(
    'https://togetherly.day/#download',
  );
  static final Uri _boostyUri = Uri.parse('https://boosty.to/sntcompany');

  /// Разовый донат картой или СБП.
  static final Uri _donationAlertsUri = Uri.parse(
    'https://www.donationalerts.com/r/thet1me',
  );

  /// Lava.top — приём платежей внутри страны.
  static final Uri _lavaUri = Uri.parse(
    'https://app.lava.top/togetherly-store?tabId=donate',
  );

  /// Почта поддержки. Письмо уходит с темой и версией приложения — иначе
  /// разбирать обращения приходится вслепую.
  static const String supportEmail = 'support@togetherly.day';

  Color get _accent => widget.userData.themeAccent;
  Color get _accentLight => widget.userData.themeAccentLight;
  AppStrings get _s => LocaleService.current;

  /// Активная тема из контекста (семантические токены для тёмной темы).
  AppTheme get _t => context.appTheme;

  /// M3-схема экрана, выведенная из [AppTheme.primary] темы как seed
  /// (вибрант, как в Kadr). Кэшируется по идентичности темы, чтобы не гонять
  /// `fromSeed` на каждый вызов примитива.
  Object? _csSig;
  ColorScheme? _csCache;

  /// Свёрнутость секций «Оформление»-стиля (по ключу секции).
  final Map<String, bool> _expanded = {};

  /// Локальный путь к фото-баннеру профиля (пока без синка на сервер).
  String? _bannerPath;
  WeekStats? _ownWeek; // мои «Я скучаю» по дням недели

  ColorScheme get _cs {
    // Схема профиля совпадает с темой приложения: тот же сырой акцент палитры,
    // тот же вариант (Мягко/Сочно/Точь-в-точь) и та же яркость.
    final ud = widget.userData;
    final seed = paletteByIndex(ud.previewThemeId ?? ud.themeId).accent;
    final b = _t.brightness;
    final flavor = ud.themeFlavor;
    final sig = Object.hash(seed.toARGB32(), b, flavor);
    if (_csSig != sig || _csCache == null) {
      _csSig = sig;
      _csCache = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: b,
        dynamicSchemeVariant: flavor.variant,
      );
    }
    return _csCache!;
  }

  /// UID of the partner selected in the profile (null = first from active group)
  String? _selectedPartnerUid;

  /// Local relationship type used when no group is connected
  RelationshipType _localRelType = RelationshipType.couple;

  /// Timer to refresh day counter every hour
  Timer? _dayTimer;

  /// Toggle for Relationship Stats
  // Notification preferences
  bool _notifMissYou = true;
  bool _notifNewMemory = true;
  bool _notifMood = true;
  bool _notifChat = true;
  // Постоянный счётчик «дней вместе» в шторке. Состояние хранит сам сервис
  // (DaysTogetherNotificationService), здесь — только зеркало для тумблера.
  bool _notifDaysTogether = false;
  static const _kNotifMissYou = 'notif_miss_you';
  static const _kNotifNewMemory = 'notif_new_memory';
  static const _kNotifMood = 'notif_mood';
  static const _kNotifChat = 'notif_chat';

  // Lock screen mood
  bool _lockScreenMood = false;
  static const _kLockScreenMood = 'lock_screen_mood_enabled';

  // Режим боковой кнопки навбара: стрелка → (открыть Ленту) или плюс + (создать
  // пин). См. [UiPrefs]; синхронно с удержанием кнопки на главной.
  bool _sideActionIsArrow = true;

  // Подсказка про колесо «Дни вместе» под полем «Годовщина».
  // Скрывается навсегда по крестику.
  int? _memoriesCount;
  int? _missYouCount;
  int? _drawingsCount;
  StreamSubscription? _missYouSub;
  String? _lastLoadedGroupId;

  int _calculateDaysTogether(DateTime? fallbackDate) =>
      coupleDaysTogether(
        timerStart: widget.timerService.systemTimer?.startDate,
        groupStart: fallbackDate,
      ) ??
      0;

  /// Дней вместе в активной паре — та же дата, что у счётчика на главной.
  /// null — пары нет (в шапке тогда показываем email).
  int? _daysTogetherActive() => coupleDaysTogether(
        timerStart: widget.timerService.systemTimer?.startDate,
        groupStart: widget.pairData.startDate,
      );

  /// Дней вместе в произвольной связи из «Друзей». Таймеры привязаны к активной
  /// группе, поэтому чужой связи достаётся только дата коннекта.
  int? _daysTogetherOf(Connection c) => coupleDaysTogether(
        timerStart: c.pairId == widget.pairData.pairId
            ? widget.timerService.systemTimer?.startDate
            : null,
        groupStart: c.startDate,
      );

  @override
  void initState() {
    super.initState();
    _selectedPartnerUid = widget.pairData.manager.preferredPartnerUid;
    widget.pairData.addListener(_onPairDataChanged);
    SharedPreferences.getInstance().then((p) {
      final b = p.getString('profileBannerPath');
      if (b != null && b.isNotEmpty && File(b).existsSync() && mounted) {
        setState(() => _bannerPath = b);
      }
    });
    // Refresh every hour so the day count updates when crossing midnight
    _dayTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadStats();
    _loadNotifPrefs();
    // НЕ грузим rewarded на открытии профиля — это фоновый запрос, который
    // в 90%+ случаев впустую (юзер не открывает магазин). Предзагрузка
    // происходит в _showCoinShop, когда юзер осознанно идёт за коинами.
    _initIap();
  }

  Future<void> _loadNotifPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final daysTogether =
        await DaysTogetherNotificationService.instance.isEnabled();
    if (!mounted) return;
    setState(() {
      _notifMissYou = prefs.getBool(_kNotifMissYou) ?? true;
      _notifNewMemory = prefs.getBool(_kNotifNewMemory) ?? true;
      _notifMood = prefs.getBool(_kNotifMood) ?? true;
      _notifChat = prefs.getBool(_kNotifChat) ?? true;
      _notifDaysTogether = daysTogether;
      _lockScreenMood = prefs.getBool(_kLockScreenMood) ?? false;
      _sideActionIsArrow = prefs.getBool(UiPrefs.kHomeSideActionArrow) ?? true;
    });
    // Синхронизируем текущие настройки в PocketBase (колонки users.notif_*),
    // чтобы PbPushService учитывал их при показе уведомлений.
    final notifUid = PocketBaseService().userId ?? '';
    if (notifUid.isNotEmpty) {
      PbDataService().updateUserProfile(notifUid, {
        'notifMissYou': prefs.getBool(_kNotifMissYou) ?? true,
        'notifNewMemory': prefs.getBool(_kNotifNewMemory) ?? true,
        'notifMood': prefs.getBool(_kNotifMood) ?? true,
        'notifChat': prefs.getBool(_kNotifChat) ?? true,
      });
    }
  }

  /// Переключить режим боковой кнопки навбара (стрелка ↔ плюс) и запомнить.
  /// Заодно гасим одноразовую подсказку — юзер и так нашёл настройку.
  Future<void> _toggleSideAction() async {
    final next = !_sideActionIsArrow;
    setState(() => _sideActionIsArrow = next);
    await UiPrefs.setSideActionIsArrow(next);
    await UiPrefs.markSideActionHintSeen();
  }

  Future<void> _saveNotifPref(String key, bool value) async {
    // Сохраняем локально
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    // Сохраняем в PocketBase (users.notif_*), чтобы PbPushService учитывал.
    final uid = PocketBaseService().userId ?? '';
    if (uid.isEmpty) return;
    switch (key) {
      case _kNotifMissYou:
        PbDataService().updateUserProfile(uid, {'notifMissYou': value});
        break;
      case _kNotifNewMemory:
        PbDataService().updateUserProfile(uid, {'notifNewMemory': value});
        break;
      case _kNotifMood:
        PbDataService().updateUserProfile(uid, {'notifMood': value});
        break;
      case _kNotifChat:
        PbDataService().updateUserProfile(uid, {'notifChat': value});
        break;
    }
  }

  void _loadStats() {
    // Determine which groupId to load stats for.
    // If a partner is manually selected, use their connection's ID.
    // Otherwise fall back to the global active connection.
    String? currentGroupId;
    if (_selectedPartnerUid != null && _selectedPartnerUid!.isNotEmpty) {
      final allConnections = widget.pairData.manager.connections;
      for (final conn in allConnections) {
        if (conn.partners.any((m) => m.uid == _selectedPartnerUid)) {
          currentGroupId = conn.pairId;
          break;
        }
      }
    }
    currentGroupId ??= widget.pairData.pairId;

    if (currentGroupId.isEmpty) return;
    if (_lastLoadedGroupId == currentGroupId) return;

    _lastLoadedGroupId = currentGroupId;
    _missYouSub?.cancel();

    // Счётчики воспоминаний/рисунков из денормализованных колонок group-дока PB.
    final gid = currentGroupId;
    PbDataService().loadGroupById(gid).then((rec) {
      if (rec == null || !mounted || _lastLoadedGroupId != gid) return;
      setState(() {
        _memoriesCount = (rec.data['memories_count'] as num?)?.toInt() ?? 0;
        _drawingsCount = (rec.data['drawings_count'] as num?)?.toInt() ?? 0;
      });
    });

    // Мои столбики «Я скучаю» по дням недели.
    final myUid = PocketBaseService().userId ?? '';
    if (myUid.isNotEmpty) {
      PbDataService()
          .fetchMissYouFor(groupId: gid, uid: myUid)
          .then((miss) {
        if (!mounted || _lastLoadedGroupId != gid) return;
        setState(
            () => _ownWeek = parseWeekdays(miss?['by_weekday'] as String?));
      });
    }

    // Live-счётчик «Я скучаю» (сумма по паре) из PB.
    _missYouSub = MissYouRepository().watchCounts(gid).listen((counts) {
      if (mounted && _lastLoadedGroupId == gid) {
        setState(
          () => _missYouCount = counts.values.fold<int>(0, (s, v) => s + v),
        );
      }
    });
  }

  @override
  void dispose() {
    _missYouSub?.cancel();
    widget.pairData.removeListener(_onPairDataChanged);
    _dayTimer?.cancel();
    _rewardedAd.dispose();
    _iap.dispose();
    super.dispose();
  }

  void _onPairDataChanged() {
    if (mounted) {
      _loadStats();
      setState(() {});
    }
  }

  Future<void> _openPrivacyPolicy() async {
    await _openExternalUri(_privacyPolicyUri);
  }

  Future<void> _openTerms() async {
    await _openExternalUri(_termsUri);
  }

  /// Письмо в поддержку: тема и версия подставляются сами, человеку остаётся
  /// описать проблему. Почтовика нет — показываем адрес и кладём в буфер.
  Future<void> _openSupportMail() async {
    final info = await PackageInfo.fromPlatform();
    final subject = Uri.encodeComponent(
        'Togetherly ${info.version} (${info.buildNumber})');
    final uri = Uri.parse('mailto:$supportEmail?subject=$subject');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    await Clipboard.setData(const ClipboardData(text: supportEmail));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_s.supportCopied(supportEmail))),
    );
  }

  Future<void> _openAboutApp() async {
    await _openExternalUri(_aboutAppUri);
  }

  Future<void> _openBoosty() async {
    await _openExternalUri(_boostyUri);
  }

  Future<void> _openDonationAlerts() async {
    final email = widget.userData.email.trim();
    // В sideload/веб-сборках донат = монеты: сперва M3-лист с email-подсказкой,
    // чтобы воркер смог опознать плательщика. На Play/App Store — просто открыть.
    if (kDonationsEnabled && email.isNotEmpty) {
      await _showDonationAlertsSheet(email);
    } else {
      await _openExternalUri(_donationAlertsUri);
    }
  }

  /// M3-лист снизу: email аккаунта + подсказка вставить его в сообщение к донату.
  Future<void> _showDonationAlertsSheet(String email) async {
    final cs = _cs;
    final ru = LocaleService.instance.isRussian;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surfaceContainerLow,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ru ? 'Донат → монеты' : 'Donation → coins',
                style: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: -0.4,
                    color: cs.onSurface),
              ),
              const SizedBox(height: 10),
              Text(
                ru
                    ? 'Чтобы монеты пришли автоматически, укажи в сообщении к донату свой email:'
                    : 'To get coins automatically, put your email in the donation message:',
                style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 14.5,
                    height: 1.35,
                    color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Material(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: email));
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(ru ? 'Email скопирован' : 'Email copied')));
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: ProfileTheme.bodyFont,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: cs.onSurface)),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.copy_rounded, size: 20, color: cs.primary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _daStep(cs, '1',
                  ru ? 'Скопируй email кнопкой выше' : 'Copy the email above'),
              _daStep(
                  cs,
                  '2',
                  ru
                      ? 'Вставь его в сообщение к донату'
                      : 'Paste it into the donation message'),
              _daStep(
                  cs,
                  '3',
                  ru
                      ? 'От 50 ₽ — монеты придут сами за пару минут'
                      : 'From 50 ₽ — coins arrive on their own in a couple of minutes'),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _openExternalUri(_donationAlertsUri);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 19),
                  label: Text(
                      ru ? 'Открыть DonationAlerts' : 'Open DonationAlerts',
                      style: const TextStyle(
                          fontFamily: ProfileTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _daStep(ColorScheme cs, String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
              child: Text(n,
                  style: TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: cs.onPrimaryContainer)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(text,
                    style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 14,
                        height: 1.3,
                        color: cs.onSurface)),
              ),
            ),
          ],
        ),
      );

  Future<void> _openLava() async {
    await _openExternalUri(_lavaUri);
  }

  Future<void> _openExternalUri(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) return;
    _showError(_s.error);
  }

  Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      return '1.1.4';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Экран профиля живёт в своей M3-теме (Kadr-стиль): схема из seed темы,
    // шрифты Unbounded/Onest, тональные поверхности, кнопки-пилюли.
    final paired = widget.pairData.isPaired && widget.giftsEnabled;
    return Theme(
      data: ProfileTheme.data(_cs),
      child: Builder(
        builder: (context) => ColoredBox(
          color: _cs.surface,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 110,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Шапка во всю ширину: баннер + свисающий аватар.
                _m3Header(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Профиль показывает только то, ради чего на него
                      // заходят каждый день. Всё остальное — оформление,
                      // уведомления, данные, аккаунт — уехало на отдельный
                      // экран настроек: здесь оно тонуло в девяти
                      // сворачивающихся блоках со своими стилями.
                      _buildFriendsGroup(context),
                      _m3Group('stats', _s.relationshipStats,
                          Icons.insights_rounded,
                          child: _m3Stats(context)),
                      _m3Group('missweek', _s.selfMissTitle,
                          Icons.calendar_view_week_rounded,
                          child: _m3Card([
                            Padding(
                                padding: const EdgeInsets.all(16),
                                child: _missYouWeek())
                          ])),
                      if (paired) ...[
                        const SizedBox(height: 8),
                        _buildPairGroup(context),
                      ],
                      const SizedBox(height: 22),
                      _buildDonationCard(context),
                      const SizedBox(height: 16),
                      SettingsGroup([
                        SettingsRow(
                          icon: Icons.settings_rounded,
                          title: _s.settingsOpen,
                          subtitle: _s.settingsOpenHint,
                          trailing: const SettingsChevron(),
                          onTap: () => _openSettings(context),
                        ),
                      ]),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Секция как в Kadr: заголовок СНАРУЖИ карточки — иконка + акцентный текст +
  /// сворачивание. Содержимое [child] обычно [_m3Card] (плоская карточка).
  Widget _m3Group(
    String key,
    String title,
    IconData icon, {
    bool initiallyExpanded = true,
    required Widget child,
  }) {
    final cs = _cs;
    final expanded = _expanded[key] ?? initiallyExpanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded[key] = !expanded);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 18, 6, 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: ProfileTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 0.2,
                      color: cs.primary,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more_rounded,
                      color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// Плоская M3-карточка: тональная поверхность, без тени/бордера/градиента.
  Widget _m3Card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: _cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  Widget _m3Divider() =>
      Divider(height: 1, indent: 16, endIndent: 16, color: _cs.outlineVariant);

  /// Шапка: широкий баннер-градиент со скруглённым низом и круглым аватаром,
  /// свисающим в кольце цвета поверхности (приём Kadr). Тап по аватару и по
  /// иконке карандаша ведёт в редактирование профиля.
  /// Сменить фото-баннер профиля: камера или галерея, кроп 16:9. Пока хранится
  /// локально на устройстве (синк на сервер — отдельной задачей).
  Future<void> _pickBanner(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _cs.surfaceContainerHigh,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_rounded,
                  color: _cs.onSurfaceVariant),
              title: Text(_s.photoFromCamera,
                  style: TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      color: _cs.onSurface)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded,
                  color: _cs.onSurfaceVariant),
              title: Text(_s.photoFromGallery,
                  style: TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      color: _cs.onSurface)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picker = ImagePicker();
    final image = await safePick(
      () => picker.pickImage(
          source: source, imageQuality: 90, maxWidth: 1600, maxHeight: 1000),
    );
    if (image == null || !mounted) return;
    CroppedFile? cropped;
    try {
      cropped = await ImageCropper().cropImage(
        sourcePath: image.path,
        compressQuality: 90,
        aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: _s.appearanceTitle,
            toolbarColor: const Color(0xFF1A1A2E),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: _accent,
            lockAspectRatio: true,
          ),
          IOSUiSettings(title: _s.appearanceTitle, aspectRatioLockEnabled: true),
        ],
      );
    } catch (e) {
      debugPrint('_pickBanner: crop failed: $e');
      cropped = null;
    }
    if (cropped == null || !mounted) return;
    // Грузим на сервер → banner_url (виден партнёру), как аватар.
    final userId = PocketBaseService().userId ?? '';
    if (userId.isEmpty) {
      if (mounted) _showError(_s.userNotAuthorized);
      return;
    }
    final ext = cropped.path.split('.').last;
    final url = await MediaService()
        .uploadFile(cropped.path, 'banners/$userId/profile.$ext');
    if (url == null) {
      if (mounted) _showError(_s.failedUploadImage);
      return;
    }
    await widget.userData.updateProfile(bannerUrl: url);
    if (mounted) setState(() => _bannerPath = null);
  }

  Widget _m3Header(BuildContext context) {
    final cs = _cs;
    final days = _daysTogetherActive();
    final partnerName = widget.pairData.partnerDisplayName;
    final chipText = (days != null && partnerName.isNotEmpty)
        ? _s.partnerDaysTogether(days)
        : widget.userData.email;
    return ProfileHero(
      cs: cs,
      uid: widget.userData.uid,
      avatarUrl: widget.userData.avatarUrl,
      name: widget.userData.displayName,
      bannerUrl: widget.userData.bannerUrl,
      localBannerPath: _bannerPath,
      subtitle: chipText,
      onEdit: () => _editProfile(context),
      onPickBanner: () => _pickBanner(context),
      onTapAvatar: () => _editProfile(context),
    );
  }

  /// Статистика в духе Kadr: hero-градиент с крупным числом дней и ряд плиток
  /// на тональных контейнерах.
  Widget _missYouWeek() {
    final w = _ownWeek;
    if (w == null || w.byDay.every((d) => d == 0)) {
      return Text(_s.partnerMissEmpty,
          style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontSize: 13,
              color: _cs.onSurfaceVariant));
    }
    return MissYouWeekChart(theme: _t, week: w);
  }

  Widget _m3Stats(BuildContext context) {
    final days = _calculateDaysTogether(widget.pairData.startDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _m3StatHero(value: '$days', label: _s.daysTogetherStat),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _m3StatTile(
                icon: Icons.photo_library_rounded,
                value: _memoriesCount,
                label: _s.memoriesStat,
                variant: 0,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _m3StatTile(
                icon: Icons.brush_rounded,
                value: _drawingsCount,
                label: _s.drawingsStat,
                variant: 1,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _m3StatTile(
                icon: Icons.favorite_rounded,
                value: _missYouCount,
                label: _s.missYousStat,
                variant: 2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _m3StatHero({required String value, required String label}) {
    final cs = _cs;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: cs.primaryContainer,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              letterSpacing: 2,
              color: cs.onPrimaryContainer.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 48,
                height: 1,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _m3StatTile({
    required IconData icon,
    required int? value,
    required String label,
    required int variant,
  }) {
    final cs = _cs;
    final bg = [
      cs.primaryContainer,
      cs.secondaryContainer,
      cs.tertiaryContainer,
    ][variant % 3];
    final fg = [
      cs.onPrimaryContainer,
      cs.onSecondaryContainer,
      cs.onTertiaryContainer,
    ][variant % 3];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value?.toString() ?? '…',
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 24,
                height: 1,
                color: fg,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontSize: 11,
              color: fg.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  /// Старый метод-обёртка оставлен неиспользуемым намеренно на время рефактора;
  /// M3-верх собирается в [build] через [_m3Header]/[_m3Stats].
  // ignore: unused_element
  Widget _buildProfilePresentation(BuildContext context) {
    if (!widget.pairData.isPaired || !widget.giftsEnabled) {
      return _buildProfileHeader(context);
    }
    final myUid = widget.userData.uid.isNotEmpty
        ? widget.userData.uid
        : (PocketBaseService().userId ?? '');
    final days = _daysTogetherActive();
    return Column(
      children: [
        GiftProfileBody(
          theme: _t,
          groupId: widget.pairData.pairId,
          uid: myUid,
          name: widget.userData.displayName,
          avatarUrl: widget.userData.avatarUrl,
          daysTogether: days,
          isSelf: true,
          onAvatarTap: () => _editProfile(context),
        ),
        const SizedBox(height: 16),
        _buildPartnerTile(context),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  ОФОРМЛЕНИЕ: палитра × режим × вариант × AMOLED
  // ═══════════════════════════════════════════════════

  /// Секция «Оформление»: лента палитр (выбор/покупка) + тумблеры режима
  /// (свет/тьма/система — бесплатно), сочности и AMOLED.
  Widget _buildAppearanceCard(BuildContext context) {
    final cs = _cs;
    final ud = widget.userData;
    Widget caption(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(t,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              )),
        );
    return _m3Card([
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            caption(_s.paletteLabel),
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kPalettes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _paletteSwatch(context, i),
              ),
            ),
            const SizedBox(height: 18),
            caption(_s.themeModeLabel),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<AppThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: AppThemeMode.light,
                      icon: const Icon(Icons.light_mode_rounded),
                      tooltip: _s.themeModeLight),
                  ButtonSegment(
                      value: AppThemeMode.dark,
                      icon: const Icon(Icons.dark_mode_rounded),
                      tooltip: _s.themeModeDark),
                  ButtonSegment(
                      value: AppThemeMode.system,
                      icon: const Icon(Icons.brightness_auto_rounded),
                      tooltip: _s.themeModeSystem),
                ],
                selected: {ud.themeMode},
                onSelectionChanged: (s) => ud.setThemeMode(s.first),
              ),
            ),
            const SizedBox(height: 18),
            caption(_s.themeStyleLabel),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<SchemeFlavor>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: SchemeFlavor.soft, label: Text(_s.themeFlavorSoft)),
                  ButtonSegment(
                      value: SchemeFlavor.juicy,
                      label: Text(_s.themeFlavorJuicy)),
                  ButtonSegment(
                      value: SchemeFlavor.exact,
                      label: Text(_s.themeFlavorExact)),
                ],
                selected: {ud.themeFlavor},
                onSelectionChanged: (s) => ud.setThemeFlavor(s.first),
              ),
            ),
          ],
        ),
      ),
      _m3Divider(),
      SwitchListTile(
        title: Text(_s.amoledLabel,
            style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            )),
        secondary: Icon(Icons.contrast_rounded, color: cs.onSurfaceVariant),
        value: ud.amoled,
        onChanged: (v) => ud.setAmoled(v),
      ),
    ]);
  }

  /// Один кружок палитры в ленте: акцент, галочка у выбранной, ценник у платной.
  Widget _paletteSwatch(BuildContext context, int i) {
    final cs = _cs;
    final ud = widget.userData;
    final p = kPalettes[i];
    final selected = ud.themeId == i;
    final locked = p.isPremium && !ud.hasTheme(i);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SeedSwatch(
          seed: p.accent,
          selected: selected,
          size: 46,
          flavor: ud.themeFlavor,
          onTap: () => _onPaletteTap(context, i),
        ),
        if (locked)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/icons/coin.webp',
                    width: 11, height: 11),
                const SizedBox(width: 2),
                Text('${p.price}',
                    style: TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurfaceVariant,
                    )),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _onPaletteTap(BuildContext context, int i) async {
    final ud = widget.userData;
    final p = kPalettes[i];
    final locked = p.isPremium && !ud.hasTheme(i);
    if (locked) {
      final t = buildAppTheme(p, _t.brightness,
          flavor: ud.themeFlavor, amoled: ud.amoled);
      final result = await _confirmPurchaseTheme(context, t);
      if (result == false) return; // отмена
      if (result == null) {
        // Предпросмотр без покупки.
        ud.setPreviewTheme(i);
        return;
      }
      // result == true → палитра куплена
    }
    await ud.setThemeId(i);
    if (mounted) setState(() {});
  }

  // ── Группы настроек (плоские M3-карточки, заголовок даёт _m3Group) ──

  /// Открывает экран настроек. Логика остаётся здесь — экран получает готовые
  /// обработчики и ничего не знает ни про PocketBase, ни про покупки.
  Future<void> _openSettings(BuildContext context) async {
    final version = await _getAppVersion();
    if (!mounted) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatefulBuilder(
          builder: (ctx, setSheetState) => SettingsScreen(
            scheme: _cs,
            appVersion: 'Togetherly $version',
            onAppearance: () => _openAppearance(ctx),
            onNotifications: () => _showNotificationSettings(ctx),
            onLanguage: () => _showLanguagePicker(ctx),
            onCoinShop: () => _showCoinShop(ctx),
            onPrivacyPolicy: _openPrivacyPolicy,
            onExport: () => _handleExportConfig(ctx),
            onResetMissYou: () => _handleResetMissYouCount(ctx),
            onTerms: _openTerms,
            onSupport: _openSupportMail,
            onAbout: _openAboutApp,
            onLogout: () => _showLogoutDialog(ctx),
            onDeleteAccount: () => _showDeleteAccountDialog(ctx),
            lockScreenMood: _lockScreenMood,
            onLockScreenMoodChanged: (v) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(_kLockScreenMood, v);
              if (!mounted) return;
              setState(() => _lockScreenMood = v);
              setSheetState(() {});
            },
            sideActionIsArrow: _sideActionIsArrow,
            onToggleSideAction: () async {
              await _toggleSideAction();
              setSheetState(() {});
            },
            plusActive: PlusService.instance.active,
            onPlus: () => _openPlus(ctx),
            cycleAvailable: CycleService.availableFor(widget.userData),
            cycleShared: CycleService.instance.shareWithPartner,
            onCycleSharedChanged: (v) async {
              await CycleService.instance.setShareWithPartner(v);
              setSheetState(() {});
            },
            onCycleWipe: () => _confirmCycleWipe(ctx, setSheetState),
          ),
        ),
      ),
    );
  }

  /// Экран Togetherly+.
  void _openPlus(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlusScreen(scheme: _cs)),
    );
  }

  /// Стирание данных цикла: спрашиваем прежде, чем удалять, — вернуть нельзя.
  Future<void> _confirmCycleWipe(
    BuildContext context,
    StateSetter refreshSheet,
  ) async {
    final ok = await AppDialog.confirm(
      context,
      title: _s.cycleWipe,
      message: _s.cycleWipeConfirm,
      confirmLabel: _s.delete,
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok) return;
    await CycleService.instance.wipe();
    refreshSheet(() {});
  }

  /// Оформление отдельным экраном — как в эталоне. Внутри та же карточка, что
  /// раньше лежала прямо в профиле.
  void _openAppearance(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: ProfileTheme.data(_cs),
          child: Builder(
            builder: (ctx) => Scaffold(
              backgroundColor: _cs.surface,
              appBar: AppBar(
                backgroundColor: _cs.surface,
                surfaceTintColor: Colors.transparent,
                centerTitle: true,
                title: Text(
                  _s.appearanceTitle,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    fontVariations: const [FontVariation('wght', 600)],
                    color: _cs.onSurface,
                  ),
                ),
              ),
              body: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(ctx).padding.bottom + 32,
                ),
                children: [_buildAppearanceCard(ctx)],
              ),
            ),
          ),
        ),
      ),
    );
  }





  // ── Друзья / партнёры (все группы) ──

  List<_PartnerEntry> _allPartnerEntries() {
    final entries = <_PartnerEntry>[];
    for (final conn in widget.pairData.manager.connections) {
      if (conn.isPaired) {
        for (final m in conn.partners) {
          entries.add(_PartnerEntry(member: m, connection: conn));
        }
      }
    }
    return entries;
  }

  void _openPartnerProfile(BuildContext context, _PartnerEntry e) {
    final days = _daysTogetherOf(e.connection);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PartnerProfileScreen(
          theme: _t,
          groupId: e.connection.pairId,
          partnerUid: e.member.uid,
          partnerName: e.member.name,
          partnerAvatarUrl: e.member.avatar,
          daysTogether: days,
        ),
        settings: const RouteSettings(name: '/partner'),
      ),
    );
  }

  /// Свой профиль-«Открытка»: полка полученных подарков и «Я скучаю» по дням —
  /// симметрично профилю партнёра (тап по аватару в «Друзьях»).
  void _openSelfProfile(BuildContext context) {
    final days = _daysTogetherActive();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelfProfileScreen(
          theme: _t,
          groupId: widget.pairData.pairId,
          // Фолбэк на id сессии PB: пустой uid в профиле (бывает после
          // восстановления сессии) оставлял полку подарков пустой навсегда.
          selfUid: widget.userData.uid.isNotEmpty
              ? widget.userData.uid
              : (PocketBaseService().userId ?? ''),
          selfName: widget.userData.displayName,
          selfAvatarUrl: widget.userData.avatarUrl,
          bannerUrl: widget.userData.bannerUrl,
          daysTogether: days,
        ),
        settings: const RouteSettings(name: '/self_gifts'),
      ),
    );
  }

  /// Друзья/партнёры в ряд — как в Kadr: аватар (или буква на цветном круге) +
  /// имя. Много групп и партнёров — все здесь.
  Widget _buildFriendsGroup(BuildContext context) {
    final entries = _allPartnerEntries();
    if (entries.isEmpty) return const SizedBox.shrink();
    return _m3Group('friends', _s.friends, Icons.group_rounded,
        child: _m3Card([
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: SizedBox(
              height: 86,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (c, i) {
                  final m = entries[i].member;
                  return GestureDetector(
                    onTap: () => _openPartnerProfile(context, entries[i]),
                    child: SizedBox(
                      width: 62,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AvatarWidget(
                            uid: m.uid,
                            liveUrl: m.avatar,
                            name: m.name,
                            size: 56,
                            primary: _cs.primary,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            m.name.isEmpty ? '—' : m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: ProfileTheme.bodyFont,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ]));
  }

  /// «Отношения»: статус и даты (открывается в шите; партнёры — в «Друзьях»).
  /// Даты и статус пары — прямо в профиле, без обёртки.
  ///
  /// Раньше это был блок «Отношения» с единственным пунктом «Статус
  /// отношений», который открывал лист с теми же полями: три уровня, чтобы
  /// добраться до годовщины. Теперь строки лежат на виду, а лист остаётся
  /// только для правки конкретного поля.
  Widget _buildPairGroup(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(_s.relationships),
        _buildRelationshipCard(context),
        if (widget.giftsEnabled) ...[
          const SizedBox(height: 10),
          SettingsGroup([
            SettingsRow(
              icon: Icons.card_giftcard_rounded,
              title: _s.selfGiftsTitle,
              trailing: const SettingsChevron(),
              onTap: () => _openSelfProfile(context),
            ),
          ]),
        ],
      ],
    );
  }


  /// Заметная карточка доната (как в Kadr): заголовок + текст + три кнопки.
  /// Не сворачивается, стоит отдельным блоком над «О приложении».
  Widget _buildDonationCard(BuildContext context) {
    final cs = _cs;
    TextStyle btn() => const TextStyle(
        fontFamily: ProfileTheme.displayFont,
        fontWeight: FontWeight.w700,
        fontSize: 15);
    return Container(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.volunteer_activism_rounded,
                  color: cs.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_s.supportAuthors,
                    style: TextStyle(
                        fontFamily: ProfileTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: cs.onSurface)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_s.supportIntro,
              style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 13.5,
                  height: 1.35,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openBoosty,
            icon: const Icon(Icons.favorite_rounded, size: 19),
            label: Text('Boosty', style: btn()),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _openDonationAlerts,
            icon: const Icon(Icons.card_giftcard_rounded, size: 19),
            label: Text('DonationAlerts', style: btn()),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _openLava,
            icon: const Icon(Icons.water_drop_rounded, size: 19),
            label: Text('Lava.top', style: btn()),
          ),
        ],
      ),
    );
  }


  // ═══════════════════════════════════════════════════
  //  ВЕРХ СТРАНИЦЫ: ЛИЧНЫЙ ПРОФИЛЬ + ПАРТНЁР (M3 — см. _m3Header/_m3Stats)
  // ═══════════════════════════════════════════════════

  /// Карточка-вход в профиль партнёра прямо со страницы «Профиль».
  Widget _buildPartnerTile(BuildContext context) {
    final t = _t;
    final name = widget.pairData.partnerDisplayName;
    final avatar = widget.pairData.partnerAvatarUrl;
    final days = _daysTogetherActive();
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PartnerProfileScreen(
            theme: t,
            groupId: widget.pairData.pairId,
            partnerUid: widget.pairData.partnerUid,
            partnerName: name,
            partnerAvatarUrl: avatar,
            daysTogether: days,
          ),
          settings: const RouteSettings(name: '/partner'),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: t.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.divider, width: 0.5),
        ),
        child: Row(
          children: [
            AvatarWidget(
              uid: widget.pairData.partnerUid,
              liveUrl: avatar,
              name: name,
              size: 44,
              primary: t.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? _s.partnerGiftsTitle : name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _s.openPartnerProfile,
                    style: TextStyle(fontSize: 12.5, color: t.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  PROFILE HEADER
  // ═══════════════════════════════════════════════════
  Widget _buildProfileHeader(BuildContext context) {
    return Column(
      children: [
        // Avatar with glow
        GestureDetector(
          onTap: () => _editProfile(context),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: _t.accentGlow(
                    _accent,
                    opacity: 0.2,
                    blurRadius: 32,
                    spreadRadius: 4,
                    offset: Offset.zero,
                  ),
                ),
                child: LevelAvatar(
                  size: 100,
                  ring: 4,
                  child: ColoredBox(
                    color: _accentLight,
                    child: widget.userData.avatarUrl.isNotEmpty
                        ? StorageImage(
                            imageUrl: widget.userData.avatarUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 200,
                            memCacheHeight: 200,
                            errorWidget: (context, url, error) =>
                                _buildAvatarFallback(),
                          )
                        : _buildAvatarFallback(),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Name
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.userData.displayName.isNotEmpty
                  ? widget.userData.displayName
                  : _s.user,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: _t.textPrimary,
              ),
            ),
            // Закреплённая иконка-бейдж. Тап открывает магазин иконок,
            // где можно сменить/купить/снять иконку.
            GestureDetector(
              onTap: () => _showIconPicker(context),
              child: widget.userData.equippedIcon != null
                  // Лёгкий сдвиг влево компенсирует прозрачные поля внутри
                  // ассета, чтобы иконка «прижималась» к имени.
                  ? Transform.translate(
                      offset: const Offset(-4, 0),
                      child: Image.asset(
                        ProfileIcon.byId(widget.userData.equippedIcon)?.asset ??
                            'assets/images/icons/${widget.userData.equippedIcon}.webp',
                        width: 38,
                        height: 38,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add_reaction_outlined,
                          size: 18,
                          color: _accent.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Email
        Text(
          widget.userData.email.isNotEmpty ? widget.userData.email : _s.noEmail,
          style: TextStyle(fontSize: 14, color: _t.textMuted),
        ),
        const SizedBox(height: 12),
        // Gender badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _accent.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.userData.isMale
                    ? Icons.male_rounded
                    : Icons.female_rounded,
                color: _accent,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                widget.userData.isMale ? _s.boy : _s.girl,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarFallback() {
    return Center(
      child: Text(
        widget.userData.initials,
        style: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w800,
          color: _accent.withOpacity(0.6),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  EDIT PROFILE
  // ═══════════════════════════════════════════════════
  Future<void> _editProfile(BuildContext context) async {
    final nameController = TextEditingController(
      text: widget.userData.displayName,
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _t.cardSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _s.editProfile,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _t.textPrimary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Avatar edit
              Center(
                child: GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    await _changeAvatar();
                  },
                  child: Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accentLight,
                          border: Border.all(
                            color: _accent.withOpacity(0.2),
                            width: 3,
                          ),
                        ),
                        child: widget.userData.avatarUrl.isNotEmpty
                            ? ClipOval(
                                child: StorageImage(
                                  imageUrl: widget.userData.avatarUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      _buildAvatarFallback(),
                                ),
                              )
                            : _buildAvatarFallback(),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Name field
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: _s.name,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Save button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    final newName = nameController.text.trim();
                    if (newName.isNotEmpty &&
                        newName != widget.userData.displayName) {
                      await _changeName(newName);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _s.save,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeAvatar() async {
    final picker = ImagePicker();
    final image = await safePick(
      () => picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1024,
        maxHeight: 1024,
      ),
    );

    if (image == null || !mounted) return;

    // Обрезаем до круга (аватарка). Нативный кроппер может кинуть
    // PlatformException — это не краш, трактуем как отмену.
    CroppedFile? croppedFile;
    try {
      croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            cropStyle: CropStyle.circle,
            toolbarTitle: LocaleService.current.cropAvatarTitle,
            toolbarColor: const Color(0xFF1A1A2E),
            toolbarWidgetColor: Colors.white,
            statusBarColor: const Color(0xFF1A1A2E),
            backgroundColor: const Color(0xFF0D0D1A),
            activeControlsWidgetColor: _accent,
            cropFrameColor: _accent,
            cropGridColor: Colors.transparent,
            dimmedLayerColor: const Color(0xCC0D0D1A),
            showCropGrid: false,
            lockAspectRatio: true,
            initAspectRatio: CropAspectRatioPreset.square,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            cropStyle: CropStyle.circle,
            title: LocaleService.current.avatarTitle,
            doneButtonTitle: LocaleService.current.done,
            cancelButtonTitle: LocaleService.current.cancel,
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            rotateButtonsHidden: false,
            hidesNavigationBar: true,
          ),
        ],
      );
    } catch (e) {
      debugPrint('_changeAvatar: cropImage failed: $e');
      croppedFile = null;
    }

    if (croppedFile == null || !mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _t.cardSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                M3Loading(color: _accentLight),
                const SizedBox(height: 16),
                Text(
                  _s.uploading,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _t.textSecondary,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final fb = MediaService();
      final userId = PocketBaseService().userId ?? '';
      if (userId.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        if (mounted) _showError(_s.userNotAuthorized);
        return;
      }

      final ext = croppedFile.path.split('.').last;
      final destination = 'avatars/$userId/profile.$ext';
      final downloadUrl = await fb.uploadFile(croppedFile.path, destination);

      if (mounted) Navigator.of(context).pop();

      if (downloadUrl == null) {
        if (mounted) _showError(_s.failedUploadImage);
        return;
      }

      // Update profile
      await widget.userData.updateProfile(avatarUrl: downloadUrl);
      // Профиль кэшируется в WidgetService на сессию — без явного рефреша
      // виджет (и партнёр) показывали бы старый аватар до перезахода.
      await widget.widgetService.refreshProfileOnWidget();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_s.avatarUpdated),
            backgroundColor: _accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) _showError(_s.uploadError(e.toString()));
    }
  }

  Future<void> _changeName(String newName) async {
    try {
      await widget.userData.updateProfile(displayName: newName);
      // Имя на виджете кэшируется в WidgetService — рефрешим, иначе оно
      // обновится только после перезахода (как и аватар).
      await widget.widgetService.refreshProfileOnWidget();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_s.nameUpdated),
            backgroundColor: _accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError(_s.uploadError(e.toString()));
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  RELATIONSHIP CARD
  // ═══════════════════════════════════════════════════
  Widget _buildRelationshipCard(BuildContext context) {
    // Gather all partners from ALL connections (not just the active one)
    final allConnections = widget.pairData.manager.connections;
    final allPartners = <_PartnerEntry>[];
    for (final conn in allConnections) {
      if (conn.isPaired) {
        for (final m in conn.partners) {
          allPartners.add(_PartnerEntry(member: m, connection: conn));
        }
      }
    }

    // Resolve selected partner (respects manual choice or falls back to first)
    _PartnerEntry? selectedPartner;
    if (_selectedPartnerUid != null && _selectedPartnerUid!.isNotEmpty) {
      final found = allPartners.where(
        (p) => p.member.uid == _selectedPartnerUid,
      );
      selectedPartner = found.isNotEmpty ? found.first : null;
    }

    // Fallback: active connection first, then any connection
    if (selectedPartner == null && allPartners.isNotEmpty) {
      final activePartner = allPartners.where(
        (p) => p.connection.id == widget.pairData.manager.activeConnection?.id,
      );
      selectedPartner = activePartner.isNotEmpty
          ? activePartner.first
          : allPartners.first;
    }

    // Relationship type: synced with selected partner's group, or local override
    final relType =
        selectedPartner?.connection.relationshipType ?? _localRelType;
    final customLabel =
        selectedPartner?.connection.customRelationshipLabel ?? '';
    final relLabel =
        relType == RelationshipType.custom && customLabel.isNotEmpty
        ? customLabel
        : _relTypeToRussian(relType);
    final relColor = _relTypeToColor(relType);
    final relIcon = _relTypeToIcon(relType);

    // ── Days together — ALWAYS from system clock (DateTime.now) ──
    final startDate = selectedPartner?.connection.startDate;
    final daysString = _s.daysTogetherLabel(
      '${_calculateDaysTogether(startDate)}',
    );

    final hasPaired = allPartners.isNotEmpty;

    // Вид собран на общем каркасе настроек: круглые чипы-иконки, разделитель
    // до иконки, крупный текст. Расчёты выше не трогаем — там выбор партнёра
    // из нескольких связей и даты.
    return SettingsGroup([
      SettingsRow(
        icon: relIcon,
        title: _s.relationshipStatus,
        subtitle: relLabel,
        iconBg: relColor.withValues(alpha: 0.16),
        iconFg: relColor,
        trailing: const SettingsChevron(),
        onTap: () => _showRelationshipTypePicker(
          context,
          selectedPartner?.connection,
        ),
      ),
      if (hasPaired) ...[
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.person_rounded,
          title: _s.partnerLabel,
          subtitle: selectedPartner?.member.name ?? _s.notSet,
          trailing: const SettingsChevron(),
          onTap: () => _showPartnerPicker(context, allPartners),
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.calendar_month_rounded,
          title: _s.together,
          subtitle: daysString,
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.celebration_rounded,
          title: _s.anniversaryDate,
          subtitle: _formatCelebrationDate(selectedPartner?.connection.anniversaryDate),
          trailing: const SettingsChevron(),
          onTap: () => _showAnniversaryDatePicker(
            context,
            selectedPartner?.connection,
          ),
        ),
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.favorite_rounded,
          title: _s.firstKissDate,
          subtitle: _formatCelebrationDate(selectedPartner?.connection.firstKissDate),
          trailing: const SettingsChevron(),
          onTap: () => _showFirstKissDatePicker(
            context,
            selectedPartner?.connection,
          ),
        ),
      ],
      const SettingsDivider(),
      SettingsRow(
        icon: widget.userData.isMale
            ? Icons.male_rounded
            : widget.userData.isFemale
                ? Icons.female_rounded
                : Icons.transgender_rounded,
        title: _s.gender,
        subtitle: _genderLabel(),
        trailing: const SettingsChevron(),
        onTap: () => _showGenderPicker(context),
      ),
      const SettingsDivider(),
      SettingsRow(
        icon: Icons.cake_rounded,
        title: _s.myBirthday,
        subtitle: _formatCelebrationDate(widget.userData.birthDate),
        trailing: const SettingsChevron(),
        onTap: () => _showBirthdayPicker(context),
      ),
      if (hasPaired) ...[
        const SettingsDivider(),
        SettingsRow(
          icon: Icons.cake_outlined,
          title: _s.partnerBirthday,
          subtitle: _formatCelebrationDate(
            selectedPartner == null
                ? null
                : selectedPartner.connection
                    .memberBirthdays[selectedPartner.member.uid],
          ),
        ),
      ],
    ]);
  }

  // ── Celebration helpers ──

  String _formatCelebrationDate(DateTime? date) {
    if (date == null) return _s.notSet;
    final d = '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    if (date.hour == 0 && date.minute == 0) return d;
    final t = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '$d  $t';
  }


  /// Выбор даты и времени. Открывает полноэкранный [DateTimePickerScreen]:
  /// нижний лист с полем «ДД.ММ.ГГГГ» ушёл — крупная типографика в него не
  /// влезала, месяц наезжал на год, а системная клавиатура занимала полэкрана.
  /// [firstYear] / [lastYear] — допустимый диапазон лет.
  /// Возвращает выбранную дату или null, если отменили.
  Future<DateTime?> _showDateInputDialog({
    required BuildContext context,
    required String title,
    required DateTime? initial,
    required int firstYear,
    required int lastYear,
  }) =>
      Navigator.of(context).push<DateTime>(
        MaterialPageRoute<DateTime>(
          builder: (_) => DateTimePickerScreen(
            title: title,
            theme: _t,
            initial: initial,
            firstYear: firstYear,
            lastYear: lastYear,
          ),
          settings: const RouteSettings(name: '/date_picker'),
        ),
      );



  Future<void> _showAnniversaryDatePicker(
    BuildContext context,
    Connection? connection,
  ) async {
    final groupId = connection?.pairId ?? '';
    if (groupId.isEmpty) return;
    final picked = await _showDateInputDialog(
      context: context,
      title: _s.anniversaryDate,
      initial: connection?.anniversaryDate,
      firstYear: 1900,
      lastYear: DateTime.now().year,
    );
    if (picked == null || !mounted) return;
    await PbDataService().updateGroupFields(groupId, {
      'anniversary_date': picked.toIso8601String(),
    });
    await CelebrationNotificationService.instance.onDatesChanged(
      anniversaryDate: picked,
      birthDate: widget.userData.birthDate,
    );
    if (mounted) setState(() {});
  }

  Future<void> _showFirstKissDatePicker(
    BuildContext context,
    Connection? connection,
  ) async {
    final groupId = connection?.pairId ?? '';
    if (groupId.isEmpty) return;
    final picked = await _showDateInputDialog(
      context: context,
      title: _s.firstKissDate,
      initial: connection?.firstKissDate,
      firstYear: 1900,
      lastYear: DateTime.now().year,
    );
    if (picked == null || !mounted) return;
    await PbDataService().updateGroupFields(groupId, {
      'first_kiss_date': picked.toIso8601String(),
    });
    if (mounted) setState(() {});
  }

  Future<void> _showBirthdayPicker(BuildContext context) async {
    final picked = await _showDateInputDialog(
      context: context,
      title: _s.myBirthday,
      initial: widget.userData.birthDate,
      firstYear: 1920,
      lastYear: DateTime.now().year,
    );
    if (picked == null || !mounted) return;
    await widget.userData.updateBirthDate(picked);
    final conn = widget.pairData.manager.activeConnection;
    await CelebrationNotificationService.instance.onDatesChanged(
      anniversaryDate: conn?.anniversaryDate,
      birthDate: picked,
    );
    if (mounted) setState(() {});
  }

  // ── Пол ──

  /// Что показать в строке профиля: свой вариант человек пишет сам.
  String _genderLabel() {
    final u = widget.userData;
    if (u.isMale) return _s.male;
    if (u.isFemale) return _s.female;
    final custom = u.customGender?.trim() ?? '';
    if (custom.isNotEmpty) return custom;
    return u.gender == null ? _s.genderNotSet : _s.genderPreferNotSay;
  }

  /// Пол меняется и после регистрации: его видит партнёр, от него зависит
  /// календарь цикла и оформление виджетов. Набор вариантов тот же, что при
  /// входе, включая свой — иначе смена пола означала бы новый аккаунт.
  Future<void> _showGenderPicker(BuildContext context) async {
    final u = widget.userData;
    final ctrl = TextEditingController(text: u.customGender ?? '');
    bool customOpen =
        u.gender == Gender.unspecified && (u.customGender ?? '').isNotEmpty;

    Future<void> apply(
      BuildContext sheetCtx,
      Gender gender, {
      String? custom,
    }) async {
      Navigator.pop(sheetCtx);
      await u.updateGender(gender, customGender: custom);
      // Профиль кэшируется в WidgetService на сессию: без рефреша виджет и
      // партнёр держали бы прежний пол до перезахода.
      await widget.widgetService.refreshProfileOnWidget();
      if (mounted) setState(() {});
    }

    await showAppSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SheetScaffold(
          title: _s.gender,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            children: [
              SettingsGroup([
                SettingsRow(
                  icon: Icons.male_rounded,
                  title: _s.male,
                  trailing: u.isMale ? const Icon(Icons.check_rounded) : null,
                  onTap: () => apply(ctx, Gender.male),
                ),
                const SettingsDivider(),
                SettingsRow(
                  icon: Icons.female_rounded,
                  title: _s.female,
                  trailing: u.isFemale ? const Icon(Icons.check_rounded) : null,
                  onTap: () => apply(ctx, Gender.female),
                ),
                const SettingsDivider(),
                SettingsRow(
                  icon: Icons.do_not_disturb_on_rounded,
                  title: _s.genderPreferNotSay,
                  trailing: (u.gender == Gender.unspecified &&
                          (u.customGender ?? '').isEmpty)
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => apply(ctx, Gender.unspecified),
                ),
                const SettingsDivider(),
                SettingsRow(
                  icon: Icons.edit_rounded,
                  title: _s.genderCustom,
                  subtitle: customOpen ? null : u.customGender,
                  trailing: customOpen
                      ? const Icon(Icons.keyboard_arrow_up_rounded)
                      : (u.customGender ?? '').isNotEmpty
                          ? const Icon(Icons.check_rounded)
                          : const SettingsChevron(),
                  onTap: () => setSheet(() => customOpen = !customOpen),
                ),
              ]),
              if (customOpen) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _s.genderCustom,
                    hintText: _s.genderCustomHint,
                    prefixIcon: const Icon(Icons.edit_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setSheet(() {}),
                  onSubmitted: (v) => v.trim().isEmpty
                      ? null
                      : apply(ctx, Gender.unspecified, custom: v),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: ctrl.text.trim().isEmpty
                        ? null
                        : () => apply(ctx, Gender.unspecified, custom: ctrl.text),
                    child: Text(_s.save),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();
  }

  // ── Relationship type helpers ──
  String _relTypeToRussian(RelationshipType type) {
    switch (type) {
      case RelationshipType.couple:
        return _s.inLoveRelType;
      case RelationshipType.married:
        return _s.marriedRelType;
      case RelationshipType.friends:
        return _s.friendsRelType;
      case RelationshipType.buddies:
        return _s.bestFriendsRelType;
      case RelationshipType.custom:
        return _s.customStatus;
    }
  }

  Color _relTypeToColor(RelationshipType type) {
    switch (type) {
      case RelationshipType.couple:
        return const Color(0xFFE91E8C);
      case RelationshipType.married:
        return const Color(0xFF9B59B6);
      case RelationshipType.friends:
        return const Color(0xFF3498DB);
      case RelationshipType.buddies:
        return const Color(0xFF2ECC71);
      case RelationshipType.custom:
        return _accent;
    }
  }

  IconData _relTypeToIcon(RelationshipType type) {
    switch (type) {
      case RelationshipType.couple:
        return Icons.favorite_rounded;
      case RelationshipType.married:
        return Icons.diamond_outlined;
      case RelationshipType.friends:
        return Icons.people_outline_rounded;
      case RelationshipType.buddies:
        return Icons.diversity_1_rounded;
      case RelationshipType.custom:
        return Icons.star_outline_rounded;
    }
  }

  // ── Picker: тип отношений ──
  Future<void> _showRelationshipTypePicker(
    BuildContext context,
    Connection? connection,
  ) async {
    final types = [
      RelationshipType.couple,
      RelationshipType.married,
      RelationshipType.friends,
      RelationshipType.buddies,
    ];

    final current = connection?.relationshipType ?? _localRelType;

    // M3-лист: выбранный тип — тональная карточка secondaryContainer с
    // галочкой, остальные ровные. Цветных обводок нет: цвет здесь означал бы
    // категорию, а категория тут одна.
    await showAppSheet<void>(
      context,
      builder: (ctx) => SheetScaffold(
        title: _s.relationshipType,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...types.map((type) {
                final label = _relTypeToRussian(type);
                final icon = _relTypeToIcon(type);
                final isSelected = current == type;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isSelected
                        ? _cs.secondaryContainer
                        : _cs.surfaceContainerHigh,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: InkWell(
                      onTap: () {
                        if (connection != null) {
                          connection.setRelationshipType(type);
                        } else {
                          setState(() => _localRelType = type);
                        }
                        Navigator.pop(ctx);
                        setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _cs.onSecondaryContainer
                                        .withValues(alpha: 0.12)
                                    : _cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                icon,
                                size: 23,
                                color: isSelected
                                    ? _cs.onSecondaryContainer
                                    : _cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontFamily: 'Onest',
                                  fontSize: 16,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? _cs.onSecondaryContainer
                                      : _cs.onSurface,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle_rounded,
                                  size: 22, color: _cs.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ── Picker: выбор партнёра из всех групп ──
  Future<void> _showPartnerPicker(
    BuildContext context,
    List<_PartnerEntry> allPartners,
  ) async {
    if (allPartners.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_s.noConnectedPartners),
          backgroundColor: _accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: _t.cardSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _t.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _s.selectPartner,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _t.textPrimary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...allPartners.map((entry) {
                final defaultUid = allPartners.first.member.uid;
                final isSelected =
                    entry.member.uid == (_selectedPartnerUid ?? defaultUid);
                final relColor = _relTypeToColor(
                  entry.connection.relationshipType,
                );
                final initial = entry.member.name.firstGraphemeUpper('?');
                return GestureDetector(
                  onTap: () {
                    final uid = entry.member.uid;
                    setState(() => _selectedPartnerUid = uid);
                    widget.pairData.manager.setPreferredPartnerUid(uid);

                    final idx = widget.pairData.manager.connections.indexOf(
                      entry.connection,
                    );
                    if (idx != -1 &&
                        idx != widget.pairData.manager.activeConnectionIndex) {
                      widget.pairData.manager.switchToConnection(idx);
                    }

                    Navigator.pop(ctx);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _accent.withOpacity(0.08)
                          : _t.surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? _accent : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _accentLight,
                          ),
                          child: entry.member.avatar.isNotEmpty
                              ? ClipOval(
                                  child: StorageImage(
                                    imageUrl: entry.member.avatar,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) =>
                                        Center(
                                          child: Text(
                                            initial,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: _accent,
                                            ),
                                          ),
                                        ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    initial,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _accent,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.member.name.isNotEmpty
                                    ? entry.member.name
                                    : _s.partner,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: _t.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _relTypeToRussian(
                                  entry.connection.relationshipType,
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: relColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle_rounded,
                            color: _accent,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  NOTIFICATION SETTINGS
  // ═══════════════════════════════════════════════════
  /// Уведомления — крупным меню снизу, на общем каркасе.
  ///
  /// Иконки раньше были каждая своего цвета (синяя, оранжевая, зелёная) и
  /// спорили с темой приложения. Теперь чипы одного тона, как в остальных
  /// разделах: цвет несёт смысл только там, где он что-то значит.
  void _showNotificationSettings(BuildContext context) {
    final s = LocaleService.current;

    showAppSheet<void>(
      context,
      expand: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SheetScaffold(
          title: s.notifications,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            children: [
              SettingsGroup([
                SettingsRow(
                  icon: Icons.favorite_rounded,
                  title: s.notifMissYou,
                  subtitle: s.notifMissYouSub,
                  trailing: Switch(
                    value: _notifMissYou,
                    onChanged: (v) {
                      setModal(() => _notifMissYou = v);
                      _saveNotifPref(_kNotifMissYou, v);
                    },
                  ),
                  onTap: () {
                    setModal(() => _notifMissYou = !_notifMissYou);
                    _saveNotifPref(_kNotifMissYou, _notifMissYou);
                  },
                ),
                const SettingsDivider(),
                SettingsRow(
                  icon: Icons.photo_library_rounded,
                  title: s.notifNewMemory,
                  subtitle: s.notifNewMemorySub,
                  trailing: Switch(
                    value: _notifNewMemory,
                    onChanged: (v) {
                      setModal(() => _notifNewMemory = v);
                      _saveNotifPref(_kNotifNewMemory, v);
                    },
                  ),
                  onTap: () {
                    setModal(() => _notifNewMemory = !_notifNewMemory);
                    _saveNotifPref(_kNotifNewMemory, _notifNewMemory);
                  },
                ),
                const SettingsDivider(),
                SettingsRow(
                  icon: Icons.mood_rounded,
                  title: s.notifMood,
                  subtitle: s.notifMoodSub,
                  trailing: Switch(
                    value: _notifMood,
                    onChanged: (v) {
                      setModal(() => _notifMood = v);
                      _saveNotifPref(_kNotifMood, v);
                    },
                  ),
                  onTap: () {
                    setModal(() => _notifMood = !_notifMood);
                    _saveNotifPref(_kNotifMood, _notifMood);
                  },
                ),
                const SettingsDivider(),
                SettingsRow(
                  icon: Icons.chat_bubble_rounded,
                  title: s.notifChat,
                  subtitle: s.notifChatSub,
                  trailing: Switch(
                    value: _notifChat,
                    onChanged: (v) {
                      setModal(() => _notifChat = v);
                      _saveNotifPref(_kNotifChat, v);
                    },
                  ),
                  onTap: () {
                    setModal(() => _notifChat = !_notifChat);
                    _saveNotifPref(_kNotifChat, _notifChat);
                  },
                ),
                const SettingsDivider(),
                // Постоянный счётчик «дней вместе» — локальное уведомление,
                // не пуш: состоянием управляет DaysTogetherNotificationService.
                SettingsRow(
                  icon: Icons.calendar_month_rounded,
                  title: s.notifDaysTogether,
                  subtitle: s.notifDaysTogetherSub,
                  trailing: Switch(
                    value: _notifDaysTogether,
                    onChanged: (v) => _toggleDaysTogetherNotif(v, setModal),
                  ),
                  onTap: () =>
                      _toggleDaysTogetherNotif(!_notifDaysTogether, setModal),
                ),
              ]),
            ],
          ),
          bottom: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openSystemNotificationSettings();
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                s.openSystemSettings,
                style: const TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Открывает системные настройки уведомлений приложения.
  ///
  /// На части прошивок нет Activity ни для одного из интентов — раньше это
  /// падало в отчёты о сбоях, поэтому оба вызова обёрнуты.
  Future<void> _openSystemNotificationSettings() async {
    if (Platform.isAndroid) {
      try {
        await launchUrl(Uri.parse(
          'intent:#Intent;'
          'action=android.settings.APP_NOTIFICATION_SETTINGS;'
          'S.android.provider.extra.APP_PACKAGE=com.togetherly.love;'
          'end',
        ));
        return;
      } catch (_) {
        try {
          await launchUrl(Uri.parse(
            'intent:#Intent;'
            'action=android.settings.APPLICATION_DETAILS_SETTINGS;'
            'S.android.provider.extra.APP_PACKAGE=com.togetherly.love;'
            'end',
          ));
        } catch (e) {
          debugPrint('Open app settings failed: $e');
        }
      }
      return;
    }

    final iosUri = Uri.parse('app-settings:');
    if (await canLaunchUrl(iosUri)) await launchUrl(iosUri);
  }

  /// Счётчик дней в шторке: включение просит дату старта пары.
  void _toggleDaysTogetherNotif(bool value, StateSetter setModal) {
    setModal(() => _notifDaysTogether = value);
    final start = coupleStartDate(
      timerStart: widget.timerService.systemTimer?.startDate,
      groupStart: widget.pairData.startDate,
    );
    DaysTogetherNotificationService.instance
        .setEnabled(value, startDate: start);
  }

  // ═══════════════════════════════════════════════════
  //  LANGUAGE PICKER
  // ═══════════════════════════════════════════════════
  /// Выбор языка — крупным меню снизу, а не тесным списком.
  void _showLanguagePicker(BuildContext context) {
    showAppSheet<void>(
      context,
      builder: (ctx) => SheetScaffold(
        title: _s.selectLanguage,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: SettingsGroup([
            _languageRow(ctx, code: 'ru', label: 'Русский', flag: '🇷🇺'),
            const SettingsDivider(),
            _languageRow(ctx, code: 'en', label: 'English', flag: '🇺🇸'),
          ]),
        ),
      ),
    );
  }

  /// Строка языка: флаг вместо иконки-чипа, галочка у выбранного.
  Widget _languageRow(
    BuildContext ctx, {
    required String code,
    required String label,
    required String flag,
  }) {
    final selected = LocaleService.instance.language ==
        (code == 'ru' ? AppLanguage.ru : AppLanguage.en);

    return InkWell(
      onTap: () {
        LocaleService.instance.setLanguage(
          code == 'ru' ? AppLanguage.ru : AppLanguage.en,
        );
        Navigator.pop(ctx);
        setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? _cs.primaryContainer : _cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Text(flag, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontVariations: const [FontVariation('wght', 600)],
                  color: selected ? _cs.primary : _cs.onSurface,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: _cs.primary, size: 22),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  RESET MISS YOU COUNT
  // ═══════════════════════════════════════════════════
  Future<void> _handleResetMissYouCount(BuildContext context) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: _s.resetMissYouConfirmTitle,
      message: _s.resetMissYouConfirmBody,
      confirmLabel: _s.reset,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final groupId = widget.pairData.pairId;
    if (groupId.isEmpty) return;
    final myUid = PocketBaseService().userId ?? '';
    if (myUid.isEmpty) return;
    await PbDataService().setMissYouCount(groupId, myUid, 0);
    if (!mounted) return;
    AppSnack.success(this.context, _s.resetMissYouConfirmTitle);
  }

  // ═══════════════════════════════════════════════════
  //  EXPORT MEMORIES
  // ═══════════════════════════════════════════════════
  Future<void> _handleExportConfig(BuildContext context) async {
    final groupId = widget.pairData.pairId;
    if (groupId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_s.noActiveGroupForExport),
          backgroundColor: _accent,
        ),
      );
      return;
    }

    // iPad-поповер для share-листа архива — считаем ДО листа/await.
    final shareOrigin = shareOriginFromContext(context);

    // Отмену держим здесь: лист внизу закрывается, а операция должна
    // остановиться, а не доработать в тишине и вывалить архив поверх экрана.
    var cancelled = false;

    if (!context.mounted) return;
    showAppSheet<void>(
      context,
      builder: (ctx) => PopScope(
        // Закрыть можно только кнопкой: свайп посреди сборки архива выглядел
        // бы как «отменил», хотя работа продолжалась бы.
        canPop: false,
        child: SheetScaffold(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MorphLoader(size: 64, color: _cs.primary),
                const SizedBox(height: 20),
                Text(
                  _s.creatingArchive,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    letterSpacing: -0.3,
                    color: _cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _s.exportTakesTime,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13,
                    height: 1.4,
                    color: _cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          bottom: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                cancelled = true;
                Navigator.of(ctx).pop();
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                _s.cancel,
                style: const TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final timerService = TimerService();
      await timerService.init();
      if (cancelled) return;

      final exportService = ExportService();
      await exportService.exportMemories(
        groupId: groupId,
        timers: timerService.timers,
        userData: widget.userData,
        sharePositionOrigin: shareOrigin,
      );

      // Отменили, пока собирался архив, — молча уходим: делиться тем, от чего
      // человек уже отказался, нельзя.
      if (cancelled) return;
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (cancelled) return;
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_s.exportError(e.toString())),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }




  void _showCoinShop(BuildContext context) {
    // Юзер осознанно открыл магазин коинов — теперь имеет смысл
    // предзагрузить rewarded, чтобы к тапу «Смотреть видео» он был готов.
    _rewardedAd.load();
    // Вторая попытка инициализации: init() из initState мог не успеть или
    // упасть (медленная сеть, sandbox-аккаунт, StoreKit ещё не поднялся).
    // Лист подписан на _iap, поэтому цены подтянутся прямо в открытом листе.
    if (!_iap.isAvailable || _iap.priceLabel(kCoinPacks.first.productId) == null) {
      unawaited(_initIap());
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // Лист подписан на userData: начисления (реклама/ежедневный бонус/
      // воспоминание) идут через notifyListeners, поэтому баланс и счётчик
      // «X/3» в открытом магазине обновляются сразу, без переоткрытия/рестарта.
      //
      // И на _iap: загрузка продуктов из App Store/Google Play асинхронная, и
      // раньше открытый лист на неё НЕ реагировал (setState в _initIap чинит
      // экран профиля, а не этот модальный роут). Если магазин успевали
      // открыть до окончания queryProductDetails — паки не отрисовывались и
      // не появлялись, пока лист открыт. Из-за этого App Review не нашёл
      // покупки и отклонил сборку (Guideline 2.1(b), 1.16.2).
      builder: (_) => ListenableBuilder(
        listenable: Listenable.merge([widget.userData, _iap]),
        builder: (ctx, _) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => Container(
            decoration: BoxDecoration(
              color: _t.cardSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _t.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/icons/coin.webp',
                            width: 30,
                            height: 30,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.userData.coins}',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _s.coinShopSubtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: _t.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                    children: [
                      // Выбор цветовой схемы отсюда убран: он вёл в старый
                      // список готовых тем, которого больше нет — палитра и
                      // насыщенность живут в «Оформлении».
                      // ── Иконки профиля ───────────────────────────────
                      _coinShopItem(
                        icon: Icons.add_reaction_outlined,
                        title: _s.iconShopTitle,
                        subtitle: _s.iconShopSubtitle,
                        onTap: () {
                          Navigator.pop(ctx);
                          _showIconPicker(context);
                        },
                      ),
                      // ── Заработать бесплатно ──────────────────────────
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _s.earnCoinsSection,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _t.textMuted,
                          ),
                        ),
                      ),
                      // Ежедневный вход
                      _coinShopItem(
                        icon: Icons.calendar_today_rounded,
                        title: _s.dailyBonusTitle,
                        subtitle: _s.dailyBonusSubtitle,
                        coinAmount: 1,
                        counterText: widget.userData.dailyBonusClaimedThisSession ? '✓' : null,
                        counterExhausted: widget.userData.dailyBonusClaimedThisSession,
                        onTap: widget.userData.dailyBonusClaimedThisSession
                            ? null
                            : () async {
                                final rootCtx = context;
                                final awarded = await widget.userData.claimDailyBonus();
                                if (!mounted) return;
                                if (awarded) {
                                  // ignore: use_build_context_synchronously
                                  CoinRewardToast.show(rootCtx, amount: 1, label: _s.dailyBonusTitle);
                                }
                              },
                      ),
                      // Воспоминание — скрыто в соло-режиме
                      if (!widget.pairData.isSolo)
                        _coinShopItem(
                          icon: Icons.photo_album_outlined,
                          title: _s.memoryRewardTitle,
                          subtitle: _s.memoryRewardSubtitle,
                          coinAmount: 1,
                          counterText: widget.userData.memoryRewardClaimedThisSession ? '✓' : null,
                          counterExhausted: widget.userData.memoryRewardClaimedThisSession,
                          onTap: widget.userData.memoryRewardClaimedThisSession
                              ? null
                              : () async {
                                  final amount = await widget.userData.claimMemoryReward();
                                  if (!mounted) return;
                                  if (amount > 0) {
                                    // ignore: use_build_context_synchronously
                                    CoinRewardToast.show(context, amount: amount, label: _s.memoryRewardTitle);
                                  }
                                },
                        ),
                      // Реклама
                      _coinShopItem(
                        icon: Icons.play_circle_outline_rounded,
                        title: _s.watchAdTitle,
                        subtitle: _s.watchAdSubtitle,
                        coinAmount: 3,
                        counterText:
                            '${widget.userData.adRewardsToday}/${UserData.adRewardsDailyLimit}',
                        counterExhausted: widget.userData.adRewardsRemaining == 0,
                        onTap: widget.userData.adRewardsRemaining == 0
                            ? null
                            : () async {
                                // Лист НЕ закрываем: он подписан на userData,
                                // поэтому после начисления баланс и счётчик
                                // «X/3» обновятся прямо в открытом магазине.
                                await _watchRewardedAd();
                              },
                      ),
                      // Стрик настроения
                      _coinShopItem(
                        icon: Icons.favorite_border_rounded,
                        title: _s.moodStreakRewardTitle,
                        subtitle: _s.moodStreakRewardSubtitle,
                        coinAmount: 10,
                        onTap: null,
                      ),
                      // Пригласить партнёра
                      _coinShopItem(
                        icon: Icons.person_add_outlined,
                        title: _s.partnerInviteRewardTitle,
                        subtitle: _s.partnerInviteRewardSubtitle,
                        coinAmount: 50,
                        onTap: null,
                      ),
                      // ── Купить монеты (IAP) — скрыто на iOS ───────────
                      // На iOS встроенные покупки убраны: App Review не мог
                      // найти/подтвердить продукты (Guideline 2.1(b)). Монеты
                      // на iOS остаются бесплатными (ежедневный бонус, реклама,
                      // инвайт) + донат-кнопки. На Android/RuStore паки на месте.
                      if (!Platform.isIOS && kCoinsPurchasable) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _s.coinPacksSectionTitle,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _t.textMuted,
                            ),
                          ),
                        ),
                        ...kCoinPacks.map((pack) {
                          final priceLabel =
                              _iap.priceLabel(pack.productId) ?? '…';
                          return _coinShopItem(
                            icon: Icons.shopping_bag_outlined,
                            title: _s.coinPackTitle(pack.coins),
                            subtitle: priceLabel,
                            onTap: _iapLoading || _iap.isLoading
                                ? null
                                : () async {
                                    Navigator.pop(ctx);
                                    await _buyCoins(pack.productId);
                                  },
                          );
                        }),
                        const SizedBox(height: 4),
                        _coinShopItem(
                          icon: Icons.restore_outlined,
                          title: _s.restorePurchasesTitle,
                          subtitle: '',
                          onTap: () {
                            Navigator.pop(ctx);
                            _restorePurchases();
                          },
                        ),
                        // Покупка мимо магазинов: код из телеграм-бота. Нужен
                        // тем, кто поставил приложение с GitHub — там биллинга
                        // Google нет вовсе.
                        _coinShopItem(
                          icon: Icons.confirmation_number_outlined,
                          title: _s.redeemCodeTitle,
                          subtitle: _s.redeemCodeSubtitle,
                          onTap: () {
                            Navigator.pop(ctx);
                            _askRedeemCode();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _initIap() async {
    await _iap.init(
      onGrantCoins: ({required String productId, required String purchaseToken}) =>
          widget.userData.purchaseCoins(
        productId: productId,
        purchaseToken: purchaseToken,
      ),
    );
    if (mounted) setState(() {});
  }

  /// Ввод кода пополнения из телеграм-бота.
  Future<void> _askRedeemCode() async {
    final code = await AppDialog.prompt(
      context,
      title: _s.redeemCodeTitle,
      label: _s.redeemCodeHint,
      hint: 'TG-XXXX-XXXX',
      confirmLabel: _s.redeemCodeApply,
      maxLength: 24,
      capitalization: TextCapitalization.characters,
    );
    if (code == null || code.trim().isEmpty || !mounted) return;

    final awarded = await widget.userData.redeemCode(code.trim());
    if (!mounted) return;
    final text = awarded == null
        ? _s.redeemCodeFailed
        : (awarded > 0 ? _s.redeemCodeDone(awarded) : _s.redeemCodeAlready);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _restorePurchases() async {
    setState(() => _iapLoading = true);
    try {
      await _iap.restorePurchases();
      // После восстановления подтягиваем актуальный баланс с сервера
      await widget.userData.refreshCoinsFromServer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_s.restorePurchasesSuccess),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_s.restorePurchasesError),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _iapLoading = false);
    }
  }

  Future<void> _buyCoins(String productId) async {
    if (_iapLoading) return;
    setState(() => _iapLoading = true);

    final result = await _iap.buy(productId);

    if (!mounted) return;
    setState(() => _iapLoading = false);

    String message;
    switch (result.status) {
      case IapStatus.success:
        message = _s.coinPurchaseSuccessAmount(result.coins);
      case IapStatus.pending:
        message = _s.coinPurchasePending;
      case IapStatus.cancelled:
        return; // тихо игнорируем отмену
      case IapStatus.error:
        message = _s.coinPurchaseError;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _watchRewardedAd() async {
    if (!_rewardedAd.isReady) {
      _rewardedAd.load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_s.adNotReady),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final uid = widget.userData.uid;
    if (uid.isEmpty) return;
    final earned = await _rewardedAd.show(uid: uid);
    unawaited(_rewardedAd.load());
    if (!earned || !mounted) return;

    // Начисление авторитетное для ОБЕИХ сетей: и Яндекс, и AdMob на PocketBase
    // идут через серверный роут /api/coins/ad-reward (Google-SSV нет ни у той,
    // ни у другой). Сервер вернул реальный баланс и сам увеличил суточный
    // счётчик — применяем точно, без оптимистичного угадывания (иначе «X/3»
    // откатывался к нулю при синке профиля). Если сервер не начислил (дневной
    // лимит) — не рисуем фейк; если не ответил (null) — тянем правду с сервера.
    final serverCoins = _rewardedAd.lastServerCoins;
    if (serverCoins != null) {
      widget.userData.applyServerAdReward(
        coins: serverCoins,
        granted: _rewardedAd.lastRewardGranted,
      );
      if (mounted) {
        if (_rewardedAd.lastRewardGranted) {
          CoinRewardToast.show(context,
              amount: UserData.adRewardAmount, label: _s.watchAdTitle);
        } else if (_rewardedAd.lastRateLimited) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_s.adRewardLimitReached),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      await widget.userData.refreshCoinsFromServer();
    }
    if (mounted) setState(() {});
  }

  Widget _coinShopItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    String? counterText,
    bool counterExhausted = false,
    int? coinAmount,
  }) {
    final disabled = onTap == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: disabled
            ? _t.surfaceMuted
            : _accentLight.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _t.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: disabled ? _t.textMuted : _accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: disabled
                              ? _t.textMuted
                              : _t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: _t.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Бейдж с наградой монетами (coin.webp + число)
                if (coinAmount != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: disabled ? _t.surfaceMuted : _t.cardSurface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: disabled
                          ? null
                          : _t.accentGlow(
                              _accent,
                              opacity: 0.15,
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/icons/coin.webp',
                          width: 14,
                          height: 14,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '+$coinAmount',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                            color: disabled ? _t.textMuted : _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                // Счётчик (например 1/3 для рекламы)
                if (counterText != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: counterExhausted
                          ? _t.surfaceMuted
                          : _t.cardSurface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: counterExhausted
                          ? null
                          : _t.accentGlow(
                              _accent,
                              opacity: 0.15,
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                    ),
                    child: Text(
                      counterText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        color: counterExhausted
                            ? _t.textSecondary
                            : _accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  color: _t.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _themeDisplayName(int index) {
    final names = <String>[
      _s.themeNamePink,
      _s.themeNamePurple,
      _s.themeNameBlue,
      _s.themeNamePeach,
      _s.themeNameSage,
      _s.themeNameMidnight,
      _s.themeNameLavender,
      _s.themeNameCherry,
      _s.themeNameMint,
      _s.themeNameSunset,
      _s.themeNameMonochrome,
      _s.themeNameForest,
      _s.themeNameOcean,
      _s.themeNameHoney,
      _s.themeNameLemon,
      _s.themeNameSand,
      _s.themeNameAurora,
      _s.themeNameBordeaux,
      _s.themeNameTeal,
      _s.themeNameNord,
      _s.themeNameCharcoalTeal,
      _s.themeNameCoffee,
      _s.themeNameForestDark,
      _s.themeNameGarnet,
      _s.themeNameDarkHoney,
    ];
    if (index < 0 || index >= names.length) return names[0];
    return names[index];
  }

  // null = предпросмотр запрошен, false = отмена, true = куплено
  Future<bool?> _confirmPurchaseTheme(BuildContext context, AppTheme t) async {
    final canAfford = widget.userData.coins >= t.price;
    final themeName = _themeDisplayName(t.index);

    // null = preview, false = cancel, true = buy
    final result = await showAppSheet<bool>(
      context,
      background: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            12, 0, 12, MediaQuery.of(ctx).padding.bottom + 12),
        child: Container(
          decoration: BoxDecoration(
            color: _t.cardSurface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: _t.accentGlow(
              t.primary,
              opacity: 0.18,
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Градиентная шапка с названием темы ──
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: t.heroGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      themeName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              // ── Содержимое ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  children: [
                    // ── Цена ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: t.primaryLight,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/icons/coin.webp',
                            width: 30,
                            height: 30,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${t.price}',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                              color: t.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ── Баланс ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _s.coinBalance,
                          style: TextStyle(
                            fontSize: 13,
                            color: _t.textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Image.asset(
                          'assets/images/icons/coin.webp',
                          width: 16,
                          height: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.userData.coins}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: canAfford
                                ? _t.textPrimary
                                : Colors.red.shade400,
                          ),
                        ),
                      ],
                    ),
                    if (!canAfford) ...[
                      const SizedBox(height: 6),
                      Text(
                        _s.notEnoughCoins,
                        style: TextStyle(
                          color: Colors.red.shade400,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    // ── Посмотреть ──
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(ctx, null),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: t.primary, width: 1.5),
                          foregroundColor: t.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.visibility_outlined, size: 20),
                        label: Text(
                          LocaleService.current.viewAction,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── Купить ──
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: canAfford
                              ? LinearGradient(
                                  colors: t.heroGradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: canAfford ? null : _t.surfaceMuted,
                          boxShadow: canAfford
                              ? _t.accentGlow(
                                  t.primary,
                                  opacity: 0.35,
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                )
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: canAfford
                                ? () => Navigator.pop(ctx, true)
                                : null,
                            child: Center(
                              child: Text(
                                canAfford
                                    ? _s.buyThemeConfirm
                                    : _s.notEnoughCoins,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: canAfford
                                      ? Colors.white
                                      : _t.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: _t.textMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _s.cancel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
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
    if (result == false) return false; // отмена
    if (result == null) return null;   // предпросмотр
    // result == true → покупка
    final ok = await widget.userData.purchaseTheme(t.index);
    if (!ok) return false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_s.themePurchased),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return true;
  }


  // ═══════════════════════════════════════════════════
  // Магазин профильных иконок
  // ═══════════════════════════════════════════════════

  void _showIconPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final equipped = widget.userData.equippedIcon;
          // Сортировка: сначала купленные/доступные, затем продаваемые
          // по возрастанию цены, в конце — награды (Sponsor/Helper).
          final icons = [...ProfileIcon.all]..sort((a, b) {
              int rank(ProfileIcon i) {
                if (widget.userData.ownsIcon(i.id)) return 0;
                if (i.grantOnly) return 2;
                return 1;
              }

              final ra = rank(a), rb = rank(b);
              if (ra != rb) return ra.compareTo(rb);
              return a.price.compareTo(b.price);
            });

          return DraggableScrollableSheet(
            initialChildSize: 0.78,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => Container(
              decoration: BoxDecoration(
                color: _t.cardSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Handle + заголовок + баланс
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _t.divider,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _s.iconShopTitle,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _s.iconShopSubtitle,
                              style: TextStyle(
                                fontSize: 13,
                                color: _t.textMuted,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Image.asset(
                              'assets/images/icons/coin.webp',
                              width: 16,
                              height: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.userData.coins}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _t.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                      child: Column(
                        children: [
                          // ── «Без иконки» ──
                          _noIconTile(
                            selected: equipped == null,
                            onTap: equipped == null
                                ? null
                                : () async {
                                    await widget.userData.setBadgeIcon(null);
                                    // Шторка могла закрыться за время await.
                                    if (ctx.mounted) setSheet(() {});
                                    if (mounted) setState(() {});
                                  },
                          ),
                          const SizedBox(height: 16),
                          // ── Сетка иконок ──
                          GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 0.72,
                            children: icons.map((icon) {
                              return _iconCell(
                                icon: icon,
                                isEquipped: equipped == icon.id,
                                owned: widget.userData.ownsIcon(icon.id),
                                onTap: () async {
                                  if (equipped == icon.id) {
                                    // Повторный тап по закреплённой иконке снимает её.
                                    await widget.userData.setBadgeIcon(null);
                                  } else if (widget.userData.ownsIcon(icon.id)) {
                                    await widget.userData.setBadgeIcon(icon.id);
                                  } else if (icon.grantOnly) {
                                    // Награда — купить нельзя, показываем инфо.
                                    _showIconInfo(icon, rewardLocked: true);
                                    return;
                                  } else {
                                    final bought = await _confirmPurchaseIcon(
                                        context, icon);
                                    if (bought) {
                                      await widget.userData.setBadgeIcon(icon.id);
                                    }
                                  }
                                  // После await шторка могла закрыться — setSheet
                                  // на размонтированном StatefulBuilder иначе
                                  // падает (_element! == null внутри setState).
                                  if (ctx.mounted) setSheet(() {});
                                  if (mounted) setState(() {});
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _noIconTile({required bool selected, required VoidCallback? onTap}) {
    return Material(
      color: selected ? _accentLight.withValues(alpha: 0.55) : _t.surfaceMuted,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _t.cardSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.block_rounded,
                  size: 18,
                  color: _t.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _s.noIconOption,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _t.textSecondary,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, size: 20, color: _accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconCell({
    required ProfileIcon icon,
    required bool isEquipped,
    required bool owned,
    required VoidCallback onTap,
  }) {
    final locked = !owned;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: isEquipped
              ? _accentLight.withValues(alpha: 0.55)
              : _t.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isEquipped ? _accent : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: isEquipped
              ? _t.accentGlow(
                  _accent,
                  opacity: 0.22,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Рамка-подложка, чтобы все иконки выглядели одинаково и крупно.
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _t.cardSurface,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Opacity(
                opacity: locked ? 0.5 : 1.0,
                child: Image.asset(icon.asset, width: 42, height: 42),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              icon.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isEquipped ? FontWeight.w700 : FontWeight.w500,
                color: isEquipped ? _accent : _t.textSecondary,
              ),
            ),
            const SizedBox(height: 5),
            // Нижняя строка: закреплено / куплено / награда / цена
            if (isEquipped)
              Icon(Icons.check_circle_rounded, size: 18, color: _accent)
            else if (owned)
              Icon(Icons.check_rounded, size: 16, color: _t.textMuted)
            else if (icon.grantOnly)
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded,
                      size: 11, color: _t.textMuted),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      _s.iconRewardOnly,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _t.textMuted,
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/images/icons/coin.webp',
                      width: 15, height: 15),
                  const SizedBox(width: 4),
                  Text(
                    '${icon.price}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _t.textPrimary,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showIconInfo(ProfileIcon icon, {bool rewardLocked = false}) {
    showAppSheet<void>(
      context,
      builder: (ctx) => SheetScaffold(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(icon.asset, width: 40, height: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      icon.name,
                      style: TextStyle(
                        fontFamily: 'Unbounded',
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        fontVariations: const [FontVariation('wght', 700)],
                        letterSpacing: -0.3,
                        color: _cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                rewardLocked
                    ? '${icon.description}\n\n${_s.iconRewardHint}'
                    : icon.description,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 15,
                  height: 1.4,
                  color: _cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _cs.primary,
                    foregroundColor: _cs.onPrimary,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _s.ok,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Диалог подтверждения покупки иконки. Возвращает true при успешной покупке.
  Future<bool> _confirmPurchaseIcon(BuildContext context, ProfileIcon icon) async {
    final canAfford = widget.userData.coins >= icon.price;
    final confirmed = await showAppSheet<bool>(
      context,
      background: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            12, 0, 12, MediaQuery.of(ctx).padding.bottom + 12),
        child: Container(
          decoration: BoxDecoration(
            color: _t.cardSurface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: _t.accentGlow(
              _accent,
              opacity: 0.18,
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Hero с иконкой ──
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                child: Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_accent, _accent.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -20,
                        right: -10,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.10),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Center(
                        child: Image.asset(icon.asset, width: 76, height: 76),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  children: [
                    Text(
                      icon.name,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: _t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      icon.description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: _t.textMuted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── Цена ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: _accentLight,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset('assets/images/icons/coin.webp',
                              width: 28, height: 28),
                          const SizedBox(width: 10),
                          Text(
                            '${icon.price}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                              color: _accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _s.coinBalance,
                          style: TextStyle(
                              fontSize: 13, color: _t.textMuted),
                        ),
                        const SizedBox(width: 6),
                        Image.asset('assets/images/icons/coin.webp',
                            width: 16, height: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.userData.coins}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: canAfford
                                ? _t.textPrimary
                                : Colors.red.shade400,
                          ),
                        ),
                      ],
                    ),
                    if (!canAfford) ...[
                      const SizedBox(height: 6),
                      Text(
                        _s.notEnoughCoins,
                        style: TextStyle(
                          color: Colors.red.shade400,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: canAfford
                              ? LinearGradient(
                                  colors: [_accent, _accent.withOpacity(0.7)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: canAfford ? null : _t.surfaceMuted,
                          boxShadow: canAfford
                              ? _t.accentGlow(
                                  _accent,
                                  opacity: 0.35,
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                )
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap:
                                canAfford ? () => Navigator.pop(ctx, true) : null,
                            child: Center(
                              child: Text(
                                canAfford
                                    ? _s.buyThemeConfirm
                                    : _s.notEnoughCoins,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: canAfford
                                      ? Colors.white
                                      : _t.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: _t.textMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _s.cancel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
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
    if (confirmed != true) return false;
    final ok = await widget.userData.purchaseIcon(icon);
    if (!mounted) return ok;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? _s.iconPurchased : _s.coinPurchaseError),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    return ok;
  }


  Future<void> _showLogoutDialog(BuildContext context) async {
    final ok = await AppDialog.confirm(
      context,
      title: _s.logoutQuestion,
      message: _s.logoutConfirm,
      confirmLabel: _s.logoutBtn,
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (!ok || !context.mounted) return;

    final userData = widget.userData;
    // Уходим с экрана раньше выхода: иначе notifyListeners успевает дёрнуть
    // уже размонтированное дерево.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => WelcomeScreen(userData: userData),
        settings: const RouteSettings(name: '/welcome'),
      ),
      (_) => false,
    );
    try {
      await userData.logout();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }

  /// Диалог подтверждения удаления аккаунта (App Store 5.1.1(v)).
  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final ok = await AppDialog.confirm(
      context,
      title: _s.deleteAccountQuestion,
      message: _s.deleteAccountConfirm,
      confirmLabel: _s.deleteAccountBtn,
      destructive: true,
      icon: Icons.person_remove_rounded,
    );
    if (!ok || !context.mounted) return;
    _performAccountDeletion(context);
  }

  /// Выполняет удаление: блокирующий индикатор → удаление → навигация на
  /// экран приветствия при успехе, либо SnackBar с ошибкой (сессия сохраняется,
  /// чтобы пользователь мог повторить, например после переавторизации).
  Future<void> _performAccountDeletion(BuildContext context) async {
    final userData = widget.userData;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await userData.deleteAccount();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // закрыть индикатор
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => WelcomeScreen(userData: userData),
          settings: const RouteSettings(name: '/welcome'),
        ),
        (_) => false,
      );
    } catch (e) {
      debugPrint('deleteAccount error: $e');
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // закрыть индикатор
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_s.deleteAccountError)),
      );
    }
  }
}
