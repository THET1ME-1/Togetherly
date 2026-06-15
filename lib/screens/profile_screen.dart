import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/storage_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io' show Platform;
import '../services/firebase_service.dart';
import '../models/user_data.dart';
import '../models/pair_data.dart';
import '../models/connection.dart';
import '../models/profile_icon.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common/coin_reward_toast.dart';
import '../widgets/common/m3_loading.dart';
import 'welcome_screen.dart';
import '../services/export_service.dart';
import '../services/timer_service.dart';
import '../services/home_widget_service.dart';
import '../services/widget_service.dart';
import '../services/rewarded_ad_service.dart';
import '../services/app_icon_service.dart';
import '../services/iap_service.dart';
import '../services/celebration_notification_service.dart';
import '../services/days_together_notification_service.dart';

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
  const ProfileScreen({
    super.key,
    required this.userData,
    required this.pairData,
    required this.timerService,
    required this.widgetService,
    this.onSwitchToHome,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final RewardedAdService _rewardedAd = RewardedAdService();
  String _appIconId = AppIconService.defaultId;
  final IapService _iap = IapService();
  bool _iapLoading = false;


  static final Uri _privacyPolicyUri = Uri.parse(
    'https://togetherly-d4856.web.app/privacy-policy',
  );
  static final Uri _aboutAppUri = Uri.parse(
    'https://togetherly-d4856.web.app/#download',
  );
  static final Uri _boostyUri = Uri.parse('https://boosty.to/sntcompany');

  Color get _accent => widget.userData.themeAccent;
  Color get _accentLight => widget.userData.themeAccentLight;
  AppStrings get _s => LocaleService.current;

  /// UID of the partner selected in the profile (null = first from active group)
  String? _selectedPartnerUid;

  /// Local relationship type used when no group is connected
  RelationshipType _localRelType = RelationshipType.couple;

  /// Timer to refresh day counter every hour
  Timer? _dayTimer;

  /// Toggle for Relationship Stats
  bool _showStats = false;

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

  // Подсказка про колесо «Дни вместе» под полем «Годовщина».
  // Скрывается навсегда по крестику.
  bool _anniversaryHintDismissed = false;
  static const _kAnniversaryHintDismissed = 'anniversary_wheel_hint_dismissed';

  int? _memoriesCount;
  int? _missYouCount;
  int? _drawingsCount;
  StreamSubscription? _missYouSub;
  String? _lastLoadedGroupId;

  int _calculateDaysTogether(DateTime? fallbackDate) {
    final timerDate = widget.timerService.systemTimer?.startDate;
    final date = timerDate ?? fallbackDate;
    if (date == null) return 0;
    return DateTime.now().difference(date).inDays;
  }

  @override
  void initState() {
    super.initState();
    _selectedPartnerUid = widget.pairData.manager.preferredPartnerUid;
    widget.pairData.addListener(_onPairDataChanged);
    // Refresh every hour so the day count updates when crossing midnight
    _dayTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadStats();
    _loadNotifPrefs();
    if (AppIconService.instance.isSupported) {
      AppIconService.instance.currentIconId().then((id) {
        if (mounted) setState(() => _appIconId = id);
      });
    }
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
      _anniversaryHintDismissed =
          prefs.getBool(_kAnniversaryHintDismissed) ?? false;
    });
    // Синхронизируем текущие настройки в Firestore при открытии профиля,
    // чтобы Cloud Functions всегда имели актуальные данные
    FirebaseService().updateNotifPrefs(
      missYou: prefs.getBool(_kNotifMissYou) ?? true,
      newMemory: prefs.getBool(_kNotifNewMemory) ?? true,
      mood: prefs.getBool(_kNotifMood) ?? true,
      chat: prefs.getBool(_kNotifChat) ?? true,
    );
  }

  Future<void> _saveNotifPref(String key, bool value) async {
    // Сохраняем локально
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    // Сохраняем в Firestore, чтобы Cloud Functions проверяли настройки
    switch (key) {
      case _kNotifMissYou:
        FirebaseService().updateNotifPrefs(missYou: value);
        break;
      case _kNotifNewMemory:
        FirebaseService().updateNotifPrefs(newMemory: value);
        break;
      case _kNotifMood:
        FirebaseService().updateNotifPrefs(mood: value);
        break;
      case _kNotifChat:
        FirebaseService().updateNotifPrefs(chat: value);
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

    // Load memories & drawings counts from denormalized group doc fields
    final fb = FirebaseService();
    fb.getGroupMemoriesCount(currentGroupId).then((c) {
      if (mounted && _lastLoadedGroupId == currentGroupId) {
        setState(() => _memoriesCount = c);
      }
    });
    fb.getGroupDrawingsCount(currentGroupId).then((c) {
      if (mounted && _lastLoadedGroupId == currentGroupId) {
        setState(() => _drawingsCount = c);
      }
    });

    // Listen to Miss You count
    _missYouSub = FirebaseService().listenToMissYouCount(
      groupId: currentGroupId,
      onData: (count) {
        if (mounted && _lastLoadedGroupId == currentGroupId) {
          setState(() => _missYouCount = count);
        }
      },
    );
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

  Future<void> _openAboutApp() async {
    await _openExternalUri(_aboutAppUri);
  }

  Future<void> _openBoosty() async {
    await _openExternalUri(_boostyUri);
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
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 110,
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // ═══ Avatar + Name ═══
          _buildProfileHeader(context),
          const SizedBox(height: 28),
          // ═══ Info Card ═══
          _buildInfoCard(context),
          const SizedBox(height: 20),
          // ═══ Coin Shop ═══
          _buildCoinShopCard(context),
          const SizedBox(height: 20),
          // ═══ Relationship Status Card ═══
          _buildRelationshipCard(context),
          const SizedBox(height: 20),
          // ═══ Relationship Stats Card ═══
          _buildStatsCard(context),
          const SizedBox(height: 20),
          // ═══ Settings List ═══
          _buildSettingsCard(context),
          const SizedBox(height: 20),
          // ═══ Support Authors ═══
          _buildSupportCard(context),
          const SizedBox(height: 20),
          // ═══ Danger Zone ═══
          _buildDangerZone(context),
          const SizedBox(height: 40),
        ],
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
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.2),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accentLight,
                    border: Border.all(
                      color: _accent.withOpacity(0.25),
                      width: 3,
                    ),
                  ),
                  child: widget.userData.avatarUrl.isNotEmpty
                      ? ClipOval(
                          child: StorageImage(
                            imageUrl: widget.userData.avatarUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 200,
                            memCacheHeight: 200,
                            errorWidget: (context, url, error) =>
                                _buildAvatarFallback(),
                          ),
                        )
                      : _buildAvatarFallback(),
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
                color: Colors.grey.shade900,
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
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
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
            color: Colors.white,
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
                      color: Colors.grey.shade900,
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
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (image == null || !mounted) return;

    // Обрезаем до круга (аватарка)
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: image.path,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          cropStyle: CropStyle.circle,
          toolbarTitle: '✂️  Обрезка аватарки',
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
          title: 'Аватарка',
          doneButtonTitle: 'Готово',
          cancelButtonTitle: 'Отмена',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          rotateButtonsHidden: false,
          hidesNavigationBar: true,
        ),
      ],
    );

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
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                M3LoadingDots(color: _accentLight),
                const SizedBox(height: 16),
                Text(
                  _s.uploading,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
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
      final fb = FirebaseService();
      final userId = fb.currentUser?.uid ?? '';
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
  //  INFO CARD
  // ═══════════════════════════════════════════════════
  Widget _buildInfoCard(BuildContext context) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _s.information,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade400,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 20),
          _infoRow(
            icon: Icons.person_outline_rounded,
            label: _s.name,
            value: widget.userData.displayName.isNotEmpty
                ? widget.userData.displayName
                : '—',
          ),
          _divider(),
          _infoRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: widget.userData.email.isNotEmpty
                ? widget.userData.email
                : '—',
          ),
          _divider(),
          GestureDetector(
            onTap: () => _showGenderPicker(context),
            behavior: HitTestBehavior.opaque,
            child: _infoRow(
              icon: widget.userData.isMale
                  ? Icons.male_rounded
                  : Icons.female_rounded,
              label: _s.gender,
              value: widget.userData.isMale ? _s.male : _s.female,
              trailing: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Colors.grey.shade400,
              ),
            ),
          ),
          _divider(),
          GestureDetector(
            onTap: () => _showThemePicker(context),
            behavior: HitTestBehavior.opaque,
            child: _infoRow(
              icon: Icons.palette_outlined,
              label: _s.theme,
              value: _themeDisplayName(widget.userData.themeId),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withOpacity(0.3),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
          if (AppIconService.instance.isSupported) ...[
            _divider(),
            GestureDetector(
              onTap: () => _showAppIconPicker(context),
              behavior: HitTestBehavior.opaque,
              child: _infoRow(
                icon: Icons.apps_rounded,
                label: LocaleService.instance.isRussian
                    ? 'Иконка приложения'
                    : 'App icon',
                value: _appIconName(_appIconId),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _appIconPreview(_appIconOption(_appIconId), size: 24),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  AppIconOption _appIconOption(String id) =>
      AppIconService.options.firstWhere((o) => o.id == id,
          orElse: () => AppIconService.options.first);

  String _appIconName(String id) {
    final o = _appIconOption(id);
    return LocaleService.instance.isRussian ? o.nameRu : o.nameEn;
  }

  /// Мини-превью launcher-иконки: «TY» буквами темы на её фоне (как на столе).
  Widget _appIconPreview(AppIconOption o, {required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: o.background,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      alignment: Alignment.center,
      child: Text(
        'TY',
        style: TextStyle(
          fontSize: size * 0.42,
          height: 1.0,
          fontWeight: FontWeight.w600,
          color: o.letters,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _showAppIconPicker(BuildContext context) {
    final isRu = LocaleService.instance.isRussian;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      // Иконок больше, чем влезает в дефолтную высоту листа — без этого нижние
      // ряды обрезались и были недоступны. isScrollControlled + Flexible-скролл.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
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
                const SizedBox(height: 16),
                Text(
                  isRu ? 'Иконка приложения' : 'App icon',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  isRu
                      ? 'Иконка на рабочем столе может обновиться через пару секунд.'
                      : 'The home-screen icon may take a couple of seconds to refresh.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final o in AppIconService.options)
                          _appIconChoice(o, isRu),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _appIconChoice(AppIconOption o, bool isRu) {
    final selected = o.id == _appIconId;
    return GestureDetector(
      onTap: () => _applyAppIcon(o.id),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                // Индикатор повторяет форму иконки (скруглённый квадрат),
                // а не круг: внешний радиус = радиус иконки + паддинг.
                borderRadius: BorderRadius.circular(60 * 0.22 + 3),
                border: Border.all(
                  color: selected ? _accent : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: _appIconPreview(o, size: 60),
            ),
            const SizedBox(height: 6),
            Text(
              isRu ? o.nameRu : o.nameEn,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? _accent : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyAppIcon(String id) async {
    if (id == _appIconId) {
      Navigator.of(context).maybePop();
      return;
    }
    final ok = await AppIconService.instance.setIcon(id);
    if (!mounted) return;
    if (ok) {
      setState(() => _appIconId = id);
    }
    Navigator.of(context).maybePop();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocaleService.instance.isRussian
              ? 'Не удалось сменить иконку'
              : 'Could not change the icon'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
    String? hint,
    VoidCallback? onHintDismiss,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          hint,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (onHintDismiss != null)
                        GestureDetector(
                          onTap: onHintDismiss,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6, top: 1),
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Future<void> _showGenderPicker(BuildContext context) async {
    final currentGender = widget.userData.gender;
    final selectedGender = await showModalBottomSheet<Gender>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _s.gender,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                Icons.male_rounded,
                color: currentGender == Gender.male ? _accent : Colors.grey,
              ),
              title: Text(
                _s.male,
                style: TextStyle(
                  fontWeight: currentGender == Gender.male
                      ? FontWeight.w700
                      : FontWeight.normal,
                ),
              ),
              trailing: currentGender == Gender.male
                  ? Icon(Icons.check_circle_rounded, color: _accent)
                  : null,
              onTap: () => Navigator.pop(context, Gender.male),
            ),
            ListTile(
              leading: Icon(
                Icons.female_rounded,
                color: currentGender == Gender.female ? _accent : Colors.grey,
              ),
              title: Text(
                _s.female,
                style: TextStyle(
                  fontWeight: currentGender == Gender.female
                      ? FontWeight.w700
                      : FontWeight.normal,
                ),
              ),
              trailing: currentGender == Gender.female
                  ? Icon(Icons.check_circle_rounded, color: _accent)
                  : null,
              onTap: () => Navigator.pop(context, Gender.female),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (selectedGender != null && selectedGender != currentGender) {
      if (context.mounted) {
        await widget.userData.updateProfile(gender: selectedGender);

        final partnerGender =
            widget.widgetService.firstPartnerData?.gender ?? '';
        final sysTimer = widget.timerService.systemTimer;

        final uid = widget.userData.uid;
        if (uid.isNotEmpty && widget.pairData.pairId.isNotEmpty) {
          try {
            await FirebaseFirestore.instance
                .collection('groups')
                .doc(widget.pairData.pairId)
                .collection('widgetData')
                .doc(uid)
                .set({'gender': selectedGender.name}, SetOptions(merge: true));
          } catch (e) {
            debugPrint('Failed to update widgetData gender: $e');
          }
        }

        await HomeWidgetService.instance.syncAllBoundWidgets(
          activeGroupId: widget.pairData.pairId,
          activeTimers: widget.timerService.timers,
          activeSysTimer: sysTimer,
          activeStartDate: widget.pairData.startDate,
          coupleNames: widget.pairData.partnerName.isNotEmpty
              ? widget.pairData.partnerName
              : '',
          emoji: sysTimer?.emoji ?? widget.pairData.relationshipEmoji,
          myGender: selectedGender.name,
          partnerGender: partnerGender,
          relationshipStatusId: widget.pairData.relationshipStatusId,
          isRomantic: widget.pairData.relationshipType == RelationshipType.couple ||
              widget.pairData.relationshipType == RelationshipType.married,
          themeIndex: widget.userData.themeId,
        );

        setState(() {});
      }
    }
  }

  // ═══════════════════════════════════════════════════
  //  RELATIONSHIP STATS (WRAPPED)
  // ═══════════════════════════════════════════════════
  Widget _buildStatsCard(BuildContext context) {
    final daysNum = _calculateDaysTogether(widget.pairData.startDate);
    final daysString = '$daysNum';

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showStats = !_showStats),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _s.relationshipStats,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade400,
                    letterSpacing: 3,
                  ),
                ),
                Icon(
                  _showStats
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: !_showStats
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _statBox(
                              title: _s.daysTogetherStat,
                              value: daysString,
                              icon: Icons.calendar_today_rounded,
                              color: const Color(0xFFE91E8C),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statBox(
                              title: _s.memoriesStat,
                              value: _memoriesCount?.toString() ?? '...',
                              icon: Icons.photo_library_rounded,
                              color: const Color(0xFF3498DB),
                            ),
                          ),
                        ],
                      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
                      const SizedBox(height: 8),
                      Row(
                            children: [
                              Expanded(
                                child: _statBox(
                                  title: _s.drawingsStat,
                                  value: _drawingsCount?.toString() ?? '...',
                                  icon: Icons.brush_rounded,
                                  color: const Color(0xFFF39C12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _statBox(
                                  title: _s.missYousStat,
                                  value: _missYouCount?.toString() ?? '...',
                                  icon: Icons.favorite_rounded,
                                  color: const Color(0xFF9B59B6),
                                ),
                              ),
                            ],
                          )
                          .animate()
                          .fadeIn(duration: 400.ms, delay: 100.ms)
                          .slideY(begin: 0.1),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _s.relationships,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade400,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 20),
          // ── Статус (синхронизирован с типом группы, нажимаем — меняем) ──
          GestureDetector(
            onTap: () => _showRelationshipTypePicker(
              context,
              selectedPartner?.connection,
            ),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: relColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(relIcon, color: relColor, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _s.statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        relLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: relColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
          _divider(),
          // ── Партнёр (выбор независимо от группы) ──
          GestureDetector(
            onTap: () => _showPartnerPicker(context, allPartners),
            behavior: HitTestBehavior.opaque,
            child: _infoRow(
              icon: Icons.person_rounded,
              label: _s.partnerLabel,
              value: selectedPartner?.member.name.isNotEmpty == true
                  ? selectedPartner!.member.name
                  : _s.notSelected,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
                size: 20,
              ),
            ),
          ),
          if (hasPaired) ...[
            _divider(),
            _infoRow(
              icon: Icons.calendar_today_rounded,
              label: _s.together,
              value: daysString,
            ),
            _divider(),
            // ── Годовщина ──
            GestureDetector(
              onTap: () => _showAnniversaryDatePicker(
                  context, selectedPartner?.connection),
              behavior: HitTestBehavior.opaque,
              child: _infoRow(
                icon: Icons.celebration_rounded,
                label: _s.anniversaryDate,
                value: _formatAnniversaryDate(
                    selectedPartner?.connection.anniversaryDate),
                hint: _anniversaryHintDismissed
                    ? null
                    : _s.anniversaryWheelHint,
                onHintDismiss: _dismissAnniversaryHint,
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ),
            ),
            _divider(),
            // ── Первый поцелуй ──
            GestureDetector(
              onTap: () => _showFirstKissDatePicker(
                  context, selectedPartner?.connection),
              behavior: HitTestBehavior.opaque,
              child: _infoRow(
                icon: Icons.favorite_rounded,
                label: _s.firstKissDate,
                value: _formatCelebrationDate(
                    selectedPartner?.connection.firstKissDate),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ),
            ),
            _divider(),
            // ── Мой день рождения ──
            GestureDetector(
              onTap: () => _showBirthdayPicker(context),
              behavior: HitTestBehavior.opaque,
              child: _infoRow(
                icon: Icons.cake_rounded,
                label: _s.myBirthday,
                value: _formatBirthdayDate(widget.userData.birthDate),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ),
            ),
            // ── День рождения партнёра (read-only) ──
            if (selectedPartner != null) ...[
              _divider(),
              _infoRow(
                icon: Icons.cake_rounded,
                label: _s.partnerBirthday,
                value: _formatBirthdayDate(
                  selectedPartner.connection.memberBirthdays[
                      selectedPartner.member.uid],
                ),
              ),
            ],
          ],
          if (!hasPaired) ...[
            const SizedBox(height: 12),
            Text(
              _s.invitePartnerToCount,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Celebration helpers ──

  String _formatCelebrationDate(DateTime? date) {
    if (date == null) return _s.notSet;
    final d = '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    if (date.hour == 0 && date.minute == 0) return d;
    final t = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '$d  $t';
  }

  String _formatAnniversaryDate(DateTime? date) => _formatCelebrationDate(date);
  String _formatBirthdayDate(DateTime? date) => _formatCelebrationDate(date);

  /// Показывает диалог ввода даты с авто-точками (ДД.ММ.ГГГГ).
  /// [firstYear] / [lastYear] — допустимый диапазон лет.
  /// Возвращает выбранную дату или null если отменено.
  Future<DateTime?> _showDateInputDialog({
    required BuildContext context,
    required String title,
    required DateTime? initial,
    required int firstYear,
    required int lastYear,
  }) async {
    final primary = _accent;
    final ctrl = TextEditingController(
      text: initial != null
          ? '${initial.day.toString().padLeft(2, '0')}.${initial.month.toString().padLeft(2, '0')}.${initial.year}'
          : '',
    );
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);

    // Контроллер времени — предзаполняем если уже есть время (не 00:00)
    final hasTime = initial != null &&
        (initial.hour != 0 || initial.minute != 0);
    final timeCtrl = TextEditingController(
      text: hasTime
          ? '${initial.hour.toString().padLeft(2, '0')}:${initial.minute.toString().padLeft(2, '0')}'
          : '',
    );

    final result = await showDialog<DateTime>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _DateInputDialog(
        title: title,
        ctrl: ctrl,
        timeCtrl: timeCtrl,
        primary: primary,
        firstYear: firstYear,
        lastYear: lastYear,
        initial: initial,
        parseDateInput: _parseDateInput,
      ),
    );
    return result;
  }

  /// Парсит строку ДД.ММ.ГГГГ → DateTime или null если некорректно.
  DateTime? _parseDateInput(String text) {
    final parts = text.split('.');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (d < 1 || d > 31 || m < 1 || m > 12 || y < 1000) return null;
    try {
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  Future<void> _dismissAnniversaryHint() async {
    setState(() => _anniversaryHintDismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAnniversaryHintDismissed, true);
  }

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
    final fb = FirebaseService();
    await fb.updateAnniversaryDate(groupId, picked);
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
    final fb = FirebaseService();
    await fb.updateFirstKissDate(groupId, picked);
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

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
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
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _s.relationshipType,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...types.map((type) {
                final label = _relTypeToRussian(type);
                final icon = _relTypeToIcon(type);
                final color = _relTypeToColor(type);
                final isSelected = current == type;
                return GestureDetector(
                  onTap: () {
                    if (connection != null) {
                      connection.setRelationshipType(type);
                    } else {
                      setState(() => _localRelType = type);
                    }
                    Navigator.pop(ctx);
                    setState(() {});
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withOpacity(0.08)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? color : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          color: isSelected ? color : Colors.grey.shade500,
                          size: 22,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected ? color : Colors.grey.shade800,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle_rounded,
                            color: color,
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
          decoration: const BoxDecoration(
            color: Colors.white,
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
                    color: Colors.grey.shade300,
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
                      color: Colors.grey.shade900,
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
                final initial = entry.member.name.isNotEmpty
                    ? entry.member.name[0].toUpperCase()
                    : '?';
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
                          : Colors.grey.shade50,
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
                                  color: Colors.grey.shade800,
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
  //  SUPPORT AUTHORS CARD
  // ═══════════════════════════════════════════════════
  Widget _buildSupportCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _accent.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withAlpha(50)),
        boxShadow: [
          BoxShadow(
            color: _accent.withAlpha(20),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openBoosty,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _accent.withAlpha(30),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.favorite_rounded,
                    color: _accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _s.supportAuthors,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _accent.withAlpha(200),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Boosty',
                        style: TextStyle(
                          fontSize: 12,
                          color: _accent.withAlpha(130),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _accent.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: _accent,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  SETTINGS CARD
  // ═══════════════════════════════════════════════════
  Widget _buildSettingsCard(BuildContext context) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _s.settings,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade400,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 12),
          _settingsTile(
            icon: Icons.edit_outlined,
            label: _s.editProfile,
            onTap: () => _showEditProfileDialog(context),
          ),
          _divider(),
          _settingsTile(
            icon: Icons.notifications_outlined,
            label: _s.notifications,
            onTap: () => _showNotificationSettings(context),
          ),
          _divider(),
          _settingsTile(
            icon: Icons.lock_clock_outlined,
            label: _s.lockScreenMoodToggle,
            onTap: () {},
            trailing: Switch(
              value: _lockScreenMood,
              activeColor: _accent,
              onChanged: (v) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(_kLockScreenMood, v);
                if (mounted) setState(() => _lockScreenMood = v);
              },
            ),
          ),
          _divider(),
          _settingsTile(
            icon: Icons.lock_outline_rounded,
            label: _s.privacy,
            onTap: _openPrivacyPolicy,
          ),
          _divider(),
          _settingsTile(
            icon: Icons.language_rounded,
            label: _s.language,
            onTap: () => _showLanguagePicker(context),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  LocaleService.instance.language == AppLanguage.ru
                      ? 'RU'
                      : 'EN',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
          _divider(),
          _settingsTile(
            icon: Icons.archive_outlined,
            label: _s.exportMemories,
            onTap: () => _handleExportConfig(context),
          ),
          _divider(),
          _settingsTile(
            icon: Icons.replay_rounded,
            label: _s.resetMissYouCount,
            onTap: () => _handleResetMissYouCount(context),
          ),
          _divider(),
          _settingsTile(
            icon: Icons.info_outline_rounded,
            label: _s.aboutApp,
            onTap: _openAboutApp,
          ),
        ],
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey.shade600, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  NOTIFICATION SETTINGS
  // ═══════════════════════════════════════════════════
  void _showNotificationSettings(BuildContext context) {
    final s = LocaleService.current;
    final accent = _accent;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
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
              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_outlined,
                      size: 20,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    s.notifications,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Toggles
              _notifToggle(
                icon: Icons.favorite_rounded,
                color: const Color(0xFFEC4899),
                title: s.notifMissYou,
                subtitle: s.notifMissYouSub,
                value: _notifMissYou,
                onChanged: (v) {
                  setModal(() => _notifMissYou = v);
                  _saveNotifPref(_kNotifMissYou, v);
                },
              ),
              const Divider(height: 1),
              _notifToggle(
                icon: Icons.photo_library_outlined,
                color: const Color(0xFF3B82F6),
                title: s.notifNewMemory,
                subtitle: s.notifNewMemorySub,
                value: _notifNewMemory,
                onChanged: (v) {
                  setModal(() => _notifNewMemory = v);
                  _saveNotifPref(_kNotifNewMemory, v);
                },
              ),
              const Divider(height: 1),
              _notifToggle(
                icon: Icons.mood_rounded,
                color: const Color(0xFFF59E0B),
                title: s.notifMood,
                subtitle: s.notifMoodSub,
                value: _notifMood,
                onChanged: (v) {
                  setModal(() => _notifMood = v);
                  _saveNotifPref(_kNotifMood, v);
                },
              ),
              const Divider(height: 1),
              _notifToggle(
                icon: Icons.chat_bubble_rounded,
                color: const Color(0xFF10B981),
                title: s.notifChat,
                subtitle: s.notifChatSub,
                value: _notifChat,
                onChanged: (v) {
                  setModal(() => _notifChat = v);
                  _saveNotifPref(_kNotifChat, v);
                },
              ),
              const Divider(height: 1),
              // Постоянный счётчик «дней вместе» — локальное уведомление,
              // не FCM-пуш: состоянием управляет DaysTogetherNotificationService.
              _notifToggle(
                icon: Icons.favorite_border_rounded,
                color: const Color(0xFFEF4444),
                title: s.notifDaysTogether,
                subtitle: s.notifDaysTogetherSub,
                value: _notifDaysTogether,
                onChanged: (v) {
                  setModal(() => _notifDaysTogether = v);
                  final start = widget.timerService.systemTimer?.startDate ??
                      widget.pairData.startDate;
                  DaysTogetherNotificationService.instance
                      .setEnabled(v, startDate: start);
                },
              ),
              const SizedBox(height: 20),
              // System settings button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (Platform.isAndroid) {
                      final androidUri = Uri.parse(
                        'intent:#Intent;'
                        'action=android.settings.APP_NOTIFICATION_SETTINGS;'
                        'S.android.provider.extra.APP_PACKAGE=com.togetherly.love;'
                        'end',
                      );
                      try {
                        await launchUrl(androidUri);
                      } catch (_) {
                        // fallback: open general app settings
                        await launchUrl(
                          Uri.parse(
                            'intent:#Intent;'
                            'action=android.settings.APPLICATION_DETAILS_SETTINGS;'
                            'S.android.provider.extra.APP_PACKAGE=com.togetherly.love;'
                            'end',
                          ),
                        );
                      }
                    } else {
                      final iosUri = Uri.parse('app-settings:');
                      if (await canLaunchUrl(iosUri)) {
                        await launchUrl(iosUri);
                      }
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(s.openSystemSettings),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.notifSystemSettingsHint,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notifToggle({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeColor: _accent),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  LANGUAGE PICKER
  // ═══════════════════════════════════════════════════
  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              _s.selectLanguage,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 20),
            _languageOption(ctx, code: 'ru', label: 'Русский', flag: '🇷🇺'),
            const SizedBox(height: 10),
            _languageOption(ctx, code: 'en', label: 'English', flag: '🇺🇸'),
          ],
        ),
      ),
    );
  }

  Widget _languageOption(
    BuildContext ctx, {
    required String code,
    required String label,
    required String flag,
  }) {
    final isSelected =
        LocaleService.instance.language ==
        (code == 'ru' ? AppLanguage.ru : AppLanguage.en);
    return GestureDetector(
      onTap: () {
        LocaleService.instance.setLanguage(
          code == 'ru' ? AppLanguage.ru : AppLanguage.en,
        );
        Navigator.pop(ctx);
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? _accent.withOpacity(0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? _accent : Colors.grey.shade800,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: _accent, size: 20),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  RESET MISS YOU COUNT
  // ═══════════════════════════════════════════════════
  Future<void> _handleResetMissYouCount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_s.resetMissYouConfirmTitle),
        content: Text(_s.resetMissYouConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
            child: Text(_s.reset),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final groupId = widget.pairData.pairId;
    if (groupId.isEmpty) return;
    await FirebaseService().resetMyMissYouCount(groupId: groupId);
    if (!mounted) return;
    ScaffoldMessenger.of(this.context).showSnackBar(
      SnackBar(
        content: Text(_s.resetMissYouConfirmTitle),
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                M3LoadingDots(color: _accentLight),
                const SizedBox(height: 16),
                Text(
                  _s.creatingArchive,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
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
      final timerService = TimerService();
      await timerService.init();

      final exportService = ExportService();
      await exportService.exportMemories(
        groupId: groupId,
        timers: timerService.timers,
        userData: widget.userData,
      );

      if (context.mounted) {
        Navigator.pop(context); // close dialog
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_s.exportError(e.toString())),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════
  //  DANGER ZONE
  // ═══════════════════════════════════════════════════
  Widget _buildDangerZone(BuildContext context) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<String>(
            future: _getAppVersion(),
            builder: (context, snapshot) {
              final version = snapshot.data ?? 'unknown';
              return Text(
                'Love App v$version',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              );
            },
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _showLogoutDialog(context),
            child: Row(
              children: [
                Icon(
                  Icons.logout_rounded,
                  color: Colors.red.shade400,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  _s.logout,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════
  Widget _glassCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xC7FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x99FFFFFF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _divider() {
    return Divider(color: Colors.grey.shade100, height: 1, thickness: 1);
  }

  Widget _buildCoinShopCard(BuildContext context) {
    return GestureDetector(
      onTap: () => _showCoinShop(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _accent.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/images/icons/coin.webp',
              width: 38,
              height: 38,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s.coinShopTitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _s.coinShopSubtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _accentLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${widget.userData.coins}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _accent,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  void _showCoinShop(BuildContext context) {
    // Юзер осознанно открыл магазин коинов — теперь имеет смысл
    // предзагрузить rewarded, чтобы к тапу «Смотреть видео» он был готов.
    _rewardedAd.load();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // Лист подписан на userData: начисления (реклама/ежедневный бонус/
      // воспоминание) идут через notifyListeners, поэтому баланс и счётчик
      // «X/3» в открытом магазине обновляются сразу, без переоткрытия/рестарта.
      builder: (_) => ListenableBuilder(
        listenable: widget.userData,
        builder: (ctx, _) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
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
                          color: Colors.grey.shade300,
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
                          color: Colors.grey.shade500,
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
                      // ── Тема ─────────────────────────────────────────
                      _coinShopItem(
                        icon: Icons.palette_outlined,
                        title: _s.chooseColorTheme,
                        subtitle: '${AppThemes.all.where((t) => t.isPremium).length} × ${_s.themeNameLavender}, ${_s.themeNameMidnight}…',
                        onTap: () {
                          Navigator.pop(ctx);
                          _showThemePicker(context);
                        },
                      ),
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
                            color: Colors.grey.shade500,
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
                      // ── Купить монеты (IAP) ───────────────────────────
                      if (_iap.isAvailable) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _s.coinPacksSectionTitle,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                        ...kCoinPacks.map((pack) {
                          final pd = _iap.product(pack.productId);
                          final priceLabel = pd?.price ?? '…';
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

    // Яндекс (основная сеть): начисление авторитетное и синхронное —
    // grantAdReward уже вернул реальный баланс. Применяем его точно, без
    // оптимистичного угадывания. Если сервер не начислил (дневной лимит) —
    // не рисуем фейковую награду; если callable не ответил (null) — тянем
    // правду с сервера.
    if (_rewardedAd.lastShowWasYandex) {
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
      return;
    }

    // AdMob (резерв): награда приходит асинхронно через SSV-коллбэк, поэтому
    // показываем мгновенно и подтягиваем реальное значение позже.
    widget.userData.applyOptimisticAdReward(UserData.adRewardAmount);
    CoinRewardToast.show(context,
        amount: UserData.adRewardAmount, label: _s.watchAdTitle);
    setState(() {});
    // Запомним оптимистичный баланс — он нижняя граница при синхронизации.
    final rewardedCoins = widget.userData.coins;

    // В фоне синхронизируем с сервером, чтобы подтянуть реальное значение.
    // Если SSV ещё не успел — сервер вернёт старый баланс, поэтому
    // ensureCoinsAtLeast не даёт просесть ниже уже показанного значения.
    unawaited(() async {
      for (final delayMs in const [2000, 5000]) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        if (!mounted) return;
        await widget.userData.refreshCoinsFromServer();
        widget.userData.ensureCoinsAtLeast(rewardedCoins);
        if (mounted) setState(() {});
      }
    }());
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
            ? Colors.grey.shade100
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: disabled ? Colors.grey.shade400 : _accent,
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
                              ? Colors.grey.shade500
                              : Colors.grey.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
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
                      color: disabled ? Colors.grey.shade200 : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: disabled ? null : [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
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
                            color: disabled ? Colors.grey.shade500 : _accent,
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
                          ? Colors.grey.shade300
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: counterExhausted
                          ? null
                          : [
                              BoxShadow(
                                color: _accent.withValues(alpha: 0.15),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                    ),
                    child: Text(
                      counterText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        color: counterExhausted
                            ? Colors.grey.shade600
                            : _accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
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
    ];
    if (index < 0 || index >= names.length) return names[0];
    return names[index];
  }

  // null = предпросмотр запрошен, false = отмена, true = куплено
  Future<bool?> _confirmPurchaseTheme(BuildContext context, AppTheme t) async {
    final canAfford = widget.userData.coins >= t.price;
    final themeName = _themeDisplayName(t.index);

    // null = preview, false = cancel, true = buy
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: t.primary.withOpacity(0.18),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
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
                            color: Colors.grey.shade500,
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
                                ? Colors.grey.shade800
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
                        label: const Text(
                          'Посмотреть',
                          style: TextStyle(
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
                          color: canAfford ? null : Colors.grey.shade200,
                          boxShadow: canAfford
                              ? [
                                  BoxShadow(
                                    color: t.primary.withOpacity(0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ]
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
                                      : Colors.grey.shade500,
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
                          foregroundColor: Colors.grey.shade500,
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

  void _showThemePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Handle + заголовок (фиксированные)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Column(
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
                          _s.chooseColorTheme,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _s.changesApplyImmediately,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                  // Прокручиваемая сетка
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                      child: GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.88,
                        children: List.generate(AppThemes.all.length, (i) {
                          final t = AppThemes.all[i];
                          final accent = t.primary;
                          final isSelected = widget.userData.themeId == i;
                          final isLocked =
                              t.isPremium && !widget.userData.hasTheme(i);
                          return GestureDetector(
                            onTap: () async {
                              if (isLocked) {
                                final result =
                                    await _confirmPurchaseTheme(context, t);
                                if (result == false) return; // отмена
                                if (result == null) {
                                  // Предпросмотр: закрыть шторку, применить
                                  // тему временно и перейти на главный экран
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                  widget.userData.setPreviewTheme(t.index);
                                  widget.onSwitchToHome?.call();
                                  return;
                                }
                                // result == true → тема куплена
                              }
                              await widget.userData.setThemeId(i);
                              setSheet(() {});
                              if (mounted) setState(() {});
                            },
                            child: Stack(
                              children: [
                                AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: t.primaryLight,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? accent
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: accent.withOpacity(0.25),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // ── Мини-превью карточки ──
                                  Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.fromLTRB(
                                        10,
                                        10,
                                        10,
                                        6,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: t.heroGradient,
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        8,
                                        10,
                                        8,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Мок число
                                          Text(
                                            '365',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              height: 1.0,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          // Мок подпись
                                          Container(
                                            height: 4,
                                            width: 36,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(
                                                0.5,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                          const Spacer(),
                                          // Мок тоггле
                                          Container(
                                            height: 14,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(
                                                t.heroGlassOpacity * 0.75,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // ── Название + галочка ──
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      10,
                                      10,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _themeDisplayName(t.index),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: isSelected
                                                  ? accent
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Icon(
                                            Icons.check_circle_rounded,
                                            size: 16,
                                            color: accent,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                                if (isLocked)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(22),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.10,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'assets/images/icons/coin.webp',
                                            width: 22,
                                            height: 22,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            '${t.price}',
                                            style: TextStyle(
                                              fontSize: 16,
                                              height: 1.0,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.grey.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
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
              decoration: const BoxDecoration(
                color: Colors.white,
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
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _s.iconShopTitle,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade900,
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
                                color: Colors.grey.shade500,
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
                                color: Colors.grey.shade800,
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
                                    setSheet(() {});
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
                                  setSheet(() {});
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
      color: selected ? _accentLight.withValues(alpha: 0.55) : Colors.grey.shade100,
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
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.block_rounded,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _s.noIconOption,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
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
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isEquipped ? _accent : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: isEquipped
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
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
                color: Colors.white,
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
                color: isEquipped ? _accent : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 5),
            // Нижняя строка: закреплено / куплено / награда / цена
            if (isEquipped)
              Icon(Icons.check_circle_rounded, size: 18, color: _accent)
            else if (owned)
              Icon(Icons.check_rounded, size: 16, color: Colors.grey.shade400)
            else if (icon.grantOnly)
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded,
                      size: 11, color: Colors.grey.shade400),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      _s.iconRewardOnly,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
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
                      color: Colors.grey.shade800,
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Row(
          children: [
            Image.asset(icon.asset, width: 28, height: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(icon.name)),
          ],
        ),
        content: Text(
          rewardLocked ? '${icon.description}\n\n${_s.iconRewardHint}' : icon.description,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Диалог подтверждения покупки иконки. Возвращает true при успешной покупке.
  Future<bool> _confirmPurchaseIcon(BuildContext context, ProfileIcon icon) async {
    final canAfford = widget.userData.coins >= icon.price;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: _accent.withOpacity(0.18),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
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
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      icon.description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
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
                              fontSize: 13, color: Colors.grey.shade500),
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
                                ? Colors.grey.shade800
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
                          color: canAfford ? null : Colors.grey.shade200,
                          boxShadow: canAfford
                              ? [
                                  BoxShadow(
                                    color: _accent.withOpacity(0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ]
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
                                      : Colors.grey.shade500,
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
                          foregroundColor: Colors.grey.shade500,
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

  void _showEditProfileDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: widget.userData.displayName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final mq = MediaQuery.of(ctx);
          return Padding(
            padding: EdgeInsets.only(
              bottom: mq.viewInsets.bottom + mq.viewPadding.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Цветная шапка с градиентом ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_accent, _accent.withOpacity(0.75)],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Аватар с кнопкой смены
                        GestureDetector(
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _changeAvatar();
                          },
                          child: Stack(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.2),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.6),
                                    width: 2.5,
                                  ),
                                ),
                                child: widget.userData.avatarUrl.isNotEmpty
                                    ? ClipOval(
                                        child: StorageImage(
                                          imageUrl: widget.userData.avatarUrl,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) =>
                                              _buildAvatarFallback(),
                                        ),
                                      )
                                    : _buildAvatarFallback(),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _accent.withOpacity(0.3),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.camera_alt_rounded,
                                    color: _accent,
                                    size: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Имя + подсказка
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _s.editProfile,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.userData.displayName,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(0.8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Кнопка закрыть
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Поля формы ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: Column(
                      children: [
                        // Имя
                        TextField(
                          controller: nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: _s.name,
                            labelStyle: TextStyle(color: Colors.grey.shade500),
                            prefixIcon: Icon(
                              Icons.person_outline_rounded,
                              color: _accent,
                              size: 20,
                            ),
                            filled: true,
                            fillColor: _accent.withOpacity(0.04),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: _accent,
                                width: 1.8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Email (только отображение, не редактируется)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.email_outlined,
                                color: Colors.grey.shade400,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Email',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade400,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.userData.email.isNotEmpty
                                          ? widget.userData.email
                                          : '—',
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.lock_outline_rounded,
                                color: Colors.grey.shade300,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Кнопки ──
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + mq.viewPadding.bottom),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey.shade600,
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              _s.cancel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () async {
                              final newName = nameCtrl.text.trim();
                              if (newName.isNotEmpty &&
                                  newName != widget.userData.displayName) {
                                await _changeName(newName);
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shadowColor: _accent.withOpacity(0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              _s.save,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
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
          );
        },
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_s.logoutQuestion),
        content: Text(_s.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_s.cancel),
          ),
          TextButton(
            onPressed: () async {
              final userData = widget.userData;
              Navigator.of(ctx).pop();

              // Navigate first to avoid race condition with notifyListeners
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => WelcomeScreen(userData: userData),
                    settings: const RouteSettings(name: '/welcome'),
                  ),
                  (_) => false,
                );
              }

              // Logout after navigation so dispose() runs cleanly first
              try {
                await userData.logout();
              } catch (e) {
                debugPrint('Logout error: $e');
              }
            },
            child: Text(
              _s.logoutBtn,
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Форматтер авто-точек для ввода даты ДД.ММ.ГГГГ ──────────────────────────

class _DateDotFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue old,
    TextEditingValue value,
  ) {
    final digits = value.text.replaceAll(RegExp(r'[^\d]'), '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) buf.write('.');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ── Форматтер авто-двоеточия для ввода времени ЧЧ:ММ ────────────────────────

class _TimeColonFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue old,
    TextEditingValue value,
  ) {
    final digits = value.text.replaceAll(RegExp(r'[^\d]'), '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length && i < 4; i++) {
      if (i == 2) buf.write(':');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ── Диалог ввода даты + времени — StatefulWidget ─────────────────────────────

class _DateInputDialog extends StatefulWidget {
  final String title;
  final TextEditingController ctrl;      // дата
  final TextEditingController timeCtrl;  // время
  final Color primary;
  final int firstYear;
  final int lastYear;
  final DateTime? initial;
  final DateTime? Function(String) parseDateInput;

  const _DateInputDialog({
    required this.title,
    required this.ctrl,
    required this.timeCtrl,
    required this.primary,
    required this.firstYear,
    required this.lastYear,
    required this.initial,
    required this.parseDateInput,
  });

  @override
  State<_DateInputDialog> createState() => _DateInputDialogState();
}

class _DateInputDialogState extends State<_DateInputDialog> {
  String? _error;

  @override
  void dispose() {
    widget.ctrl.dispose();
    widget.timeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final parsedDate = widget.parseDateInput(widget.ctrl.text);
    if (parsedDate == null) {
      setState(() => _error = 'Введите дату в формате ДД.ММ.ГГГГ');
      return;
    }
    if (parsedDate.year < widget.firstYear ||
        parsedDate.year > widget.lastYear) {
      setState(() =>
          _error = 'Год от ${widget.firstYear} до ${widget.lastYear}');
      return;
    }
    // Разбираем время если введено
    int hour = 0, minute = 0;
    final timeParts = widget.timeCtrl.text.split(':');
    if (timeParts.length == 2) {
      hour = int.tryParse(timeParts[0]) ?? 0;
      minute = int.tryParse(timeParts[1]) ?? 0;
      if (hour > 23 || minute > 59) {
        setState(() => _error = 'Время должно быть в формате ЧЧ:ММ');
        return;
      }
    }
    Navigator.pop(
      context,
      DateTime(parsedDate.year, parsedDate.month, parsedDate.day, hour, minute),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required Color p,
    bool showError = false,
  }) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 20,
          color: Colors.grey.shade400,
          letterSpacing: 2,
          fontWeight: FontWeight.w400,
        ),
        errorText: showError ? _error : null,
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.shade300, width: 2),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: p, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red, width: 2),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red, width: 2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade900,
        ),
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Дата (3) + Время (2) ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Дата — flex 3
              Expanded(
                flex: 3,
                child: TextField(
                  controller: widget.ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_DateDotFormatter()],
                  textInputAction: TextInputAction.next,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: p,
                  ),
                  decoration: _fieldDecoration(
                    hint: 'ДД.ММ.ГГГГ',
                    p: p,
                    showError: true,
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Время — flex 2
              Expanded(
                flex: 2,
                child: TextField(
                  controller: widget.timeCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_TimeColonFormatter()],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: p,
                  ),
                  decoration: _fieldDecoration(hint: 'ЧЧ:ММ', p: p),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () async {
              final calInitial = widget.parseDateInput(widget.ctrl.text) ??
                  widget.initial ??
                  DateTime(widget.lastYear - 25);
              final calPicked = await showDatePicker(
                context: context,
                initialDate: calInitial,
                firstDate: DateTime(widget.firstYear),
                lastDate: DateTime(widget.lastYear, 12, 31),
                builder: (c, child) => Theme(
                  data: Theme.of(c).copyWith(
                    colorScheme: ColorScheme.light(
                      primary: p,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                      onSurface: Colors.grey.shade900,
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(foregroundColor: p),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (calPicked != null && mounted) {
                widget.ctrl.text =
                    '${calPicked.day.toString().padLeft(2, '0')}.${calPicked.month.toString().padLeft(2, '0')}.${calPicked.year}';
                widget.ctrl.selection = TextSelection.collapsed(
                    offset: widget.ctrl.text.length);
                setState(() => _error = null);
              }
            },
            icon: Icon(Icons.calendar_month_rounded, size: 16, color: p),
            label: Text('Открыть календарь',
                style: TextStyle(fontSize: 13, color: p)),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: Colors.grey.shade500),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: p,
            shape: const StadiumBorder(),
          ),
          onPressed: _submit,
          child: const Text('Готово'),
        ),
      ],
    );
  }
}
