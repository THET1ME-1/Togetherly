import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models/miss_you_batch.dart';
import 'package:flutter/services.dart';
import '../models/optimistic_count.dart';
import '../services/miss_you_repository.dart';
import '../services/hint_queue.dart';
import '../services/pocketbase_service.dart';
import '../theme/app_theme.dart';
import 'miss_you_screen.dart';

// ─── Раскладка ─────────────────────────────────────────────────────────────────
//
//  [ 295 / 155 ]  [ ♥ ]
//     счёт пары   отправить
//
//  Тап по счёту  → экран «Скучаю» (счётчики, другие импульсы, дни недели).
//  Тап по сердцу → отправить «скучаю».
//
//  Действие уехало с широкой пилюли на сердце намеренно: пилюля показывает
//  СОСТОЯНИЕ, и случайный тап по ней больше не шлёт партнёру импульс. Заодно
//  ушла надпись, лежавшая ровно на стыке заливки и трека прогресса, — читать
//  её было нечем: половина букв приходилась на один фон, половина на другой.
//
//  Панель вайбов из-под кнопки убрана 11 августа 2026: три строки с полосками
//  разделителей, обводкой и кеглем 13 не были ни M3, ни удобными. Всё, что она
//  умела, переехало на экран, где для этого есть место.

class MissYouButton extends StatefulWidget {
  final AppTheme theme;
  final String groupId;
  final String senderName;
  final bool enabled;

  /// Партнёр — для шапки экрана: аватар, имя и «в сети».
  final String partnerUid;
  final String partnerName;
  final String? partnerAvatarUrl;

  /// Рост обоих блоков. Задаёт шапка, чтобы вся строка стояла на одной линии.
  final double height;

  const MissYouButton({
    super.key,
    required this.theme,
    required this.groupId,
    required this.senderName,
    this.enabled = true,
    this.partnerUid = '',
    this.partnerName = '',
    this.partnerAvatarUrl,
    this.height = 34,
  });

  @override
  State<MissYouButton> createState() => _MissYouButtonState();
}

class _MissYouButtonState extends State<MissYouButton>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// Окно накопления нажатий: за это время серия тапов схлопывается в одну
  /// отправку. Полсекунды человек не замечает, а запросов становится втрое
  /// меньше на каждой серии.
  static const Duration _kBatchWindow = Duration(milliseconds: 600);

  /// Пауза перед повтором сорванной отправки. Дольше окна накопления: сеть
  /// только что отказала, и биться в неё сразу же смысла нет.
  static const Duration _kRetryWindow = Duration(seconds: 3);

  final MissYouBatch _batch = MissYouBatch();
  Timer? _flushTimer;

  final MissYouRepository _missYou = MissYouRepository();

  // ── Счётчик ──────────────────────────────────────────────────────────────────
  //
  // Свой счёт держит [OptimisticCount]: тап виден мгновенно, отказ отправки
  // снимает надбавку сразу, а неподтверждённое ожидание протухает само. Пока
  // это была голая пара `_myCount + _inFlightTaps`, число прыгало — надбавку
  // снимала только положительная дельта живого снимка.
  OptimisticCount _mine = const OptimisticCount();
  int _partnerCount = 0;
  StreamSubscription? _countSub;
  Timer? _listenRetryTimer;
  Timer? _staleTimer;
  int _listenRetryAttempt = 0;

  // ── Анимации ─────────────────────────────────────────────────────────────────
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  // ── Улетающие сердечки ───────────────────────────────────────────────────────
  final List<_FloatingHeart> _hearts = [];
  final _random = Random();

  @override
  void initState() {
    super.initState();
    // Слушаем уход в фон: накопленные нажатия надо успеть отправить до того,
    // как система выгрузит процесс вместе с таймером.
    WidgetsBinding.instance.addObserver(this);

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.92)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 82,
      ),
    ]).animate(_scaleController);

    _startListening();
  }

  @override
  void didUpdateWidget(covariant MissYouButton old) {
    super.didUpdateWidget(old);
    if (old.groupId != widget.groupId) {
      _countSub?.cancel();
      _mine = _mine.reset();
      _startListening();
    }
  }

  void _startListening() {
    _countSub?.cancel();
    _listenRetryTimer?.cancel();
    if (widget.groupId.isEmpty) return;
    _countSub = _missYou.watchCounts(widget.groupId).listen(
      (counts) {
        if (!mounted) return;
        _listenRetryAttempt = 0;
        final myUid = PocketBaseService().userId ?? '';
        final newMyCount = counts[myUid] ?? 0;
        final newPartnerCount = counts.entries
            .where((e) => e.key != myUid)
            .fold(0, (sum, e) => sum + e.value);

        _mine = _mine.confirm(newMyCount, now: DateTime.now());
        _partnerCount = newPartnerCount;
        if (mounted) setState(() {});
        _scheduleStaleSweep();
      },
      onError: (_) {
        // SSE-подписка PB может отвалиться (сеть/перезапуск процесса) —
        // переподнимаем с бэкоффом, иначе счётчик висит на нулях до рестарта.
        if (!mounted) return;
        final delay =
            Duration(seconds: min(30, 2 << min(_listenRetryAttempt, 4)));
        _listenRetryAttempt++;
        _listenRetryTimer?.cancel();
        _listenRetryTimer = Timer(delay, () {
          if (mounted) _startListening();
        });
      },
    );
  }

  /// Убирает протухшие ожидания, когда живых событий больше не приходит.
  /// Иначе последняя надбавка висела бы до следующего импульса — а он может не
  /// случиться до завтра.
  void _scheduleStaleSweep() {
    _staleTimer?.cancel();
    if (_mine.pending == 0) return;
    _staleTimer = Timer(OptimisticCount.ttl, () {
      if (!mounted) return;
      setState(() {
        _mine = _mine.confirm(_mine.confirmed, now: DateTime.now());
      });
      _scheduleStaleSweep();
    });
  }

  // ── Действия ─────────────────────────────────────────────────────────────────

  void _openScreen() {
    if (!widget.enabled || widget.groupId.isEmpty) return;
    // Экран нашли сами — подсказку про него не показываем.
    unawaited(HintQueue.instance.markSeen('miss_screen'));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Имя маршрута — единственный способ попасть в статистику экранов:
        // наблюдатель навигатора считает по `RouteSettings.name`, безымянные
        // маршруты пропускает намеренно (нижних листов сотни).
        settings: const RouteSettings(name: '/miss_you'),
        builder: (_) => MissYouScreen(
          theme: widget.theme,
          groupId: widget.groupId,
          myUid: PocketBaseService().userId ?? '',
          partnerUid: widget.partnerUid,
          partnerName: widget.partnerName,
          partnerAvatarUrl: widget.partnerAvatarUrl,
        ),
      ),
    ).then((_) => _refreshCounts());
  }

  /// Перечитать счётчики после возвращения с экрана «Скучаю».
  ///
  /// Импульсы уходят прямо с того экрана, и на главную их приносит живое
  /// событие. Если оно разминулось с пересозданием потока, кнопка оставалась
  /// со старым числом — «вышел на главную, там прежний счёт» (16.08.2026).
  /// Спрашиваем сервер один раз, по возвращении.
  Future<void> _refreshCounts() async {
    if (!mounted || widget.groupId.isEmpty) return;
    final counts = await _missYou.counts(widget.groupId);
    if (!mounted || counts.isEmpty) return;
    final myUid = PocketBaseService().userId ?? '';
    setState(() {
      _mine = _mine.confirm(counts[myUid] ?? 0, now: DateTime.now());
      _partnerCount = counts.entries
          .where((e) => e.key != myUid)
          .fold(0, (sum, e) => sum + e.value);
    });
  }

  /// Нажатие: отклик сразу, отправка пачкой.
  ///
  /// Каждый тап уходил своим запросом, и человек, нажимающий подряд, упирался в
  /// ограничитель сервера — «половину нажатий не регистрирует» (жалоба с
  /// iPhone, 13 августа 2026; 523 отказа 429 за сутки). Сердечки, вибрация и
  /// счётчик по-прежнему мгновенные, а на сервер уходит одно число.
  void _sendMissYou() {
    if (!widget.enabled || widget.groupId.isEmpty) return;
    HapticFeedback.mediumImpact();
    _scaleController.forward(from: 0);
    _spawnHearts();

    setState(() => _mine = _mine.tap(DateTime.now()));
    _scheduleStaleSweep();

    _batch.add();
    _flushTimer?.cancel();
    _flushTimer = Timer(_kBatchWindow, _flushMissYou);
  }

  Future<void> _flushMissYou() async {
    final count = _batch.take();
    if (count <= 0) return;
    var ok = false;
    try {
      ok = await _missYou.sendMissYou(widget.groupId, count: count);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      // Сорванная отправка снимает надбавку сразу: сервер её не принял.
      _batch.giveBack(count);
      if (mounted) setState(() => _mine = _mine.failed());
      // И пробуем ещё раз сами. Пока повтор ждал следующего нажатия, серия,
      // оборвавшаяся на неудаче, так и не доезжала до сервера.
      _flushTimer?.cancel();
      _flushTimer = Timer(_kRetryWindow, _flushMissYou);
      return;
    }
    // Пока шла отправка, человек мог нажать ещё — досылаем остаток сразу.
    // Прежде тут стояла та же пауза, что и на первую пачку: серия из сотен
    // нажатий растягивалась на минуты, и счётчик у партнёра всё это время
    // «доезжал» сам собой (жалоба 16.08.2026).
    if (_batch.pending > 0) {
      _flushTimer?.cancel();
      unawaited(_flushMissYou());
    }
  }

  void _spawnHearts() {
    // Значки вместо эмодзи: эмодзи рисует системный шрифт, они не красятся
    // ролью схемы и на тёмной теме светятся чужим цветом.
    const icons = [
      Icons.favorite_rounded,
      Icons.favorite_border_rounded,
      Icons.auto_awesome_rounded,
    ];
    for (int i = 0; i < 3; i++) {
      final heart = _FloatingHeart(
        icon: icons[_random.nextInt(icons.length)],
        controller: AnimationController(
          vsync: this,
          duration: Duration(milliseconds: 650 + _random.nextInt(450)),
        ),
        dx: (_random.nextDouble() - 0.5) * 70,
        endDy: -48 - _random.nextDouble() * 32,
        size: 11 + _random.nextDouble() * 8,
      );
      heart.controller.forward().then((_) {
        heart.controller.dispose();
        if (mounted) setState(() => _hearts.remove(heart));
      });
      setState(() => _hearts.add(heart));
    }
  }

  /// Слить накопленное целиком: экран закрывается или приложение уходит в фон.
  ///
  /// Пачками по потолку роута, но ВСЕ: `take()` отдаёт не больше двадцати, и
  /// остаток прежде оставался в памяти навсегда. На скринкасте 16.08.2026 это
  /// выглядело так: человек натыкал 6687, свернул приложение, вернулся — 6670.
  void _flushEverything() {
    for (final count in _batch.takeAllChunks()) {
      unawaited(_missYou.sendMissYou(widget.groupId, count: count));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Уходя в фон, отправляем всё: iOS выгружает процесс вместе с таймером
    // накопления, и `dispose` в этом случае не случится вовсе.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _flushTimer?.cancel();
      _flushEverything();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushTimer?.cancel();
    // Уходит экран — накопленное всё равно отправляем: человек нажимал, и
    // терять эти «скучаю» нельзя.
    _flushEverything();
    _scaleController.dispose();
    _countSub?.cancel();
    _listenRetryTimer?.cancel();
    _staleTimer?.cancel();
    for (final h in _hearts) {
      h.controller.dispose();
    }
    super.dispose();
  }

  // ── Сборка ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final fill = t.fillColor;
    final onFill = AppThemes.onColor(fill, mode: t.brightness);
    final displayMy = _mine.display;
    final radius = BorderRadius.circular(widget.height / 2);

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Счёт пары: показывает состояние, тап открывает экран ────────────
          GestureDetector(
            onTap: _openScreen,
            child: Container(
              height: widget.height,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: fill, borderRadius: radius),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$displayMy', style: _countStyle(onFill)),
                  Text(' / ',
                      style: _countStyle(onFill.withValues(alpha: 0.55))),
                  Text('$_partnerCount', style: _countStyle(onFill)),
                ],
              ),
            ),
          ),

          const SizedBox(width: 4),

          // ── Сердце: отправляет «скучаю» ─────────────────────────────────────
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Улетающие сердечки
              ..._hearts.map(
                (h) => AnimatedBuilder(
                  animation: h.controller,
                  builder: (context, _) {
                    final p = h.controller.value;
                    final ct = Curves.easeOut.transform(p);
                    return Positioned(
                      left: widget.height / 2 + h.dx * ct,
                      bottom: widget.height / 2 + (-h.endDy * ct),
                      child: Opacity(
                        opacity: (1 - p).clamp(0.0, 1.0),
                        child: Icon(h.icon, size: h.size, color: fill),
                      ),
                    );
                  },
                ),
              ),
              AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (_, child) => Transform.scale(
                  scale: _scaleAnimation.value,
                  child: child,
                ),
                child: GestureDetector(
                  onTap: _sendMissYou,
                  child: Container(
                    width: widget.height,
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: fill,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 16,
                      color: onFill,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle _countStyle(Color color) => TextStyle(
        fontFamily: 'Onest',
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: color,
      );
}

// ─── Улетающее сердечко ───────────────────────────────────────────────────────

class _FloatingHeart {
  final IconData icon;
  final AnimationController controller;
  final double dx;
  final double endDy;
  final double size;

  _FloatingHeart({
    required this.icon,
    required this.controller,
    required this.dx,
    required this.endDy,
    required this.size,
  });
}
