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
import 'package:url_launcher/url_launcher.dart';
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
import 'connect_partner_screen.dart';
import 'expandable_timer_card.dart';
import 'memory_lane_screen.dart';
import '../widgets/memory_tile_builder.dart';
import 'mini_mood_calendar.dart';
import 'mood_calendar_screen.dart';
import 'profile_screen.dart';
import '../services/home_widget_service.dart';
import '../services/mood_service.dart';
import '../services/timer_service.dart';
import '../services/widget_service.dart';
import '../services/canvas_storage_service.dart';
import 'widget_screen.dart';
import 'miss_you_button.dart';
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
  int _selectedTimeUnit = 0; // 0=Days, 1=Months, 2=Time
  int _selectedNavIndex = 0;
  bool _showReflection = false;
  bool _showTodayButton = false;
  Timer? _timer;
  StreamSubscription? _deepLinkSub;

  // -- Pair data --
  final PairData _pairData = PairData();

  // -- Timer service --
  final TimerService _timerService = TimerService();

  // -- Mood service --
  final MoodService _moodService = MoodService();

  // -- Widget service --
  final WidgetService _widgetService = WidgetService();

  // -- Memory Lane real-time --
  final FirebaseService _fb = FirebaseService();
  final CanvasStorageService _storage = CanvasStorageService.instance;
  List<Memory> _recentMemories = [];
  StreamSubscription? _memorySub;

  // -- User location (for distance calc) --
  double? _userLat;
  double? _userLng;

  // -- Daily Reflection --
  Map<String, dynamic>? _todayReflection;
  StreamSubscription? _reflectionSub;
  bool _reflectionJustSaved = false;
  bool _reflectionManuallyDismissed = false;

  bool get _hasPartnerAnswer {
    final myUid = widget.userData.uid;
    final answers = _todayReflection?['answers'] as Map<String, dynamic>?;
    if (answers == null || answers.isEmpty) return false;
    return answers.keys.any((k) => k != myUid);
  }

  List<String> get _localizedQuestions =>
      LocaleService.current.reflectionQuestions;

  String get _todayQuestion {
    final questions = _localizedQuestions;
    final dayOfYear = DateTime.now()
        .difference(DateTime(DateTime.now().year))
        .inDays;
    return questions[dayOfYear % questions.length];
  }

  @override
  void initState() {
    super.initState();
    _pairData.addListener(_onPairChanged);
    widget.userData.addListener(_onUserChanged);
    _moodService.addListener(_onMoodServiceChanged);
    _timerService.init();
    _initPairData();
    _loadReflectionState();

    // пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ "пїЅпїЅпїЅпїЅпїЅпїЅ" пїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ
    _fb.setOnlineStatus(true);

    // Dynamic timer - only start when needed (Time mode)
    _startTimerIfNeeded();

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
  }

  @override
  void dispose() {
    _timer?.cancel();
    _deepLinkSub?.cancel();
    _memorySub?.cancel();
    _reflectionSub?.cancel();
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

  /// пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ, пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅ пїЅпїЅпїЅпїЅпїЅ пїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ
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

  /// пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅ пїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ
  void _onWidgetClicked(Uri? uri) {
    if (uri != null) {
      _handleWidgetUri(uri);
    }
  }

  void _handleWidgetUri(Uri uri) {
    // loveapp://widgets > пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ (index 1)
    if (uri.host == 'widgets' || uri.toString().contains('widgets')) {
      if (mounted) {
        setState(() => _selectedNavIndex = 1);
      }
    }
    // loveapp://home > пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ (index 0)
    else if (uri.host == 'home') {
      if (mounted) {
        setState(() => _selectedNavIndex = 0);
      }
    }
    // loveapp://memory_lane > пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ Memory Lane
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
    // loveapp://mood > пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ (mood calendar)
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

  void _startTimerIfNeeded() {
    _timer?.cancel();
    _timer = null;
    if (_pairData.isPaired && _selectedTimeUnit == 2) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _onPairChanged() {
    if (mounted) {
      _startMemoryListener();
      _startReflectionListener();
      _startTimerIfNeeded();

      if (_pairData.isPaired && _pairData.startDate != null) {
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

        // пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅ: пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ
        _syncHomeWidgets();
      } else {
        _timerService.unbindFromGroup();
      }

      setState(() {});
    }
  }

  /// пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅ.
  /// пїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ.
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

  void _startReflectionListener() {
    _reflectionSub?.cancel();
    final groupId = _pairData.pairId;
    if (groupId.isEmpty || !_pairData.isPaired) {
      _todayReflection = null;
      return;
    }
    _reflectionSub = _fb.listenToTodayReflection(
      groupId: groupId,
      onData: (data) {
        if (!mounted) return;
        final myUid = widget.userData.uid;
        final alreadyAnswered =
            (data?['answers'] as Map<String, dynamic>?)?.containsKey(myUid) ??
            false;
        if (alreadyAnswered) {
          // пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅ prefs, пїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ
          _markReflectionAnsweredToday();
        }
        setState(() {
          _todayReflection = data;
          if (alreadyAnswered) _showReflection = false;
        });
      },
    );
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  /// пїЅпїЅпїЅпїЅпїЅпїЅпїЅ MoodService пїЅ пїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ
  /// пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅ пїЅ pairData (пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ, пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ)
  /// пїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅ.
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
    // пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅ пїЅ пїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ
    _syncMoodWidget();
    if (mounted) setState(() {});
  }

  /// пїЅпїЅпїЅпїЅ пїЅпїЅпїЅ SharedPreferences: пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ + пїЅпїЅпїЅ
  String get _reflectionPrefKey {
    final today = DateTime.now();
    final dateStr =
        '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    return 'reflection_answered_${widget.userData.uid}_$dateStr';
  }

  /// пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅ SharedPreferences пїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ
  Future<void> _loadReflectionState() async {
    final prefs = await SharedPreferences.getInstance();
    final answeredToday = prefs.getBool(_reflectionPrefKey) ?? false;
    if (mounted) setState(() => _showReflection = !answeredToday);
  }

  /// пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅ SharedPreferences, пїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅ
  Future<void> _markReflectionAnsweredToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reflectionPrefKey, true);
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
                _buildHeader(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
          // -- Bottom Nav (hidden when timer card is expanded) --
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomNavContent(),
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
                    child: _buildActionButtons(),
                  ),
                ),
                if (_pairData.isPaired &&
                    !_reflectionManuallyDismissed &&
                    (_showReflection || _hasPartnerAnswer)) ...[
                  const SizedBox(height: 8),
                  AnimatedSlideIn(
                    delay: const Duration(milliseconds: 400),
                    child: _buildDailyReflection(),
                  ),
                ],
                if (!_pairData.isPaired) ...[
                  const SizedBox(height: 8),
                  AnimatedSlideIn(
                    delay: const Duration(milliseconds: 400),
                    child: _buildConnectPrompt(),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
          if (_pairData.isPaired)
            AnimatedSlideIn(
              delay: const Duration(milliseconds: 500),
              child: _buildMemoryLaneSection(),
            ),
          if (!_pairData.isPaired)
            AnimatedSlideIn(
              delay: const Duration(milliseconds: 500),
              child: _buildEmptyMemoryLane(),
            ),
          const SizedBox(height: 40),
        ],
      ),
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
  // HEADER
  // =============================================
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
      child: Row(
        children: [
          // Avatars
          if (_pairData.isPaired) ...[
            SizedBox(
              width:
                  28.0 + 40.0 + (_pairData.partnerCount - 1).clamp(0, 3) * 28.0,
              height: 48,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 4,
                    child: _avatarWithMood(
                      widget.userData.avatarUrl,
                      name: widget.userData.displayName,
                      mood: _pairData.myMood,
                      moodPosition: MoodBadgePosition.topLeft,
                    ),
                  ),
                  ...List.generate(
                    _pairData.partners.length.clamp(0, 4),
                    (i) => Positioned(
                      left: 28.0 + i * 28.0,
                      top: 4,
                      child: _avatarWithMood(
                        _pairData.partners[i].avatar,
                        name: _pairData.partners[i].name,
                        mood: _pairData.moodOf(_pairData.partners[i].uid),
                        moodPosition: MoodBadgePosition.bottomRight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            _avatarCircle(
              widget.userData.avatarUrl,
              name: widget.userData.displayName,
            ),
          ],
          const SizedBox(width: 8),
          // Badge пїЅ tappable to change relationship type
          GestureDetector(
            onTap: _pairData.isPaired ? _showRelationshipTypeDialog : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _pairData.isPaired
                    ? primary.withOpacity(0.1)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _pairData.isPaired
                      ? primary.withOpacity(0.1)
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_statusBadgeEmoji.isNotEmpty) ...[
                    Text(
                      _statusBadgeEmoji,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 4),
                  ] else ...[
                    Icon(
                      Icons.favorite_border,
                      color: Colors.grey.shade400,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    _statusBadgeText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _pairData.isPaired
                          ? primary
                          : Colors.grey.shade500,
                    ),
                  ),
                  if (_pairData.isPaired) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 14,
                      color: primary.withOpacity(0.6),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_pairData.isPaired) ...[
            const SizedBox(width: 8),
            MissYouButton(
              theme: _t,
              groupId: _pairData.pairId,
              senderName: widget.userData.displayName,
              enabled: _pairData.isPaired,
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  Widget _avatarCircle(String url, {String? name}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
        ],
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 120,
                memCacheHeight: 120,
                errorWidget: (context, url, error) => _avatarPlaceholder(name),
              )
            : _avatarPlaceholder(name),
      ),
    );
  }

  Widget _avatarPlaceholder(String? name) {
    final initial = (name != null && name.isNotEmpty)
        ? name[0].toUpperCase()
        : '?';
    return Container(
      color: primary.withOpacity(0.15),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: primary,
          ),
        ),
      ),
    );
  }

  Widget _avatarWithMood(
    String url, {
    String? name,
    required MemberMood mood,
    MoodBadgePosition moodPosition = MoodBadgePosition.bottomRight,
  }) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 4, top: 4, child: _avatarCircle(url, name: name)),
          if (mood.isNotEmpty)
            Positioned(
              top: moodPosition == MoodBadgePosition.topLeft ? -4 : null,
              bottom: moodPosition == MoodBadgePosition.bottomRight ? -4 : null,
              left: moodPosition == MoodBadgePosition.topLeft ? -4 : null,
              right: moodPosition == MoodBadgePosition.bottomRight ? -4 : null,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: mood.imagePath.isNotEmpty
                    ? ClipOval(
                        child: Image.asset(
                          mood.imagePath,
                          width: 22,
                          height: 22,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox(width: 22, height: 22),
                        ),
                      )
                    : const SizedBox(width: 22, height: 22),
              ),
            ),
        ],
      ),
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
                subtitle: LocaleService.instance.isRussian
                    ? 'Начать с чистого холста'
                    : 'Start with a blank canvas',
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
                subtitle: LocaleService.instance.isRussian
                    ? 'Открыть сохранённый рисунок'
                    : 'Open a saved drawing',
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
    final mode = petalLabel == 'Days'
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

  /// пїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅ.
  void _showMoodPickerForDate(DateTime date) {
    showMoodPickerForDate(
      context: context,
      date: date,
      pairData: _pairData,
      moodService: _moodService,
      widgetService: _widgetService,
      primary: primary,
      navActiveIcon: _t.navActiveIcon, // РґРѕР±Р°РІР»РµРЅРѕ
    );
  }

  void _showMoodPicker() {
    showMoodPicker(
      context: context,
      pairData: _pairData,
      moodService: _moodService,
      widgetService: _widgetService,
      primary: primary,
      navActiveIcon: _t.navActiveIcon, // РґРѕР±Р°РІР»РµРЅРѕ
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
                          LocaleService.instance.isRussian
                              ? 'Новое фото'
                              : 'New Photo',
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
                        hintText: LocaleService.instance.isRussian
                            ? 'Заголовок…'
                            : 'Title…',
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
                        hintText: LocaleService.instance.isRussian
                            ? 'Описание (необязательно)…'
                            : 'Description (optional)…',
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
                            LocaleService.instance.isRussian
                                ? 'Фото дня на виджете'
                                : 'Set as widget photo',
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
  // EMPTY MEMORY LANE (shown when unpaired)
  // =============================================
  Widget _buildEmptyMemoryLane() {
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

  // =============================================
  // DAILY REFLECTION
  // =============================================
  Widget _buildDailyReflection() {
    final myUid = widget.userData.uid;

    final question =
        (_todayReflection?['question'] as String?) ?? _todayQuestion;
    final answers =
        (_todayReflection?['answers'] as Map<String, dynamic>?) ?? {};
    final myAnswer =
        (answers[myUid] as Map<String, dynamic>?)?['text'] as String?;
    final btnColor = _t.promptButtonColor;

    // -- Success state --
    if (_reflectionJustSaved) {
      return Container(
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: btnColor, size: 22),
            const SizedBox(width: 10),
            Text(
              LocaleService.current.answerSent,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: btnColor,
              ),
            ),
          ],
        ),
      );
    }

    // пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ (пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ)
    final partnerAnswers = answers.entries
        .where((e) => e.key != myUid)
        .toList();

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.auto_awesome, color: btnColor, size: 20),
              const SizedBox(width: 8),
              Text(
                LocaleService.current.dailyReflection,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: btnColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  LocaleService.current.today,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: btnColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Question
          Text(
            '"$question"',
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade600,
              height: 1.6,
            ),
          ),
          // My answer (if answered)
          if (myAnswer != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: btnColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: btnColor.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, color: btnColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      myAnswer,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showReflectionInput(question, myAnswer),
                    child: Icon(
                      Icons.edit_rounded,
                      size: 16,
                      color: btnColor.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Partner answers
          for (final e in partnerAnswers) ...[
            const SizedBox(height: 10),
            _buildPartnerAnswer(e.value as Map<String, dynamic>, btnColor),
          ],
          const SizedBox(height: 20),
          // Buttons row
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => _showReflectionInput(question, myAnswer),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: btnColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                      shadowColor: btnColor.withOpacity(0.25),
                    ),
                    child: Text(
                      myAnswer == null
                          ? LocaleService.current.answerPrompt
                          : LocaleService.current.editAnswer,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showReflection = false;
                    _reflectionManuallyDismissed = true;
                  });
                  _markReflectionAnsweredToday();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerAnswer(Map<String, dynamic> data, Color color) {
    final text = data['text'] as String? ?? '';
    final name = data['authorName'] as String? ?? LocaleService.current.partner;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withOpacity(0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showReflectionInput(String question, String? existing) {
    final controller = TextEditingController(text: existing ?? '');
    final btnColor = _t.promptButtonColor;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: btnColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    LocaleService.current.dailyReflection,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '"$question"',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade500,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                style: const TextStyle(fontSize: 14, height: 1.6),
                decoration: InputDecoration(
                  hintText: LocaleService.current.shareYourThoughts,
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: btnColor, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(context);
                    await _fb.saveReflectionAnswer(
                      groupId: _pairData.pairId,
                      question: question,
                      answer: text,
                      authorName: widget.userData.displayName,
                    );
                    // пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅ пїЅпїЅпїЅпїЅпїЅ пїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅпїЅ пїЅпїЅпїЅпїЅпїЅпїЅ
                    await _markReflectionAnsweredToday();
                    if (mounted) {
                      setState(() => _reflectionJustSaved = true);
                      await Future.delayed(const Duration(seconds: 1));
                      if (mounted) {
                        setState(() {
                          _reflectionJustSaved = false;
                          _showReflection = false;
                        });
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: btnColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    LocaleService.current.save,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =============================================
  // ACTION BUTTONS
  // =============================================
  Widget _buildActionButtons() {
    const drawSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M21.731 2.269a2.625 2.625 0 0 0-3.712 0l-1.157 1.157 3.712 3.712 1.157-1.157a2.625 2.625 0 0 0 0-3.712ZM19.513 8.199l-3.712-3.712-8.4 8.4a5.25 5.25 0 0 0-1.32 2.214l-.8 2.685a.75.75 0 0 0 .933.933l2.685-.8a5.25 5.25 0 0 0 2.214-1.32l8.4-8.4Z" />\n  <path d="M5.25 5.25a3 3 0 0 0-3 3v10.5a3 3 0 0 0 3 3h10.5a3 3 0 0 0 3-3V13.5a.75.75 0 0 0-1.5 0v5.25a1.5 1.5 0 0 1-1.5 1.5H5.25a1.5 1.5 0 0 1-1.5-1.5V8.25a1.5 1.5 0 0 1 1.5-1.5h5.25a.75.75 0 0 0 0-1.5H5.25Z" />\n</svg>';

    const moodSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path fill-rule="evenodd" d="M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25Zm-2.625 6c-.54 0-.828.419-.936.634a1.96 1.96 0 0 0-.189.866c0 .298.059.605.189.866.108.215.395.634.936.634.54 0 .828-.419.936-.634.13-.26.189-.568.189-.866 0-.298-.059-.605-.189-.866-.108-.215-.395-.634-.936-.634Zm4.314.634c.108-.215.395-.634.936-.634.54 0 .828.419.936.634.13.26.189.568.189.866 0 .298-.059.605-.189.866-.108.215-.395.634-.936.634-.54 0-.828-.419-.936-.634a1.96 1.96 0 0 1-.189-.866c0-.298.059-.605.189-.866Zm2.023 6.828a.75.75 0 1 0-1.06-1.06 3.75 3.75 0 0 1-5.304 0 .75.75 0 0 0-1.06 1.06 5.25 5.25 0 0 0 7.424 0Z" clip-rule="evenodd" />\n</svg>';

    const calendarSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M12.75 12.75a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM7.5 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM8.25 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM9.75 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM10.5 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM12 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM12.75 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM14.25 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM15 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM16.5 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM15 12.75a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM16.5 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z" />\n  <path fill-rule="evenodd" d="M6.75 2.25A.75.75 0 0 1 7.5 3v1.5h9V3A.75.75 0 0 1 18 3v1.5h.75a3 3 0 0 1 3 3v11.25a3 3 0 0 1-3 3H5.25a3 3 0 0 1-3-3V7.5a3 3 0 0 1 3-3H6V3a.75.75 0 0 1 .75-.75Zm13.5 9a1.5 1.5 0 0 0-1.5-1.5H5.25a1.5 1.5 0 0 0-1.5 1.5v7.5a1.5 1.5 0 0 0 1.5 1.5h13.5a1.5 1.5 0 0 0 1.5-1.5v-7.5Z" clip-rule="evenodd" />\n</svg>';

    const postSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M12 9a3.75 3.75 0 1 0 0 7.5A3.75 3.75 0 0 0 12 9Z" />\n  <path fill-rule="evenodd" d="M9.344 3.071a49.52 49.52 0 0 1 5.312 0c.967.052 1.83.585 2.332 1.39l.821 1.317c.24.383.645.643 1.11.71.386.054.77.113 1.152.177 1.432.239 2.429 1.493 2.429 2.909V18a3 3 0 0 1-3 3h-15a3 3 0 0 1-3-3V9.574c0-1.416.997-2.67 2.429-2.909.382-.064.766-.123 1.151-.178a1.56 1.56 0 0 0 1.11-.71l.822-1.315a2.942 2.942 0 0 1 2.332-1.39ZM6.75 12.75a5.25 5.25 0 1 1 10.5 0 5.25 5.25 0 0 1-10.5 0Zm12-1.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z" clip-rule="evenodd" />\n</svg>';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _pillActionButton(index: 0, svgIcon: drawSvg, onTap: _openDraw),
        const SizedBox(width: 10),
        _pillActionButton(
          index: 1,
          svgIcon: moodSvg,
          enabled: _pairData.isPaired,
          onTap: _showMoodPicker,
          moodImagePath: _pairData.myMood.imagePath,
        ),
        const SizedBox(width: 10),
        _pillActionButton(
          index: 2,
          svgIcon: calendarSvg,
          enabled: _pairData.isPaired,
          onTap: _openMoodCalendar,
        ),
        const SizedBox(width: 10),
        _pillActionButton(
          index: 3,
          svgIcon: postSvg,
          enabled: _pairData.isPaired,
          onTap: _postPhoto,
        ),
      ],
    );
  }

  Widget _pillActionButton({
    required int index,
    required String svgIcon,
    bool enabled = true,
    VoidCallback? onTap,
    String? moodImagePath,
  }) {
    final opacity = enabled ? 1.0 : 0.4;
    final hasMoodImage = moodImagePath != null && moodImagePath.isNotEmpty;

    // РўРѕС‡РЅС‹Р№ РёР·РіРёР± РєР°Рє РІ РєР°Р»РµРЅРґР°СЂРµ (РїР°СЂР°Р±РѕР»Р° 11px): С†РµРЅС‚СЂ РЅРёР¶Рµ РєСЂР°РµРІ в€Є
    // РЎРјРµС‰РµРЅРёРµ dy РІ РїРёРєСЃРµР»СЏС….
    final double dy = (index == 1 || index == 2) ? 11.0 : 0.0;

    return Transform.translate(
      offset: Offset(0, dy),
      child: Opacity(
        opacity: opacity,
        child: QuickTapScale(
          onTap: enabled ? (onTap ?? () {}) : null,
          scale: 0.92,
          child: Container(
            width: 74,
            height: 118,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Center(
              child: SizedBox(
                width: 30,
                height: 30,
                child: hasMoodImage
                    ? Image.asset(
                        moodImagePath,
                        width: 30,
                        height: 30,
                        errorBuilder: (_, __, ___) =>
                            _buildSvgIcon(svgIcon, 30, _t.navActiveIcon),
                      )
                    : _buildSvgIcon(svgIcon, 30, _t.navActiveIcon),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =============================================
  // RELATIONSHIP MEMORY LANE
  // =============================================
  Widget _buildMemoryLaneSection() {
    final tileBuilder = MemoryTileBuilder(
      primary: primary,
      cardSurface: Colors.white,
      cardBorder: const Color(0xFFE5E5E5),
    );

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
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          MemoryLaneScreen(pairData: _pairData, theme: _t),
                    ),
                  );
                },
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
        if (_recentMemories.isEmpty)
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
                for (int i = 0; i < _recentMemories.length && i < 3; i++)
                  _buildHomePreviewTile(tileBuilder, _recentMemories[i]),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Builds a single memory tile in the home preview ───────────────────────
  // Music → full inline player; text → note detail sheet; others → open Memory Lane
  Widget _buildHomePreviewTile(MemoryTileBuilder tileBuilder, Memory memory) {
    final distanceText = memory.latitude != null && memory.longitude != null
        ? _distanceKm(memory.latitude!, memory.longitude!)
        : null;

    if (memory.type == MemoryType.music) {
      return tileBuilder.buildTile(
        memory,
        musicPlayerWidget: MemoryMusicPlayer(memory: memory, theme: _t),
      );
    }

    if (memory.type == MemoryType.text) {
      return tileBuilder.buildTile(
        memory,
        onTap: () => _showHomeNoteDetail(memory),
        onOpenLocation: _openLocationInMaps,
        distanceText: distanceText,
      );
    }

    return tileBuilder.buildTile(
      memory,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MemoryLaneScreen(pairData: _pairData, theme: _t),
          ),
        );
      },
      onOpenGallery: (urls, index) {
        Navigator.of(context).push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black,
            pageBuilder: (_, __, ___) =>
                FullscreenGallery(urls: urls, initialIndex: index),
          ),
        );
      },
      onOpenLocation: _openLocationInMaps,
      distanceText: distanceText,
    );
  }

  // ─── Note detail bottom sheet ───────────────────────────────────────────────
  void _showHomeNoteDetail(Memory memory) {
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
                // Header
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

  Widget _buildBottomNavContent() {
    final s = LocaleService.current;
    const homeIcon =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M11.47 3.841a.75.75 0 0 1 1.06 0l8.69 8.69a.75.75 0 1 0 1.06-1.061l-8.689-8.69a2.25 2.25 0 0 0-3.182 0l-8.69 8.69a.75.75 0 1 0 1.061 1.06l8.69-8.689Z" />\n  <path d="m12 5.432 8.159 8.159c.03.03.06.058.091.086v6.198c0 1.035-.84 1.875-1.875 1.875H15a.75.75 0 0 1-.75-.75v-4.5a.75.75 0 0 0-.75-.75h-3a.75.75 0 0 0-.75.75V21a.75.75 0 0 1-.75.75H5.625a1.875 1.875 0 0 1-1.875-1.875v-6.198a2.29 2.29 0 0 0 .091-.086L12 5.432Z" />\n</svg>';

    const invitesIcon =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M4.913 2.658c2.075-.27 4.19-.408 6.337-.408 2.147 0 4.262.139 6.337.408 1.922.25 3.291 1.861 3.405 3.727a4.403 4.403 0 0 0-1.032-.211 50.89 50.89 0 0 0-8.42 0c-2.358.196-4.04 2.19-4.04 4.434v4.286a4.47 4.47 0 0 0 2.433 3.984L7.28 21.53A.75.75 0 0 1 6 21v-4.03a48.527 48.527 0 0 1-1.087-.128C2.905 16.58 1.5 14.833 1.5 12.862V6.638c0-1.97 1.405-3.718 3.413-3.979Z" />\n  <path d="M15.75 7.5c-1.376 0-2.739.057-4.086.169C10.124 7.797 9 9.103 9 10.609v4.285c0 1.507 1.128 2.814 2.67 2.94 1.243.102 2.5.157 3.768.165l2.782 2.781a.75.75 0 0 0 1.28-.53v-2.39l.33-.026c1.542-.125 2.67-1.433 2.67-2.94v-4.286c0-1.505-1.125-2.811-2.664-2.94A49.392 49.392 0 0 0 15.75 7.5Z" />\n</svg>';

    const profileIcon =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path fill-rule="evenodd" d="M18.685 19.097A9.723 9.723 0 0 0 21.75 12c0-5.385-4.365-9.75-9.75-9.75S2.25 6.615 2.25 12a9.723 9.723 0 0 0 3.065 7.097A9.716 9.716 0 0 0 12 21.75a9.716 9.716 0 0 0 6.685-2.653Zm-12.54-1.285A7.486 7.486 0 0 1 12 15a7.486 7.486 0 0 1 5.855 2.812A8.224 8.224 0 0 1 12 20.25a8.224 8.224 0 0 1-5.855-2.438ZM15.75 9a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z" clip-rule="evenodd" />\n</svg>';

    const widgetsIcon =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M5.566 4.657A4.505 4.505 0 0 1 6.75 4.5h10.5c.41 0 .806.055 1.183.157A3 3 0 0 0 15.75 3h-7.5a3 3 0 0 0-2.684 1.657ZM2.25 12a3 3 0 0 1 3-3h13.5a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3H5.25a3 3 0 0 1-3-3v-6ZM5.25 7.5c-.41 0-.806.055-1.184.157A3 3 0 0 1 6.75 6h10.5a3 3 0 0 1 2.683 1.657A4.505 4.505 0 0 0 18.75 7.5H5.25Z" />\n</svg>';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 32,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: _t.primary.withValues(alpha: 0.05),
              blurRadius: 12,
              spreadRadius: -2,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                NavBarItem(
                  svgIcon: homeIcon,
                  index: 0,
                  label: s.home,
                  isActive: _selectedNavIndex == 0,
                  activeColor: _t.navActiveIcon,
                  activeBg: _t.navActiveIcon.withOpacity(0.12),
                  inactiveColor: _t.timerDialBackground,
                  badgeColor: primary,
                  onTap: () => setState(() => _selectedNavIndex = 0),
                ),
                NavBarItem(
                  svgIcon: widgetsIcon,
                  index: 1,
                  label: s.widgets,
                  isActive: _selectedNavIndex == 1,
                  activeColor: _t.navActiveIcon,
                  activeBg: _t.navActiveIcon.withOpacity(0.12),
                  inactiveColor: _t.timerDialBackground,
                  badgeColor: primary,
                  onTap: () => setState(() => _selectedNavIndex = 1),
                ),
                NavBarItem(
                  svgIcon: invitesIcon,
                  index: 2,
                  label: s.connect,
                  isActive: _selectedNavIndex == 2,
                  activeColor: _t.navActiveIcon,
                  activeBg: _t.navActiveIcon.withOpacity(0.12),
                  inactiveColor: _t.timerDialBackground,
                  badgeColor: primary,
                  showBadge: !_pairData.isPaired,
                  onTap: () => setState(() => _selectedNavIndex = 2),
                ),
                NavBarItem(
                  svgIcon: profileIcon,
                  index: 3,
                  label: s.profile,
                  isActive: _selectedNavIndex == 3,
                  activeColor: _t.navActiveIcon,
                  activeBg: _t.navActiveIcon.withOpacity(0.12),
                  inactiveColor: _t.timerDialBackground,
                  badgeColor: primary,
                  onTap: () => setState(() => _selectedNavIndex = 3),
                ),
              ],
            ),
          ),
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

  /// Calculate distance in km between user and a point
  String _distanceKm(double lat, double lng) {
    if (_userLat == null || _userLng == null) return '';
    final d = Geolocator.distanceBetween(_userLat!, _userLng!, lat, lng);
    if (d < 1000) return '${d.round()}m';
    return '${(d / 1000).toStringAsFixed(1)}km';
  }

  /// Open location in external maps app (geo: URI triggers app chooser)
  Future<void> _openLocationInMaps(
    double lat,
    double lng,
    String? label,
  ) async {
    final query = label != null ? Uri.encodeComponent(label) : '$lat,$lng';
    // geo: URI works on Android; on iOS fallback to Apple Maps
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($query)');
    final appleMapsUri = Uri.parse(
      'https://maps.apple.com/?q=$query&ll=$lat,$lng',
    );

    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
    } else if (await canLaunchUrl(appleMapsUri)) {
      await launchUrl(appleMapsUri, mode: LaunchMode.externalApplication);
    } else {
      // Fallback to Google Maps web
      final webUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  /// Helper method to build SVG icon from string
  Widget _buildSvgIcon(String svgString, double size, Color color) {
    return SvgPicture.string(
      svgString,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
