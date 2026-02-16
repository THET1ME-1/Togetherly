import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import '../models/pair_data.dart';
import '../services/deep_link_service.dart';

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
  StreamSubscription? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Слушаем deep links
    _deepLinkSub = DeepLinkService().inviteCodeStream.listen((code) {
      if (mounted && !pair.isPaired) {
        _codeController.text = code;
        _showCodeInput = true;
        setState(() {});
        _submitCode();
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _pulseController.dispose();
    _deepLinkSub?.cancel();
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
    return Stack(
      children: [
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.of(context).padding.bottom + 100,
          ),
          child: Column(
            children: [
              const SizedBox(height: 48), // Space for status selector
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
                            border: Border.all(
                              color: primary.withOpacity(0.15),
                            ),
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
                      onTap: () async {
                        await Share.share(
                          'Join me on Love App! ${pair.inviteLink}',
                          subject: 'Love App Invitation',
                        );
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
                      icon: Icons.qr_code_scanner_rounded,
                      label: 'Scan QR Code',
                      subtitle: 'Scan partner\'s QR to connect',
                      color: const Color(0xFFEC4899),
                      onTap: () => _openQRScanner(),
                    ),
                    _divider(),
                    _shareOption(
                      icon: Icons.message_rounded,
                      label: 'Send via Message',
                      subtitle: 'Share code through messenger',
                      color: const Color(0xFF22C55E),
                      onTap: () async {
                        await Share.share(
                          'Join me on Love App! Use code: ${pair.inviteCode}\n\nOr click: ${pair.inviteLink}',
                          subject: 'Love App Invitation',
                        );
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
                            borderSide: const BorderSide(
                              color: primary,
                              width: 2,
                            ),
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
        ),
        // ── Status Selector (Top Left) ──
        Positioned(
          top: 16,
          left: 24,
          child: GestureDetector(
            onTap: _showRelationshipTypeDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primary.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pair.relationshipEmoji,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    pair.relationshipLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  PAIRED — Connected view
  // ═══════════════════════════════════════════════════
  Widget _buildPairedView() {
    return Stack(
      children: [
        Center(
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
                  _getConnectedMessage(),
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
        ),
        // ── Status Selector (Top Left) ──
        Positioned(
          top: 16,
          left: 24,
          child: GestureDetector(
            onTap: _showRelationshipTypeDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primary.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pair.relationshipEmoji,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    pair.relationshipLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════

  String _getConnectedMessage() {
    switch (pair.relationshipType) {
      case RelationshipType.couple:
        return 'Your love timer is running ❤️';
      case RelationshipType.friends:
        return 'Your friendship timer is running 🤝';
      case RelationshipType.buddies:
        return 'Your buddy timer is running 👯';
    }
  }

  String _getConnectedSuccessMessage() {
    switch (pair.relationshipType) {
      case RelationshipType.couple:
        return 'You\'re connected with ${pair.partnerName}!';
      case RelationshipType.friends:
        return 'You\'re now friends with ${pair.partnerName}!';
      case RelationshipType.buddies:
        return 'You\'re now buddies with ${pair.partnerName}!';
    }
  }

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

  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (pair.isSelfCode(code)) {
      setState(() => _codeError = true);
      _showSnack('Нельзя пригласить самого себя!');
      return;
    }
    final ok = await pair.acceptCode(code);
    if (ok) {
      setState(() {});
      _showSnack('🎉 ${_getConnectedSuccessMessage()}');
    } else {
      setState(() => _codeError = true);
      _showSnack('Код не найден или уже использован');
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
    // 🎲 10% шанс на Рикрол
    final random = Random();
    final isRickroll = random.nextInt(100) < 10;
    final qrData = isRickroll
        ? 'https://youtu.be/dQw4w9WgXcQ?si=owAivsztmdCvvm6v'
        : pair.inviteLink;

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
              // Реальный QR код с фиксированным размером
              Container(
                width: 240,
                height: 240,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200, width: 2),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                  padding: EdgeInsets.zero,
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
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Share.share(
                            'Join me on Love App! ${pair.inviteLink}',
                            subject: 'Love App Invitation',
                          );
                        },
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Share'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          side: const BorderSide(color: primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
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
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openQRScanner() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );

    if (code != null && mounted) {
      _codeController.text = code;
      _showCodeInput = true;
      setState(() {});
      _submitCode();
    }
  }

  void _showRelationshipTypeDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
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
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),
              _relationshipOption(
                type: RelationshipType.couple,
                icon: '❤️',
                title: 'In Love',
                subtitle: 'Perfect for romantic couples',
              ),
              const SizedBox(height: 12),
              _relationshipOption(
                type: RelationshipType.friends,
                icon: '🤝',
                title: 'Friends',
                subtitle: 'Connect with your best friend',
              ),
              const SizedBox(height: 12),
              _relationshipOption(
                type: RelationshipType.buddies,
                icon: '👯',
                title: 'Best Buddies',
                subtitle: 'For inseparable companions',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _relationshipOption({
    required RelationshipType type,
    required String icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = pair.relationshipType == type;
    return GestureDetector(
      onTap: () {
        pair.setRelationshipType(type);
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
              const Icon(Icons.check_circle_rounded, color: primary, size: 24),
          ],
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
// QR Scanner Screen
// ═══════════════════════════════════════════════════
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _codeDetected = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Scan Partner\'s QR Code',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_codeDetected) return;

          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final String? rawValue = barcode.rawValue;
            if (rawValue != null) {
              // Извлекаем код из URL или используем как есть
              String code = rawValue;

              // Если это ссылка togetherly.app/invite/CODE
              if (rawValue.contains('togetherly.app/invite/')) {
                code = rawValue.split('/invite/').last;
              }
              // Если это loveapp://invite/CODE
              else if (rawValue.contains('loveapp://invite/')) {
                code = rawValue.split('/invite/').last;
              }

              // Проверяем что код 6 символов
              if (code.length == 6) {
                _codeDetected = true;
                Navigator.pop(context, code.toUpperCase());
                return;
              }
            }
          }
        },
      ),
    );
  }
}
