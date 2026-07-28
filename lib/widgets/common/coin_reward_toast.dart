import 'dart:math' as math;

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
/// Движение построено вокруг монеты, а не вокруг прямоугольника. Плашка
/// прилетает снизу с пружинным перелётом, монета в это время переворачивается
/// ребром, как настоящая, число набегает счётчиком. На уходе плашка схлопывается
/// обратно в монету — ширина стягивается к левому краю, текст гаснет раньше — и
/// монета улетает вверх. Форма при этом всё время остаётся стадионом, поэтому
/// схлопывание читается как превращение в кружок.
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
  // ── Раскадровка (мс) ──
  // Полная длина держит паузу, за которую награду успевают прочитать; всё
  // движение живёт по краям, середина неподвижна.
  static const int _total = 2900;
  static const int _enterEnd = 460; // прилёт плашки
  static const int _coinEnd = 780; // переворот монеты и её пружина
  static const int _countEnd = 760; // счётчик добегает до числа
  static const int _collapseStart = 2280; // плашка начинает схлопываться
  static const int _collapseEnd = 2620; // остаётся один кружок монеты
  static const int _flyEnd = 2900; // монета уходит вверх

  /// Кривые M3: входит с emphasized decelerate, уходит с emphasized accelerate.
  static const Curve _decelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const Curve _accelerate = Cubic(0.3, 0, 0.8, 0.15);

  /// Пружинный перелёт на прилёте. Собственная кривая вместо easeOutBack:
  /// у неё перелёт мягче и без «отскока в минус» на старте.
  static const Curve _overshoot = Cubic(0.2, 1.35, 0.35, 1);

  late final AnimationController _ctrl;

  double _t(int ms) => ms / _total;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _total),
    )..forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Значение 0…1 внутри отрезка раскадровки.
  double _phase(double v, int fromMs, int toMs, {Curve curve = Curves.linear}) {
    final from = _t(fromMs), to = _t(toMs);
    if (v <= from) return 0;
    if (v >= to) return 1;
    return curve.transform((v - from) / (to - from));
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
        child: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              final v = _ctrl.value;

              final enter = _phase(v, 0, _enterEnd, curve: _overshoot);
              final collapse =
                  _phase(v, _collapseStart, _collapseEnd, curve: _accelerate);
              final fly = _phase(v, _collapseEnd, _flyEnd, curve: _accelerate);

              // Появление: подъём снизу с перелётом. Уход: короткий рывок вверх
              // уже схлопнутой монеты.
              final dy = (1 - enter) * 34 - fly * 22;
              final scale = 0.88 + 0.12 * enter;
              final opacity = _phase(v, 0, 170) * (1 - fly);

              // Ширина стягивается к левому краю, где сидит монета: плашка
              // складывается в кружок, а не просто уезжает.
              final widthFactor = 1 - collapse * 0.68;

              return Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, dy),
                  child: Transform.scale(
                    scale: scale,
                    child: Material(
                      // Обёртка обязательна: в оверлее нет Material-предка, и
                      // текст рисуется отладочным жёлтым с подчёркиванием.
                      color: cs.inverseSurface,
                      // Плашка всплывает поверх любого экрана, поэтому тень тут
                      // уместна: одной тональности для отделения не хватает.
                      elevation: 3,
                      shadowColor: Colors.black26,
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: widthFactor,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 22, 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, coin) {
                      final v = _ctrl.value;
                      final spin = _phase(v, 0, _coinEnd, curve: _decelerate);
                      final pop = _phase(v, 0, _coinEnd, curve: _overshoot);
                      // Монета входит ребром и доворачивается до лица —
                      // полоборота вокруг вертикальной оси.
                      final angle = (1 - spin) * math.pi / 2;
                      // На схлопывании чуть подрастает: кружок будто вбирает
                      // в себя всю плашку.
                      final grow = 1 +
                          0.08 *
                              _phase(v, _collapseStart, _collapseEnd,
                                  curve: _decelerate);
                      return Transform.scale(
                        scale: (0.5 + 0.5 * pop) * grow,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0015)
                            ..rotateY(angle),
                          child: coin,
                        ),
                      );
                    },
                    // Сама монета TY и есть кружок, поэтому подложки под ней
                    // нет: круг в круге давал ощущение, что иконку забыли
                    // обрезать. У файла широкие прозрачные поля — заметная
                    // часть размера уходит в них, отсюда 44 px вместо 24.
                    child: Image.asset(
                      'assets/images/icons/coin.webp',
                      width: 44,
                      height: 44,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Текст гаснет раньше, чем стянется ширина: иначе буквы
                  // видно, как их режет край плашки.
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, textChild) {
                      final v = _ctrl.value;
                      final out =
                          _phase(v, _collapseStart, _collapseStart + 140);
                      final appear = _phase(v, 90, 300, curve: _decelerate);
                      return Opacity(
                        opacity: (appear * (1 - out)).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset((1 - appear) * -8, 0),
                          child: textChild,
                        ),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Число набегает счётчиком — награда чувствуется
                        // начислением, а не готовым фактом.
                        AnimatedBuilder(
                          animation: _ctrl,
                          builder: (context, _) {
                            final grow = _phase(_ctrl.value, 120, _countEnd,
                                curve: Curves.easeOutCubic);
                            final shown =
                                (widget.amount * grow).ceil().clamp(1, widget.amount);
                            return Text(
                              s.coinsPlus(shown),
                              style: TextStyle(
                                fontFamily: ProfileTheme.displayFont,
                                fontSize: 17,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                fontVariations: const [
                                  FontVariation('wght', 700)
                                ],
                                color: cs.onInverseSurface,
                              ),
                            );
                          },
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
