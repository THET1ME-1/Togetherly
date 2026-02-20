import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../models/pair_data.dart';
import '../models/widget_data.dart';
import '../models/mood_entry.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';

/// Экран виджетов — два тайла (мой / партнёра) + настройки автоотправки.
class WidgetScreen extends StatefulWidget {
  final PairData pairData;
  final WidgetService widgetService;
  final AppTheme theme;

  const WidgetScreen({
    super.key,
    required this.pairData,
    required this.widgetService,
    required this.theme,
  });

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen> {
  AppTheme get _t => widget.theme;
  WidgetService get _ws => widget.widgetService;
  PairData get _pair => widget.pairData;

  @override
  void initState() {
    super.initState();
    _ws.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _ws.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_pair.isPaired) return _buildNotPaired();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _t.bgGradient,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                child: Column(
                  children: [
                    // ── Превью виджета для рабочего стола ──
                    _buildWidgetPreview(),
                    const SizedBox(height: 24),

                    // ── Мой виджет (редактируемый) ──
                    _buildMyTile(),
                    const SizedBox(height: 16),

                    // ── Виджет партнёра (только чтение) ──
                    _buildPartnerTile(),
                    const SizedBox(height: 24),

                    // ── Настройки ──
                    _buildSettingsSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HEADER
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _t.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.widgets_rounded, color: _t.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Text(
            'Виджеты',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const Spacer(),
          // Кнопка «Очистить мой виджет»
          if (_ws.myData != null && !_ws.myData!.isEmpty)
            GestureDetector(
              onTap: _confirmClearAll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.clear_all_rounded,
                      size: 16,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Сбросить',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // WIDGET PREVIEW (как выглядит на рабочем столе)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildWidgetPreview() {
    final my = _ws.myData ?? WidgetData(uid: '');
    final partner = _ws.firstPartnerData ?? WidgetData(uid: '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(
                Icons.phone_android_rounded,
                size: 14,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                'Превью на рабочем столе',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                _t.heroGradient[0],
                _t.heroGradient.length > 1
                    ? _t.heroGradient[1]
                    : _t.heroGradient[0],
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _t.heroShadowBase.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // ── Левая половина: Я ──
                    Expanded(
                      child: _buildPreviewHalf(
                        data: my,
                        label: 'Я',
                        isLeft: true,
                      ),
                    ),
                    // ── Разделитель ──
                    Container(
                      width: 1,
                      height: 80,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0),
                            Colors.white.withOpacity(0.5),
                            Colors.white.withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                    // ── Правая половина: Партнёр ──
                    Expanded(
                      child: _buildPreviewHalf(
                        data: partner,
                        label: _pair.partnerName.isNotEmpty
                            ? _pair.partnerName
                            : 'Партнёр',
                        isLeft: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewHalf({
    required WidgetData data,
    required String label,
    required bool isLeft,
  }) {
    return Column(
      crossAxisAlignment: isLeft
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        // Имя
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white.withOpacity(0.7),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        // Emoji
        if (data.hasMood)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(data.moodEmoji, width: 20, height: 20),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  data.moodLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          )
        else
          Text(
            '—',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        const SizedBox(height: 4),
        // Статус
        Text(
          data.hasStatus ? data.status : 'Нет статуса',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: data.hasStatus ? FontWeight.w600 : FontWeight.w400,
            color: Colors.white.withOpacity(data.hasStatus ? 0.95 : 0.35),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        // Сообщение
        if (data.hasMessage)
          Text(
            '«${data.message}»',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontStyle: FontStyle.italic,
              color: Colors.white.withOpacity(0.75),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        // Музыка
        if (data.hasMusic)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.music_note_rounded,
                  size: 10,
                  color: Colors.white.withOpacity(0.6),
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    '${data.musicTitle}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      color: Colors.white.withOpacity(0.65),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // MY TILE (editable)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildMyTile() {
    final data = _ws.myData ?? WidgetData(uid: '');

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_t.primary, _t.primary.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Мой виджет',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  Text(
                    'Нажми, чтобы изменить',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _buildEditBadge(),
            ],
          ),
          const SizedBox(height: 16),

          // ── Слоты ──
          _buildSlotRow(
            icon: Icons.emoji_emotions_outlined,
            iconColor: _t.iconMood,
            label: 'Настроение',
            value: data.hasMood ? data.moodLabel : null,
            trailing: data.hasMood
                ? Image.asset(data.moodEmoji, width: 24, height: 24)
                : null,
            onTap: () => _showMoodPicker(),
            onClear: data.hasMood ? () => _ws.clearMood() : null,
          ),
          _slotDivider(),
          _buildSlotRow(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: _t.primary,
            label: 'Статус',
            value: data.hasStatus ? data.status : null,
            onTap: () => _showTextEditor(
              title: 'Статус',
              hint: 'Что у тебя нового?',
              initial: data.status,
              maxLength: 50,
              onSave: (v) => _ws.updateStatus(v),
            ),
            onClear: data.hasStatus ? () => _ws.clearStatus() : null,
          ),
          _slotDivider(),
          _buildSlotRow(
            icon: Icons.mail_outline_rounded,
            iconColor: const Color(0xFFEC4899),
            label: 'Сообщение',
            value: data.hasMessage ? '«${data.message}»' : null,
            onTap: () => _showTextEditor(
              title: 'Сообщение',
              hint: 'Напиши что-нибудь приятное...',
              initial: data.message,
              maxLength: 200,
              onSave: (v) => _ws.updateMessage(v),
            ),
            onClear: data.hasMessage ? () => _ws.clearMessage() : null,
          ),
          _slotDivider(),
          _buildSlotRow(
            icon: Icons.photo_camera_outlined,
            iconColor: _t.iconPost,
            label: 'Фото',
            value: data.hasPhoto ? 'Фото загружено' : null,
            trailing: data.hasPhoto
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      data.photoUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.broken_image_rounded,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                : null,
            onTap: () => _pickPhoto(),
            onClear: data.hasPhoto ? () => _ws.clearPhoto() : null,
          ),
          _slotDivider(),
          _buildSlotRow(
            icon: Icons.music_note_rounded,
            iconColor: _t.iconCalendar,
            label: 'Музыка',
            value: data.hasMusic
                ? '${data.musicTitle} — ${data.musicArtist}'
                : null,
            onTap: () => _showMusicEditor(data),
            onClear: data.hasMusic ? () => _ws.clearMusic() : null,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PARTNER TILE (read-only)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPartnerTile() {
    final partner = _ws.firstPartnerData ?? WidgetData(uid: '');
    final partnerName = _pair.partnerName.isNotEmpty
        ? _pair.partnerName
        : 'Партнёр';

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                  image: _pair.partnerAvatarUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_pair.partnerAvatarUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _pair.partnerAvatarUrl.isEmpty
                    ? Icon(
                        Icons.person_rounded,
                        color: Colors.grey.shade500,
                        size: 18,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Виджет $partnerName',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  Text(
                    partner.isEmpty ? 'Пока пусто' : 'Обновлено',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (!partner.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.green.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Live',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Слоты (read-only) ──
          _buildReadonlySlot(
            icon: Icons.emoji_emotions_outlined,
            iconColor: _t.iconMood,
            label: 'Настроение',
            value: partner.hasMood ? partner.moodLabel : null,
            trailing: partner.hasMood
                ? Image.asset(partner.moodEmoji, width: 24, height: 24)
                : null,
          ),
          _slotDivider(),
          _buildReadonlySlot(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: _t.primary,
            label: 'Статус',
            value: partner.hasStatus ? partner.status : null,
          ),
          _slotDivider(),
          _buildReadonlySlot(
            icon: Icons.mail_outline_rounded,
            iconColor: const Color(0xFFEC4899),
            label: 'Сообщение',
            value: partner.hasMessage ? '«${partner.message}»' : null,
          ),
          _slotDivider(),
          _buildReadonlySlot(
            icon: Icons.photo_camera_outlined,
            iconColor: _t.iconPost,
            label: 'Фото',
            value: partner.hasPhoto ? 'Фото' : null,
            trailing: partner.hasPhoto
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      partner.photoUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.broken_image_rounded,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          _slotDivider(),
          _buildReadonlySlot(
            icon: Icons.music_note_rounded,
            iconColor: _t.iconCalendar,
            label: 'Музыка',
            value: partner.hasMusic
                ? '${partner.musicTitle} — ${partner.musicArtist}'
                : null,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SETTINGS SECTION
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                'Настройки виджета',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        _buildGlassCard(
          child: Column(
            children: [
              _buildSettingToggle(
                icon: Icons.photo_library_outlined,
                iconColor: _t.iconPost,
                title: 'Фото → Memory Lane',
                subtitle: 'Автоматически сохранять фото в воспоминания',
                value: _ws.autoSendPhotoToMemory,
                onChanged: (v) => _ws.setAutoSendPhotoToMemory(v),
              ),
              _settingDivider(),
              _buildSettingToggle(
                icon: Icons.chat_outlined,
                iconColor: const Color(0xFFEC4899),
                title: 'Сообщения → Memory Lane',
                subtitle: 'Автоматически сохранять сообщения',
                value: _ws.autoSendMessageToMemory,
                onChanged: (v) => _ws.setAutoSendMessageToMemory(v),
              ),
              _settingDivider(),
              _buildSettingToggle(
                icon: Icons.music_note_outlined,
                iconColor: _t.iconCalendar,
                title: 'Музыка → Memory Lane',
                subtitle: 'Автоматически сохранять треки',
                value: _ws.autoSendMusicToMemory,
                onChanged: (v) => _ws.setAutoSendMusicToMemory(v),
              ),
              _settingDivider(),
              _buildSettingToggle(
                icon: Icons.calendar_month_outlined,
                iconColor: _t.iconMood,
                title: 'Настроение → Календарь',
                subtitle: 'Автоматически отмечать в календаре настроений',
                value: _ws.autoSendMoodToCalendar,
                onChanged: (v) => _ws.setAutoSendMoodToCalendar(v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SLOT ROWS
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildSlotRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    String? value,
    Widget? trailing,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final hasValue = value != null;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (hasValue) ...[
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
            if (onClear != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ],
            if (!hasValue) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _t.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 14, color: _t.primary),
                    const SizedBox(width: 2),
                    Text(
                      'Добавить',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _t.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReadonlySlot({
    required IconData icon,
    required Color iconColor,
    required String label,
    String? value,
    Widget? trailing,
  }) {
    final hasValue = value != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.3,
                  ),
                ),
                if (hasValue) ...[
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
          if (!hasValue)
            Text(
              '—',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade300),
            ),
        ],
      ),
    );
  }

  Widget _buildSettingToggle({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 28,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: _t.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HELPERS / BUILDERS
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _t.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _t.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildEditBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _t.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_rounded, size: 12, color: _t.primary),
          const SizedBox(width: 4),
          Text(
            'Изменить',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _t.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotDivider() =>
      Divider(color: Colors.grey.shade100, height: 1, thickness: 1);

  Widget _settingDivider() =>
      Divider(color: Colors.grey.shade100, height: 8, thickness: 1);

  // ════════════════════════════════════════════════════════════════════════════
  // NOT PAIRED PLACEHOLDER
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildNotPaired() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _t.bgGradient,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _t.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.widgets_rounded,
                  size: 36,
                  color: _t.primary.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Виджеты',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Подключи партнёра, чтобы начать\nобмениваться виджетами',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // DIALOGS / EDITORS
  // ════════════════════════════════════════════════════════════════════════════

  void _showMoodPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MoodPickerSheet(
        theme: _t,
        onSelect: (option) {
          _ws.updateMood(option.imagePath, option.label);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showTextEditor({
    required String title,
    required String hint,
    required String initial,
    required int maxLength,
    required ValueChanged<String> onSave,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TextEditorSheet(
        theme: _t,
        title: title,
        hint: hint,
        initial: initial,
        maxLength: maxLength,
        onSave: (value) {
          onSave(value);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PhotoSourceSheet(theme: _t),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (file == null || !mounted) return;

    // Показываем лоадер
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
                CircularProgressIndicator(color: _t.primary),
                const SizedBox(height: 16),
                Text(
                  'Загружаем фото...',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await _ws.updatePhoto(file.path);
    if (mounted) Navigator.of(context).pop(); // закрываем лоадер
  }

  void _showMusicEditor(WidgetData data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MusicEditorSheet(
        theme: _t,
        initialTitle: data.musicTitle ?? '',
        initialArtist: data.musicArtist ?? '',
        initialUrl: data.musicUrl ?? '',
        onSave: ({required String title, required String artist, String? url}) {
          _ws.updateMusic(title: title, artist: artist, url: url);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Сбросить виджет?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Все данные твоего виджета будут очищены.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Сбросить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _ws.clearAll();
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MOOD PICKER SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _MoodPickerSheet extends StatelessWidget {
  final AppTheme theme;
  final ValueChanged<MoodOption> onSelect;

  const _MoodPickerSheet({required this.theme, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Выбери настроение',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: MoodOption.all.length,
              itemBuilder: (_, i) {
                final mood = MoodOption.all[i];
                return GestureDetector(
                  onTap: () => onSelect(mood),
                  child: Container(
                    decoration: BoxDecoration(
                      color: mood.color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: mood.color.withOpacity(0.2)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(mood.imagePath, width: 36, height: 36),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            mood.label,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: mood.color,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TEXT EDITOR SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _TextEditorSheet extends StatefulWidget {
  final AppTheme theme;
  final String title;
  final String hint;
  final String initial;
  final int maxLength;
  final ValueChanged<String> onSave;

  const _TextEditorSheet({
    required this.theme,
    required this.title,
    required this.hint,
    required this.initial,
    required this.maxLength,
    required this.onSave,
  });

  @override
  State<_TextEditorSheet> createState() => _TextEditorSheetState();
}

class _TextEditorSheetState extends State<_TextEditorSheet> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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
              widget.title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLength: widget.maxLength,
              maxLines: widget.maxLength > 100 ? 3 : 1,
              style: GoogleFonts.plusJakartaSans(fontSize: 16),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: GoogleFonts.plusJakartaSans(
                  color: Colors.grey.shade400,
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: widget.theme.primary,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => widget.onSave(_ctrl.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.theme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Сохранить',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PHOTO SOURCE SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _PhotoSourceSheet extends StatelessWidget {
  final AppTheme theme;

  const _PhotoSourceSheet({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
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
            'Выбери источник',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _sourceButton(
                  context,
                  icon: Icons.camera_alt_rounded,
                  label: 'Камера',
                  source: ImageSource.camera,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _sourceButton(
                  context,
                  icon: Icons.photo_library_rounded,
                  label: 'Галерея',
                  source: ImageSource.gallery,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sourceButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: theme.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.primary.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: theme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MUSIC EDITOR SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _MusicEditorSheet extends StatefulWidget {
  final AppTheme theme;
  final String initialTitle;
  final String initialArtist;
  final String initialUrl;
  final void Function({
    required String title,
    required String artist,
    String? url,
  })
  onSave;

  const _MusicEditorSheet({
    required this.theme,
    required this.initialTitle,
    required this.initialArtist,
    required this.initialUrl,
    required this.onSave,
  });

  @override
  State<_MusicEditorSheet> createState() => _MusicEditorSheetState();
}

class _MusicEditorSheetState extends State<_MusicEditorSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _artistCtrl;
  late TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _artistCtrl = TextEditingController(text: widget.initialArtist);
    _urlCtrl = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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
              'Музыка',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 20),
            _buildField(_titleCtrl, 'Название трека', Icons.music_note_rounded),
            const SizedBox(height: 12),
            _buildField(_artistCtrl, 'Исполнитель', Icons.person_rounded),
            const SizedBox(height: 12),
            _buildField(_urlCtrl, 'Ссылка (необязательно)', Icons.link_rounded),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  final title = _titleCtrl.text.trim();
                  final artist = _artistCtrl.text.trim();
                  if (title.isEmpty || artist.isEmpty) return;
                  final url = _urlCtrl.text.trim();
                  widget.onSave(
                    title: title,
                    artist: artist,
                    url: url.isNotEmpty ? url : null,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.theme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Сохранить',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      style: GoogleFonts.plusJakartaSans(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(color: Colors.grey.shade400),
        prefixIcon: Icon(icon, color: widget.theme.primary, size: 20),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: widget.theme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
