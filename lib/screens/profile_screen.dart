import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common/m3_loading.dart';
import 'welcome_screen.dart';
import '../services/export_service.dart';
import '../services/timer_service.dart';
import '../services/home_widget_service.dart';
import '../services/widget_service.dart';
import '../services/rewarded_ad_service.dart';
import '../services/iap_service.dart';

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
  const ProfileScreen({
    super.key,
    required this.userData,
    required this.pairData,
    required this.timerService,
    required this.widgetService,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final RewardedAdService _rewardedAd = RewardedAdService();
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
  static const _kNotifMissYou = 'notif_miss_you';
  static const _kNotifNewMemory = 'notif_new_memory';
  static const _kNotifMood = 'notif_mood';

  // Lock screen mood
  bool _lockScreenMood = false;
  static const _kLockScreenMood = 'lock_screen_mood_enabled';

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
    _rewardedAd.load(); // предзагружаем rewarded для магазина Коинов
    _initIap();
  }

  Future<void> _loadNotifPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifMissYou = prefs.getBool(_kNotifMissYou) ?? true;
      _notifNewMemory = prefs.getBool(_kNotifNewMemory) ?? true;
      _notifMood = prefs.getBool(_kNotifMood) ?? true;
      _lockScreenMood = prefs.getBool(_kLockScreenMood) ?? false;
    });
    // Синхронизируем текущие настройки в Firestore при открытии профиля,
    // чтобы Cloud Functions всегда имели актуальные данные
    FirebaseService().updateNotifPrefs(
      missYou: prefs.getBool(_kNotifMissYou) ?? true,
      newMemory: prefs.getBool(_kNotifNewMemory) ?? true,
      mood: prefs.getBool(_kNotifMood) ?? true,
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
                          child: CachedNetworkImage(
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
            if (widget.userData.badge != null)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: GestureDetector(
                  onTap: () {
                    final badge = widget.userData.badge!;
                    final title = badge;
                    final desc = badge == 'Sponsor'
                        ? 'Спонсор проекта'
                        : badge == 'Helper'
                            ? 'Помощник проекта'
                            : badge;
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Row(
                          children: [
                            Image.asset(
                              'assets/images/icons/$title.png',
                              width: 24,
                              height: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(title),
                          ],
                        ),
                        content: Text(desc),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Image.asset(
                    'assets/images/icons/${widget.userData.badge}.png',
                    width: 40,
                    height: 40,
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
                                child: CachedNetworkImage(
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
                M3LoadingDots(color: _accent),
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
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
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
                                  child: CachedNetworkImage(
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
            icon: Icons.favorite_outline_rounded,
            label: _s.supportAuthors,
            onTap: _openBoosty,
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
                M3LoadingDots(color: _accent),
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
              'assets/images/icons/coin.png',
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
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
                            'assets/images/icons/coin.png',
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
                      _coinShopItem(
                        icon: Icons.palette_outlined,
                        title: _s.chooseColorTheme,
                        subtitle: '${AppThemes.all.where((t) => t.isPremium).length} × ${_s.themeNameLavender}, ${_s.themeNameMidnight}…',
                        onTap: () {
                          Navigator.pop(ctx);
                          _showThemePicker(context);
                        },
                      ),
                      _coinShopItem(
                        icon: Icons.play_circle_outline_rounded,
                        title: _s.watchAdTitle,
                        subtitle: _s.watchAdSubtitle,
                        counterText:
                            '${widget.userData.adRewardsToday}/${UserData.adRewardsDailyLimit}',
                        counterExhausted: widget.userData.adRewardsRemaining == 0,
                        onTap: widget.userData.adRewardsRemaining == 0
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _watchRewardedAd();
                              },
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
    // Сразу подгружаем следующую — пока пользователь смотрит/закрывает.
    unawaited(_rewardedAd.load());
    if (!earned || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_s.rewardPending),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    // SSV прилетает обычно <1с после закрытия. Дёргаем баланс с сервера
    // несколько раз с задержкой — на случай сетевой задержки.
    for (final delayMs in const [1500, 3500, 7000]) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (!mounted) return;
      final before = widget.userData.coins;
      await widget.userData.refreshCoinsFromServer();
      if (widget.userData.coins > before) {
        setState(() {});
        break;
      }
    }
  }

  Widget _coinShopItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    String? counterText,
    bool counterExhausted = false,
  }) {
    final disabled = onTap == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: disabled
            ? Colors.grey.shade100
            : _accentLight.withOpacity(0.45),
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
                                color: _accent.withOpacity(0.15),
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
    ];
    if (index < 0 || index >= names.length) return names[0];
    return names[index];
  }

  Future<bool> _confirmPurchaseTheme(BuildContext context, AppTheme t) async {
    final canAfford = widget.userData.coins >= t.price;
    final themeName = _themeDisplayName(t.index);

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
                color: t.primary.withOpacity(0.18),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Превью темы (hero gradient) ──
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Container(
                  height: 130,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: t.heroGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // декоративные «пузырьки»
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
                      Positioned(
                        bottom: -30,
                        left: 20,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.22),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _s.coinShopSubtitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              themeName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Содержимое ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                child: Column(
                  children: [
                    Text(
                      _s.buyThemeTitle,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                            'assets/images/icons/coin.png',
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
                    const SizedBox(height: 14),
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
                          'assets/images/icons/coin.png',
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
                    const SizedBox(height: 22),
                    // ── Кнопка покупки ──
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
    if (confirmed != true) return false;
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
                                final purchased =
                                    await _confirmPurchaseTheme(context, t);
                                if (!purchased) return;
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
                                            'assets/images/icons/coin.png',
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

  void _showEditProfileDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: widget.userData.displayName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
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
                                        child: CachedNetworkImage(
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
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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
