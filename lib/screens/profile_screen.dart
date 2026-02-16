import 'package:flutter/material.dart';
import '../models/user_data.dart';
import '../models/pair_data.dart';
import 'setup_screen.dart';

class ProfileScreen extends StatelessWidget {
  final UserData userData;
  final PairData pairData;
  const ProfileScreen({
    super.key,
    required this.userData,
    required this.pairData,
  });

  Color get _accent => userData.themeAccent;
  Color get _accentLight => userData.themeAccentLight;

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
              border: Border.all(color: _accent.withOpacity(0.25), width: 3),
            ),
            child: userData.avatarUrl.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      userData.avatarUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 200,
                      cacheHeight: 200,
                      errorBuilder: (_, __, ___) => _buildAvatarFallback(),
                    ),
                  )
                : _buildAvatarFallback(),
          ),
        ),
        const SizedBox(height: 16),
        // Name
        Text(
          userData.displayName.isNotEmpty
              ? userData.displayName
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
          userData.email.isNotEmpty ? userData.email : 'Нет email',
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
                userData.isMale ? Icons.male_rounded : Icons.female_rounded,
                color: _accent,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                userData.isMale ? 'Парень' : 'Девушка',
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
        userData.initials,
        style: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w800,
          color: _accent.withOpacity(0.6),
        ),
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
            value: userData.displayName.isNotEmpty ? userData.displayName : '—',
          ),
          _divider(),
          _infoRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: userData.email.isNotEmpty ? userData.email : '—',
          ),
          _divider(),
          _infoRow(
            icon: userData.isMale ? Icons.male_rounded : Icons.female_rounded,
            label: 'Пол',
            value: userData.isMale ? 'Мужской' : 'Женский',
          ),
          _divider(),
          _infoRow(
            icon: Icons.palette_outlined,
            label: 'Тема',
            value: userData.isMale ? 'Синяя' : 'Розовая',
            trailing: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(color: _accent.withOpacity(0.3), blurRadius: 6),
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
          // Status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: pairData.isPaired
                      ? const Color(0xFF22C55E).withOpacity(0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  pairData.isPaired ? Icons.favorite : Icons.favorite_border,
                  color: pairData.isPaired
                      ? const Color(0xFF22C55E)
                      : Colors.grey.shade400,
                  size: 18,
                ),
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
                      pairData.isPaired ? 'В паре' : 'Без пары',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: pairData.isPaired
                            ? const Color(0xFF22C55E)
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pairData.isPaired) ...[
            _divider(),
            _infoRow(
              icon: Icons.person_rounded,
              label: 'Партнёр',
              value: pairData.partnerName,
            ),
            _divider(),
            _infoRow(
              icon: Icons.calendar_today_rounded,
              label: 'Вместе',
              value: '${pairData.daysInLove} дней',
            ),
          ],
          if (!pairData.isPaired) ...[
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

  void _showEditProfileDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: userData.displayName);
    final emailCtrl = TextEditingController(text: userData.email);

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
              userData.updateProfile(
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
              await userData.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => SetupScreen(userData: userData),
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
