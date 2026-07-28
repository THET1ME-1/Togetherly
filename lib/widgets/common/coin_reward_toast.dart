import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';

/// Плашка «монеты начислены».
///
/// Живёт в [Overlay], поэтому обязана нести собственный [Material]: без него
/// Flutter рисует текст жёлтым с двойным подчёркиванием — так выглядела награда
/// до 28 июля, и это читалось как поломка, а не как поздравление.
///
/// Цвета берём из схемы (`inverseSurface` — та самая роль, на которой M3 строит
/// снекбары), а не из захардкоженного тёмно-синего: на тёплых темах он выпадал
/// из оформления.
///
/// Использование:
///   CoinRewardToast.show(context, amount: 5, label: 'Ежедневный вход');
class CoinRewardToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required int amount,
    String? label,
  }) {
    if (amount <= 0) return;
    _safeRemove(_current);
    _current = null;

    // Схему снимаем ДО вставки в оверлей: он живёт в дереве навигатора и
    // переживает экран, с которого пришёл вызов.
    final scheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CoinToastWidget(
        amount: amount,
        label: label,
        scheme: scheme,
        onDone: () {
          if (_current == entry) _current = null;
          _safeRemove(entry);
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  /// Снимает оверлей безопасно — даже если его уже снял следующий тост.
  ///
  /// При двух начислениях подряд первый оверлей убирался в show(), а его
  /// анимация потом доигрывала и звала remove() второй раз. Внутри OverlayEntry
  /// это дёргает `_overlay!` по null → «Null check operator used on a null
  /// value» в микротаске, и приложение молча вылетает. try/catch это гасит.
  static void _safeRemove(OverlayEntry? entry) {
    if (entry == null) return;
    try {
      entry.remove();
    } catch (_) {
      // Оверлей уже снят — штатная гонка, игнорируем.
    }
  }
}

class _CoinToastWidget extends StatefulWidget {
  final int amount;
  final String? label;
  final ColorScheme scheme;
  final VoidCallback onDone;

  const _CoinToastWidget({
    required this.amount,
    required this.scheme,
    required this.onDone,
    this.label,
  });

  @override
  State<_CoinToastWidget> createState() => _CoinToastWidgetState();
}

class _CoinToastWidgetState extends State<_CoinToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  /// M3-кривые: входит с emphasized decelerate, уходит с emphasized accelerate.
  static const Curve _enter = Cubic(0.05, 0.7, 0.1, 1);
  static const Curve _exit = Cubic(0.3, 0, 0.8, 0.15);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 12),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 63),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(_ctrl);

    _slide = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: const Offset(0, 0.5), end: Offset.zero)
            .chain(CurveTween(curve: _enter)),
        weight: 15,
      ),
      TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 60),
      TweenSequenceItem(
        tween: Tween(begin: Offset.zero, end: const Offset(0, -0.5))
            .chain(CurveTween(curve: _exit)),
        weight: 25,
      ),
    ]).animate(_ctrl);

    // Лёгкий пружинный доворот на входе — плашка «прилетает», а не проявляется.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.88, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 82),
    ]).animate(_ctrl);

    _ctrl.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    final s = LocaleService.current;

    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 100,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _slide,
              child: ScaleTransition(scale: _scale, child: child),
            ),
          ),
          child: Center(
            child: Material(
              // Обёртка обязательна: в оверлее нет Material-предка, и текст
              // рисуется отладочным жёлтым с двойным подчёркиванием.
              color: cs.inverseSurface,
              // Плашка всплывает поверх любого экрана, поэтому небольшая тень
              // тут уместна: тональности для отделения не хватает.
              elevation: 3,
              shadowColor: Colors.black26,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 22, 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Coin(scheme: cs),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.coinsPlus(widget.amount),
                          style: TextStyle(
                            fontFamily: ProfileTheme.displayFont,
                            fontSize: 17,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            fontVariations: const [FontVariation('wght', 700)],
                            color: cs.onInverseSurface,
                          ),
                        ),
                        if (widget.label != null && widget.label!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              widget.label!,
                              style: TextStyle(
                                fontFamily: ProfileTheme.bodyFont,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: cs.onInverseSurface
                                    .withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Монета в тональном кружке: на тёмной плашке светлая иконка сама по себе
/// теряется, а круг задаёт ей место и повторяет форму самой плашки.
class _Coin extends StatefulWidget {
  const _Coin({required this.scheme});

  final ColorScheme scheme;

  @override
  State<_Coin> createState() => _CoinState();
}

class _CoinState extends State<_Coin> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = Tween(begin: 0.4, end: 1.0)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_ctrl);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: widget.scheme.inversePrimary.withValues(alpha: 0.28),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Image.asset(
          'assets/images/icons/coin.webp',
          width: 24,
          height: 24,
        ),
      ),
    );
  }
}
