import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pair_data.dart';
import '../models/timer_item.dart';
import '../models/widget_data.dart';
import '../models/user_data.dart';
import '../models/mood_entry.dart';
import '../services/home_widget_service.dart';
import '../services/locale_service.dart';
import '../services/mood_service.dart';
import '../services/timer_service.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';

/// Экран виджетов — два тайла (мой / партнёра) + настройки автоотправки.
class WidgetScreen extends StatefulWidget {
  final UserData userData;
  final PairData pairData;
  final WidgetService widgetService;
  final MoodService moodService;
  final TimerService timerService;
  final AppTheme theme;

  const WidgetScreen({
    super.key,
    required this.userData,
    required this.pairData,
    required this.widgetService,
    required this.moodService,
    required this.timerService,
    required this.theme,
  });

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen> {
  AppTheme get _t => widget.theme;
  WidgetService get _ws => widget.widgetService;
  MoodService get _moodService => widget.moodService;
  TimerService get _timerService => widget.timerService;
  PairData get _pair => widget.pairData;
  AppStrings get _s => LocaleService.current;

  bool _canPinWidgets = false;
  bool _pairWidgetExpanded = false;
  bool _timerWidgetExpanded = false;
  String? _widgetTimerId;

  String get _widgetTimerKey => 'widget_timer_id_${_pair.pairId}';

  // Геттер: выбранный таймер для виджета (non-system)
  TimerItem? get _widgetTimer {
    final nonSystem = _timerService.timers.where((t) => !t.isSystem).toList();
    if (nonSystem.isEmpty) return null;
    if (_widgetTimerId != null) {
      try {
        return nonSystem.firstWhere((t) => t.id == _widgetTimerId);
      } catch (_) {}
    }
    return nonSystem.first;
  }

  @override
  void initState() {
    super.initState();
    _ws.addListener(_onDataChanged);
    _timerService.addListener(_onDataChanged);
    _moodService.addListener(_onDataChanged);
    _checkPinSupport();
    _loadWidgetTimerId();
    // Подписываемся на настроение партнёров
    for (final p in _pair.partners) {
      _moodService.listenToPartner(p.uid);
    }
  }

  Future<void> _loadWidgetTimerId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_widgetTimerKey);
    if (mounted) setState(() => _widgetTimerId = id);
  }

  Future<void> _selectWidgetTimer(TimerItem timer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_widgetTimerKey, timer.id);
    setState(() => _widgetTimerId = timer.id);
    await HomeWidgetService.instance.syncTimer(timer);
  }

  Future<void> _checkPinSupport() async {
    if (!Platform.isAndroid) return;
    // requestPinWidget supported on Android 8.0+ (API 26+) on most launchers.
    // Some launchers return false even though pinning works — show button anyway.
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      if (mounted)
        setState(() => _canPinWidgets = (supported ?? false) || true);
    } catch (e) {
      // Fallback: show button on Android regardless
      if (mounted) setState(() => _canPinWidgets = true);
    }
  }

  Future<void> _pinWidget(String qualifiedName, {String? widgetType}) async {
    try {
      await HomeWidget.requestPinWidget(qualifiedAndroidName: qualifiedName);
      // Привязываем виджет к текущей группе и СРАЗУ синхронизируем данные
      if (widgetType != null && _pair.pairId.isNotEmpty) {
        await HomeWidgetService.instance.bindWidgetToGroup(
          widgetType,
          _pair.pairId,
        );
        // Немедленно записать актуальные данные в виджет
        await _syncWidgetDataAfterPin(widgetType);
      }
    } catch (e) {
      debugPrint('Pin widget failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LocaleService.instance.isRussian
                  ? 'Не удалось добавить виджет'
                  : 'Failed to add widget',
            ),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  /// Сразу после пина записывает данные текущей группы в виджет.
  Future<void> _syncWidgetDataAfterPin(String widgetType) async {
    final hws = HomeWidgetService.instance;
    switch (widgetType) {
      case 'days_counter':
        final sysTimer = _timerService.systemTimer;
        final start = sysTimer?.startDate ?? _pair.startDate;
        final emoji = sysTimer?.emoji ?? _pair.relationshipEmoji;
        final days = sysTimer != null
            ? sysTimer.daysElapsed.abs()
            : (start != null ? DateTime.now().difference(start).inDays : 0);
        final startLabel = start != null
            ? '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')}.${start.year}'
            : '';
        final names = _pair.partnerName.isNotEmpty ? _pair.partnerName : '';
        await hws.syncDaysCounter(
          daysCount: days,
          coupleNames: names,
          emoji: emoji,
          startDate: startLabel,
        );
        break;
      case 'timer':
        final timer = _widgetTimer;
        if (timer != null) await hws.syncTimer(timer);
        break;
      case 'photo_day':
        await hws.refreshPhotoOfDay(_pair.pairId);
        break;
      case 'pair':
        // Парный виджет синхронизируется WidgetService
        break;
      case 'mood':
        // Синхронизируем из Mood Calendar за сегодня
        {
          final today = DateTime.now();
          final myEntries = _moodService.myEntriesForDay(today);
          final myEntry = myEntries.isNotEmpty ? myEntries.first : null;
          final partnerUid = _pair.partners.isNotEmpty
              ? _pair.partners.first.uid
              : '';
          final partnerEntries = partnerUid.isNotEmpty
              ? _moodService.partnerEntriesForDay(partnerUid, today)
              : <MoodEntry>[];
          final partnerEntry = partnerEntries.isNotEmpty
              ? partnerEntries.first
              : null;
          await hws.syncMood(
            moodEmojiAssetPath: myEntry?.imagePath ?? '',
            moodLabel: myEntry?.label ?? '',
            userName: _ws.myData?.displayName ?? '',
            partnerMoodEmojiAssetPath: partnerEntry?.imagePath ?? '',
            partnerMoodLabel: partnerEntry?.label ?? '',
            partnerUserName: _pair.partnerName,
          );
        }
        break;
    }
  }

  @override
  void didUpdateWidget(WidgetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pairData.pairId != widget.pairData.pairId) {
      // Сменилась группа — загружаем выбор таймера для новой группы
      _loadWidgetTimerId();
    }
  }

  @override
  void dispose() {
    _ws.removeListener(_onDataChanged);
    _timerService.removeListener(_onDataChanged);
    _moodService.removeListener(_onDataChanged);
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

    return Stack(
      fit: StackFit.expand,
      children: [
        _t.bgImageUrl != null
            ? CachedNetworkImage(
                imageUrl: _t.bgImageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, __) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _t.bgGradient,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _t.bgGradient,
                    ),
                  ),
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _t.bgGradient,
                  ),
                ),
              ),
        SafeArea(
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
                      // ── Галерея виджетов рабочего стола ──
                      _buildWidgetGallery(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
            _s.widgetsTitle,
            style: GoogleFonts.rubik(
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
                      _s.resetBtn,
                      style: GoogleFonts.rubik(
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
                _s.desktopPreview,
                style: GoogleFonts.rubik(
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
                        label: _s.me,
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
                            : _s.partner,
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
          style: GoogleFonts.rubik(
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
                  style: GoogleFonts.rubik(
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
          data.hasStatus ? data.status : _s.noStatus,
          style: GoogleFonts.rubik(
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
            style: GoogleFonts.rubik(
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
                    style: GoogleFonts.rubik(
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
  // WIDGET GALLERY — все виджеты с превью и кнопкой «Добавить»
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildWidgetGallery() {
    final isRu = LocaleService.instance.isRussian;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Icon(
                Icons.dashboard_customize_rounded,
                size: 16,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                isRu ? 'Виджеты рабочего стола' : 'Home Screen Widgets',
                style: GoogleFonts.rubik(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),

        // ── 1. Парный виджет ──
        _buildGalleryItem(
          title: isRu ? 'Парный виджет' : 'Pair Widget',
          subtitle: isRu
              ? 'Настроение, статус, сообщения и фото'
              : 'Mood, status, messages & photos',
          icon: Icons.favorite_rounded,
          iconColor: const Color(0xFFEE2B6C),
          qualifiedName: 'com.example.love_app.LoveWidgetProvider',
          preview: _buildWidgetPreview(),
          widgetType: 'pair',
          expandedContent: _buildPairWidgetExpandedContent(),
          isExpanded: _pairWidgetExpanded,
          onToggleExpand: () =>
              setState(() => _pairWidgetExpanded = !_pairWidgetExpanded),
        ),
        const SizedBox(height: 16),

        // ── 2. Счётчик дней вместе ──
        _buildGalleryItem(
          title: isRu ? 'Дни вместе' : 'Days Together',
          subtitle: isRu
              ? 'Системный счётчик дней отношений'
              : 'Relationship day counter',
          icon: Icons.calendar_today_rounded,
          iconColor: const Color(0xFFFF6B8A),
          qualifiedName: 'com.example.love_app.DaysCounterWidgetProvider',
          preview: _buildDaysCounterPreview(),
          widgetType: 'days_counter',
        ),
        const SizedBox(height: 16),

        // ── 3. Таймер ──
        _buildGalleryItem(
          title: isRu ? 'Таймер' : 'Timer',
          subtitle: isRu
              ? 'Выберите таймер для виджета'
              : 'Choose a timer for the widget',
          icon: Icons.timer_rounded,
          iconColor: const Color(0xFF8B5CF6),
          qualifiedName: 'com.example.love_app.TimerWidgetProvider',
          preview: _buildTimerPreview(),
          widgetType: 'timer',
          expandedContent: _buildTimerSelector(),
          isExpanded: _timerWidgetExpanded,
          onToggleExpand: () =>
              setState(() => _timerWidgetExpanded = !_timerWidgetExpanded),
        ),
        const SizedBox(height: 16),

        // ── 4. Фото дня ──
        _buildGalleryItem(
          title: isRu ? 'Фото дня' : 'Photo of the Day',
          subtitle: isRu
              ? 'Последнее фото из ленты воспоминаний'
              : 'Latest photo from Memory Lane',
          icon: Icons.photo_camera_rounded,
          iconColor: const Color(0xFFEC4899),
          qualifiedName: 'com.example.love_app.PhotoDayWidgetProvider',
          preview: _buildPhotoDayPreview(),
          widgetType: 'photo_day',
        ),
        const SizedBox(height: 16),

        // ── 5. Настроение ──
        _buildGalleryItem(
          title: isRu ? 'Настроение' : 'Mood',
          subtitle: isRu
              ? 'Горизонтальный виджет: моё и партнёра'
              : 'Horizontal widget: mine & partner\'s',
          icon: Icons.emoji_emotions_rounded,
          iconColor: const Color(0xFFFBBF24),
          qualifiedName: 'com.example.love_app.MoodWidgetProvider',
          preview: _buildMoodPreview(),
          widgetType: 'mood',
        ),
      ],
    );
  }

  Widget _buildGalleryItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required String qualifiedName,
    required Widget preview,
    String? widgetType,
    Widget? expandedContent,
    bool isExpanded = false,
    VoidCallback? onToggleExpand,
  }) {
    final isRu = LocaleService.instance.isRussian;

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Заголовок ──
          GestureDetector(
            onTap: onToggleExpand,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.rubik(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.rubik(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onToggleExpand != null)
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.grey.shade400,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ── Превью виджета ──
          ClipRRect(borderRadius: BorderRadius.circular(16), child: preview),
          // ── Кнопка «Добавить на рабочий стол» ──
          if (_canPinWidgets) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _pinWidget(qualifiedName, widgetType: widgetType),
                icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
                label: Text(
                  isRu ? 'Добавить на рабочий стол' : 'Add to Home Screen',
                  style: GoogleFonts.rubik(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _t.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
          // ── Раскрываемое содержимое ──
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            child: expandedContent != null && isExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Divider(color: Colors.grey.shade200, height: 1),
                      const SizedBox(height: 16),
                      expandedContent,
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Счётчик дней
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildDaysCounterPreview() {
    final isRu = LocaleService.instance.isRussian;
    // Данные берём ИЗ системного таймера (isSystem == true)
    final sysTimer = _timerService.systemTimer;
    final start = sysTimer?.startDate ?? _pair.startDate;
    final totalDays = sysTimer != null
        ? sysTimer.daysElapsed.abs()
        : (start != null ? DateTime.now().difference(start).inDays : 0);
    final startLabel = start != null
        ? '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')}.${start.year}'
        : '';

    final myGender = widget.userData.gender?.name ?? 'male';
    final partnerGender = _ws.firstPartnerData?.gender.isNotEmpty == true ? _ws.firstPartnerData!.gender : 'female';

    String imgName = 'widget_couple_mf';
    if (myGender == 'female' && partnerGender == 'female') {
      imgName = 'widget_couple_ff';
    } else if (myGender == 'male' && partnerGender == 'male') {
      imgName = 'widget_couple_mm';
    }

    final years = totalDays ~/ 365;
    String yearsText;
    if (years % 10 == 1 && years % 100 != 11) {
      yearsText = '$years год уже ❤️';
    } else if (years % 10 >= 2 && years % 10 <= 4 && (years % 100 < 10 || years % 100 >= 20)) {
      yearsText = '$years года уже ❤️';
    } else {
      yearsText = '$years лет уже ❤️';
    }
    
    if (!isRu) {
      yearsText = '$years years already ❤️';
    }

    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFFFD1DC), width: 3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(21)),
              child: Image.asset(
                'assets/images/widget/$imgName.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                yearsText,
                style: GoogleFonts.rubik(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF5D4037),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$totalDays',
                  style: GoogleFonts.rubik(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF5D4037),
                    height: 1.0,
                  ),
                ),
                Text(
                  isRu ? 'дней' : 'Days',
                  style: GoogleFonts.rubik(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF5D4037),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  startLabel,
                  style: GoogleFonts.rubik(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF5D4037),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Таймер
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildTimerPreview() {
    final timer = _widgetTimer;
    final isRu = LocaleService.instance.isRussian;

    if (timer == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F0FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              Icons.timer_off_rounded,
              size: 36,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              isRu ? 'Нет таймеров' : 'No timers',
              style: GoogleFonts.rubik(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isRu
                  ? 'Добавьте таймер в разделе «Таймеры»'
                  : 'Add a timer in the Timers section',
              style: GoogleFonts.rubik(
                fontSize: 11,
                color: Colors.grey.shade400,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final title = timer.title;
    final emoji = timer.emoji;
    final days = timer.daysElapsed.abs();
    final isCountdown = timer.isCountdown;
    final daysLabel = isCountdown
        ? (isRu ? 'дней осталось' : 'days left')
        : (isRu ? 'дней прошло' : 'days elapsed');
    final date = timer.formattedStartDate;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFFF3F0FF), const Color(0xFFEDE4FF)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: GoogleFonts.rubik(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$days',
            style: GoogleFonts.rubik(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF8B5CF6),
              height: 1.1,
            ),
          ),
          Text(
            daysLabel,
            style: GoogleFonts.rubik(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
          if (date.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              date,
              style: GoogleFonts.rubik(
                fontSize: 10,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВЫБОР ТАЙМЕРА ДЛЯ ВИДЖЕТА
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildTimerSelector() {
    final isRu = LocaleService.instance.isRussian;
    final nonSystem = _timerService.timers.where((t) => !t.isSystem).toList();

    if (nonSystem.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          isRu
              ? 'Нет таймеров. Добавьте таймер в разделе «Таймеры».'
              : 'No timers. Add a timer in the Timers section.',
          style: GoogleFonts.rubik(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isRu ? 'Выберите таймер для виджета:' : 'Select timer for widget:',
          style: GoogleFonts.rubik(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 10),
        ...nonSystem.map((timer) {
          final isSelected = timer.id == (_widgetTimerId ?? nonSystem.first.id);
          return GestureDetector(
            onTap: () => _selectWidgetTimer(timer),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF8B5CF6).withOpacity(0.1)
                    : Colors.grey.shade50,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF8B5CF6)
                      : Colors.grey.shade200,
                  width: isSelected ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(timer.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timer.title,
                          style: GoogleFonts.rubik(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? const Color(0xFF8B5CF6)
                                : Colors.grey.shade800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${timer.daysElapsed.abs()} '
                          '${timer.isCountdown ? (isRu ? 'дн. осталось' : 'd. left') : (isRu ? 'дн. прошло' : 'd. elapsed')} • ${timer.formattedStartDate}',
                          style: GoogleFonts.rubik(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: const Color(0xFF8B5CF6),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Фото дня
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPhotoDayPreview() {
    final isRu = LocaleService.instance.isRussian;

    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Заглушка
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📷', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 6),
                Text(
                  isRu ? 'Фото дня' : 'Photo of the Day',
                  style: GoogleFonts.rubik(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isRu
                      ? 'Последнее фото из воспоминаний'
                      : 'Latest photo from memories',
                  style: GoogleFonts.rubik(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          // Нижний оверлей
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.4)],
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Text('📸', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text(
                    isRu ? 'Фото дня' : 'Photo of the Day',
                    style: GoogleFonts.rubik(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
  // ВИДЖЕТ-ПРЕВЬЮ: Настроение
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildMoodPreview() {
    final isRu = LocaleService.instance.isRussian;
    final today = DateTime.now();

    // Моё настроение из Mood Calendar за сегодня
    final myEntries = _moodService.myEntriesForDay(today);
    final myEntry = myEntries.isNotEmpty ? myEntries.first : null;

    // Настроение партнёра из Mood Calendar за сегодня
    final partnerUid = _pair.partners.isNotEmpty
        ? _pair.partners.first.uid
        : '';
    final partnerEntries = partnerUid.isNotEmpty
        ? _moodService.partnerEntriesForDay(partnerUid, today)
        : <MoodEntry>[];
    final partnerEntry = partnerEntries.isNotEmpty
        ? partnerEntries.first
        : null;

    final myName = _ws.myData?.displayName.isNotEmpty == true
        ? _ws.myData!.displayName
        : (isRu ? 'Я' : 'Me');
    final partnerName = _pair.partnerName.isNotEmpty
        ? _pair.partnerName
        : (isRu ? 'Партнёр' : 'Partner');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8E1), Color(0xFFFFF3CD)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // ── Левая часть: Моё настроение ──
          Expanded(
            child: _buildMoodHalf(
              entry: myEntry,
              name: myName,
              isLeft: true,
              isRu: isRu,
            ),
          ),
          // ── Разделитель ──
          Container(
            width: 1,
            height: 80,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.grey.shade200.withOpacity(0),
                  Colors.grey.shade300,
                  Colors.grey.shade200.withOpacity(0),
                ],
              ),
            ),
          ),
          // ── Правая часть: Настроение партнёра ──
          Expanded(
            child: _buildMoodHalf(
              entry: partnerEntry,
              name: partnerName,
              isLeft: false,
              isRu: isRu,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodHalf({
    required MoodEntry? entry,
    required String name,
    required bool isLeft,
    required bool isRu,
  }) {
    return Column(
      crossAxisAlignment: isLeft
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text(
          name,
          style: GoogleFonts.rubik(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500,
            letterSpacing: 0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        if (entry != null) ...[
          Image.asset(
            entry.imagePath,
            width: 48,
            height: 48,
            errorBuilder: (_, __, ___) =>
                const Text('😶', style: TextStyle(fontSize: 36)),
          ),
          const SizedBox(height: 4),
          Text(
            entry.label,
            style: GoogleFonts.rubik(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFFF6B8A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ] else ...[
          const Text('😶', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 4),
          Text(
            isRu ? 'Нет' : 'None',
            style: GoogleFonts.rubik(
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PAIR WIDGET — раскрытые настройки
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPairWidgetExpandedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMyTile(),
        const SizedBox(height: 12),
        _buildPartnerTile(),
        const SizedBox(height: 12),
        _buildSettingsSection(),
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
                    _s.myWidget,
                    style: GoogleFonts.rubik(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  Text(
                    _s.tapToEdit,
                    style: GoogleFonts.rubik(
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
            label: _s.mood,
            value: data.hasMood ? data.moodLabel : null,
            trailing: data.hasMood
                ? Image.asset(data.moodEmoji, width: 24, height: 24)
                : null,
            onTap: () => _showMoodPicker(),
            onClear: data.hasMood
                ? () async {
                    final today = DateTime.now();
                    for (final e in _moodService.myEntriesForDay(today)) {
                      await _moodService.deleteMoodEntry(e.id);
                    }
                    _pair.clearMood();
                    _ws.clearMood();
                  }
                : null,
          ),
          _slotDivider(),
          _buildSlotRow(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: _t.primary,
            label: _s.status,
            value: data.hasStatus ? data.status : null,
            onTap: () => _showTextEditor(
              title: _s.status,
              hint: _s.statusHint,
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
            label: _s.message,
            value: data.hasMessage ? '«${data.message}»' : null,
            onTap: () => _showTextEditor(
              title: _s.message,
              hint: _s.messageHint,
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
            label: _s.photo,
            value: data.hasPhoto ? _s.photoUploaded : null,
            trailing: data.hasPhoto
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: data.photoUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      progressIndicatorBuilder: (context, url, downloadProgress) {
                        return Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _t.primary,
                                value: downloadProgress.progress,
                              ),
                            ),
                          ),
                        );
                      },
                      errorWidget: (context, url, error) => Container(
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
            label: _s.music,
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
        : _s.partner;

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
                    _s.widgetOfPartner(partnerName),
                    style: GoogleFonts.rubik(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  Text(
                    partner.isEmpty ? _s.emptyYet : _s.updated,
                    style: GoogleFonts.rubik(
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
                        style: GoogleFonts.rubik(
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
            label: _s.mood,
            value: partner.hasMood ? partner.moodLabel : null,
            trailing: partner.hasMood
                ? Image.asset(partner.moodEmoji, width: 24, height: 24)
                : null,
          ),
          _slotDivider(),
          _buildReadonlySlot(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: _t.primary,
            label: _s.status,
            value: partner.hasStatus ? partner.status : null,
          ),
          _slotDivider(),
          _buildReadonlySlot(
            icon: Icons.mail_outline_rounded,
            iconColor: const Color(0xFFEC4899),
            label: _s.message,
            value: partner.hasMessage ? '«${partner.message}»' : null,
          ),
          _slotDivider(),
          _buildReadonlySlot(
            icon: Icons.photo_camera_outlined,
            iconColor: _t.iconPost,
            label: _s.photo,
            value: partner.hasPhoto ? _s.photo : null,
            trailing: partner.hasPhoto
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: partner.photoUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      progressIndicatorBuilder: (context, url, downloadProgress) {
                        return Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _t.primary,
                                value: downloadProgress.progress,
                              ),
                            ),
                          ),
                        );
                      },
                      errorWidget: (context, url, error) => Container(
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
            label: _s.music,
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
                _s.widgetSettings,
                style: GoogleFonts.rubik(
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
                title: _s.photoToMemoryLane,
                subtitle: _s.autoSavePhotoToMemories,
                value: _ws.autoSendPhotoToMemory,
                onChanged: (v) => _ws.setAutoSendPhotoToMemory(v),
              ),
              _settingDivider(),
              _buildSettingToggle(
                icon: Icons.chat_outlined,
                iconColor: const Color(0xFFEC4899),
                title: _s.messagestoMemoryLane,
                subtitle: _s.autoSaveMessages,
                value: _ws.autoSendMessageToMemory,
                onChanged: (v) => _ws.setAutoSendMessageToMemory(v),
              ),
              _settingDivider(),
              _buildSettingToggle(
                icon: Icons.music_note_outlined,
                iconColor: _t.iconCalendar,
                title: _s.musicToMemoryLane,
                subtitle: _s.autoSaveTracks,
                value: _ws.autoSendMusicToMemory,
                onChanged: (v) => _ws.setAutoSendMusicToMemory(v),
              ),
              _settingDivider(),
              _buildSettingToggle(
                icon: Icons.calendar_month_outlined,
                iconColor: _t.iconMood,
                title: _s.moodToCalendar,
                subtitle: _s.autoMarkMoodCalendar,
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
                    style: GoogleFonts.rubik(
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
                      style: GoogleFonts.rubik(
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
                      _s.addBtn,
                      style: GoogleFonts.rubik(
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
                  style: GoogleFonts.rubik(
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
                    style: GoogleFonts.rubik(
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
                  style: GoogleFonts.rubik(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.rubik(
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
            _s.editBtn,
            style: GoogleFonts.rubik(
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
    return Stack(
      fit: StackFit.expand,
      children: [
        _t.bgImageUrl != null
            ? CachedNetworkImage(
                imageUrl: _t.bgImageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, __) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _t.bgGradient,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _t.bgGradient,
                    ),
                  ),
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _t.bgGradient,
                  ),
                ),
              ),
        Center(
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
                  _s.widgetsTitle,
                  style: GoogleFonts.rubik(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _s.connectPartnerForWidgets,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.rubik(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
        onSelect: (option) async {
          Navigator.pop(ctx);
          _pair.setMood(option.imagePath, option.label);
          // Добавляем в календарь с корректным id
          _moodService.addMood(
            moodId: option.id,
            imagePath: option.imagePath,
            label: option.label,
          );
          // skipCalendar: moodService уже добавил запись — не дублируем
          _ws.updateMood(option.imagePath, option.label, skipCalendar: true);
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
                  _s.uploadingPhoto,
                  style: GoogleFonts.rubik(fontSize: 14),
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
          _s.resetWidget,
          style: GoogleFonts.rubik(fontWeight: FontWeight.w700),
        ),
        content: Text(
          _s.resetWidgetConfirm,
          style: GoogleFonts.rubik(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _s.cancel,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_s.resetBtn, style: TextStyle(color: Colors.red)),
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
            LocaleService.current.chooseMood,
            style: GoogleFonts.rubik(
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
                            style: GoogleFonts.rubik(
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
              style: GoogleFonts.rubik(
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
              style: GoogleFonts.rubik(fontSize: 16),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: GoogleFonts.rubik(
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
                  LocaleService.current.save,
                  style: GoogleFonts.rubik(
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
            LocaleService.current.chooseSource,
            style: GoogleFonts.rubik(
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
                  label: LocaleService.current.camera,
                  source: ImageSource.camera,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _sourceButton(
                  context,
                  icon: Icons.photo_library_rounded,
                  label: LocaleService.current.gallery,
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
              style: GoogleFonts.rubik(
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
              LocaleService.current.music,
              style: GoogleFonts.rubik(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 20),
            _buildField(
              _titleCtrl,
              LocaleService.current.trackName,
              Icons.music_note_rounded,
            ),
            const SizedBox(height: 12),
            _buildField(
              _artistCtrl,
              LocaleService.current.artist,
              Icons.person_rounded,
            ),
            const SizedBox(height: 12),
            _buildField(
              _urlCtrl,
              LocaleService.current.linkOptional,
              Icons.link_rounded,
            ),
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
                  LocaleService.current.save,
                  style: GoogleFonts.rubik(
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
      style: GoogleFonts.rubik(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.rubik(color: Colors.grey.shade400),
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
