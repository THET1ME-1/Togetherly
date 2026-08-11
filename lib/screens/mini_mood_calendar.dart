import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import '../models/mood_entry.dart';
import '../widgets/mood_image.dart';
import '../services/mood_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';

/// Горизонтальный мини-календарь с настроениями по дням.
/// Листается бесконечно вперёд и назад. Сегодня — выделен.
/// При прокрутке от сегодня появляется кнопка «Сегодня».
class MiniMoodCalendar extends StatefulWidget {
  final MoodService moodService;
  final AppTheme theme;
  final void Function(DateTime date)? onDayTap;
  final void Function(bool visible)? onTodayButtonVisibilityChanged;

  const MiniMoodCalendar({
    super.key,
    required this.moodService,
    required this.theme,
    this.onDayTap,
    this.onTodayButtonVisibilityChanged,
  });

  static List<String> get _dayNames => LocaleService.current.shortWeekdaysUpper;

  @override
  State<MiniMoodCalendar> createState() => _MiniMoodCalendarState();
}

class _MiniMoodCalendarState extends State<MiniMoodCalendar> {
  // Виртуальный центр списка — сегодня
  static const int _kCenter = 500000;
  static const double _kCellWidth = 74.0;
  static const double _kSeparator = 10.0;
  static const double _kItemStride = _kCellWidth + _kSeparator;

  late final ScrollController _scrollController;

  /// Когда лента появилась на экране: первые полсекунды ячейки выходят
  /// очередью слева направо, дальше — сразу, как их построит прокрутка.
  final DateTime _mountedAt = DateTime.now();

  Duration _spawnDelay(int index) {
    if (DateTime.now().difference(_mountedAt) > const Duration(milliseconds: 500)) {
      return Duration.zero;
    }
    final first = _scrollController.hasClients
        ? (_scrollController.position.pixels / _kItemStride).floor()
        : index;
    final place = index - first;
    if (place < 0 || place > 6) return Duration.zero;
    return Duration(milliseconds: 45 * place);
  }
  late DateTime _today;
  late DateTime _todayNorm;
  Timer? _midnightTimer;

  bool _showBackToToday = false;
  double _todayScrollOffset = _kCenter * _kItemStride;
  int _lastDaysScrolled = 0;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _todayNorm = DateTime(_today.year, _today.month, _today.day);
    _scrollController = ScrollController(
      initialScrollOffset: _kCenter * _kItemStride,
    );
    _scrollController.addListener(_onScroll);
    // После первого фрейма сдвигаем скролл так, чтобы сегодня был последним справа
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final viewport = _scrollController.position.viewportDimension;
      _todayScrollOffset = (_kCenter * _kItemStride) - viewport + _kItemStride;
      _scrollController.jumpTo(_todayScrollOffset);
    });
    _scheduleMidnightUpdate();
  }

  /// Планирует таймер ровно на следующую полночь.
  void _scheduleMidnightUpdate() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final untilMidnight = nextMidnight.difference(now);
    _midnightTimer = Timer(untilMidnight, _onNewDay);
  }

  /// Вызывается в 00:00: обновляет «сегодня» и перепланирует таймер.
  void _onNewDay() {
    if (!mounted) return;
    setState(() {
      _today = DateTime.now();
      _todayNorm = DateTime(_today.year, _today.month, _today.day);
    });
    _scheduleMidnightUpdate();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final diff = (offset - _todayScrollOffset).abs() / _kItemStride;
    final shouldShow = diff > 0.8;
    if (shouldShow != _showBackToToday) {
      setState(() => _showBackToToday = shouldShow);
      widget.onTodayButtonVisibilityChanged?.call(shouldShow);
    }

    // Вибрация при пролистывании за экран каждого дня
    final daysScrolled = diff.floor();
    if (daysScrolled != _lastDaysScrolled) {
      _lastDaysScrolled = daysScrolled;
      HapticFeedback.selectionClick();
    }
  }

  void _scrollToToday() {
    _scrollController.animateTo(
      _todayScrollOffset,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Переводим виртуальный индекс → дата
  DateTime _dateForIndex(int index) {
    return _todayNorm.add(Duration(days: index - _kCenter));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 154,
          child: ListenableBuilder(
            listenable: widget.moodService,
            builder: (context, _) {
              return ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                clipBehavior: Clip.none,
                physics: const BouncingScrollPhysics(),
                // Ровно один день про запас: с большим кэшем ячейка успевала
                // отыграть появление ещё за краем экрана и выезжала готовой.
                cacheExtent: _kItemStride,
                itemCount: _kCenter * 2,
                itemExtent: _kItemStride,
                itemBuilder: (context, index) {
                  final date = _dateForIndex(index);

                  return AnimatedBuilder(
                    animation: _scrollController,
                    builder: (context, child) {
                      double dy = 0.0;
                      if (_scrollController.hasClients) {
                        final position = _scrollController.position;
                        final viewportWidth = position.viewportDimension;
                        final scrollOffset = position.pixels;

                        final viewportCenter =
                            scrollOffset + (viewportWidth / 2);
                        final itemCenter =
                            (index * _kItemStride) + (_kCellWidth / 2);
                        final distance = (itemCenter - viewportCenter).abs();

                        // Парарабола, чтобы боковые карточки опускались: dy = a * x^2
                        dy = (distance * distance) * 0.00075;
                        if (dy > 45.0) dy = 45.0; // ограничиваем сдвиг
                      }

                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: child,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: _kSeparator),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: RepaintBoundary(
                          child: _SpawnIn(
                            delay: _spawnDelay(index),
                            child: _DayCell(
                              date: date,
                              today: _today,
                              moodService: widget.moodService,
                              theme: widget.theme,
                              onTap: widget.onDayTap,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),

        // ── Кнопка «Today» — под списком, по центру ──
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _showBackToToday
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GestureDetector(
                    onTap: _scrollToToday,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: widget.theme.fillColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.today_rounded,
                            color: AppThemes.onColor(widget.theme.fillColor,
                                mode: widget.theme.brightness),
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            LocaleService.current.todayLabel,
                            style: TextStyle(
                              color: AppThemes.onColor(
                                widget.theme.fillColor,
                              ),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Появление ячейки календаря: масштаб от 0,86 и прозрачность, пружиной.
///
/// Ячейки строятся лениво, поэтому та же анимация работает и при прокрутке:
/// день, выехавший из-за края, не возникает готовым, а вырастает. На первом
/// кадре родитель раздаёт задержки слева направо, дальше задержки нет — иначе
/// при быстрой прокрутке дни отставали бы от пальца.
class _SpawnIn extends StatefulWidget {
  const _SpawnIn({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<_SpawnIn> createState() => _SpawnInState();
}

class _SpawnInState extends State<_SpawnIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 300,
    ratio: 0.75,
  );

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _ctrl.value = 1;
        return;
      }
      if (widget.delay == Duration.zero) {
        _ctrl.animateWith(SpringSimulation(_spring, 0, 1, 0));
      } else {
        Future.delayed(widget.delay, () {
          if (mounted) _ctrl.animateWith(SpringSimulation(_spring, 0, 1, 0));
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = _ctrl.value;
          return Opacity(
            opacity: t.clamp(0.0, 1.0) < 0.5 ? (t / 0.5).clamp(0.0, 1.0) : 1.0,
            child: Transform.scale(scale: 0.86 + 0.14 * t, child: child),
          );
        },
        child: widget.child,
      );
}

class _DayCell extends StatefulWidget {
  final DateTime date;
  final DateTime today;
  final MoodService moodService;
  final AppTheme theme;
  final void Function(DateTime)? onTap;

  const _DayCell({
    required this.date,
    required this.today,
    required this.moodService,
    required this.theme,
    this.onTap,
  });

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> with TickerProviderStateMixin {
  int _currentIndex = 0;
  Timer? _timer;

  double _displayFactor = 0.0;
  Ticker? _chaseTicker;
  DateTime? _lastProcessedDate;

  // Анимация пульсации при наступлении нового дня
  AnimationController? _newDayPulseController;
  Animation<double>? _newDayScaleAnimation;

  bool get isToday =>
      widget.date.year == widget.today.year &&
      widget.date.month == widget.today.month &&
      widget.date.day == widget.today.day;

  bool get isFuture => widget.date.isAfter(
    DateTime(widget.today.year, widget.today.month, widget.today.day),
  );

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();

    // Инициализируем _lastProcessedDate
    _lastProcessedDate = widget.date;

    // Если это сегодня, инициализируем _displayFactor текущим временем
    if (isToday) {
      final now = DateTime.now();
      final secToday =
          now.hour * 3600 +
          now.minute * 60 +
          now.second +
          (now.millisecond / 1000.0);
      _displayFactor = (secToday / 86400.0).clamp(0.0, 1.0);
    } else {
      _displayFactor = 0.0;
    }

    _updateAnimationState();
  }

  void _updateAnimationState() {
    // Проверяем, изменилась ли дата
    final dateChanged =
        _lastProcessedDate != null &&
        (_lastProcessedDate!.year != widget.date.year ||
            _lastProcessedDate!.month != widget.date.month ||
            _lastProcessedDate!.day != widget.date.day);

    _lastProcessedDate = widget.date;

    // Останавливаем старый ticker если дата больше не "сегодня"
    if (!isToday && _chaseTicker != null) {
      _chaseTicker?.stop();
      _chaseTicker?.dispose();
      _chaseTicker = null;
      _displayFactor = 0.0;
    }

    // Запускаем новый ticker если это "сегодня" и его нет
    if (isToday && _chaseTicker == null) {
      try {
        _chaseTicker = createTicker(_onChaseTick)..start();
        debugPrint(
          '_DayCell: Ticker started for date=${widget.date}, theme=${widget.theme.name}',
        );
      } catch (e) {
        debugPrint('Error creating ticker for day cell: $e');
      }
    }

    // Сброс анимации если дата изменилась
    if (dateChanged && !isToday) {
      _displayFactor = 0.0;
    }

    // Смена суток (полночь): ячейка остаётся «сегодня», но дата изменилась
    if (dateChanged && isToday) {
      _displayFactor = 0.0; // новый день — заполнение начинается с нуля
      _playNewDayPulse();
    }
  }

  /// Запускает кратковременную пульсирующую анимацию масштаба при наступлении нового дня.
  void _playNewDayPulse() {
    _newDayPulseController?.stop();
    _newDayPulseController?.dispose();
    _newDayPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _newDayScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.08,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 65,
      ),
    ]).animate(_newDayPulseController!);
    _newDayPulseController!.addListener(() {
      if (mounted) setState(() {});
    });
    _newDayPulseController!.forward().whenComplete(() {
      if (mounted) {
        setState(() {
          _newDayScaleAnimation = null;
          _newDayPulseController?.dispose();
          _newDayPulseController = null;
        });
      }
    });
  }

  void _onChaseTick(Duration elapsed) {
    // Проверяем, что widget всё ещё существует и это "сегодня"
    if (!mounted || !isToday) {
      _chaseTicker?.stop();
      return;
    }

    final now = DateTime.now();
    // Вычисляем процент прошедшего времени за сегодняшний день
    final secToday =
        now.hour * 3600 +
        now.minute * 60 +
        now.second +
        (now.millisecond / 1000.0);
    final target = (secToday / 86400.0).clamp(0.0, 1.0);

    final oldDisplayFactor = _displayFactor;
    final diff = target - _displayFactor;

    // Плавное заполнение, как в PetalTimerDial
    if (diff.abs() > 0.0005) {
      _displayFactor += diff * 0.15;
    } else if ((_displayFactor - target).abs() > 0.00001) {
      _displayFactor = target;
    }

    // Проверяем, есть ли заметное изменение
    if ((oldDisplayFactor - _displayFactor).abs() > 0.0001) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void didUpdateWidget(_DayCell old) {
    super.didUpdateWidget(old);

    // Всегда проверяем состояние анимации при обновлении виджета
    _updateAnimationState();
    _maybeStartTimer();
  }

  void _maybeStartTimer() {
    // Для сегодняшней ячейки НИКОГДА не циклим — должна совпадать с шапкой,
    // которая показывает только последнюю запись. Цикл для прошлых дат
    // имеет смысл показать историю настроений за день — НО только если включён
    // режим «несколько настроений в день». В одиночном режиме (по умолчанию)
    // день показывает последнее настроение без мелькания, даже если в данных
    // случайно остались дубли (напр. после смены пака настроений: поставили
    // классическое, потом розовое — оба записались, и иконка мигала classic↔pink
    // каждые 5 сек). _currentIndex=0 → build берёт entries[0] = последнюю запись.
    if (isToday || !widget.moodService.allowMultipleMoodsPerDay) {
      _timer?.cancel();
      _timer = null;
      _currentIndex = 0;
      return;
    }
    final entries = widget.moodService.myEntriesForDay(widget.date);
    if (entries.length > 1 && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) {
          setState(() {
            final entries = widget.moodService.myEntriesForDay(widget.date);
            if (entries.length > 1) {
              _currentIndex = (_currentIndex + 1) % entries.length;
            }
          });
        }
      });
    } else if (entries.length <= 1) {
      _timer?.cancel();
      _timer = null;
      _currentIndex = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chaseTicker?.dispose();
    _newDayPulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.moodService.myEntriesForDay(widget.date);
    final safeIndex = entries.isEmpty ? 0 : _currentIndex % entries.length;
    final MoodEntry? current = entries.isNotEmpty ? entries[safeIndex] : null;
    final dayName = MiniMoodCalendar._dayNames[widget.date.weekday - 1];

    // Фон невыбранной пилюли: на светлых темах — прежнее полупрозрачное «стекло»
    // (белый овал), на тёмной — приподнятая графитовая поверхность, чтобы
    // пилюля не была светлым пятном на тёмном фоне.
    final Color cardBg = isToday
        ? widget.theme.timerDialBackground
        : (widget.theme.isDark
            ? widget.theme.cardSurface
            : Colors.white.withOpacity(0.75));

    // Число дня красится акцентом темы (`primary`): в светлой это винный или
    // розовый тон на белой плитке, в тёмной — светлый. Раньше здесь стоял
    // `navActiveIcon` — цвет ПОВЕРХ заливки, — и в тёмной теме числа 7, 8, 9
    // становились тёмными на тёмном и пропадали.
    final Color baseTextColor = widget.theme.primary.withValues(alpha: 0.75);
    final Color baseNumColor = widget.theme.primary;

    // Текст поверх заливки «сегодня» (слой 2). Фон этого слоя = navActiveIcon,
    // поэтому цвет берём контрастным именно к нему: на тёмной теме заливка
    // светлая → текст тёмный, на светлых темах → белый (как было).
    final Color fillTextColor = AppThemes.onColor(widget.theme.fillColor,
        mode: widget.theme.brightness);

    return GestureDetector(
      onTap: isFuture || widget.onTap == null ? null : () => widget.onTap!(widget.date),
      child: Transform.scale(
        scale: _newDayScaleAnimation?.value ?? 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 74,
          height: 118,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(100),
            // Свечение под сегодняшним днём убрано: цветная подсветка вокруг
            // капсулы читалась как ореол и спорила с заливкой внутри неё.
            // Сегодняшний день и без того выделен цветом и заполнением.
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Заполнение текущего дня снизу вверх
              if (isToday)
                FractionallySizedBox(
                  heightFactor: _displayFactor,
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: widget.theme.fillColor,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),

              // Контент (текст и иконка)
              Opacity(
                opacity: isFuture ? 0.35 : 1.0,
                child: Stack(
                  children: [
                    // Слой 1: Обычный текст (виден на пустом фоне)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Center(
                          child: Text(
                            dayName,
                            style: TextStyle(
                              fontFamily: ProfileTheme.bodyFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: isToday
                                  ? Colors.white.withOpacity(0.9)
                                  : baseTextColor,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Center(
                          child: Text(
                            widget.date.day.toString(),
                            style: const TextStyle(
                              fontFamily: ProfileTheme.displayFont,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ).copyWith(
                              color: isToday ? Colors.white : baseNumColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 500),
                            child:
                                current != null && current.imagePath.isNotEmpty
                                ? ClipOval(
                                    key: ValueKey(current.id),
                                    child: MoodImage(
                                      current.imagePath,
                                      width: 30,
                                      height: 30,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),

                    // Слой 2: Белый текст (виден только поверх заливки)
                    if (isToday)
                      ClipRect(
                        clipper: _BottomHeightClipper(_displayFactor),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Center(
                              child: Text(
                                dayName,
                                style: TextStyle(
                                  fontFamily: ProfileTheme.bodyFont,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: fillTextColor.withOpacity(0.9),
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Center(
                              child: Text(
                                widget.date.day.toString(),
                                // Тот же шрифт, что слоем ниже: пока здесь
                                // стоял системный, метрики расходились и число
                                // сегодняшнего дня двоилось по краю заливки.
                                style: const TextStyle(
                                  fontFamily: ProfileTheme.displayFont,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ).copyWith(color: fillTextColor),
                              ),
                            ),
                            // Иконка в инверсии не нужна, так как изображение само по себе цветное
                            const SizedBox(
                              height: 34,
                            ), // Отступ под цифрой, чтобы пропустить иконку
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ), // Transform.scale
      ),
    );
  }
}

class _BottomHeightClipper extends CustomClipper<Rect> {
  final double factor;
  _BottomHeightClipper(this.factor);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      0,
      size.height * (1 - factor),
      size.width,
      size.height,
    );
  }

  @override
  bool shouldReclip(_BottomHeightClipper oldClipper) =>
      oldClipper.factor != factor;
}
