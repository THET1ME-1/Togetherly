import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:home_widget/home_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/memory.dart';
import '../models/pair_data.dart';
import '../models/user_data.dart';
import '../models/mood_entry.dart';
import '../services/deep_link_service.dart';
import '../services/firebase_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common/animations.dart';
import '../widgets/common/m3_loading.dart';
import 'home/widgets/mood_picker_dialog.dart';
import 'home/widgets/relationship_type_dialog.dart';
import 'home/home_header.dart';
import 'home/home_action_buttons.dart';
import 'home/home_memory_preview.dart';
import 'home/home_bottom_nav.dart';
import 'connect_partner_screen.dart';
import 'expandable_timer_card.dart';
import 'memory_lane_screen.dart';
import 'mini_mood_calendar.dart';
import 'mood_calendar_screen.dart';
import 'profile_screen.dart';
import '../services/home_widget_service.dart';
import '../services/mood_service.dart';
import '../services/timer_service.dart';
import '../services/widget_service.dart';
import '../models/mascot.dart';
import '../services/canvas_storage_service.dart';
import '../services/mascot_service.dart';
import '../widgets/active_mascot_widget.dart';
import 'mascot_gallery_screen.dart';
import 'widget_screen.dart';
import 'draw_screen.dart';
import 'draw_gallery_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserData userData;
  const HomeScreen({super.key, required this.userData});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // -- Theme --
  AppTheme get _t => widget.userData.theme;
  Color get primary => _t.primary;
  Color get primaryLight => _t.primaryLight;

  // -- State --
  int _selectedNavIndex = 0;
  bool _showTodayButton = false;
  StreamSubscription? _deepLinkSub;

  // -- Pair data --
  final PairData _pairData = PairData();

  // -- Timer service --
  final TimerService _timerService = TimerService();

  // -- Mood service --
  final MoodService _moodService = MoodService();

  // -- Widget service --
  final WidgetService _widgetService = WidgetService();

  // -- Mascot service --
  final MascotService _mascotService = MascotService();
  AppLifecycleListener? _appLifecycleListener;

  // -- Memory Lane real-time --
  final FirebaseService _fb = FirebaseService();
  final CanvasStorageService _storage = CanvasStorageService.instance;
  List<Memory> _recentMemories = [];
  StreamSubscription? _memorySub;

  // -- User location (for distance calc) --
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    _pairData.addListener(_onPairChanged);
    widget.userData.addListener(_onUserChanged);
    _moodService.addListener(_onMoodServiceChanged);
    _timerService.init();
    _initPairData();

    // Устанавливаем статус «онлайн»
    _fb.setOnlineStatus(true);

    // Check if launched from homescreen widget > open Widgets tab
    _checkWidgetLaunch();
    HomeWidget.widgetClicked.listen(_onWidgetClicked);

    // Listen to deep link invites
    _deepLinkSub = DeepLinkService().inviteCodeStream.listen((code) {
      if (mounted && !_pairData.isPaired) {
        // Switch to Connect Partner tab
        setState(() => _selectedNavIndex = 1);
        // The connect_partner_screen will handle the code
      }
    });

    // Fetch user location for distance display
    _fetchUserLocation();

    _appLifecycleListener = AppLifecycleListener(
      onResume: () {
        if (_pairData.isPaired) {
          _mascotService.recordDailyActivity();
        }
      },
    );
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _memorySub?.cancel();
    _appLifecycleListener?.dispose();
    _mascotService.dispose();
    _pairData.removeListener(_onPairChanged);
    widget.userData.removeListener(_onUserChanged);
    _moodService.removeListener(_onMoodServiceChanged);
    _widgetService.dispose();
    _pairData.dispose();
    super.dispose();
  }

  Future<void> _initPairData() async {
    await _pairData.init(myName: widget.userData.displayName);
    if (mounted) setState(() {});
  }

  /// Проверяет, запущено ли приложение кликом на виджет
  Future<void> _checkWidgetLaunch() async {
    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (uri != null) {
        _handleWidgetUri(uri);
      }
    } catch (e) {
      debugPrint('HomeWidget initial launch check failed: $e');
    }
  }

  /// Обработчик клика на виджет рабочего стола
  void _onWidgetClicked(Uri? uri) {
    if (uri != null) {
      _handleWidgetUri(uri);
    }
  }

  void _handleWidgetUri(Uri uri) {
    // loveapp://widgets → вкладка виджетов (index 1)
    if (uri.host == 'widgets' || uri.toString().contains('widgets')) {
      if (mounted) {
        setState(() => _selectedNavIndex = 1);
      }
    }
    // loveapp://home → главная (index 0)
    else if (uri.host == 'home') {
      if (mounted) {
        setState(() => _selectedNavIndex = 0);
      }
    }
    // loveapp://memory_lane → открыть Memory Lane
    else if (uri.host == 'memory_lane') {
      if (mounted && _pairData.isPaired) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MemoryLaneScreen(pairData: _pairData, theme: _t),
          ),
        );
      }
    }
    // loveapp://mood → открыть Mood Calendar
    else if (uri.host == 'mood') {
      if (mounted && _pairData.isPaired) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MoodCalendarScreen(
              pairData: _pairData,
              moodService: _moodService,
              widgetService: _widgetService,
              theme: _t,
            ),
          ),
        );
      }
    }
  }

  void _onPairChanged() {
    if (mounted) {
      _startMemoryListener();

      if (_pairData.isPaired && _pairData.startDate != null) {
        // Bind mascot service and record today's activity.
        _bindMascotService(_pairData.pairId);

        // Bind timer service to group for Firestore sync
        _timerService.bindToGroup(_pairData.pairId);

        // Bind mood service to group for Firestore sync
        _moodService.bindToGroup(_pairData.pairId);

        // Bind widget service to group for Firestore sync
        _widgetService.bindToGroup(_pairData.pairId);
        for (final p in _pairData.partners) {
          _widgetService.listenToPartner(p.uid);
          // Subscribe to partner moods so MoodWidgetProvider stays updated
          _moodService.listenToPartner(p.uid);
        }

        // Create system timer if it doesn't exist yet
        _timerService.createSystemTimer(
          startDate: _pairData.startDate!,
          relationshipLabel: _pairData.relationshipLabel,
          relationshipEmoji: _pairData.relationshipEmoji,
          partnerName: _pairData.partnerDisplayName,
        );

        // Синхронизируем виджеты рабочего стола с актуальными данными
        _syncHomeWidgets();
      } else {
        _timerService.unbindFromGroup();
        _mascotService.unbind();
      }

      setState(() {});
    }
  }

  void _bindMascotService(String groupId) {
    _mascotService.bindToGroup(groupId);
    // Record that someone opened the app today (streak tracking).
    _mascotService.recordDailyActivity();
  }

  void _openMascotGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MascotGalleryScreen(
          mascotService: _mascotService,
          theme: _t,
          myUid: widget.userData.uid,
        ),
      ),
    );
  }

  /// Синхронизирует виджеты рабочего стола.
  /// Вызов дешёвый — обновляет данные виджета только при необходимости.
  Future<void> _syncHomeWidgets() async {
    if (!_pairData.isPaired) return;

    final hws = HomeWidgetService.instance;
    final myName = widget.userData.displayName;
    final partnerName = _pairData.partnerDisplayName;

    final myGender = widget.userData.gender?.name ?? '';
    final partnerGender = _widgetService.firstPartnerData?.gender ?? '';

    await hws.syncAllBoundWidgets(
      activeGroupId: _pairData.pairId,
      activeTimers: _timerService.timers,
      activeSysTimer: _timerService.systemTimer,
      activeStartDate: _pairData.startDate,
      coupleNames: '$myName & $partnerName',
      emoji: _pairData.relationshipEmoji,
      myGender: myGender,
      partnerGender: partnerGender,
    );

    // Sync the mood widget from today's Mood Calendar entries
    await _syncMoodWidget();
  }

  /// пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ (MoodWidgetProvider) пїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ
  /// Mood Calendar пїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅ пїЅ пїЅ пїЅпїЅпїЅпїЅпїЅ, пїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ.
  Future<void> _syncMoodWidget() async {
    if (!_pairData.isPaired) return;
    final today = DateTime.now();

    // пїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ
    final myEntries = _moodService.myEntriesForDay(today);
    final myEntry = myEntries.isNotEmpty ? myEntries.first : null;

    // пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ
    final partnerUid = _pairData.partners.isNotEmpty
        ? _pairData.partners.first.uid
        : '';
    final partnerEntries = partnerUid.isNotEmpty
        ? _moodService.partnerEntriesForDay(partnerUid, today)
        : <MoodEntry>[];
    final partnerEntry = partnerEntries.isNotEmpty
        ? partnerEntries.first
        : null;

    await HomeWidgetService.instance.syncMood(
      moodEmojiAssetPath: myEntry?.imagePath ?? '',
      moodLabel: myEntry?.label ?? '',
      userName: widget.userData.displayName,
      partnerMoodEmojiAssetPath: partnerEntry?.imagePath ?? '',
      partnerMoodLabel: partnerEntry?.label ?? '',
      partnerUserName: _pairData.partnerDisplayName,
    );
  }

  void _startMemoryListener() {
    _memorySub?.cancel();
    final groupId = _pairData.pairId;
    if (groupId.isEmpty || !_pairData.isPaired) {
      _recentMemories = [];
      return;
    }
    _memorySub = _fb.listenToMemories(
      groupId: groupId,
      limit: 10,
      onData: (memories) {
        if (mounted) setState(() => _recentMemories = memories);
      },
    );
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  /// Обновление MoodService: применять изменения настроения из pairData
  /// и синхронизировать виджет настроения при изменении состояния.
  void _onMoodServiceChanged() {
    if (!mounted || !_pairData.isPaired) return;
    final today = DateTime.now();
    final todayEntries = _moodService.myEntriesForDay(today);
    final current = _pairData.myMood;
    if (todayEntries.isNotEmpty) {
      final entry = todayEntries.first;
      if (current.imagePath != entry.imagePath) {
        _pairData.setMood(entry.imagePath, entry.label);
      }
    } else {
      if (current.isNotEmpty) {
        _pairData.clearMood();
      }
    }
    // Синхронизируем виджет настроения после обновления
    _syncMoodWidget();
    if (mounted) setState(() {});
  }

  String get _statusBadgeText {
    if (!_pairData.isPaired) return LocaleService.current.solo;
    return _pairData.relationshipLabel;
  }

  String get _statusBadgeEmoji {
    if (!_pairData.isPaired) return '';
    return _pairData.relationshipEmoji;
  }

  // =============================================
  // BUILD
  // =============================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // -- Background --
          Positioned.fill(
            child: RepaintBoundary(
              child: _t.bgImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: _t.bgImageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (_, __) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: _t.bgGradient,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: _t.bgGradient,
                          ),
                        ),
                      ),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: _t.bgGradient,
                        ),
                      ),
                    ),
            ),
          ),
          // -- Main content --
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                HomeHeader(
                  theme: _t,
                  isPaired: _pairData.isPaired,
                  partnerCount: _pairData.partnerCount,
                  myAvatarUrl: widget.userData.avatarUrl,
                  myDisplayName: widget.userData.displayName,
                  partners: _pairData.partners,
                  myMood: _pairData.myMood,
                  moodOf: _pairData.moodOf,
                  statusBadgeText: _statusBadgeText,
                  statusBadgeEmoji: _statusBadgeEmoji,
                  onRelationshipTap: _showRelationshipTypeDialog,
                  pairId: _pairData.pairId,
                ),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
          // -- Active mascot floating overlay --
          if (_pairData.isPaired)
            ActiveMascotWidget(
              mascotService: _mascotService,
              theme: _t,
              onOpenGallery: _openMascotGallery,
            ),
          // -- Bottom Nav (hidden when timer card is expanded) --
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: HomeBottomNav(
              selectedIndex: _selectedNavIndex,
              theme: _t,
              isPaired: _pairData.isPaired,
              onTap: (i) => setState(() => _selectedNavIndex = i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedNavIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildWidgetsTab();
      case 2:
        return ConnectPartnerScreen(pairData: _pairData, theme: _t);
      case 3:
        return _buildProfileTab();
      default:
        return _buildHomeTab();
    }
  }

  // =============================================
  // HOME TAB
  // =============================================
  Widget _buildHomeTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 100,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                AnimatedSlideIn(
                  delay: const Duration(milliseconds: 100),
                  child: MiniMoodCalendar(
                    moodService: _moodService,
                    theme: _t,
                    onDayTap: _showMoodPickerForDate,
                    onTodayButtonVisibilityChanged: (v) =>
                        setState(() => _showTodayButton = v),
                  ),
                ),
                const SizedBox(height: 8),
                // Shift dial UP closer to calendar (disabled when Today button is visible)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  transform: Matrix4.translationValues(
                    0,
                    _showTodayButton ? 0 : -20,
                    0,
                  ),
                  child: AnimatedSlideIn(
                    delay: const Duration(milliseconds: 200),
                    child: ExpandableTimerCard(
                      theme: _t,
                      timerService: _timerService,
                      myAvatarUrl: widget.userData.avatarUrl,
                      partnerAvatarUrl: _pairData.partnerAvatarUrl,
                      isPaired: _pairData.isPaired,
                      onPetalTap: _pairData.isPaired
                          ? (label) => _openMemoryLaneForPetal(label)
                          : null,
                    ),
                  ),
                ),
                // Restore buttons offset to -15 for tighter layout
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  transform: Matrix4.translationValues(
                    0,
                    _showTodayButton ? 0 : -15,
                    0,
                  ),
                  child: AnimatedSlideIn(
                    delay: const Duration(milliseconds: 300),
                    child: HomeActionButtons(
                      theme: _t,
                      isPaired: _pairData.isPaired,
                      myMoodImagePath: _pairData.myMood.imagePath,
                      onDraw: _openDraw,
                      onMood: _showMoodPicker,
                      onCalendar: _openMoodCalendar,
                      onPost: _postPhoto,
                    ),
                  ),
                ),
                if (!_pairData.isPaired) ...[
                  const SizedBox(height: 8),
                  AnimatedSlideIn(
                    delay: const Duration(milliseconds: 400),
                    child: _buildConnectPrompt(),
                  ),
                ],
                if (_pairData.isPaired) ...[
                  const SizedBox(height: 8),
                  AnimatedSlideIn(
                    delay: const Duration(milliseconds: 380),
                    child: _buildMascotRow(),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
          AnimatedSlideIn(
            delay: const Duration(milliseconds: 500),
            child: MemoryLanePreview(
              isPaired: _pairData.isPaired,
              memories: _recentMemories,
              pairData: _pairData,
              theme: _t,
              userLat: _userLat,
              userLng: _userLng,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildMascotRow() {
    final mascot = _mascotService.activeMascot;
    final streak = _mascotService.state.streakDays;

    return ValueListenableBuilder<bool>(
      valueListenable: mascotHiddenNotifier,
      builder: (context, isHidden, _) {
        return GestureDetector(
          onTap: _openMascotGallery,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _t.cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _t.cardBorder),
            ),
            child: Row(
              children: [
                // Mascot preview
                SizedBox(
                  width: 48,
                  height: 48,
                  child: mascot != null
                      ? _MascotPreviewWidget(
                          mascot: mascot,
                          service: _mascotService,
                        )
                      : Icon(
                          Icons.sentiment_satisfied_alt,
                          size: 36,
                          color: _t.primary.withAlpha(120),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mascot != null ? mascot.name : 'Маскот группы',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        streak > 0
                            ? '🔥 Серия: $streak дн.'
                            : mascot != null
                            ? 'Нажмите для галереи'
                            : 'Выберите маскота',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Show/hide mascot toggle
                if (mascot != null)
                  GestureDetector(
                    onTap: () async {
                      if (isHidden) {
                        await showMascotOverlay();
                      }
                      // If not hidden, the tap on the card opens gallery — no conflict
                    },
                    behavior: HitTestBehavior.opaque,
                    child: isHidden
                        ? Padding(
                            padding: const EdgeInsets.only(left: 4, right: 2),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _t.primary.withAlpha(20),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _t.primary.withAlpha(60),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.visibility_outlined,
                                    size: 14,
                                    color: _t.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Показать',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _t.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =============================================
  // WIDGETS TAB
  // =============================================
  Widget _buildWidgetsTab() {
    return WidgetScreen(
      userData: widget.userData,
      pairData: _pairData,
      widgetService: _widgetService,
      moodService: _moodService,
      timerService: _timerService,
      theme: _t,
    );
  }

  // =============================================
  // PROFILE TAB
  // =============================================
  Widget _buildProfileTab() {
    return ProfileScreen(
      userData: widget.userData,
      pairData: _pairData,
      timerService: _timerService,
    );
  }

  // =============================================
  // RELATIONSHIP TYPE DIALOG
  // =============================================
  void _showRelationshipTypeDialog() {
    showRelationshipTypeDialog(
      context: context,
      pairData: _pairData,
      primary: primary,
      onStateChanged: () => setState(() {}),
    );
  }

  // =============================================
  // MOOD PICKER
  // =============================================

  void _openDraw() {
    final s = LocaleService.current;
    final t = _t;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                s.drawingMode,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              DrawModeOption(
                icon: Icons.add_circle_outline_rounded,
                color: t.primary,
                title: s.newCanvas,
                subtitle: s.startWithBlankCanvas,
                onTap: () {
                  Navigator.pop(ctx);
                  _openNewCanvas();
                },
              ),
              const SizedBox(height: 10),
              DrawModeOption(
                icon: Icons.collections_rounded,
                color: const Color(0xFF8B5CF6),
                title: s.myDrawings,
                subtitle: s.openSavedDrawing,
                onTap: () {
                  Navigator.pop(ctx);
                  _openDrawGallery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMemoryLaneForPetal(String petalLabel) {
    if (!_pairData.isPaired) return;
    final mode = petalLabel == LocaleService.current.daysShortLabel
        ? MemoryFilterMode.day
        : MemoryFilterMode.month;
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) =>
            MemoryLaneScreen(pairData: _pairData, theme: _t, filterMode: mode),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.12),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openNewCanvas() async {
    final s = LocaleService.current;
    final canvases = await _storage.getCanvases(widget.userData.uid);
    final meta = await _storage.createCanvas(
      widget.userData.uid,
      name: '${s.untitledCanvas} ${canvases.length + 1}',
      groupId: _pairData.pairId,
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrawScreen(
          userData: widget.userData,
          pairData: _pairData,
          theme: _t,
          canvasId: meta.id,
          canvasName: meta.name,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  void _openDrawGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrawGalleryScreen(
          userData: widget.userData,
          pairData: _pairData,
          theme: _t,
        ),
      ),
    );
  }

  void _openMoodCalendar() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MoodCalendarScreen(
          pairData: _pairData,
          moodService: _moodService,
          widgetService: _widgetService,
          theme: _t,
        ),
      ),
    );
  }

  /// Открыть выбор настроения для конкретной даты.
  void _showMoodPickerForDate(DateTime date) {
    showMoodPickerForDate(
      context: context,
      date: date,
      pairData: _pairData,
      moodService: _moodService,
      widgetService: _widgetService,
      primary: primary,
      navActiveIcon: _t.navActiveIcon, // добавлено
    );
  }

  void _showMoodPicker() {
    showMoodPicker(
      context: context,
      pairData: _pairData,
      moodService: _moodService,
      widgetService: _widgetService,
      primary: primary,
      navActiveIcon: _t.navActiveIcon, // добавлено
    );
  }

  // =============================================
  // POST PHOTO (camera > upload > Memory Lane)
  // =============================================
  Future<void> _postPhoto() async {
    if (!_pairData.isPaired || _pairData.pairId.isEmpty) return;

    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (photo == null || !mounted) return;

    // Extract EXIF geolocation from photo
    double? photoLat;
    double? photoLng;
    String? photoLocationName;
    try {
      final bytes = await File(photo.path).readAsBytes();
      final exifData = await readExifFromBytes(bytes);
      final latTag = exifData['GPS GPSLatitude'];
      final lngTag = exifData['GPS GPSLongitude'];
      final latRef = exifData['GPS GPSLatitudeRef'];
      final lngRef = exifData['GPS GPSLongitudeRef'];
      if (latTag != null && lngTag != null) {
        photoLat = _exifGpsToDouble(latTag.values, latRef?.printable ?? 'N');
        photoLng = _exifGpsToDouble(lngTag.values, lngRef?.printable ?? 'E');
      }
    } catch (e) {
      debugPrint('EXIF extraction failed: \$e');
    }

    // If no EXIF, try current device location
    if (photoLat == null || photoLng == null) {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied) {
            perm = await Geolocator.requestPermission();
          }
          if (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse) {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 5),
              ),
            );
            photoLat = pos.latitude;
            photoLng = pos.longitude;
          }
        }
      } catch (e) {
        debugPrint('Geolocator fallback failed: \$e');
      }
    }

    // Reverse geocode to get location name
    if (photoLat != null && photoLng != null) {
      try {
        final placemarks = await placemarkFromCoordinates(photoLat, photoLng);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[
            if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
            if (p.country != null && p.country!.isNotEmpty) p.country!,
          ];
          if (parts.isNotEmpty) photoLocationName = parts.join(', ');
        }
      } catch (e) {
        debugPrint('Reverse geocode failed: \$e');
      }
    }

    // Show caption dialog (with optional "set as widget photo" toggle)
    final result = await _showCaptionDialog();
    if (!mounted) return;
    // null means user cancelled
    if (result == null) return;

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
                M3LoadingDots(color: primary),
                const SizedBox(height: 16),
                Text(
                  LocaleService.current.posting,
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
      // Upload to Firebase Storage
      final ext = photo.path.split('.').last;
      final destination =
          'memories/${_pairData.pairId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final downloadUrl = await _fb.uploadFile(photo.path, destination);

      if (downloadUrl == null) {
        if (mounted) Navigator.of(context).pop(); // dismiss loading
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LocaleService.current.failedUploadPhoto)),
          );
        }
        return;
      }

      // Create memory
      await _fb.addMemory(
        groupId: _pairData.pairId,
        type: MemoryType.photo,
        imageUrl: downloadUrl,
        title: result.title,
        caption: result.caption,
        locationName: photoLocationName,
        latitude: photoLat,
        longitude: photoLng,
      );

      // If user chose to set as widget Photo of the Day
      if (result.setAsWidget) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await _widgetService.setPhotoDayMode('custom');
          await _widgetService.updatePhotoUrl(downloadUrl);
          await prefs.setString(
            'photo_day_path_${_pairData.pairId}',
            photo.path,
          );
          final hws = HomeWidgetService.instance;
          await hws.setPhotoDayMode(_pairData.pairId, 'custom');
          await hws.refreshPhotoOfDay(_pairData.pairId);
        } catch (e) {
          debugPrint('Failed to set widget photo day: $e');
        }
      }

      if (mounted) Navigator.of(context).pop(); // dismiss loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocaleService.current.postedToMemoryLane),
            backgroundColor: primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // dismiss loading
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<({String? title, String? caption, bool setAsWidget})?>
  _showCaptionDialog() async {
    final titleController = TextEditingController();
    final controller = TextEditingController();
    return showDialog<({String? title, String? caption, bool setAsWidget})>(
      context: context,
      builder: (ctx) {
        bool setAsWidget = false;
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          'assets/icons/ic_photo.svg',
                          width: 22,
                          height: 22,
                          colorFilter: ColorFilter.mode(
                            Colors.grey.shade900,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          LocaleService.current.newPhoto,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Заголовок
                    TextField(
                      controller: titleController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 60,
                      decoration: InputDecoration(
                        hintText: LocaleService.current.titleHint,
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Описание
                    TextField(
                      controller: controller,
                      autofocus: false,
                      maxLines: 3,
                      maxLength: 200,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: LocaleService.current.descriptionOptionalHint,
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Опция: установить как фото дня виджета
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            LocaleService.current.setAsWidgetPhoto,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        Switch.adaptive(
                          value: setAsWidget,
                          activeColor: primary,
                          onChanged: (v) => setDlgState(() => setAsWidget = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              LocaleService.current.skip,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final titleText = titleController.text.trim();
                              final text = controller.text.trim();
                              Navigator.pop(ctx, (
                                title: titleText.isEmpty ? null : titleText,
                                caption: text.isEmpty ? null : text,
                                setAsWidget: setAsWidget,
                              ));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text(
                              LocaleService.current.post,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // =============================================
  // CONNECT PROMPT (shown when unpaired)
  // =============================================
  Widget _buildConnectPrompt() {
    return GestureDetector(
      onTap: () => setState(() => _selectedNavIndex = 2),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _t.cardSurface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: _t.cardBorder, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_add_rounded, color: primary, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocaleService.current.inviteYourPartner,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    LocaleService.current.shareLinkCodeQr,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: primary),
          ],
        ),
      ),
    );
  }

  // =============================================
  // HELPER METHODS: Location, EXIF, Time
  // =============================================

  /// Fetch user location for distance calculation on photo cards
  Future<void> _fetchUserLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 10),
          ),
        );
        if (mounted) {
          setState(() {
            _userLat = pos.latitude;
            _userLng = pos.longitude;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to get user location: $e');
    }
  }

  /// Convert EXIF GPS rational values to double degrees.
  /// Based on the official exif package example (gps_coords.dart).
  double _exifGpsToDouble(IfdValues values, String ref) {
    if (values is! IfdRatios) return 0.0;

    double sum = 0.0;
    double unit = 1.0;
    for (final v in values.ratios) {
      sum += v.toDouble() * unit;
      unit /= 60.0;
    }

    if (ref == 'S' || ref == 'W') sum = -sum;
    return sum;
  }
}

// ── Mascot preview in the home row ────────────────────────────────────────────

class _MascotPreviewWidget extends StatelessWidget {
  final Mascot mascot;
  final MascotService service;

  const _MascotPreviewWidget({required this.mascot, required this.service});

  @override
  Widget build(BuildContext context) {
    final asset = service.resolvedAssetForMood(mascot);
    if (asset != null) {
      return buildMascotAssetImage(asset, fit: BoxFit.contain);
    }
    if (mascot.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: mascot.imageUrl!,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => const Icon(Icons.face),
      );
    }
    return const Icon(Icons.face);
  }
}
