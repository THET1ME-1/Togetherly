import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import '../models/pair_data.dart';
import '../models/connection.dart';
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

    _deepLinkSub = DeepLinkService().inviteCodeStream.listen((code) {
      if (mounted) {
        // acceptCode handles creating/joining group automatically
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
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildGroupTabs(),
        Expanded(
          child: pair.isPaired
              ? _buildConnectedContent()
              : _buildInviteContent(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  GROUP TABS — horizontal scrollable chips
  // ═══════════════════════════════════════════════════
  Widget _buildGroupTabs() {
    final connections = pair.manager.connections;
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        itemCount: connections.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == connections.length) {
            return _buildAddGroupChip();
          }
          final connection = connections[index];
          final isActive = index == pair.manager.activeConnectionIndex;
          return _buildGroupChip(connection, index, isActive);
        },
      ),
    );
  }

  Widget _buildGroupChip(Connection connection, int index, bool isActive) {
    final name = connection.isPaired
        ? (connection.partnerCount > 1
              ? '${connection.partners.first.name} +${connection.partnerCount - 1}'
              : connection.partnerName)
        : 'Waiting...';
    return GestureDetector(
      onTap: () async {
        await pair.manager.switchToConnection(index);
        _resetCodeInput();
        setState(() {});
      },
      onLongPress: () {
        if (pair.manager.connections.length > 1) {
          _confirmDeleteConnection(connection.id);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? primary.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? primary : Colors.grey.shade200,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: primary.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              connection.relationshipEmoji,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isActive ? primary : Colors.grey.shade700,
              ),
            ),
            if (connection.isPaired) ...[
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddGroupChip() {
    return GestureDetector(
      onTap: _showAddGroupDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 18, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              'New',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetCodeInput() {
    _codeController.clear();
    _showCodeInput = false;
    _codeError = false;
  }

  // ═══════════════════════════════════════════════════
  //  CONNECTED — partner linked (no days counter)
  // ═══════════════════════════════════════════════════
  Widget _buildConnectedContent() {
    final partners = pair.partners;
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
          const SizedBox(height: 24),
          _glassCard(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF22C55E),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  partners.length == 1
                      ? 'Connected with ${partners.first.name}'
                      : 'Group of ${partners.length + 1}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 10),
                // Relationship type badge — tappable
                GestureDetector(
                  onTap: _showRelationshipTypeDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          pair.relationshipEmoji,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          pair.relationshipLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.edit_rounded,
                          size: 12,
                          color: primary.withOpacity(0.6),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // ── Members list ──
                _buildMembersList(partners),
                const SizedBox(height: 20),
                // ── Invite More button ──
                if (pair.canInviteMore) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _showInviteMoreSheet,
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: Text(
                        'Invite More (${pair.members.length}/${pair.maxMembers})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 8,
                        shadowColor: primary.withOpacity(0.3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: 180,
                  height: 42,
                  child: OutlinedButton(
                    onPressed: _showUnpairDialog,
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
          const SizedBox(height: 20),
          // ── Join another group via code ──
          _buildJoinAnotherGroupCard(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  INVITE — connect partner (unpaired)
  // ═══════════════════════════════════════════════════
  Widget _buildInviteContent() {
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
          // ── Hero pulse ──
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              final scale = 1.0 + _pulseController.value * 0.05;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: primary,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── Relationship type badge — tappable ──
          GestureDetector(
            onTap: _showRelationshipTypeDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
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
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: primary.withOpacity(0.7),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'Connect Your Partner',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 6),
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
          const SizedBox(height: 28),

          // ── Invite Code Card ──
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
                  subtitle: "Scan partner's QR to connect",
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

          // ── Enter partner's code ──
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
                            "Enter your partner's invite code",
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
  //  MEMBERS LIST
  // ═══════════════════════════════════════════════════
  Widget _buildMembersList(List<GroupMember> partners) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MEMBERS (${partners.length + 1})',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade400,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        ...partners.map(
          (member) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _memberAvatar(member.avatar, member.name, 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    member.name.isNotEmpty ? member.name : 'Member',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _memberAvatar(String url, String name, double size) {
    final initial = (name.isNotEmpty) ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4),
        ],
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: primary.withOpacity(0.15),
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: size * 0.4,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                  ),
                ),
              )
            : Container(
                color: primary.withOpacity(0.15),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: size * 0.4,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  void _showInviteMoreSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              'Invite More Members',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${pair.members.length}/${pair.maxMembers} members',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
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
            Row(
              children: [
                Expanded(
                  child: _outlineButton(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: pair.inviteCode));
                      Navigator.pop(context);
                      _showSnack('Code copied!');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await Share.share(
                          'Join our group on Love App! Use code: ${pair.inviteCode}\n\nOr click: ${pair.inviteLink}',
                          subject: 'Love App Group Invitation',
                        );
                      },
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text(
                        'Share',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  UI HELPERS
  // ═══════════════════════════════════════════════════

  String _getConnectedSuccessMessage() {
    switch (pair.relationshipType) {
      case RelationshipType.couple:
        return "You're connected with ${pair.partnerName}!";
      case RelationshipType.married:
        return "You're married to ${pair.partnerName}! 💍";
      case RelationshipType.friends:
        return "You're now friends with ${pair.partnerName}!";
      case RelationshipType.buddies:
        return "You're now buddies with ${pair.partnerName}!";
      case RelationshipType.custom:
        return "You're now ${pair.relationshipLabel} with ${pair.partnerName}!";
    }
  }

  // ═══════════════════════════════════════════════════
  //  JOIN ANOTHER GROUP (in connected view)
  // ═══════════════════════════════════════════════════
  Widget _buildJoinAnotherGroupCard() {
    return _glassCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.group_add_rounded,
                  color: Color(0xFF3B82F6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Join Another Group',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Enter an invite code to join a new group',
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
                  style: TextStyle(fontSize: 12, color: Colors.red.shade400),
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
                  'Join Group',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

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

  // ═══════════════════════════════════════════════════
  //  ACTIONS
  // ═══════════════════════════════════════════════════

  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (pair.isSelfCode(code)) {
      setState(() => _codeError = true);
      _showSnack("You can't invite yourself!");
      return;
    }
    final ok = await pair.acceptCode(code);
    if (ok) {
      setState(() {});
      _showSnack('\u{1F389} ${_getConnectedSuccessMessage()}');
    } else {
      setState(() => _codeError = true);
      _showSnack('Code not found or already used');
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

  // ═══════════════════════════════════════════════════
  //  DIALOGS
  // ═══════════════════════════════════════════════════

  void _showQRDialog() {
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
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final customTypes = pair.customRelationshipTypes;
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
                      _relationshipOption(
                        type: RelationshipType.couple,
                        icon: '❤️',
                        title: 'In Love',
                        subtitle: 'Perfect for romantic couples',
                      ),
                      const SizedBox(height: 12),
                      _relationshipOption(
                        type: RelationshipType.married,
                        icon: '💍',
                        title: 'Married',
                        subtitle: 'For married partners',
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
                      // Custom relationship types
                      ...customTypes.map((entry) {
                        final isSelected =
                            pair.relationshipType == RelationshipType.custom &&
                            pair.relationshipLabel == entry['label'];
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: GestureDetector(
                            onTap: () {
                              pair.setRelationshipType(
                                RelationshipType.custom,
                                label: entry['label'] ?? '',
                                emoji: entry['emoji'] ?? '✨',
                              );
                              Navigator.of(ctx).pop();
                              setState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primary.withOpacity(0.08)
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? primary
                                      : Colors.grey.shade200,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    entry['emoji'] ?? '✨',
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      entry['label'] ?? 'Custom',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? primary
                                            : Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: primary,
                                      size: 24,
                                    ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () async {
                                      await pair.deleteCustomRelationshipType(
                                        entry['id'] ?? '',
                                      );
                                      setDialogState(() {});
                                      setState(() {});
                                    },
                                    child: Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Colors.red.shade400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
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
                await pair.addCustomRelationshipType(
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

  void _showAddGroupDialog() {
    // Collect unique custom relationship types from all connections
    final allCustomTypes = <String, Map<String, String>>{};
    for (final conn in pair.manager.connections) {
      for (final ct in conn.customRelationshipTypes) {
        final id = ct['id'] ?? '';
        if (id.isNotEmpty && !allCustomTypes.containsKey(id)) {
          allCustomTypes[id] = ct;
        }
      }
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Add New Connection',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose the type for your new connection',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 24),
                _addGroupOption(
                  type: RelationshipType.couple,
                  icon: '\u2764\uFE0F',
                  title: 'In Love',
                  subtitle: 'Perfect for romantic couples',
                ),
                const SizedBox(height: 12),
                _addGroupOption(
                  type: RelationshipType.married,
                  icon: '\u{1F48D}',
                  title: 'Married',
                  subtitle: 'For married partners',
                ),
                const SizedBox(height: 12),
                _addGroupOption(
                  type: RelationshipType.friends,
                  icon: '\u{1F91D}',
                  title: 'Friends',
                  subtitle: 'Connect with your best friend',
                ),
                const SizedBox(height: 12),
                _addGroupOption(
                  type: RelationshipType.buddies,
                  icon: '\u{1F46F}',
                  title: 'Best Buddies',
                  subtitle: 'For inseparable companions',
                ),
                // Show user-created custom relationship types
                ...allCustomTypes.values.map((ct) {
                  final label = ct['label'] ?? 'Custom';
                  final emoji = ct['emoji'] ?? '✨';
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _addGroupOption(
                      type: RelationshipType.custom,
                      icon: emoji,
                      title: label,
                      subtitle: 'Your custom type',
                      customLabel: label,
                      customEmoji: emoji,
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addGroupOption({
    required RelationshipType type,
    required String icon,
    required String title,
    required String subtitle,
    String customLabel = '',
    String customEmoji = '',
  }) {
    return GestureDetector(
      onTap: () async {
        await pair.manager.addNewConnection(
          type: type,
          customLabel: customLabel,
          customEmoji: customEmoji,
        );
        Navigator.of(context).pop();
        _resetCodeInput();
        setState(() {});
        _showSnack('New connection added!');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
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
                      color: Colors.grey.shade800,
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

  void _confirmDeleteConnection(String connectionId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Connection?'),
        content: const Text(
          'This will remove this connection permanently. If paired, it will disconnect your partner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await pair.manager.removeConnection(connectionId);
              Navigator.of(context).pop();
              _resetCodeInput();
              setState(() {});
              _showSnack('Connection removed');
            },
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
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
          'This will reset your timer and disconnect your partner.',
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
          "Scan Partner's QR Code",
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
              String code = rawValue;

              if (rawValue.contains('togetherly.app/invite/')) {
                code = rawValue.split('/invite/').last;
              } else if (rawValue.contains('loveapp://invite/')) {
                code = rawValue.split('/invite/').last;
              }

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
