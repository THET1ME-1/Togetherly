import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/timer_page.dart';

import '../models/timer_item.dart';
import '../services/timer_service.dart';
import '../theme/app_theme.dart';
import '../services/locale_service.dart';
import '../models/symbol_catalog.dart';
import '../theme/profile_theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/petal_timer_dial.dart';
import '../widgets/common/app_dialog.dart';
import 'date_time_picker_screen.dart';
import 'symbol_picker_screen.dart';

/// Карусель таймеров с ИДЕАЛЬНОЙ геометрией радиального меню, адаптированной под размеры контейнера.
class ExpandableTimerCard extends StatefulWidget {
  final AppTheme theme;
  final TimerService timerService;
  final String partnerAvatarUrl;
  final String myAvatarUrl;
  final bool isPaired;
  final ValueChanged<bool>? onExpandChanged;
  final ValueChanged<String>? onPetalTap;

  const ExpandableTimerCard({
    super.key,
    required this.theme,
    required this.timerService,
    required this.partnerAvatarUrl,
    required this.myAvatarUrl,
    required this.isPaired,
    this.onExpandChanged,
    this.onPetalTap,
  });

  @override
  State<ExpandableTimerCard> createState() => _ExpandableTimerCardState();
}

class _ExpandableTimerCardState extends State<ExpandableTimerCard> {
  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _ticker;

  /// Листал ли человек карусель сам. Пока нет — держим основной таймер, даже
  /// если список приехал уже после первого кадра.
  bool _userSwiped = false;

  AppTheme get _t => widget.theme;

  @override
  void initState() {
    super.initState();
    final timers = widget.timerService.timers;
    final defaultT = widget.timerService.defaultTimer;
    _currentIndex = timerPageFor(
      ids: [for (final t in timers) t.id],
      defaultId: defaultT?.id,
      current: 0,
      userSwiped: false,
    );

    _pageController = PageController(initialPage: _currentIndex);
    widget.timerService.addListener(_onTimerChanged);
    _startTicker();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ticker?.cancel();
    widget.timerService.removeListener(_onTimerChanged);
    super.dispose();
  }

  void _onTimerChanged() {
    if (!mounted) return;
    final timers = widget.timerService.timers;
    if (timers.isNotEmpty && _currentIndex >= timers.length) {
      // После удаления — переходим на системный таймер, иначе на последний
      final sysIdx = timers.indexWhere((t) => t.isSystem);
      _currentIndex = sysIdx >= 0 ? sysIdx : timers.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      });
    } else {
      // Список таймеров приезжает позже первого кадра, и до 13 августа 2026
      // карусель так и оставалась на нулевой странице — человек каждый запуск
      // доматывал до своего таймера рукой.
      final want = timerPageFor(
        ids: [for (final t in timers) t.id],
        defaultId: widget.timerService.defaultTimer?.id,
        current: _currentIndex,
        userSwiped: _userSwiped,
      );
      if (want != _currentIndex) {
        _currentIndex = want;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(_currentIndex);
          }
        });
      }
    }
    setState(() {});
  }

  /// Секундный тик карточки.
  ///
  /// Раньше он раз в секунду пересобирал ВСЮ карточку: карусель, круг, кнопки,
  /// подписи. Цифры на круге обновляет сам круг (`PetalTimerDial` тикает своим
  /// тикером и рисует мимо дерева), поэтому карточке остаётся редкая работа —
  /// подписи с днями, а они меняются раз в сутки. Минута вместо секунды даёт
  /// шестьдесят перестроек в час вместо трёх с половиной тысяч.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _goToPage(int page) {
    // Листание руками: дальше карусель не возвращается к основному таймеру
    // сама, даже если список обновится.
    _userSwiped = true;
    if (page >= 0 && page < widget.timerService.timers.length) {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final timers = widget.timerService.timers;
    if (timers.isEmpty) {
      return SizedBox(
        height: 300,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(LocaleService.current.noTimers),
              const SizedBox(height: 16),
              _RadialButton(
                icon: Icons.add_rounded,
                onTap: _showCreateDialog,
                theme: _t,
              ),
              const SizedBox(height: 10),
              Text(
                LocaleService.current.createTimer,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _t.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Получаем реальную ширину КОНТЕЙНЕРА, а не экрана
        final actualWidth = constraints.maxWidth;
        // Диаграмма занимает почти всю ширину, кнопки могут "парить" за пределами благодаря Clip.none
        final dialSize = actualWidth * 0.95;

        // Уменьшаем отступ, так как Clip.none позволяет кнопкам парить выше
        final topPadding = 45.0;
        final containerHeight = dialSize + topPadding + 10;

        final centerX = actualWidth / 2;
        final centerY = topPadding + (dialSize / 2);

        return SizedBox(
          height: containerHeight,
          width: actualWidth,
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              // 1. Carousel
              Positioned(
                top: topPadding,
                child: SizedBox(
                  width: actualWidth,
                  height: dialSize,
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (idx) {
                      setState(() => _currentIndex = idx);
                      // setDefault не вызываем здесь — менять основной таймер
                      // должен только явный переключатель в диалоге настроек.
                      // Вызов на каждый свайп приводил к дублям isDefault=true
                      // при race condition с Firestore-слушателем.
                    },
                    itemCount: timers.length,
                    itemBuilder: (context, index) {
                      return Center(
                        child: SizedBox(
                          width: dialSize,
                          height: dialSize,
                          child: PetalTimerDial(
                            theme: _t,
                            startDate: timers[index].startDate,
                            isCountdown: timers[index].isCountdown,
                            onPetalTap: widget.onPetalTap,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // 2. Arc Controls
              _buildArcControls(dialSize / 2, centerX, centerY),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArcControls(double radius, double centerX, double centerY) {
    final timers = widget.timerService.timers;
    final timer = timers[_currentIndex];

    final actions = [
      _ArcAction(
        icon: Icons.chevron_left_rounded,
        onTap: () => _goToPage(_currentIndex - 1),
        visible: _currentIndex > 0,
      ),
      _ArcAction(icon: Icons.edit_rounded, onTap: () => _showEditDialog(timer)),
      _ArcAction(icon: Icons.add_rounded, onTap: _showCreateDialog),
      _ArcAction(
        icon: Icons.delete_outline_rounded,
        onTap: () => _showDeleteConfirm(timer),
        visible: !timer.isSystem,
      ),
      _ArcAction(
        icon: Icons.chevron_right_rounded,
        onTap: () => _goToPage(_currentIndex + 1),
        visible: _currentIndex < timers.length - 1,
      ),
    ];

    final visibleActions = actions.where((a) => a.visible).toList();

    const double fixedStep = 15.0;
    // СМЕЩАЕМ КЛАСТЕР НА 12 ЧАСОВ (-90 градусов)
    const double centerAngle = -90.0;
    final double startAngle =
        centerAngle - ((visibleActions.length - 1) * fixedStep / 2);

    // Сдвиг радиуса: диаграмма сама рисуется на radius-2.
    // Увеличено до +32 для существенного зазора.
    final buttonRadius = radius + 32;

    return Stack(
      clipBehavior: Clip.none,
      children: List.generate(visibleActions.length, (i) {
        final angleDeg = startAngle + (fixedStep * i);
        final angleRad = angleDeg * math.pi / 180;

        final x = buttonRadius * math.cos(angleRad);
        final y = buttonRadius * math.sin(angleRad);

        return Positioned(
          left: centerX + x - 18,
          top: centerY + y - 18,
          child: _RadialButton(
            icon: visibleActions[i].icon,
            onTap: visibleActions[i].onTap,
            theme: _t,
          ),
        );
      }),
    );
  }

  // ── Action Handlers ──

  void _showCreateDialog() {
    _showTimerSettingsDialog(
      title: LocaleService.current.createTimer,
      initialTitle: '',
      initialDate: DateTime.now(),
      // Новый таймер сразу заводится на имени символа, а не на эмодзи.
      initialEmoji: 'favorite',
      initialIsDefault: widget.timerService.count == 0,
      initialIsCountdown: false,
      onSave: (t, d, e, def, c) => widget.timerService.addTimer(
        title: t,
        startDate: d,
        emoji: e,
        isDefault: def,
        isCountdown: c,
      ),
    );
  }

  void _showEditDialog(TimerItem timer) {
    _showTimerSettingsDialog(
      title: LocaleService.current.editTimer,
      initialTitle: timer.title,
      initialDate: timer.startDate,
      initialEmoji: timer.emoji,
      initialIsDefault: timer.isDefault,
      initialIsCountdown: timer.isCountdown,
      onSave: (t, d, e, def, c) async {
        final saved = await widget.timerService.updateTimer(
          timer.copyWith(
            title: t,
            startDate: d,
            emoji: e,
            isDefault: def,
            isCountdown: c,
          ),
        );
        // Правка идёт через прокси и иногда не доезжает. Раньше об этом никто
        // не узнавал: дата на экране менялась, на сервере оставалась прежняя,
        // а партнёр видел старый счётчик.
        if (!saved && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LocaleService.current.timerSaveFailed)),
          );
        }
      },
    );
  }

  /// Лист создания и правки таймера.
  ///
  /// Раньше он жил на старых цветах: подписи капсом («НАЗВАНИЕ», «ДАТА
  /// НАЧАЛА»), кружки-радиокнопки вместо переключателей, «СОХРАНИТЬ» капсом и
  /// сетка из шестнадцати эмодзи на треть экрана. Теперь — M3-тема профиля,
  /// поля с меткой на контуре, живой предпросмотр сверху и пять символов на
  /// виду; остальные 4334 открываются поиском.
  void _showTimerSettingsDialog({
    required String title,
    required String initialTitle,
    required DateTime initialDate,
    required String initialEmoji,
    required bool initialIsDefault,
    required bool initialIsCountdown,
    required void Function(String, DateTime, String, bool, bool) onSave,
  }) {
    final cs = ProfileTheme.themeFor(_t).colorScheme;
    final s = LocaleService.current;
    final titleCtrl = TextEditingController(text: initialTitle);
    var pickedDate = initialDate;
    // В базе лежит либо имя символа (новые таймеры), либо эмодзи (старые) —
    // разбираем оба, наружу отдаём имя.
    var symbol = SymbolCatalog.nameFromStored(initialEmoji);
    var isDefault = initialIsDefault;
    var isCountdown = initialIsCountdown;

    // Каталог нужен, чтобы нарисовать символ; грузится один раз за запуск.
    unawaited(SymbolCatalog.load());

    showAppSheet<void>(
      context,
      background: cs.surfaceContainer,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final days = _daysBetween(pickedDate, isCountdown);
          return Theme(
            data: ProfileTheme.data(cs),
            child: SheetScaffold(
              bottom: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(s.cancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: FilledButton(
                      onPressed: () {
                        if (titleCtrl.text.trim().isEmpty) return;
                        onSave(
                          titleCtrl.text.trim(),
                          _normalizeTimerDate(pickedDate),
                          symbol,
                          isDefault,
                          isCountdown,
                        );
                        Navigator.pop(ctx);
                      },
                      child: Text(s.saveSettings),
                    ),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: ProfileTheme.displayFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Живой предпросмотр: символ, название и счёт дней сразу
                    // показывают, что получится.
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [cs.primaryContainer, cs.secondaryContainer],
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            alignment: Alignment.center,
                            child: SymbolIcon(symbol,
                                size: 27, color: cs.onPrimary),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  titleCtrl.text.trim().isEmpty
                                      ? s.timerNameLabel
                                      : titleCtrl.text.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onPrimaryContainer
                                        .withValues(alpha: 0.8),
                                  ),
                                ),
                                Text(
                                  s.timerDaysCount(days),
                                  style: TextStyle(
                                    fontFamily: ProfileTheme.displayFont,
                                    fontSize: 28,
                                    height: 1.1,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: titleCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setSheet(() {}),
                      decoration: InputDecoration(
                        labelText: s.timerNameLabel,
                        hintText: s.egAnniversary,
                        filled: true,
                        fillColor: cs.surfaceContainerHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Дата и время выбираются на своём экране крупными
                    // барабанами: набирать «дд.мм.гггг чч:мм» с системной
                    // клавиатуры дольше, чем прокрутить.
                    Material(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () async {
                          final picked =
                              await Navigator.of(ctx).push<DateTime>(
                            MaterialPageRoute<DateTime>(
                              builder: (_) => DateTimePickerScreen(
                                title: isCountdown ? s.targetDate : s.startDate,
                                theme: _t,
                                initial: pickedDate,
                                firstYear: 1900,
                                lastYear: 2100,
                              ),
                              settings:
                                  const RouteSettings(name: '/date_picker'),
                            ),
                          );
                          if (picked == null || !ctx.mounted) return;
                          setSheet(() => pickedDate = picked);
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isCountdown ? s.targetDate : s.startDate,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: cs.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatDate(pickedDate),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.calendar_month_rounded,
                                  color: cs.primary, size: 22),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (isCountdown && pickedDate.isBefore(DateTime.now()))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 16, color: cs.error),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                s.countdownPastDateWarning,
                                style:
                                    TextStyle(fontSize: 12, color: cs.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          s.symbolLabel,
                          style: TextStyle(
                            fontFamily: ProfileTheme.displayFont,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Пять привычных символов на виду; шестнадцать сеткой
                        // занимали треть листа, а выбирали из них те же пять.
                        for (final name in SymbolCatalog.quickPicks) ...[
                          Expanded(
                            child: _symbolBox(
                              cs: cs,
                              name: name,
                              selected: symbol == name,
                              onTap: () => setSheet(() => symbol = name),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Остальной каталог — отдельным экраном с поиском.
                        Material(
                          color: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: cs.outline),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () async {
                              final picked =
                                  await Navigator.of(ctx).push<String>(
                                MaterialPageRoute<String>(
                                  builder: (_) => SymbolPickerScreen(
                                    theme: _t,
                                    selected: symbol,
                                  ),
                                  settings: const RouteSettings(
                                      name: '/symbol_picker'),
                                ),
                              );
                              if (picked == null || !ctx.mounted) return;
                              setSheet(() => symbol = picked);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 13),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.grid_view_rounded,
                                      size: 18, color: cs.onSurface),
                                  const SizedBox(width: 6),
                                  Text(
                                    s.symbolPickerAll,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: isCountdown,
                            onChanged: (v) => setSheet(() => isCountdown = v),
                            title: Text(s.countdownMode),
                            subtitle: Text(s.countdownModeHint),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: cs.outlineVariant,
                          ),
                          SwitchListTile(
                            value: isDefault,
                            onChanged: (v) => setSheet(() => isDefault = v),
                            title: Text(s.setAsMain),
                            subtitle: Text(s.setAsMainHint),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Квадрат символа в ряду быстрого выбора.
  Widget _symbolBox({
    required ColorScheme cs,
    required String name,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 1,
          child: Center(
            child: SymbolIcon(
              name,
              size: 23,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  /// Сколько дней показывает предпросмотр: прошло от даты или осталось до неё.
  int _daysBetween(DateTime date, bool countdown) {
    final now = DateTime.now();
    final diff = countdown ? date.difference(now) : now.difference(date);
    final days = diff.inDays;
    return days < 0 ? 0 : days;
  }

  Future<void> _showDeleteConfirm(TimerItem timer) async {
    final ok = await AppDialog.confirm(
      context,
      title: LocaleService.current.deleteTimerQuestion,
      message: LocaleService.current.timerDeleteConfirm(timer.title),
      confirmLabel: LocaleService.current.delete,
      destructive: true,
      icon: Icons.timer_off_rounded,
    );
    if (!ok || !mounted) return;

    // deleteTimer правит список синхронно, поэтому ниже он уже обновлён.
    widget.timerService.deleteTimer(timer.id);
    final updatedTimers = widget.timerService.timers;
    if (updatedTimers.isEmpty) return;
    final sysIdx = updatedTimers.indexWhere((t) => t.isSystem);
    final targetIdx =
        (sysIdx >= 0 ? sysIdx : 0).clamp(0, updatedTimers.length - 1);
    setState(() => _currentIndex = targetIdx);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(targetIdx);
      }
    });
  }

  String _formatDate(DateTime d) {
    final date =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return '$date  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }


  DateTime _normalizeTimerDate(DateTime date) => date;
}

class _ArcAction {
  final IconData icon;
  final VoidCallback onTap;
  final bool visible;
  _ArcAction({required this.icon, required this.onTap, this.visible = true});
}

class _RadialButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final AppTheme theme;

  const _RadialButton({
    required this.icon,
    required this.onTap,
    required this.theme,
  });

  @override
  State<_RadialButton> createState() => _RadialButtonState();
}

class _RadialButtonState extends State<_RadialButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: widget.theme.fillColor,
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
