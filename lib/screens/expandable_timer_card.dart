import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/timer_item.dart';
import '../services/timer_service.dart';
import '../theme/app_theme.dart';

/// Расширяемая карточка таймера.
///
/// В свёрнутом виде показывает дефолтный таймер (или первый).
/// При раскрытии — вытягивается на весь экран вниз с ease-in-out анимацией,
/// показывая список всех таймеров с возможностью CRUD.
class ExpandableTimerCard extends StatefulWidget {
  final AppTheme theme;
  final TimerService timerService;
  final String partnerAvatarUrl;
  final String myAvatarUrl;
  final bool isPaired;

  /// Callback, уведомляющий родителя о состоянии раскрытия
  /// (чтобы скрывать bottom nav).
  final ValueChanged<bool>? onExpandChanged;

  const ExpandableTimerCard({
    super.key,
    required this.theme,
    required this.timerService,
    required this.partnerAvatarUrl,
    required this.myAvatarUrl,
    required this.isPaired,
    this.onExpandChanged,
  });

  @override
  State<ExpandableTimerCard> createState() => _ExpandableTimerCardState();
}

class _ExpandableTimerCardState extends State<ExpandableTimerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnim;
  late Animation<double> _arrowRotation;

  bool _expanded = false;
  int _selectedTimeUnit = 0; // 0=Days, 1=Months, 2=Time
  Timer? _ticker;
  String? _uploadingBackgroundId; // id таймера во время загрузки фона

  // Кешированные цвета — чтобы не создавать объекты на каждый кадр
  late Color _shadowColorBase;
  late Color _shadowColorExpanded;

  static const _darkOverlay = BoxDecoration(color: Color(0x59000000));
  static const _cardRadius = 32.0;

  AppTheme get _t => widget.theme;

  BorderRadius get _cardBorderRadius =>
      const BorderRadius.all(Radius.circular(_cardRadius));

  BoxDecoration get _cardDecoration => BoxDecoration(
    borderRadius: _cardBorderRadius,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: _t.heroGradient,
    ),
  );

  // Emoji palette для выбора
  static const _emojis = [
    '❤️',
    '💕',
    '💖',
    '🔥',
    '⭐',
    '🌙',
    '🎂',
    '🏠',
    '🎓',
    '💼',
    '✈️',
    '🐾',
    '🌸',
    '💍',
    '👶',
    '🎯',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _expandAnim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _arrowRotation = Tween<double>(
      begin: 0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _shadowColorBase = _t.heroShadowBase;
    _shadowColorExpanded = _t.heroShadowExpanded;

    widget.timerService.addListener(_onTimerChanged);
    _loadSelectedTimeUnit();
    _startTickerIfNeeded();
  }

  @override
  void dispose() {
    _controller.dispose();
    _ticker?.cancel();
    widget.timerService.removeListener(_onTimerChanged);
    super.dispose();
  }

  void _onTimerChanged() {
    if (mounted) setState(() {});
  }

  /// Загрузить сохраненное значение выбранного режима отображения
  Future<void> _loadSelectedTimeUnit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('timer_selected_time_unit');
      if (saved != null && saved >= 0 && saved <= 2) {
        setState(() => _selectedTimeUnit = saved);
        _startTickerIfNeeded();
      }
    } catch (e) {
      // Игнорируем ошибки загрузки
    }
  }

  /// Сохранить выбранный режим отображения
  Future<void> _saveSelectedTimeUnit(int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('timer_selected_time_unit', value);
    } catch (e) {
      // Игнорируем ошибки сохранения
    }
  }

  void _startTickerIfNeeded() {
    _ticker?.cancel();
    _ticker = null;
    if (_selectedTimeUnit == 2) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    widget.onExpandChanged?.call(_expanded);
  }

  // ── Helpers ──

  TimerItem? get _displayTimer => widget.timerService.defaultTimer;

  String _counterValue(TimerItem timer) {
    switch (_selectedTimeUnit) {
      case 0:
        final days = timer.daysElapsed;
        return days.abs().toString();
      case 1:
        final months = timer.monthsElapsed;
        return months.abs().toString();
      case 2:
        return timer.formattedTime;
      default:
        return '0';
    }
  }

  String _counterLabel(TimerItem timer) {
    final suffix = timer.isCountdown ? ' LEFT' : '';
    switch (_selectedTimeUnit) {
      case 0:
        return 'DAYS$suffix';
      case 1:
        return 'MONTHS$suffix';
      case 2:
        return timer.isCountdown ? 'TIME LEFT' : 'TIME';
      default:
        return 'DAYS$suffix';
    }
  }

  // =============================================
  // BUILD
  // =============================================
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenHeight = mq.size.height;
    final topPadding = mq.padding.top;
    final bottomPadding = mq.padding.bottom;
    // Высота карточки в свёрнутом виде
    const collapsedHeight = 280.0;
    const headerHeight = 64.0;
    const cardTopOffset = 16.0;
    const bottomNavHeight = 64.0;
    const bottomNavMargin = 12.0;
    const gap = 12.0;
    final expandedHeight =
        screenHeight -
        topPadding -
        headerHeight -
        cardTopOffset -
        bottomPadding -
        bottomNavMargin -
        bottomNavHeight -
        gap;

    // Кешируем child-виджеты, которые НЕ зависят от анимации
    final compactContent = _buildCompactContent();
    final bgImage = _buildBackgroundImage();

    return AnimatedBuilder(
      animation: _expandAnim,
      builder: (context, _) {
        final t = _expandAnim.value;
        final height = collapsedHeight + (expandedHeight - collapsedHeight) * t;

        return SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: _cardBorderRadius,
              boxShadow: [
                BoxShadow(
                  color: Color.lerp(_shadowColorBase, _shadowColorExpanded, t)!,
                  blurRadius: 32,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: _cardBorderRadius,
              child: DecoratedBox(
                decoration: _cardDecoration,
                child: _buildCardStack(
                  bgImage,
                  compactContent,
                  t,
                  bottomPadding,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardStack(
    Widget? bgImage,
    Widget compactContent,
    double t,
    double bottomPadding,
  ) {
    return Stack(
      children: [
        // -- Custom background image --
        if (bgImage != null) bgImage,
        // -- Gradient overlay (decorative circles) --
        // -- Content --
        Column(
          children: [
            compactContent,
            if (t > 0.01)
              Expanded(
                child: FadeTransition(
                  opacity: _expandAnim,
                  child: _buildExpandedContent(),
                ),
              )
            else
              const Spacer(),
          ],
        ),
        // -- Arrow button --
        Positioned(
          right: 16,
          bottom: 12 + bottomPadding * t,
          child: _buildArrowButton(),
        ),
      ],
    );
  }

  /// Фоновое изображение — кешированный виджет, не зависит от анимации
  Widget? _buildBackgroundImage() {
    final path = _displayTimer?.backgroundImagePath;
    if (path == null) return null;

    // Если идёт загрузка — показываем индикатор
    if (_uploadingBackgroundId == _displayTimer!.id) {
      return const SizedBox(
        height: 280,
        width: double.infinity,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Локальный путь (не URL) — не показываем партнёру
    if (!path.startsWith('http')) {
      debugPrint(
        'ExpandableTimerCard: backgroundImagePath не является URL ($path), пропускаем',
      );
      return null;
    }

    debugPrint('ExpandableTimerCard: загружаю фон из сети: $path');

    return SizedBox(
      height: 280,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              path,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              cacheWidth: 720,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: Colors.black26,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  ),
                );
              },
              errorBuilder: (_, error, __) {
                debugPrint('ExpandableTimerCard: ошибка загрузки фона: $error');
                return const SizedBox.shrink();
              },
            ),
          ),
          const Positioned.fill(child: DecoratedBox(decoration: _darkOverlay)),
        ],
      ),
    );
  }

  /// Фоновые фото — кешированный список, не зависит от анимации
  List<Widget>? _buildBackgroundPhotos() {
    if (!widget.isPaired || _displayTimer?.backgroundImagePath != null) {
      return null;
    }
    return [
      Positioned(
        top: -8,
        left: -16,
        child: _photoFragment(widget.myAvatarUrl, 80, 80, -0.2),
      ),
      Positioned(
        top: 48,
        right: 8,
        child: _photoFragment(widget.partnerAvatarUrl, 64, 64, 0.1),
      ),
      Positioned(
        bottom: -24,
        left: 60,
        child: _photoFragment(widget.myAvatarUrl, 96, 96, -0.05),
      ),
      Positioned(
        bottom: 16,
        right: -8,
        child: _photoFragment(widget.partnerAvatarUrl, 56, 56, 0.2),
      ),
    ];
  }

  // ── Compact content (shown always) ──
  Widget _buildCompactContent() {
    final timer = _displayTimer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 12),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Counter number — фиксированная высота чтобы не прыгало при смене режима
            SizedBox(
              height: 76,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  key: ValueKey(
                    '$_selectedTimeUnit-${timer != null ? _counterValue(timer) : "0"}',
                  ),
                  child: Text(
                    timer != null ? _counterValue(timer) : '0',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      color: timer != null
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Label
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                timer != null
                    ? '${_counterLabel(timer)} • ${timer.title}'
                    : 'NO TIMERS YET',
                key: ValueKey(
                  '${timer != null ? _counterLabel(timer) : 'none'}-${timer?.title}',
                ),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: timer != null
                      ? Colors.white.withOpacity(0.9)
                      : Colors.white.withOpacity(0.4),
                  letterSpacing: 2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            // Emoji
            if (timer != null)
              Text(timer.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            // Toggle
            _buildTimeToggle(),
          ],
        ),
      ),
    );
  }

  // ── Expanded content ──
  Widget _buildExpandedContent() {
    final timers = widget.timerService.timers;
    return Column(
      children: [
        const SizedBox(height: 8),
        Divider(color: Colors.white.withOpacity(0.2), height: 1),
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
          child: Row(
            children: [
              Text(
                'All Timers',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${timers.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              // Add button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showCreateDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'New',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: timers.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 60),
                  physics: const BouncingScrollPhysics(),
                  itemCount: timers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _buildTimerMiniCard(timers[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 48,
            color: Colors.white.withOpacity(0.35),
          ),
          const SizedBox(height: 12),
          Text(
            'No timers yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "New" to create your first timer',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.45),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mini card for each timer ──
  Widget _buildTimerMiniCard(TimerItem timer) {
    final isDefault = timer.isDefault;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDefault
              ? Colors.white.withOpacity(0.18)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDefault
                ? Colors.white.withOpacity(0.45)
                : Colors.white.withOpacity(0.20),
            width: isDefault ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showEditDialog(timer),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Emoji
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      timer.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              timer.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDefault) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'DEFAULT',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                          if (timer.isSystem) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'SYSTEM',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        timer.isCountdown
                            ? '${timer.daysElapsed.abs()} days left • until ${timer.formattedStartDate}'
                            : '${timer.daysElapsed} days • since ${timer.formattedStartDate}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                // Actions
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: Colors.white.withOpacity(0.70),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (v) => _onMenuAction(v, timer),
                  itemBuilder: (_) => [
                    if (!isDefault)
                      const PopupMenuItem(
                        value: 'default',
                        child: _PopupRow(
                          icon: Icons.star_rounded,
                          label: 'Set as default',
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'background',
                      child: _PopupRow(
                        icon: Icons.image_rounded,
                        label: 'Set background',
                      ),
                    ),
                    if (timer.backgroundImagePath != null)
                      const PopupMenuItem(
                        value: 'remove_bg',
                        child: _PopupRow(
                          icon: Icons.hide_image_outlined,
                          label: 'Remove background',
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: _PopupRow(icon: Icons.edit_rounded, label: 'Edit'),
                    ),
                    if (!timer.isSystem)
                      const PopupMenuItem(
                        value: 'delete',
                        child: _PopupRow(
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete',
                          danger: true,
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

  void _onMenuAction(String action, TimerItem timer) {
    switch (action) {
      case 'default':
        widget.timerService.setDefault(timer.id);
        break;
      case 'edit':
        _showEditDialog(timer);
        break;
      case 'delete':
        _showDeleteConfirm(timer);
        break;
      case 'background':
        _pickBackgroundImage(timer);
        break;
      case 'remove_bg':
        widget.timerService.removeTimerBackground(timer);
        break;
    }
  }

  Future<void> _pickBackgroundImage(TimerItem timer) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (image == null) return;

    // Показываем индикатор загрузки
    if (mounted) setState(() => _uploadingBackgroundId = timer.id);
    try {
      final ok = await widget.timerService.uploadTimerBackground(
        timer,
        image.path,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось загрузить фон. Проверьте подключение.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingBackgroundId = null);
    }
  }

  // ── Arrow button ──
  Widget _buildArrowButton() {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(_t.heroGlassOpacity),
          shape: BoxShape.circle,
        ),
        child: RotationTransition(
          turns: _arrowRotation,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  // ── Time toggle ──
  Widget _buildTimeToggle() {
    const labels = ['Days', 'Months', 'Time'];
    return Container(
      height: 40,
      constraints: const BoxConstraints(maxWidth: 240),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(_t.heroGlassOpacity * 0.75),
        borderRadius: BorderRadius.circular(24),
        border: _t.heroToggleBorder
            ? Border.all(color: Colors.white.withOpacity(0.3))
            : null,
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
                        _saveSelectedTimeUnit(i);
                        _startTickerIfNeeded();
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
                                ? _t.heroToggleSelectedColor
                                : Colors.white.withOpacity(
                                    _t.heroGlassOpacity * 4,
                                  ),
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

  // ── Photo fragment (background decoration) ──
  Widget _photoFragment(String url, double w, double h, double angle) {
    return RepaintBoundary(
      child: Transform.rotate(
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
      ),
    );
  }

  // =============================================
  // DIALOGS
  // =============================================

  /// Показать диалог создания нового таймера.
  void _showCreateDialog() {
    _showTimerFormDialog(
      title: 'New Timer',
      initialTitle: '',
      initialDate: DateTime.now(),
      initialEmoji: '❤️',
      initialIsDefault: widget.timerService.timers.isEmpty,
      initialIsCountdown: false,
      onSave: (title, date, emoji, isDefault, isCountdown) {
        widget.timerService.addTimer(
          title: title,
          startDate: date,
          emoji: emoji,
          isDefault: isDefault,
          isCountdown: isCountdown,
        );
      },
    );
  }

  /// Показать диалог редактирования таймера.
  void _showEditDialog(TimerItem timer) {
    _showTimerFormDialog(
      title: 'Edit Timer',
      initialTitle: timer.title,
      initialDate: timer.startDate,
      initialEmoji: timer.emoji,
      initialIsDefault: timer.isDefault,
      initialIsCountdown: timer.isCountdown,
      onSave: (title, date, emoji, isDefault, isCountdown) {
        widget.timerService.updateTimer(
          timer.copyWith(
            title: title,
            startDate: date,
            emoji: emoji,
            isDefault: isDefault,
            isCountdown: isCountdown,
          ),
        );
      },
    );
  }

  /// Общий форм-диалог для создания/редактирования.
  void _showTimerFormDialog({
    required String title,
    required String initialTitle,
    required DateTime initialDate,
    required String initialEmoji,
    required bool initialIsDefault,
    required bool initialIsCountdown,
    required void Function(
      String title,
      DateTime date,
      String emoji,
      bool isDefault,
      bool isCountdown,
    )
    onSave,
  }) {
    final titleCtrl = TextEditingController(text: initialTitle);
    final dateCtrl = TextEditingController(text: _formatDate(initialDate));
    var pickedDate = initialDate;
    var selectedEmoji = initialEmoji;
    var isDefault = initialIsDefault;
    var isCountdown = initialIsCountdown;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
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
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Title ──
                  Text(
                    'Name',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'e.g. Together with Alex',
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
                        borderSide: BorderSide(color: _t.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Date ──
                  Text(
                    isCountdown ? 'Target Date' : 'Start Date',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Manual input
                      Expanded(
                        child: TextField(
                          controller: dateCtrl,
                          style: const TextStyle(fontSize: 15),
                          keyboardType: TextInputType.datetime,
                          decoration: InputDecoration(
                            hintText: 'dd.mm.yyyy',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: _t.primary,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          onChanged: (v) {
                            final parsed = _parseDate(v);
                            if (parsed != null) {
                              setSheetState(() => pickedDate = parsed);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Calendar picker
                      GestureDetector(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: pickedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            builder: (c, child) => Theme(
                              data: Theme.of(c).copyWith(
                                colorScheme: ColorScheme.light(
                                  primary: _t.primary,
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (d != null) {
                            setSheetState(() {
                              pickedDate = d;
                              dateCtrl.text = _formatDate(d);
                            });
                          }
                        },
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: _t.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.calendar_today_rounded,
                            color: _t.primary,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Emoji ──
                  Text(
                    'Icon',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _emojis.map((e) {
                      final sel = selectedEmoji == e;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedEmoji = e),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: sel
                                ? _t.primary.withOpacity(0.12)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: sel
                                ? Border.all(color: _t.primary, width: 2)
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              e,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // ── Countdown toggle ──
                  GestureDetector(
                    onTap: () =>
                        setSheetState(() => isCountdown = !isCountdown),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCountdown
                                ? _t.primary
                                : Colors.transparent,
                            border: Border.all(
                              color: isCountdown
                                  ? _t.primary
                                  : Colors.grey.shade400,
                              width: 2,
                            ),
                          ),
                          child: isCountdown
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Countdown mode (days left until date)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Default toggle ──
                  GestureDetector(
                    onTap: () => setSheetState(() => isDefault = !isDefault),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDefault ? _t.primary : Colors.transparent,
                            border: Border.all(
                              color: isDefault
                                  ? _t.primary
                                  : Colors.grey.shade400,
                              width: 2,
                            ),
                          ),
                          child: isDefault
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Show by default when collapsed',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Save button ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        final t = titleCtrl.text.trim();
                        if (t.isEmpty) return;
                        // Парсим дату из поля, если пользователь ввёл вручную
                        final manualDate = _parseDate(dateCtrl.text);
                        final finalDate = manualDate ?? pickedDate;
                        onSave(
                          t,
                          finalDate,
                          selectedEmoji,
                          isDefault,
                          isCountdown,
                        );
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _t.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
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

  /// Диалог подтверждения удаления.
  void _showDeleteConfirm(TimerItem timer) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red.shade400,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Delete Timer?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '"${timer.title}" will be removed permanently.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          widget.timerService.deleteTimer(timer.id);
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade400,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Delete',
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

  // ── Helpers ──
  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  DateTime? _parseDate(String s) {
    // Формат dd.mm.yyyy
    final parts = s.split('.');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (year < 1900 || year > 2100) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }
}

// ── Popup menu row helper ──
class _PopupRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const _PopupRow({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red.shade400 : Colors.grey.shade700;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
