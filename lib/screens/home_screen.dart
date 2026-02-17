import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../models/memory.dart';
import '../models/pair_data.dart';
import '../models/user_data.dart';
import '../models/mood_entry.dart';
import '../services/deep_link_service.dart';
import '../services/firebase_service.dart';
import 'connect_partner_screen.dart';
import 'expandable_timer_card.dart';
import 'memory_lane_screen.dart';
import 'mood_calendar_screen.dart';
import 'profile_screen.dart';
import '../services/mood_service.dart';
import '../services/timer_service.dart';

class HomeScreen extends StatefulWidget {
  final UserData userData;
  const HomeScreen({super.key, required this.userData});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // -- Colors --
  Color get primary => widget.userData.themeAccent;
  Color get primaryLight => widget.userData.themeAccentLight;
  static const Color bgLight = Color(0xFFF8F6F6);

  // -- Cached painter --
  static final _bgPainter = _BgPatternPainter();

  // -- State --
  int _selectedTimeUnit = 0; // 0=Days, 1=Months, 2=Time
  int _selectedNavIndex = 0;
  bool _showReflection = true;
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

  // -- Memory Lane real-time --
  final FirebaseService _fb = FirebaseService();
  List<Memory> _recentMemories = [];
  StreamSubscription? _memorySub;

  @override
  void initState() {
    super.initState();
    _pairData.addListener(_onPairChanged);
    widget.userData.addListener(_onUserChanged);
    _timerService.init();
    _initPairData();

    // Dynamic timer - only start when needed (Time mode)
    _startTimerIfNeeded();

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
    _pairData.removeListener(_onPairChanged);
    widget.userData.removeListener(_onUserChanged);
    _pairData.dispose();
    super.dispose();
  }

  Future<void> _initPairData() async {
    await _pairData.init(myName: widget.userData.displayName);
    if (mounted) setState(() => _pairLoading = false);
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
      _startTimerIfNeeded();

      if (_pairData.isPaired && _pairData.startDate != null) {
        // Bind timer service to group for Firestore sync
        _timerService.bindToGroup(_pairData.pairId);

        // Bind mood service to group for Firestore sync
        _moodService.bindToGroup(_pairData.pairId);

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

  void _onUserChanged() {
    if (mounted) setState(() {});
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
    if (!_pairData.isPaired) return 'WAITING FOR CONNECTION';
    final suffix = _pairData.relationshipType == RelationshipType.couple
        ? 'IN LOVE'
        : 'TOGETHER';
    switch (_selectedTimeUnit) {
      case 0:
        return 'DAYS $suffix';
      case 1:
        return 'MONTHS $suffix';
      case 2:
        return 'TIME $suffix';
      default:
        return 'DAYS $suffix';
    }
  }

  String get _statusBadgeText {
    if (!_pairData.isPaired) return 'Solo';
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
              child: Container(
                color: bgLight,
                child: CustomPaint(painter: _bgPainter, size: Size.infinite),
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
        return ConnectPartnerScreen(pairData: _pairData);
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
    return Stack(
      children: [
        // Scrollable content behind the card
        SingleChildScrollView(
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
                    // Placeholder space for the timer card (16 top + 280 card)
                    const SizedBox(height: 296),
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
        ),
        // Expandable Timer Card overlay
        Positioned(
          top: 16,
          left: 24,
          right: 24,
          child: ExpandableTimerCard(
            primary: primary,
            primaryLight: primaryLight,
            timerService: _timerService,
            myAvatarUrl: widget.userData.avatarUrl,
            partnerAvatarUrl: _pairData.partnerAvatarUrl,
            isPaired: _pairData.isPaired,
            onExpandChanged: (expanded) {
              setState(() => _timerCardExpanded = expanded);
            },
          ),
        ),
      ],
    );
  }

  // =============================================
  // WIDGETS TAB (shared widgets — placeholder)
  // =============================================
  Widget _buildWidgetsTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.widgets_rounded, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Shared Widgets',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _pairData.isPaired
                ? 'Your shared widgets will appear here'
                : 'Connect with a partner to start\nusing widgets together',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
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
                        'Relationship Status',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose how you want to connect',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildRelationshipOption(
                        type: RelationshipType.couple,
                        icon: '❤️',
                        title: 'In Love',
                        subtitle: 'Perfect for romantic couples',
                      ),
                      const SizedBox(height: 12),
                      _buildRelationshipOption(
                        type: RelationshipType.married,
                        icon: '💍',
                        title: 'Married',
                        subtitle: 'For married partners',
                      ),
                      const SizedBox(height: 12),
                      _buildRelationshipOption(
                        type: RelationshipType.friends,
                        icon: '🤝',
                        title: 'Friends',
                        subtitle: 'Connect with your best friend',
                      ),
                      const SizedBox(height: 12),
                      _buildRelationshipOption(
                        type: RelationshipType.buddies,
                        icon: '👯',
                        title: 'Best Buddies',
                        subtitle: 'For inseparable companions',
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
                        label: const Text('Add Custom Status'),
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
        title: const Text('Add Custom Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emojiCtrl,
              decoration: const InputDecoration(
                labelText: 'Emoji',
                hintText: '💕',
              ),
              maxLength: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g., Soulmates',
              ),
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
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
            child: const Text('Add'),
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
        title: const Text('Edit Custom Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emojiCtrl,
              decoration: const InputDecoration(
                labelText: 'Emoji',
                hintText: '💕',
              ),
              maxLength: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g., Soulmates',
              ),
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
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
            child: const Text('Save'),
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
        builder: (_) =>
            MoodCalendarScreen(pairData: _pairData, moodService: _moodService),
      ),
    );
  }

  void _showMoodPicker() {
    final currentEmoji = _pairData.myMood.imagePath;
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
                'How are you feeling?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your partner will see your mood',
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
                        _pairData.setMood(mood.imagePath, mood.label);
                        _moodService.addMood(
                          moodId: mood.id,
                          imagePath: mood.imagePath,
                          label: mood.label,
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
              // Clear mood button
              if (currentEmoji.isNotEmpty) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pairData.clearMood();
                  },
                  child: Text(
                    'Clear Mood',
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
                  'Posting...',
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
            const SnackBar(content: Text('Failed to upload photo')),
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
            content: const Text('Posted to Memory Lane! 📸'),
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
                'Add a caption',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Optional — describe this moment',
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
                  hintText: 'Write something...',
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
                        'Skip',
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
                      child: const Text(
                        'Post',
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
          color: primaryLight.withOpacity(0.35),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: primary.withOpacity(0.08)),
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
                    'Invite Your Partner',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share a link, code, or QR to connect',
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
                'Relationship Memory Lane',
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
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.grey.shade200,
                style: BorderStyle.solid,
              ),
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
                  'Memories will appear here',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Connect with your partner to start',
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
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.12),
            blurRadius: 40,
            spreadRadius: -8,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 260),
        decoration: BoxDecoration(
          color: const Color(0xF0FFFFFF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x99FFFFFF)),
        ),
        child: Stack(
          children: [
            // -- Photo fragments (subtle background) --
            if (_pairData.isPaired) ...[
              Positioned(
                top: -8,
                left: -16,
                child: _photoFragment(widget.userData.avatarUrl, 80, 80, -0.2),
              ),
              Positioned(
                top: 48,
                right: 8,
                child: _photoFragment(_pairData.partnerAvatarUrl, 64, 64, 0.1),
              ),
              Positioned(
                bottom: -24,
                left: 60,
                child: _photoFragment(widget.userData.avatarUrl, 96, 96, -0.05),
              ),
              Positioned(
                bottom: 16,
                right: -8,
                child: _photoFragment(_pairData.partnerAvatarUrl, 56, 56, 0.2),
              ),
            ],
            // -- Gradient overlay --
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
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
    const labels = ['Days', 'Months', 'Time'];
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
                          labels[i],
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: primaryLight.withOpacity(0.35),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primary.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Daily Reflection',
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
                  color: primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'TODAY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '"What is one small thing ${_pairData.partnerName} did today that made you feel appreciated?"',
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade600,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 8,
                      shadowColor: primary.withOpacity(0.25),
                    ),
                    child: const Text(
                      'Answer Prompt',
                      style: TextStyle(
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

  // =============================================
  // ACTION BUTTONS
  // =============================================
  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _actionButton(
          icon: Icons.brush_rounded,
          label: 'Draw',
          iconColor: const Color(0xFFF472B6),
          enabled: _pairData.isPaired,
        ),
        _actionButton(
          icon: Icons.sentiment_satisfied_alt_rounded,
          label: 'Mood',
          iconColor: const Color(0xFFFBBF24),
          enabled: _pairData.isPaired,
          onTap: _showMoodPicker,
          moodImagePath: _pairData.myMood.imagePath,
        ),
        _actionButton(
          icon: Icons.calendar_month_rounded,
          label: 'Calendar',
          iconColor: const Color(0xFF60A5FA),
          enabled: _pairData.isPaired,
          onTap: _openMoodCalendar,
        ),
        _actionButton(
          icon: Icons.photo_camera_rounded,
          label: 'Post',
          iconColor: const Color(0xFF34D399),
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
                'Relationship Memory Lane',
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
                      builder: (_) => MemoryLaneScreen(pairData: _pairData),
                    ),
                  );
                },
                child: Text(
                  'View All',
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
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
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
                      'No memories yet',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add your first memory in Memory Lane',
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
            builder: (_) => MemoryLaneScreen(pairData: _pairData),
          ),
        );
      },
      child: Container(
        width: 160,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
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
            memory.caption ?? 'Photo',
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
            child: const Text(
              'VIDEO',
              style: TextStyle(
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
            memory.caption ?? 'Video',
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
            memory.locationName ?? 'Location',
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
            memory.musicTitle ?? 'Audio',
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
              color: isActive ? primary.withOpacity(0.1) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? primary : Colors.grey.shade400,
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

// =============================================
// BACKGROUND PATTERN PAINTER
// =============================================
class _BgPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint1 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.8, -0.6),
        radius: 0.8,
        colors: [
          const Color(0xFFEE2B6C).withOpacity(0.08),
          const Color(0xFFEE2B6C).withOpacity(0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint1);
    final paint2 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.8, 0.2),
        radius: 0.8,
        colors: [
          const Color(0xFFEE2B6C).withOpacity(0.05),
          const Color(0xFFEE2B6C).withOpacity(0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

enum _MoodBadgePosition { topLeft, bottomRight }
