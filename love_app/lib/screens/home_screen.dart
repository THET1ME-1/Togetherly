import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pair_data.dart';
import 'connect_partner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // -- Colors --
  static const Color primary = Color(0xFFEE2B6C);
  static const Color primaryLight = Color(0xFFFEEAF1);
  static const Color bgLight = Color(0xFFF8F6F6);

  // -- State --
  int _selectedTimeUnit = 0; // 0=Days, 1=Months, 2=Time
  int _selectedNavIndex = 0;
  bool _showReflection = true;
  Timer? _timer;

  // -- Pair data --
  final PairData _pairData = PairData();

  // -- Image URLs --
  static const String _avatar1 =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuCXnoETm_vtC3lKFupdlHAb12mktCOPy3W4mltZ672WBgc7mvyXZw-0e8SzJCwkkh2ALZzpECL86Wf3PmizJk0iAkRRTEK_k9OaooFCpeyqNtmXpF--Hfuzj64ovK5QFjeHiJqbhvj-bkXs8MNb9sKIlcVpbM2PGDOARTWWmo_kD25ax_5HZ3tdN2ZhQ4o4JpnIIHClKQe2ktHHheFA5x5GTivaKrVmlZr-cPgCFoOvjKqONIQDAuZMi1LYHZFaLiFYvFp287oVwqA';
  static const String _avatar2 =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuBja92tC-GNSOJPqL6bNPRKeHAqLJWK4aAcquDO9CpDFs8aj0ZB3zUdqDz_E8sppd96foaSj7sTdITtT-T7NNftpKmiHCMOOK0GMVO6zrLl98R70H0jEj4Z3b_QbWsOa0SnG2MmGPUzPvkbCcpgRqUZayJ8WzM0jqgr51Qk7jojilzjvC1WC6lfLqdKnbkUZJ6QDhbIwRmAequdHpEZg2OuCvxeS6DajJJ1VslTIqIu7z3Osegz9PKlwgO2DUbK_U3CjUsa3IXgKS8';
  static const String _memoryImg =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuAGzfqi2pS4mAG0Kaau3LdjNhkBQC-DDJm-0B093UORH766JIx5e_NoYz1GKog7MrLXHW67kOjDg6NG9fZnINlYB8--Z5OUziFlrYrLdL6NgPAdk4bnZw5Np8-N1lWgyd1NEdH0SX00mq4Bd7eT93SNtY8M4gZIA3yQSV_kEyASlr5LiIRiVd6U7yJSpKykY1fBbabdSUtG10PcBqX88I7t-SK1BlQ_gDvrfAUR1VU7WEW36WItTHYIeHRABr2mN2zygEeknxRhL4M';
  static const String _memoryImg2 =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuCahdRPpqdMrToKNj6w6kpHPFIegfw1IeLMM-8Kmqt5s9S4yZNg1OBD5E-IWdNhEiKCh2rO3BVN5oNTvfe6S-tpRi61TyL5O553ut73KPy63REO_ytDy61dq-IkJTn2N84zoOwQ0hSGWz_WJvLjaJp8LlgpQfxZwuSaxBF7cPXUjLDhIWmXLF3a76fkHJexvjbp8JTW0JEySIsUsQa41RpFSKe6Kdoz7-vWV3DuRWJOd_MKK1mr_ipluRupPz7HEG27oAvxT4YPA64';

  @override
  void initState() {
    super.initState();
    _pairData.addListener(_onPairChanged);
    // Dynamic timer - update every second for live counter
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_pairData.isPaired && _selectedTimeUnit == 2 && mounted) {
        setState(() {}); // Refresh counter when in Time mode
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pairData.removeListener(_onPairChanged);
    _pairData.dispose();
    super.dispose();
  }

  void _onPairChanged() {
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
    if (!_pairData.isPaired) return 'WAITING FOR LOVE';
    switch (_selectedTimeUnit) {
      case 0:
        return 'DAYS IN LOVE';
      case 1:
        return 'MONTHS IN LOVE';
      case 2:
        return 'TIME IN LOVE';
      default:
        return 'DAYS IN LOVE';
    }
  }

  String get _statusBadgeText => _pairData.isPaired ? 'In love' : 'Solo';

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
            child: Container(
              color: bgLight,
              child: CustomPaint(
                painter: _BgPatternPainter(),
                size: Size.infinite,
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
          // -- Bottom Nav --
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedNavIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildMemoriesTab();
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
                _buildCounterCard(),
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
  // MEMORIES TAB (placeholder)
  // =============================================
  Widget _buildMemoriesTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_motion_rounded,
            size: 48,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Memories',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _pairData.isPaired
                ? 'Your shared moments will appear here'
                : 'Connect with a partner to start\ncreating memories together',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // =============================================
  // PROFILE TAB (placeholder)
  // =============================================
  Widget _buildProfileTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_outline_rounded,
            size: 48,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Profile',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your profile settings',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
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
              width: 68,
              height: 40,
              child: Stack(
                children: [
                  Positioned(left: 0, child: _avatarCircle(_avatar1)),
                  Positioned(left: 28, child: _avatarCircle(_avatar2)),
                ],
              ),
            ),
          ] else ...[
            _avatarCircle(_avatar1),
          ],
          const SizedBox(width: 12),
          // Badge
          Container(
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
                Icon(
                  _pairData.isPaired ? Icons.favorite : Icons.favorite_border,
                  color: _pairData.isPaired ? primary : Colors.grey.shade400,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  _statusBadgeText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _pairData.isPaired ? primary : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.settings_outlined, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _avatarCircle(String url) {
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
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey.shade200,
            child: Icon(Icons.person, color: Colors.grey.shade400, size: 20),
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
              child: const Icon(
                Icons.person_add_rounded,
                color: primary,
                size: 24,
              ),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 260),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.75),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.6)),
            ),
            child: Stack(
              children: [
                // -- Photo fragments (subtle background) --
                if (_pairData.isPaired) ...[
                  Positioned(
                    top: -8,
                    left: -16,
                    child: _photoFragment(_memoryImg, 80, 80, -0.2),
                  ),
                  Positioned(
                    top: 48,
                    right: 8,
                    child: _photoFragment(_memoryImg2, 64, 64, 0.1),
                  ),
                  Positioned(
                    bottom: -24,
                    left: 60,
                    child: _photoFragment(_avatar1, 96, 96, -0.05),
                  ),
                  Positioned(
                    bottom: 16,
                    right: -8,
                    child: _photoFragment(_avatar2, 56, 56, 0.2),
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 40,
                    horizontal: 20,
                  ),
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
                      onTap: () => setState(() => _selectedTimeUnit = i),
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
          icon: Icons.favorite_rounded,
          label: 'Nudge',
          iconColor: Colors.white,
          isPrimary: true,
          enabled: _pairData.isPaired,
        ),
        _actionButton(
          icon: Icons.sentiment_satisfied_alt_rounded,
          label: 'Mood',
          iconColor: const Color(0xFFFBBF24),
          enabled: _pairData.isPaired,
        ),
        _actionButton(
          icon: Icons.brush_rounded,
          label: 'Draw',
          iconColor: const Color(0xFF60A5FA),
          enabled: _pairData.isPaired,
        ),
        _actionButton(
          icon: Icons.photo_camera_rounded,
          label: 'Post',
          iconColor: const Color(0xFF34D399),
          enabled: _pairData.isPaired,
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
  }) {
    final opacity = enabled ? 1.0 : 0.4;
    return Opacity(
      opacity: opacity,
      child: Column(
        children: [
          GestureDetector(
            onTap: enabled ? () {} : null,
            child: AnimatedContainer(
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
              child: Icon(icon, color: iconColor, size: 28),
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
                onTap: () {},
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
        SizedBox(
          height: 200,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: [
              _memoryPhotoCard(),
              const SizedBox(width: 16),
              _memoryLocationCard(),
              const SizedBox(width: 16),
              _memoryConnectedCard(),
              const SizedBox(width: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _memoryPhotoCard() {
    return Container(
      width: 160,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              _memoryImg,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: Colors.grey.shade300),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.15),
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MONTH ${_pairData.monthsInLove}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(0.8),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Coffee Date',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memoryLocationCard() {
    return Container(
      width: 160,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.75),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.near_me,
                            color: Color(0xFF3B82F6),
                            size: 16,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF22C55E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '${_pairData.partnerName} is at',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Central Park\nCoffee',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '12 mins ago',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _memoryConnectedCard() {
    return Container(
      width: 160,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.75),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.battery_charging_full,
                        color: Color(0xFF22C55E),
                        size: 16,
                      ),
                    ),
                    const Spacer(),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            '85%',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'CONNECTED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ],
            ),
          ),
        ),
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
      child: Container(
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
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.78),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withOpacity(0.6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navItem(Icons.home_rounded, 0),
                  _navItem(Icons.auto_awesome_motion_rounded, 1),
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
