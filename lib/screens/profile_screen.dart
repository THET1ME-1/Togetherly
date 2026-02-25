import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_data.dart';
import '../models/pair_data.dart';
import '../models/connection.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import 'welcome_screen.dart';

/// Entry for a partner across all connections
class _PartnerEntry {
  final GroupMember member;
  final Connection connection;
  const _PartnerEntry({required this.member, required this.connection});
}

class ProfileScreen extends StatefulWidget {
  final UserData userData;
  final PairData pairData;
  const ProfileScreen({
    super.key,
    required this.userData,
    required this.pairData,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Color get _accent => widget.userData.themeAccent;
  Color get _accentLight => widget.userData.themeAccentLight;

  /// UID of the partner selected in the profile (null = first from active group)
  String? _selectedPartnerUid;

  /// Local relationship type used when no group is connected
  RelationshipType _localRelType = RelationshipType.couple;

  /// Timer to refresh day counter every hour
  Timer? _dayTimer;

  @override
  void initState() {
    super.initState();
    widget.pairData.addListener(_onPairDataChanged);
    // Refresh every hour so the day count updates when crossing midnight
    _dayTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.pairData.removeListener(_onPairDataChanged);
    _dayTimer?.cancel();
    super.dispose();
  }

  void _onPairDataChanged() {
    if (mounted) setState(() {});
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
          // ═══ Relationship Status Card ═══
          _buildRelationshipCard(context),
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
                          child: Image.network(
                            widget.userData.avatarUrl,
                            fit: BoxFit.cover,
                            cacheWidth: 200,
                            cacheHeight: 200,
                            errorBuilder: (_, __, ___) =>
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
        Text(
          widget.userData.displayName.isNotEmpty
              ? widget.userData.displayName
              : 'Пользователь',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade900,
          ),
        ),
        const SizedBox(height: 4),
        // Email
        Text(
          widget.userData.email.isNotEmpty
              ? widget.userData.email
              : 'Нет email',
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
                widget.userData.isMale ? 'Парень' : 'Девушка',
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
                    'Редактировать профиль',
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
                                child: Image.network(
                                  widget.userData.avatarUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
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
                  labelText: 'Имя',
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
                  child: const Text(
                    'Сохранить',
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
      imageQuality: 85,
      maxWidth: 512,
      maxHeight: 512,
    );

    if (image == null || !mounted) return;

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
                CircularProgressIndicator(color: _accent),
                const SizedBox(height: 16),
                Text(
                  'Загрузка...',
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
        if (mounted) _showError('Ошибка: пользователь не авторизован');
        return;
      }

      final ext = image.path.split('.').last;
      final destination = 'avatars/$userId/profile.$ext';
      final downloadUrl = await fb.uploadFile(image.path, destination);

      if (mounted) Navigator.of(context).pop();

      if (downloadUrl == null) {
        if (mounted) _showError('Не удалось загрузить изображение');
        return;
      }

      // Update profile
      await widget.userData.updateProfile(avatarUrl: downloadUrl);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Аватарка обновлена'),
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
      if (mounted) _showError('Ошибка загрузки: ${e.toString()}');
    }
  }

  Future<void> _changeName(String newName) async {
    try {
      await widget.userData.updateProfile(displayName: newName);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Имя обновлено'),
            backgroundColor: _accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError('Ошибка: ${e.toString()}');
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
            'ИНФОРМАЦИЯ',
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
            label: 'Имя',
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
          _infoRow(
            icon: widget.userData.isMale
                ? Icons.male_rounded
                : Icons.female_rounded,
            label: 'Пол',
            value: widget.userData.isMale ? 'Мужской' : 'Женский',
          ),
          _divider(),
          GestureDetector(
            onTap: () => _showThemePicker(context),
            behavior: HitTestBehavior.opaque,
            child: _infoRow(
              icon: Icons.palette_outlined,
              label: 'Тема',
              value: widget.userData.themeName,
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
          if (trailing != null) trailing,
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
    if (_selectedPartnerUid != null) {
      final found = allPartners.where(
        (p) => p.member.uid == _selectedPartnerUid,
      );
      selectedPartner = found.isNotEmpty ? found.first : null;
    }
    selectedPartner ??= allPartners.isNotEmpty ? allPartners.first : null;

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
    final daysString = startDate != null
        ? '${DateTime.now().difference(startDate).inDays} дней'
        : '—';

    final hasPaired = allPartners.isNotEmpty;

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ОТНОШЕНИЯ',
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
                        'Статус',
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
              label: 'Партнёр',
              value: selectedPartner?.member.name.isNotEmpty == true
                  ? selectedPartner!.member.name
                  : 'Не выбран',
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
              label: 'Вместе',
              value: daysString,
            ),
          ],
          if (!hasPaired) ...[
            const SizedBox(height: 12),
            Text(
              'Пригласите партнёра, чтобы начать\nсчитать дни вместе ❤️',
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
        return 'Влюблённые';
      case RelationshipType.married:
        return 'Женаты';
      case RelationshipType.friends:
        return 'Друзья';
      case RelationshipType.buddies:
        return 'Лучшие друзья';
      case RelationshipType.custom:
        return 'Свой статус';
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
                    'Тип отношений',
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
          content: const Text('Нет подключённых партнёров'),
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
                    'Выберите партнёра',
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
                    setState(() => _selectedPartnerUid = entry.member.uid);
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
                                  child: Image.network(
                                    entry.member.avatar,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
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
                                    : 'Партнёр',
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
            'НАСТРОЙКИ',
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
            label: 'Редактировать профиль',
            onTap: () => _showEditProfileDialog(context),
          ),
          _divider(),
          _settingsTile(
            icon: Icons.palette_outlined,
            label: 'Тема',
            onTap: () => _showThemePicker(context),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
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
            icon: Icons.notifications_outlined,
            label: 'Уведомления',
            onTap: () {},
          ),
          _divider(),
          _settingsTile(
            icon: Icons.lock_outline_rounded,
            label: 'Конфиденциальность',
            onTap: () {},
          ),
          _divider(),
          _settingsTile(
            icon: Icons.info_outline_rounded,
            label: 'О приложении',
            onTap: () {},
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
  //  DANGER ZONE
  // ═══════════════════════════════════════════════════
  Widget _buildDangerZone(BuildContext context) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Love App v1.0.0',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
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
                  'Выйти из аккаунта',
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
                          'Выбери цветовую тему',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Изменения применяются сразу',
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
                          return GestureDetector(
                            onTap: () async {
                              await widget.userData.setThemeId(i);
                              setSheet(() {});
                              setState(() {});
                            },
                            child: AnimatedContainer(
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
                                            t.name,
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
    final emailCtrl = TextEditingController(text: widget.userData.email);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Редактировать профиль'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Имя',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              decoration: InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              widget.userData.updateProfile(
                displayName: nameCtrl.text.trim(),
                email: emailCtrl.text.trim(),
              );
              Navigator.of(ctx).pop();
            },
            child: Text('Сохранить', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Выйти?'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await widget.userData.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => WelcomeScreen(userData: widget.userData),
                  ),
                  (_) => false,
                );
              }
            },
            child: Text('Выйти', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }
}
