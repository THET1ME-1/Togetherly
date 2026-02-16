import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/pair_data.dart';

class ConnectPartnerScreen extends StatefulWidget {
  final PairData pairData;
  const ConnectPartnerScreen({super.key, required this.pairData});

  @override
  State<ConnectPartnerScreen> createState() => _ConnectPartnerScreenState();
}

class _ConnectPartnerScreenState extends State<ConnectPartnerScreen>
    with SingleTickerProviderStateMixin {
  static const Color primary = Color(0xFFEE2B6C);
  final _codeController = TextEditingController();
  bool _showCodeInput = false;
  bool _codeError = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  PairData get pair => widget.pairData;

  @override
  Widget build(BuildContext context) {
    if (pair.isPaired) {
      return _buildPairedView();
    }
    return _buildUnpairedView();
  }

  // ═══════════════════════════════════════════════════
  //  UNPAIRED — Invite partner
  // ═══════════════════════════════════════════════════
  Widget _buildUnpairedView() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 100,
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // ── Hero illustration ──
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              final scale = 1.0 + _pulseController.value * 0.05;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: primary,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 28),
          Text(
            'Connect Your Partner',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share your invite code so your\npartner can join this space',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 36),

          // ── Your Code Card ──
          _glassCard(
            child: Column(
              children: [
                Text(
                  'YOUR INVITE CODE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade400,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 16),
                // Code display
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: pair.inviteCode.split('').map((ch) {
                    return Container(
                      width: 42,
                      height: 52,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: primary.withOpacity(0.15)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        ch,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: primary,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                // Copy & Regenerate row
                Row(
                  children: [
                    Expanded(
                      child: _outlineButton(
                        icon: Icons.copy_rounded,
                        label: 'Copy Code',
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: pair.inviteCode),
                          );
                          _showSnack('Code copied!');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    _iconOutlineButton(
                      icon: Icons.refresh_rounded,
                      onTap: () {
                        pair.regenerateCode();
                        setState(() {});
                        _showSnack('New code generated');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Share Options ──
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SHARE VIA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade400,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 16),
                _shareOption(
                  icon: Icons.link_rounded,
                  label: 'Share Link',
                  subtitle: pair.inviteLink,
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: pair.inviteLink));
                    _showSnack('Link copied!');
                  },
                ),
                _divider(),
                _shareOption(
                  icon: Icons.qr_code_2_rounded,
                  label: 'Show QR Code',
                  subtitle: 'Let partner scan to connect',
                  color: const Color(0xFF8B5CF6),
                  onTap: () => _showQRDialog(),
                ),
                _divider(),
                _shareOption(
                  icon: Icons.message_rounded,
                  label: 'Send via Message',
                  subtitle: 'Share code through messenger',
                  color: const Color(0xFF22C55E),
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(
                        text:
                            'Join me on Love App! Use code: ${pair.inviteCode}\n${pair.inviteLink}',
                      ),
                    );
                    _showSnack('Invite text copied!');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Or enter partner's code ──
          _glassCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.keyboard_rounded,
                        color: Color(0xFFFBBF24),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Have a code?',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Enter your partner\'s invite code',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_showCodeInput)
                      GestureDetector(
                        onTap: () => setState(() => _showCodeInput = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Enter',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_showCodeInput) ...[
                  const SizedBox(height: 20),
                  TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                      color: primary,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '------',
                      hintStyle: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                        color: Colors.grey.shade300,
                      ),
                      filled: true,
                      fillColor: primary.withOpacity(0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: _codeError
                              ? Colors.red.shade300
                              : primary.withOpacity(0.15),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: _codeError
                              ? Colors.red.shade300
                              : primary.withOpacity(0.15),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: primary, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                    ),
                    onChanged: (_) {
                      if (_codeError) setState(() => _codeError = false);
                    },
                  ),
                  if (_codeError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Invalid code. Please check and try again.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade400,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submitCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 8,
                        shadowColor: primary.withOpacity(0.3),
                      ),
                      child: const Text(
                        'Connect Partner',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  PAIRED — Connected view
  // ═══════════════════════════════════════════════════
  Widget _buildPairedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF22C55E),
                size: 44,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Connected with ${pair.partnerName}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your love timer is running ❤️',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 32),
            Text(
              '${pair.daysInLove} days together',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 200,
              height: 44,
              child: OutlinedButton(
                onPressed: () {
                  _showUnpairDialog();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade400,
                  side: BorderSide(color: Colors.red.shade200),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Disconnect',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _outlineButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconOutlineButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Icon(icon, size: 18, color: Colors.grey.shade600),
      ),
    );
  }

  Widget _shareOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _divider() {
    return Divider(color: Colors.grey.shade100, height: 1, thickness: 1);
  }

  void _submitCode() {
    final code = _codeController.text.trim().toUpperCase();
    if (pair.isSelfCode(code)) {
      setState(() => _codeError = true);
      _showSnack('Нельзя пригласить самого себя!');
      return;
    }
    if (pair.acceptCode(code)) {
      setState(() {});
      _showSnack('🎉 Connected with ${pair.partnerName}!');
    } else {
      setState(() => _codeError = true);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 100),
        backgroundColor: Colors.grey.shade800,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showQRDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scan to Connect',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 24),
              // Simulated QR code
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200, width: 2),
                ),
                child: CustomPaint(
                  painter: _SimpleQRPainter(pair.inviteCode),
                  size: const Size(200, 200),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                pair.inviteCode,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: primary,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnpairDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Disconnect?'),
        content: const Text(
          'This will reset your love timer and disconnect your partner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              pair.unpair();
              Navigator.of(context).pop();
              setState(() {});
            },
            child: Text(
              'Disconnect',
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Simple QR-like pattern painter (decorative)
// ═══════════════════════════════════════════════════
class _SimpleQRPainter extends CustomPainter {
  final String code;
  _SimpleQRPainter(this.code);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1A1A1A);
    final cellSize = size.width / 15;
    final margin = cellSize * 1.5;

    // Use code chars to seed a pattern
    int seed = 0;
    for (var c in code.codeUnits) {
      seed = (seed * 31 + c) & 0x7FFFFFFF;
    }

    // Draw corner markers (like a real QR code)
    _drawFinderPattern(canvas, paint, margin, margin, cellSize);
    _drawFinderPattern(
      canvas,
      paint,
      size.width - margin - cellSize * 3,
      margin,
      cellSize,
    );
    _drawFinderPattern(
      canvas,
      paint,
      margin,
      size.height - margin - cellSize * 3,
      cellSize,
    );

    // Draw data pattern
    final rng = seed;
    for (int row = 0; row < 15; row++) {
      for (int col = 0; col < 15; col++) {
        // Skip finder pattern areas
        if (_inFinderArea(row, col)) continue;
        // Pseudo-random based on seed
        int v = ((rng * (row * 15 + col + 1)) >> 3) & 0xF;
        if (v < 6) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                col * cellSize + margin / 2,
                row * cellSize + margin / 2,
                cellSize * 0.85,
                cellSize * 0.85,
              ),
              const Radius.circular(2),
            ),
            paint,
          );
        }
      }
    }
  }

  bool _inFinderArea(int row, int col) {
    // Top-left 4x4
    if (row < 4 && col < 4) return true;
    // Top-right 4x4
    if (row < 4 && col > 10) return true;
    // Bottom-left 4x4
    if (row > 10 && col < 4) return true;
    return false;
  }

  void _drawFinderPattern(
    Canvas canvas,
    Paint paint,
    double x,
    double y,
    double cell,
  ) {
    // Outer square
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, cell * 3, cell * 3),
        const Radius.circular(4),
      ),
      paint,
    );
    // White inner
    final whitePaint = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + cell * 0.5, y + cell * 0.5, cell * 2, cell * 2),
        const Radius.circular(2),
      ),
      whitePaint,
    );
    // Black center
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + cell, y + cell, cell, cell),
        const Radius.circular(2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
