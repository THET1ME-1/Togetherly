import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/miss_you_repository.dart';
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
    with TickerProviderStateMixin {
  final MissYouRepository _missYou = MissYouRepository();

  // ── Счётчик ──────────────────────────────────────────────────────────────────
  int _myCount = 0;
  int _partnerCount = 0;
  int _inFlightTaps = 0;
  StreamSubscription? _countSub;
  Timer? _listenRetryTimer;
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
      _inFlightTaps = 0;
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

        final confirmed = newMyCount - _myCount;
        if (confirmed > 0) _inFlightTaps = max(0, _inFlightTaps - confirmed);

        _myCount = newMyCount;
        _partnerCount = newPartnerCount;
        if (mounted) setState(() {});
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

  // ── Действия ─────────────────────────────────────────────────────────────────

  void _openScreen() {
    if (!widget.enabled || widget.groupId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MissYouScreen(
          theme: widget.theme,
          groupId: widget.groupId,
          myUid: PocketBaseService().userId ?? '',
          partnerUid: widget.partnerUid,
          partnerName: widget.partnerName,
          partnerAvatarUrl: widget.partnerAvatarUrl,
        ),
      ),
    );
  }

  Future<void> _sendMissYou() async {
    if (!widget.enabled || widget.groupId.isEmpty) return;
    HapticFeedback.mediumImpact();
    _scaleController.forward(from: 0);
    _spawnHearts();

    _inFlightTaps++;
    if (mounted) setState(() {});

    try {
      await _missYou.sendMissYou(widget.groupId);
    } catch (_) {
      if (mounted) {
        setState(() => _inFlightTaps = max(0, _inFlightTaps - 1));
      }
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

  @override
  void dispose() {
    _scaleController.dispose();
    _countSub?.cancel();
    _listenRetryTimer?.cancel();
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
    final displayMy = _myCount + _inFlightTaps;
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
