import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../widgets/storage_image.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import '../models/pair_data.dart';
import '../models/connection.dart';
import '../models/profile_icon.dart';
import '../services/deep_link_service.dart';
import '../services/firebase_service.dart';
import '../services/locale_service.dart';
import '../services/nickname_service.dart';
import '../theme/app_theme.dart';

class ConnectPartnerScreen extends StatefulWidget {
  final PairData pairData;
  final AppTheme theme;
  const ConnectPartnerScreen({
    super.key,
    required this.pairData,
    required this.theme,
  });

  @override
  State<ConnectPartnerScreen> createState() => _ConnectPartnerScreenState();
}

class _ConnectPartnerScreenState extends State<ConnectPartnerScreen>
    with SingleTickerProviderStateMixin {
  Color get primary => widget.theme.primary;
  Color get primaryLight => widget.theme.primaryLight;
  final _codeController = TextEditingController();
  bool _showCodeInput = false;
  bool _codeError = false;
  late AnimationController _pulseController;
  StreamSubscription? _deepLinkSub;

  // Presence: uid → isOnline
  final Map<String, bool> _partnerOnlineStatus = {};
  final Map<String, String?> _partnerBadges = {};
  final Map<String, StreamSubscription<Map<String, dynamic>>> _presenceSubs =
      {};

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

    // Подписываемся на присутствие партнёров
    _subscribeToPartnerPresence();
    // Переподписываемся при изменении состава группы
    widget.pairData.addListener(_onPairDataChanged);
  }

  void _onPairDataChanged() {
    _subscribeToPartnerPresence();
  }

  void _subscribeToPartnerPresence() {
    final partners = widget.pairData.partners;
    final newUids = partners.map((p) => p.uid).toSet();

    // Отменяем подписки для вышедших участников
    final removed = _presenceSubs.keys.toSet().difference(newUids);
    for (final uid in removed) {
      _presenceSubs.remove(uid)?.cancel();
      _partnerOnlineStatus.remove(uid);
      _partnerBadges.remove(uid);
    }

    // Добавляем подписки для новых участников
    for (final member in partners) {
      if (member.uid.isEmpty || _presenceSubs.containsKey(member.uid)) continue;
      final sub = FirebaseService().streamUserPresence(member.uid).listen((
        data,
      ) {
        if (mounted) {
          setState(() {
            _partnerOnlineStatus[member.uid] =
                (data['isOnline'] as bool?) ?? false;
            _partnerBadges[member.uid] = data['badge'] as String?;
          });
        }
      });
      _presenceSubs[member.uid] = sub;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _pulseController.dispose();
    _deepLinkSub?.cancel();
    widget.pairData.removeListener(_onPairDataChanged);
    for (final sub in _presenceSubs.values) {
      sub.cancel();
    }
    _presenceSubs.clear();
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
    final isSoloActive = pair.manager.isSoloMode;
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        itemCount: connections.length + 2, // +1 for solo, +1 for add
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          // First item is solo button
          if (index == 0) {
            return _buildSoloChip(isActive: isSoloActive);
          }
          // Second to second-to-last are connections
          if (index <= connections.length) {
            final connIndex = index - 1;
            if (connIndex >= connections.length) return const SizedBox();
            final connection = connections[connIndex];
            // Skip solo connection in the list (it's at index 0 in manager but we handle it separately)
            if (connection.isSolo) return const SizedBox();
            // UI index maps directly to manager index (manager has solo at 0, we skip it)
            final isActive = pair.manager.activeConnectionIndex == connIndex;
            return _buildGroupChip(connection, connIndex, isActive);
          }
          // Last item is add button
          return _buildAddGroupChip();
        },
      ),
    );
  }

  Widget _buildSoloChip({required bool isActive}) {
    return GestureDetector(
      onTap: () async {
        await pair.manager.switchToSolo();
        _resetCodeInput();
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? primary : Colors.white,
          border: Border.all(
            color: isActive ? primary : Colors.grey.shade300,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: primary.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Icon(
            Icons.person_outline,
            color: isActive ? Colors.white : Colors.grey.shade600,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildGroupChip(Connection connection, int index, bool isActive) {
    final name = connection.isPaired
        ? (connection.partnerCount > 1
              ? '${connection.partners.first.name} +${connection.partnerCount - 1}'
              : connection.partnerName)
        : LocaleService.current.waiting;
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
              LocaleService.current.newGroup,
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
  //  CONNECTED — partner linked
  // ═══════════════════════════════════════════════════
  Widget _buildConnectedContent() {
    final partners = pair.partners;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.of(context).padding.bottom + 100,
      ),
      child: Column(
        children: [
          // ── Hero Connected Card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.theme.heroGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: primary.withOpacity(0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Avatars stack
                SizedBox(
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Partner avatars spread out
                      for (int i = 0; i < partners.length && i < 3; i++)
                        Positioned(
                          left: (partners.length == 1)
                              ? null
                              : (i * 32.0) +
                                    (90 - partners.length * 16).toDouble(),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: partners[i].avatar.isNotEmpty
                                  ? StorageImage(
                                      imageUrl: partners[i].avatar,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) =>
                                          _avatarFallback(partners[i].name, 48),
                                    )
                                  : _avatarFallback(partners[i].name, 48),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Status
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4ADE80),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        LocaleService.current.connected,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withOpacity(0.9),
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      partners.length == 1
                          ? pair.displayNameOf(partners.first)
                          : LocaleService.current.groupOf(
                              partners.length + 1),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (partners.length == 1)
                      _badgeIcon(partners.first.uid),
                  ],
                ),
                const SizedBox(height: 8),
                // Relationship type chip
                GestureDetector(
                  onTap: _showRelationshipTypeDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
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
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.edit_rounded,
                          size: 10,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Members Card ──
          _themedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleService.current.membersCount(partners.length + 1),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade400,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 14),
                ...partners.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        _memberAvatar(m.avatar, m.name, 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    pair.displayNameOf(m).isNotEmpty
                                        ? pair.displayNameOf(m)
                                        : LocaleService.current.member,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  _badgeIcon(m.uid),
                                ],
                              ),
                              if (NicknameService.instance
                                  .get(m.uid)
                                  .isNotEmpty)
                                Text(
                                  m.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _showRenameDialog(m),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 16,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _buildPresenceBadge(m.uid),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Action Row ──
          Row(
            children: [
              if (pair.canInviteMore)
                Expanded(
                  child: _actionTile(
                    icon: Icons.person_add_rounded,
                    label: LocaleService.current.inviteMore,
                    onTap: _showInviteMoreSheet,
                  ),
                ),
              if (pair.canInviteMore) const SizedBox(width: 12),
              Expanded(
                child: _actionTile(
                  icon: Icons.qr_code_2_rounded,
                  label: LocaleService.current.showQr,
                  onTap: _showQRDialog,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Join another group ──
          _buildJoinAnotherGroupCard(),
          const SizedBox(height: 16),

          // ── Disconnect ──
          GestureDetector(
            onTap: _showUnpairDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Center(
                child: Text(
                  LocaleService.current.disconnect,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade400,
                  ),
                ),
              ),
            ),
          ),
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
        20,
        8,
        20,
        MediaQuery.of(context).padding.bottom + 100,
      ),
      child: Column(
        children: [
          // ── Hero Card with gradient ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.theme.heroGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: primary.withOpacity(0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Pulse icon
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, __) {
                    final scale = 1.0 + _pulseController.value * 0.08;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  LocaleService.current.connectYourPartner,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  LocaleService.current.shareInviteCodeDesc,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                // Relationship type chip
                GestureDetector(
                  onTap: _showRelationshipTypeDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
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
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Invite Code Card ──
          _themedCard(
            child: Column(
              children: [
                Text(
                  LocaleService.current.yourInviteCode,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade400,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: pair.inviteCode.split('').map((ch) {
                    return Container(
                      width: 40,
                      height: 50,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: primary.withOpacity(0.12)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        ch,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: primary,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _themedOutlineButton(
                        icon: Icons.copy_rounded,
                        label: LocaleService.current.copy,
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: pair.inviteCode),
                          );
                          _showSnack(LocaleService.current.codeCopied);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _themedOutlineButton(
                        icon: Icons.share_rounded,
                        label: LocaleService.current.share,
                        onTap: () async {
                          await Share.share(
                            LocaleService.current.shareInviteText(
                              pair.inviteCode,
                              pair.inviteLink,
                            ),
                            subject: LocaleService.current.loveAppInvitation,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    _themedIconButton(
                      icon: Icons.refresh_rounded,
                      onTap: () {
                        pair.regenerateCode();
                        setState(() {});
                        _showSnack(LocaleService.current.newCodeGenerated);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Quick Actions Row ──
          Row(
            children: [
              Expanded(
                child: _actionTile(
                  icon: Icons.qr_code_2_rounded,
                  label: LocaleService.current.showQr,
                  onTap: _showQRDialog,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionTile(
                  icon: Icons.qr_code_scanner_rounded,
                  label: LocaleService.current.scanQr,
                  onTap: _openQRScanner,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Enter partner's code ──
          _themedCard(
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showCodeInput = !_showCodeInput),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.keyboard_rounded,
                          color: primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          LocaleService.current.haveACode,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _showCodeInput ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showCodeInput) ...[
                  const SizedBox(height: 16),
                  _buildCodeInput(),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _submitCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        LocaleService.current.connectPartnerBtn,
                        style: const TextStyle(
                          fontSize: 14,
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

  /// Бейдж онлайн/офлайн статуса для партнёра
  Widget _buildPresenceBadge(String uid) {
    final isOnline = _partnerOnlineStatus[uid] ?? false;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(isOnline),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isOnline
              ? const Color(0xFF4ADE80).withOpacity(0.12)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOnline
                    ? const Color(0xFF16A34A)
                    : Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              isOnline
                  ? LocaleService.current.online
                  : LocaleService.current.offline,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isOnline
                    ? const Color(0xFF16A34A)
                    : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgeIcon(String uid) {
    final badge = _partnerBadges[uid];
    if (badge == null || badge.isEmpty) return const SizedBox.shrink();
    final icon = ProfileIcon.byId(badge);
    return Transform.translate(
      offset: const Offset(-4, 0),
      child: GestureDetector(
        onTap: icon == null ? null : () => _showBadgeInfo(icon),
        child: Image.asset(
          icon?.asset ?? 'assets/images/icons/$badge.webp',
          width: 38,
          height: 38,
        ),
      ),
    );
  }

  void _showBadgeInfo(ProfileIcon icon) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Image.asset(icon.asset, width: 28, height: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(icon.name)),
          ],
        ),
        content: Text(icon.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
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
            ? StorageImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
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
              LocaleService.current.inviteMoreMembers,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LocaleService.current.membersOfMax(
                pair.members.length,
                pair.maxMembers,
              ),
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
                    style: TextStyle(
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
                    label: LocaleService.current.copy,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: pair.inviteCode));
                      Navigator.pop(context);
                      _showSnack(LocaleService.current.codeCopied);
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
                          LocaleService.current.shareGroupInviteText(
                            pair.inviteCode,
                            pair.inviteLink,
                          ),
                          subject: LocaleService.current.groupInvitation,
                        );
                      },
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: Text(
                        LocaleService.current.share,
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
    final s = LocaleService.current;
    switch (pair.relationshipType) {
      case RelationshipType.couple:
        return s.connectedWithCouple(pair.partnerName);
      case RelationshipType.married:
        return s.marriedTo(pair.partnerName);
      case RelationshipType.friends:
        return s.friendsWith(pair.partnerName);
      case RelationshipType.buddies:
        return s.buddiesWith(pair.partnerName);
      case RelationshipType.custom:
        return s.customRelWith(pair.relationshipLabel, pair.partnerName);
    }
  }

  // ═══════════════════════════════════════════════════
  //  JOIN ANOTHER GROUP (in connected view)
  // ═══════════════════════════════════════════════════
  Widget _buildJoinAnotherGroupCard() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                      LocaleService.current.joinAnotherGroup,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      LocaleService.current.enterCodeScanQr,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Quick actions: Scan QR and Enter Code ──
          Row(
            children: [
              Expanded(
                child: _outlineButton(
                  icon: Icons.qr_code_scanner_rounded,
                  label: LocaleService.current.scanQr,
                  onTap: _openQRScanner,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _showCodeInput = !_showCodeInput),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _showCodeInput ? primary : Colors.grey.shade200,
                      ),
                      color: _showCodeInput ? primary.withOpacity(0.05) : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.keyboard_rounded,
                          size: 16,
                          color: _showCodeInput
                              ? primary
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          LocaleService.current.enterCode,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _showCodeInput
                                ? primary
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_showCodeInput) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: TextStyle(
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
                  borderSide: BorderSide(color: primary, width: 2),
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
                  LocaleService.current.invalidCodeTryAgain,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade400),
                ),
              ),
            const SizedBox(height: 12),
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
                child: Text(
                  LocaleService.current.joinGroup,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
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

  // ═══════════════════════════════════════════════════
  //  THEMED HELPERS
  // ═══════════════════════════════════════════════════

  Widget _themedCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.theme.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: widget.theme.cardBorder, width: 0.5),
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

  Widget _themedOutlineButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primary.withOpacity(0.15)),
          color: primary.withOpacity(0.04),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themedIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primary.withOpacity(0.15)),
          color: primary.withOpacity(0.04),
        ),
        child: Icon(icon, size: 16, color: primary),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: widget.theme.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: widget.theme.cardBorder, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: primary),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeInput() {
    return TextField(
      controller: _codeController,
      textCapitalization: TextCapitalization.characters,
      maxLength: 6,
      textAlign: TextAlign.center,
      style: TextStyle(
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
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _codeError ? Colors.red.shade300 : primary.withOpacity(0.12),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _codeError ? Colors.red.shade300 : primary.withOpacity(0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 20,
        ),
      ),
      onChanged: (_) {
        if (_codeError) setState(() => _codeError = false);
      },
    );
  }

  Widget _avatarFallback(String name, double size) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      color: Colors.white,
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
    );
  }

  // ═══════════════════════════════════════════════════
  //  ACTIONS
  // ═══════════════════════════════════════════════════

  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (pair.isSelfCode(code)) {
      setState(() => _codeError = true);
      _showSnack(LocaleService.current.cantInviteSelf);
      return;
    }
    final ok = await pair.acceptCode(code);
    if (ok) {
      setState(() {});
      _showSnack('\u{1F389} ${_getConnectedSuccessMessage()}');
    } else {
      setState(() => _codeError = true);
      _showSnack(LocaleService.current.codeNotFound);
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
                LocaleService.current.scanToConnect,
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
                style: TextStyle(
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
                            LocaleService.current.joinMeLinkText(
                              pair.inviteLink,
                            ),
                            subject: LocaleService.current.loveAppInvitation,
                          );
                        },
                        icon: const Icon(Icons.share_rounded),
                        label: Text(LocaleService.current.share),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          side: BorderSide(color: primary),
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
                        child: Text(
                          LocaleService.current.done,
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
      MaterialPageRoute(
        builder: (_) => const QRScannerScreen(),
        settings: const RouteSettings(name: '/qr_scanner'),
      ),
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
                      _relationshipOption(
                        type: RelationshipType.couple,
                        icon: '❤️',
                        title: LocaleService.current.inLoveStatus,
                        subtitle: LocaleService.current.perfectForCouples,
                      ),
                      const SizedBox(height: 12),
                      _relationshipOption(
                        type: RelationshipType.married,
                        icon: '💍',
                        title: LocaleService.current.married,
                        subtitle: LocaleService.current.forMarriedPartners,
                      ),
                      const SizedBox(height: 12),
                      _relationshipOption(
                        type: RelationshipType.friends,
                        icon: '🤝',
                        title: LocaleService.current.friends,
                        subtitle: LocaleService.current.connectWithBestFriend,
                      ),
                      const SizedBox(height: 12),
                      _relationshipOption(
                        type: RelationshipType.buddies,
                        icon: '👯',
                        title: LocaleService.current.bestBuddies,
                        subtitle:
                            LocaleService.current.forInseparableCompanions,
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
                                      entry['label'] ??
                                          LocaleService.current.custom,
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
                                    Icon(
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
              Icon(Icons.check_circle_rounded, color: primary, size: 24),
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
            child: Text(LocaleService.current.add),
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
                  LocaleService.current.addNewConnection,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  LocaleService.current.chooseTypeForConnection,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 24),
                _addGroupOption(
                  type: RelationshipType.couple,
                  icon: '\u2764\uFE0F',
                  title: LocaleService.current.inLoveStatus,
                  subtitle: LocaleService.current.perfectForCouples,
                ),
                const SizedBox(height: 12),
                _addGroupOption(
                  type: RelationshipType.married,
                  icon: '\u{1F48D}',
                  title: LocaleService.current.married,
                  subtitle: LocaleService.current.forMarriedPartners,
                ),
                const SizedBox(height: 12),
                _addGroupOption(
                  type: RelationshipType.friends,
                  icon: '\u{1F91D}',
                  title: LocaleService.current.friends,
                  subtitle: LocaleService.current.connectWithBestFriend,
                ),
                const SizedBox(height: 12),
                _addGroupOption(
                  type: RelationshipType.buddies,
                  icon: '\u{1F46F}',
                  title: LocaleService.current.bestBuddies,
                  subtitle: LocaleService.current.forInseparableCompanions,
                ),
                // Show user-created custom relationship types
                ...allCustomTypes.values.map((ct) {
                  final label = ct['label'] ?? LocaleService.current.custom;
                  final emoji = ct['emoji'] ?? '✨';
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _addGroupOption(
                      type: RelationshipType.custom,
                      icon: emoji,
                      title: label,
                      subtitle: LocaleService.current.yourCustomType,
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
        _showSnack(LocaleService.current.newConnectionAdded);
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

  void _showRenameDialog(GroupMember member) {
    final current = NicknameService.instance.get(member.uid);
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          LocaleService.current.renamePartner,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleService.current.renamePartnerHint,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 30,
              decoration: InputDecoration(
                hintText: member.name,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (current.isNotEmpty)
            TextButton(
              onPressed: () async {
                await pair.clearNickname(member.uid);
                if (ctx.mounted) Navigator.of(ctx).pop();
                setState(() {});
              },
              child: Text(
                LocaleService.current.resetNickname,
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(LocaleService.current.cancel),
          ),
          TextButton(
            onPressed: () async {
              await pair.setNickname(member.uid, controller.text);
              if (ctx.mounted) Navigator.of(ctx).pop();
              setState(() {});
            },
            child: Text(
              LocaleService.current.save,
              style: TextStyle(color: primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteConnection(String connectionId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(LocaleService.current.deleteConnection),
        content: Text(LocaleService.current.deleteConnectionDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(LocaleService.current.cancel),
          ),
          TextButton(
            onPressed: () async {
              await pair.manager.removeConnection(connectionId);
              Navigator.of(context).pop();
              _resetCodeInput();
              setState(() {});
              _showSnack(LocaleService.current.connectionRemoved);
            },
            child: Text(
              LocaleService.current.delete,
              style: TextStyle(color: Colors.red.shade400),
            ),
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
        title: Text(LocaleService.current.disconnectQuestion),
        content: Text(LocaleService.current.disconnectDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(LocaleService.current.cancel),
          ),
          TextButton(
            onPressed: () {
              pair.unpair();
              Navigator.of(context).pop();
              setState(() {});
            },
            child: Text(
              LocaleService.current.disconnect,
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
        title: Text(
          LocaleService.current.scanPartnersQr,
          style: const TextStyle(color: Colors.white),
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

              if (rawValue.contains('/invite/')) {
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
