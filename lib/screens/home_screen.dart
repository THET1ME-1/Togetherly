import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'connect_partner_screen.dart';
import 'expandable_timer_card.dart';
import 'memory_lane_screen.dart';
import 'mini_mood_calendar.dart';
import 'mood_calendar_screen.dart';
import 'profile_screen.dart';
import '../services/mood_service.dart';
import '../services/timer_service.dart';
import '../services/widget_service.dart';
import 'widget_screen.dart';

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
  Timer? _timer;
  StreamSubscription? _deepLinkSub;

  // -- Pair data --
  final PairData _pairData = PairData();
  bool _pairLoading = true;

  // -- Timer service --
  final TimerService _timerService = TimerService();
  bool _timerCardExpanded = false;

  // -- Mood service --
  final MoodService _moodService = MoodService();

  // -- Widget service --
  final WidgetService _widgetService = WidgetService();

  // -- Memory Lane real-time --
  final FirebaseService _fb = FirebaseService();
  List<Memory> _recentMemories = [];
  StreamSubscription? _memorySub;

  // -- Daily Reflection --
  Map<String, dynamic>? _todayReflection;
  StreamSubscription? _reflectionSub;
  bool _reflectionJustSaved = false;

  static const _reflectionQuestions = <String>[]; // replaced by locale

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

    // Dynamic timer - only start when needed (Time mode)
    _startTimerIfNeeded();

    // Check if launched from homescreen widget → open Widgets tab
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
    if (mounted) setState(() => _pairLoading = false);
  }

  /// Проверяем, открыто ли приложение по клику на виджет
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

  /// Обработка клика по виджету пока приложение работает
  void _onWidgetClicked(Uri? uri) {
    if (uri != null) {
      _handleWidgetUri(uri);
    }
  }

  void _handleWidgetUri(Uri uri) {
    // loveapp://widgets → переключаемся на вкладку виджетов (index 1)
    if (uri.host == 'widgets' || uri.toString().contains('widgets')) {
      if (mounted) {
        setState(() => _selectedNavIndex = 1);
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
        }

        // Create system timer if it doesn't exist yet
        _timerService.createSystemTimer(
          startDate: _pairData.startDate!,
          relationshipLabel: _pairData.relationshipLabel,
          relationshipEmoji: _pairData.relationshipEmoji,
          partnerName: _pairData.partnerName,
        );
      } else {
        _timerService.unbindFromGroup();
      }

      setState(() {});
    }
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
          // Сохраняем в prefs, чтобы после перезапуска не показывать
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

  /// Слушаем MoodService — при любом изменении настроения за сегодня
  /// синхронизируем его в pairData (аватарка, видимость партнёру).
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
    if (mounted) setState(() {});
  }

  /// Ключ для SharedPreferences: уникален для каждого пользователя + дня
  String get _reflectionPrefKey {
    final today = DateTime.now();
    final dateStr =
        '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    return 'reflection_answered_${widget.userData.uid}_$dateStr';
  }

  /// Загружает из SharedPreferences — отвечал ли пользователь сегодня
  Future<void> _loadReflectionState() async {
    final prefs = await SharedPreferences.getInstance();
    final answeredToday = prefs.getBool(_reflectionPrefKey) ?? false;
    if (mounted) setState(() => _showReflection = !answeredToday);
  }

  /// Сохраняет в SharedPreferences, что пользователь ответил сегодня
  Future<void> _markReflectionAnsweredToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reflectionPrefKey, true);
  }

  // -- Computed Values --
  String get _counterValue {
    if (!_pairData.isPaired) return '0';
    final start = _pairData.startDate!;
    final now = DateTime.now();
    switch (_selectedTimeUnit) {
      case 0:
        return now.difference(start).inDays.toString();
      case 1:
        int months = (now.year - start.year) * 12 + now.month - start.month;
        if (now.day < start.day) months--;
        return months.toString();
      case 2:
        final diff = now.difference(start);
        final d = diff.inDays;
        final h = diff.inHours % 24;
        final m = diff.inMinutes % 60;
        final s = diff.inSeconds % 60;
        if (d > 0) return '${d}d ${h}h ${m}m';
        if (h > 0) return '${h}h ${m}m ${s}s';
        return '${m}m ${s}s';
      default:
        return '0';
    }
  }

  String get _counterLabel {
    final s = LocaleService.current;
    if (!_pairData.isPaired) return s.waitingForConnection;
    final suffix = _pairData.relationshipType == RelationshipType.couple
        ? s.inLove
        : s.together;
    switch (_selectedTimeUnit) {
      case 0:
        return s.daysLabel(suffix);
      case 1:
        return s.monthsLabel(suffix);
      case 2:
        return s.timeLabel(suffix);
      default:
        return s.daysLabel(suffix);
    }
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
              child: DecoratedBox(
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
            bottom: MediaQuery.of(context).padding.bottom + 12,
            left: 24,
            right: 24,
            child: AnimatedOpacity(
              opacity: _timerCardExpanded ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: _timerCardExpanded,
                child: _buildBottomNavContent(),
              ),
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
      physics: _timerCardExpanded
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
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
                MiniMoodCalendar(
                  moodService: _moodService,
                  theme: _t,
                  onDayTap: _showMoodPickerForDate,
                ),
                const SizedBox(height: 8),
                ExpandableTimerCard(
                  theme: _t,
                  timerService: _timerService,
                  myAvatarUrl: widget.userData.avatarUrl,
                  partnerAvatarUrl: _pairData.partnerAvatarUrl,
                  isPaired: _pairData.isPaired,
                  onExpandChanged: (expanded) {
                    setState(() => _timerCardExpanded = expanded);
                  },
                ),
                if (_pairData.isPaired && _showReflection) ...[
                  const SizedBox(height: 32),
                  _buildDailyReflection(),
                ],
                if (!_pairData.isPaired) ...[
                  const SizedBox(height: 32),
                  _buildConnectPrompt(),
                ],
                const SizedBox(height: 32),
                _buildActionButtons(),
                const SizedBox(height: 40),
              ],
            ),
          ),
          if (_pairData.isPaired) _buildMemoryLaneSection(),
          if (!_pairData.isPaired) _buildEmptyMemoryLane(),
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
      pairData: _pairData,
      widgetService: _widgetService,
      moodService: _moodService,
      theme: _t,
    );
  }

  // =============================================
  // PROFILE TAB
  // =============================================
  Widget _buildProfileTab() {
    return ProfileScreen(userData: widget.userData, pairData: _pairData);
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
                      moodPosition: _MoodBadgePosition.topLeft,
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
                        moodPosition: _MoodBadgePosition.bottomRight,
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
          const SizedBox(width: 12),
          // Badge — tappable to change relationship type
          GestureDetector(
            onTap: _pairData.isPaired ? _showRelationshipTypeDialog : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    const SizedBox(width: 5),
                  ] else ...[
                    Icon(
                      Icons.favorite_border,
                      color: Colors.grey.shade400,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
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
            ? Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: 120,
                cacheHeight: 120,
                errorBuilder: (_, __, ___) => _avatarPlaceholder(name),
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
    _MoodBadgePosition moodPosition = _MoodBadgePosition.bottomRight,
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
              top: moodPosition == _MoodBadgePosition.topLeft ? -4 : null,
              bottom: moodPosition == _MoodBadgePosition.bottomRight
                  ? -4
                  : null,
              left: moodPosition == _MoodBadgePosition.topLeft ? -4 : null,
              right: moodPosition == _MoodBadgePosition.bottomRight ? -4 : null,
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
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final customTypes = _pairData.customRelationshipTypes;
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        LocaleService.current.relationshipStatus,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        LocaleService.current.chooseHowToConnect,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildRelationshipOption(
                        type: RelationshipType.couple,
                        icon: '❤️',
                        title: LocaleService.current.inLoveStatus,
                        subtitle: LocaleService.current.perfectForCouples,
                      ),
                      const SizedBox(height: 12),
                      _buildRelationshipOption(
                        type: RelationshipType.married,
                        icon: '💍',
                        title: LocaleService.current.married,
                        subtitle: LocaleService.current.forMarriedPartners,
                      ),
                      const SizedBox(height: 12),
                      _buildRelationshipOption(
                        type: RelationshipType.friends,
                        icon: '🤝',
                        title: LocaleService.current.friends,
                        subtitle: LocaleService.current.connectWithBestFriend,
                      ),
                      const SizedBox(height: 12),
                      _buildRelationshipOption(
                        type: RelationshipType.buddies,
                        icon: '👯',
                        title: LocaleService.current.bestBuddies,
                        subtitle:
                            LocaleService.current.forInseparableCompanions,
                      ),
                      // Custom relationship types
                      ...customTypes.map((entry) {
                        final isSelected =
                            _pairData.relationshipType ==
                                RelationshipType.custom &&
                            _pairData.relationshipLabel == entry['label'];
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _buildCustomRelTypeOption(
                            entry: entry,
                            isSelected: isSelected,
                            onSelect: () {
                              _pairData.setRelationshipType(
                                RelationshipType.custom,
                                label: entry['label'] ?? '',
                                emoji: entry['emoji'] ?? '✨',
                              );
                              Navigator.of(ctx).pop();
                              setState(() {});
                            },
                            onEdit: () {
                              Navigator.of(ctx).pop();
                              _showEditCustomRelTypeDialog(entry);
                            },
                            onDelete: () async {
                              await _pairData.deleteCustomRelationshipType(
                                entry['id'] ?? '',
                              );
                              setDialogState(() {});
                              setState(() {});
                            },
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      // Add custom type button
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showAddCustomRelTypeDialog();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(LocaleService.current.addCustomStatus),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 20,
                          ),
                          side: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRelationshipOption({
    required RelationshipType type,
    required String icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _pairData.relationshipType == type;
    return GestureDetector(
      onTap: () {
        _pairData.setRelationshipType(type);
        Navigator.of(context).pop();
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? primary.withOpacity(0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? primary : Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: primary, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomRelTypeOption({
    required Map<String, String> entry,
    required bool isSelected,
    required VoidCallback onSelect,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? primary.withOpacity(0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(entry['emoji'] ?? '✨', style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                entry['label'] ?? 'Custom',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? primary : Colors.grey.shade800,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: primary, size: 24),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onEdit,
              child: Icon(Icons.edit, size: 18, color: Colors.blue.shade400),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCustomRelTypeDialog() {
    final labelCtrl = TextEditingController();
    final emojiCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(LocaleService.current.addCustomStatus),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emojiCtrl,
              decoration: InputDecoration(
                labelText: LocaleService.current.emoji,
                hintText: '💕',
              ),
              maxLength: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelCtrl,
              decoration: InputDecoration(
                labelText: LocaleService.current.label,
                hintText: LocaleService.current.egSoulmates,
              ),
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(LocaleService.current.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final label = labelCtrl.text.trim();
              final emoji = emojiCtrl.text.trim();
              if (label.isNotEmpty) {
                await _pairData.addCustomRelationshipType(
                  label,
                  emoji.isNotEmpty ? emoji : '✨',
                );
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                  _showRelationshipTypeDialog();
                }
              }
            },
            child: Text(LocaleService.current.add),
          ),
        ],
      ),
    );
  }

  void _showEditCustomRelTypeDialog(Map<String, String> entry) {
    final labelCtrl = TextEditingController(text: entry['label'] ?? '');
    final emojiCtrl = TextEditingController(text: entry['emoji'] ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(LocaleService.current.editCustomStatus),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emojiCtrl,
              decoration: InputDecoration(
                labelText: LocaleService.current.emoji,
                hintText: '💕',
              ),
              maxLength: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelCtrl,
              decoration: InputDecoration(
                labelText: LocaleService.current.label,
                hintText: LocaleService.current.egSoulmates,
              ),
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(LocaleService.current.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final label = labelCtrl.text.trim();
              final emoji = emojiCtrl.text.trim();
              if (label.isNotEmpty) {
                await _pairData.updateCustomRelationshipType(
                  entry['id'] ?? '',
                  label,
                  emoji.isNotEmpty ? emoji : '✨',
                );
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                  _showRelationshipTypeDialog();
                }
              }
            },
            child: Text(LocaleService.current.save),
          ),
        ],
      ),
    );
  }

  // =============================================
  // MOOD PICKER
  // =============================================

  void _openMoodCalendar() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MoodCalendarScreen(
          pairData: _pairData,
          moodService: _moodService,
          widgetService: _widgetService,
        ),
      ),
    );
  }

  /// Открыть выбор настроения для конкретной даты.
  void _showMoodPickerForDate(DateTime date) {
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);
    // Запрет выбора настроения на будущие даты
    if (date.isAfter(todayNorm)) return;
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    // Найти уже выбранное настроение на эту дату
    final existingEntries = _moodService.myEntriesForDay(date);
    final existingPath = existingEntries.isNotEmpty
        ? existingEntries.first.imagePath
        : '';

    // Формат заголовка: «Сегодня» или «Пн, 18 фев»
    final _s = LocaleService.current;
    final months = _s.shortMonths;
    final weekdays = _s.shortWeekdays;
    final dateLabel = isToday
        ? _s.todayDate
        : '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
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
                _s.moodDateLabel(dateLabel),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isToday ? _s.partnerWillSeeMood : _s.indicateMoodForDay,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: MoodOption.all.length,
                  itemBuilder: (ctx2, i) {
                    final mood = MoodOption.all[i];
                    final isSelected = existingPath == mood.imagePath;
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx2);
                        if (isToday) {
                          _pairData.setMood(mood.imagePath, mood.label);
                          _widgetService.updateMood(mood.imagePath, mood.label);
                        }
                        _moodService.addMood(
                          moodId: mood.id,
                          imagePath: mood.imagePath,
                          label: mood.label,
                          date: date,
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primary.withOpacity(0.12)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? primary : Colors.grey.shade200,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (mood.imagePath.isNotEmpty)
                              Image.asset(
                                mood.imagePath,
                                width: 44,
                                height: 44,
                                errorBuilder: (context, error, stackTrace) =>
                                    const SizedBox(width: 44, height: 44),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              mood.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? primary
                                    : Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (existingPath.isNotEmpty) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    // Удаляем запись за этот день
                    for (final e in _moodService.myEntriesForDay(date)) {
                      await _moodService.deleteMoodEntry(e.id);
                    }
                    if (isToday) {
                      _pairData.clearMood();
                      _widgetService.clearMood();
                    }
                  },
                  child: Text(
                    _s.removeMood,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showMoodPicker() {
    // Единый источник истины — MoodService (сегодняшняя запись)
    final today = DateTime.now();
    final todayEntries = _moodService.myEntriesForDay(today);
    final currentEmoji = todayEntries.isNotEmpty
        ? todayEntries.first.imagePath
        : _pairData.myMood.imagePath;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
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
                LocaleService.current.howAreYouFeeling,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                LocaleService.current.partnerWillSeeMood,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),
              // Mood grid — scrollable
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: MoodOption.all.length,
                  itemBuilder: (ctx2, i) {
                    final mood = MoodOption.all[i];
                    final isSelected = currentEmoji == mood.imagePath;
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx2);
                        // Сначала удаляем предыдущие записи за сегодня,
                        // чтобы не было дублей в moodService
                        for (final e in _moodService.myEntriesForDay(today)) {
                          _moodService.deleteMoodEntry(e.id);
                        }
                        _pairData.setMood(mood.imagePath, mood.label);
                        _moodService.addMood(
                          moodId: mood.id,
                          imagePath: mood.imagePath,
                          label: mood.label,
                        );
                        _widgetService.updateMood(mood.imagePath, mood.label);
                      },
                      // _onMoodServiceChanged подхватит изменение и обновит pairData
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primary.withOpacity(0.12)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? primary : Colors.grey.shade200,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (mood.imagePath.isNotEmpty)
                              Image.asset(
                                mood.imagePath,
                                width: 44,
                                height: 44,
                                errorBuilder: (context, error, stackTrace) =>
                                    const SizedBox(width: 44, height: 44),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              mood.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? primary
                                    : Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Clear mood button
              if (currentEmoji.isNotEmpty) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    // Удаляем из всех хранилищ
                    for (final e in _moodService.myEntriesForDay(today)) {
                      await _moodService.deleteMoodEntry(e.id);
                    }
                    _pairData.clearMood();
                    _widgetService.clearMood();
                  },
                  child: Text(
                    LocaleService.current.clearMood,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // =============================================
  // POST PHOTO (camera → upload → Memory Lane)
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

    // Show caption dialog
    final caption = await _showCaptionDialog();
    if (!mounted) return;

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
                CircularProgressIndicator(color: primary),
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
        caption: caption,
      );

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

  Future<String?> _showCaptionDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LocaleService.current.addCaption,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                LocaleService.current.optionalDescribe,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: LocaleService.current.writeSmth,
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, null),
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
                        final text = controller.text.trim();
                        Navigator.pop(ctx, text.isEmpty ? null : text);
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
      ),
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
  // COUNTER CARD (Glass morphism)
  // =============================================
  Widget _buildCounterCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 32,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 260),
        decoration: BoxDecoration(
          color: const Color(0x99FFFFFF),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0x4DFFFFFF)),
        ),
        child: Stack(
          children: [
            // -- Gradient overlay --
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.15),
                      Colors.white.withOpacity(0.5),
                    ],
                  ),
                ),
              ),
            ),
            // -- Content --
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Counter number
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        key: ValueKey('$_selectedTimeUnit-$_counterValue'),
                        child: Text(
                          _counterValue,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: _selectedTimeUnit == 2 ? 42 : 64,
                            fontWeight: FontWeight.w800,
                            color: _pairData.isPaired
                                ? const Color(0xFF1A1A1A)
                                : Colors.grey.shade300,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Counter label
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _counterLabel,
                        key: ValueKey(_counterLabel),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _pairData.isPaired
                              ? primary
                              : Colors.grey.shade400,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                    // Partner mood display
                    if (_pairData.isPaired &&
                        _pairData.partnerMood.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
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
                            if (_pairData.partnerMood.imagePath.isNotEmpty)
                              Image.asset(
                                _pairData.partnerMood.imagePath,
                                width: 28,
                                height: 28,
                                errorBuilder: (context, error, stackTrace) =>
                                    const SizedBox(width: 28, height: 28),
                              ),
                            const SizedBox(width: 8),
                            Text(
                              '${_pairData.partnerName} is ${_pairData.partnerMood.label}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                    // Toggle
                    _buildTimeToggle(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoFragment(String url, double w, double h, double angle) {
    return Transform.rotate(
      angle: angle,
      child: Opacity(
        opacity: 0.12,
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.grey,
            BlendMode.saturation,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: w,
              height: h,
              fit: BoxFit.cover,
              cacheWidth: (w * 2).toInt(),
              cacheHeight: (h * 2).toInt(),
              errorBuilder: (_, __, ___) => SizedBox(width: w, height: h),
            ),
          ),
        ),
      ),
    );
  }

  // =============================================
  // TIME TOGGLE
  // =============================================
  Widget _buildTimeToggle() {
    const labels = <String>[]; // replaced by locale
    final localLabels = [
      LocaleService.current.days,
      LocaleService.current.months,
      LocaleService.current.time,
    ];
    return Container(
      height: 40,
      constraints: const BoxConstraints(maxWidth: 240),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / 3;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                left: _selectedTimeUnit * itemWidth,
                top: 0,
                bottom: 0,
                width: itemWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: List.generate(3, (i) {
                  final selected = _selectedTimeUnit == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedTimeUnit = i);
                        _startTimerIfNeeded();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Text(
                          localLabels[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected
                                ? Colors.grey.shade900
                                : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  // =============================================
  // DAILY REFLECTION
  // =============================================
  Widget _buildDailyReflection() {
    final myUid = widget.userData.uid;
    final myName = widget.userData.displayName;
    final question =
        (_todayReflection?['question'] as String?) ?? _todayQuestion;
    final answers =
        (_todayReflection?['answers'] as Map<String, dynamic>?) ?? {};
    final myAnswer =
        (answers[myUid] as Map<String, dynamic>?)?['text'] as String?;
    final btnColor = _t.promptButtonColor;

    // ── Success state ──
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

    // Собираем чужие ответы (партнёры)
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
                onTap: () => setState(() => _showReflection = false),
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
                    // Сохраняем факт ответа локально — чтобы не показывать завтра
                    await _markReflectionAnsweredToday();
                    if (mounted) {
                      setState(() => _reflectionJustSaved = true);
                      await Future.delayed(const Duration(seconds: 1));
                      if (mounted)
                        setState(() {
                          _reflectionJustSaved = false;
                          _showReflection = false;
                        });
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _actionButton(
          icon: Icons.brush_rounded,
          label: LocaleService.current.draw,
          iconColor: _t.iconDraw,
          enabled: _pairData.isPaired,
        ),
        _actionButton(
          icon: Icons.sentiment_satisfied_alt_rounded,
          label: LocaleService.current.mood,
          iconColor: _t.iconMood,
          enabled: _pairData.isPaired,
          onTap: _showMoodPicker,
          moodImagePath: _pairData.myMood.imagePath,
        ),
        _actionButton(
          icon: Icons.calendar_month_rounded,
          label: LocaleService.current.calendar,
          iconColor: _t.iconCalendar,
          enabled: _pairData.isPaired,
          onTap: _openMoodCalendar,
        ),
        _actionButton(
          icon: Icons.photo_camera_rounded,
          label: LocaleService.current.post,
          iconColor: _t.iconPost,
          enabled: _pairData.isPaired,
          onTap: _postPhoto,
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color iconColor,
    bool isPrimary = false,
    bool enabled = true,
    VoidCallback? onTap,
    String? badge,
    String? moodImagePath,
  }) {
    final opacity = enabled ? 1.0 : 0.4;
    final hasMoodImage = moodImagePath != null && moodImagePath.isNotEmpty;
    return Opacity(
      opacity: opacity,
      child: Column(
        children: [
          GestureDetector(
            onTap: enabled ? (onTap ?? () {}) : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: isPrimary ? primary : Colors.white,
                    shape: BoxShape.circle,
                    border: isPrimary
                        ? null
                        : Border.all(color: Colors.grey.shade100),
                    boxShadow: isPrimary
                        ? [
                            BoxShadow(
                              color: primary.withOpacity(0.25),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                            ),
                          ],
                  ),
                  child: hasMoodImage
                      ? Center(
                          child: Image.asset(
                            moodImagePath,
                            width: 38,
                            height: 38,
                            errorBuilder: (_, __, ___) =>
                                Icon(icon, color: iconColor, size: 28),
                          ),
                        )
                      : Icon(icon, color: iconColor, size: 28),
                ),
                if (badge != null)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
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
                      child: Text(badge, style: const TextStyle(fontSize: 14)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // =============================================
  // RELATIONSHIP MEMORY LANE
  // =============================================
  Widget _buildMemoryLaneSection() {
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
                child: Text(
                  LocaleService.current.viewAll,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: primary,
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
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _recentMemories.length,
              addAutomaticKeepAlives: false,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (_, i) => _memoryPreviewCard(_recentMemories[i]),
            ),
          ),
      ],
    );
  }

  Widget _memoryPreviewCard(Memory memory) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MemoryLaneScreen(pairData: _pairData, theme: _t),
          ),
        );
      },
      child: Container(
        width: 160,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE5E5E5), width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: _previewByType(memory),
        ),
      ),
    );
  }

  Widget _previewByType(Memory memory) {
    switch (memory.type) {
      case MemoryType.photo:
        return _photoPreview(memory);
      case MemoryType.video:
        return _videoPreview(memory);
      case MemoryType.location:
        return _locationPreview(memory);
      case MemoryType.music:
        return _musicPreview(memory);
      case MemoryType.text:
        return _textPreview(memory);
    }
  }

  Widget _photoPreview(Memory memory) {
    final hasImage = memory.imageUrl != null && memory.imageUrl!.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImage)
          Image.network(
            memory.imageUrl!,
            fit: BoxFit.cover,
            cacheWidth: 480,
            cacheHeight: 600,
            errorBuilder: (_, __, ___) =>
                Container(color: Colors.grey.shade200),
          )
        else
          Container(
            color: const Color(0xFFF3E8FF),
            child: Icon(
              Icons.image_rounded,
              size: 48,
              color: Colors.grey.shade300,
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
            ),
          ),
        ),
        Positioned(
          top: 10,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('📸', style: TextStyle(fontSize: 14)),
          ),
        ),
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: Text(
            memory.caption ?? LocaleService.current.photo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _videoPreview(Memory memory) {
    final hasThumb = memory.imageUrl != null && memory.imageUrl!.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasThumb)
          Image.network(
            memory.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: Colors.grey.shade900),
          )
        else
          Container(color: const Color(0xFF1E1B2E)),
        Container(color: Colors.black.withOpacity(0.45)),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              size: 28,
              color: Color(0xFFEC4899),
            ),
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEC4899),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              LocaleService.current.video.toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: Text(
            memory.caption ?? LocaleService.current.videoLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _locationPreview(Memory memory) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFF0FAF4)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F7ED),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: Color(0xFF22C55E),
              size: 22,
            ),
          ),
          const Spacer(),
          Text(
            memory.locationName ?? LocaleService.current.location,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          if (memory.latitude != null) ...[
            const SizedBox(height: 4),
            Text(
              '${memory.latitude!.toStringAsFixed(3)}, ${memory.longitude?.toStringAsFixed(3) ?? ""}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
          if (memory.caption != null && memory.caption!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              memory.caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            memory.authorName,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _musicPreview(Memory memory) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFF5F0FF)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (memory.musicCoverUrl != null &&
                  memory.musicCoverUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    memory.musicCoverUrl!,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFF8B5CF6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            memory.musicTitle ?? LocaleService.current.audio,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          if (memory.musicArtist != null)
            Text(
              memory.musicArtist!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          const SizedBox(height: 4),
          // Waveform placeholder
          Row(
            children: List.generate(
              12,
              (i) => Expanded(
                child: Container(
                  height:
                      4.0 +
                      (i % 3 == 0
                          ? 8.0
                          : i % 2 == 0
                          ? 4.0
                          : 6.0),
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            memory.authorName,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _textPreview(Memory memory) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFFFFBEB)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📝', style: TextStyle(fontSize: 22)),
          const Spacer(),
          Text(
            memory.caption ?? '',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade800,
              height: 1.4,
            ),
          ),
          const Spacer(),
          Text(
            memory.authorName,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  // =============================================
  // BOTTOM NAVIGATION
  // =============================================
  Widget _buildBottomNav() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 12,
      left: 24,
      right: 24,
      child: _buildBottomNavContent(),
    );
  }

  Widget _buildBottomNavContent() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xC7FFFFFF),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0x99FFFFFF)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _navItem(Icons.home_rounded, 0),
              _navItem(Icons.widgets_rounded, 1),
              Container(width: 1, height: 24, color: Colors.grey.shade200),
              _navItem(
                _pairData.isPaired
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.person_add_alt_1_rounded,
                2,
                showBadge: !_pairData.isPaired,
              ),
              _navItem(Icons.person_outline_rounded, 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, int index, {bool showBadge = false}) {
    final isActive = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedNavIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive ? _t.navActiveBg : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? _t.navActiveIcon : Colors.grey.shade400,
              size: 26,
            ),
          ),
          if (showBadge)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _MoodBadgePosition { topLeft, bottomRight }
