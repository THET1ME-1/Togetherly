import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../models/season_backdrop.dart';
import '../../services/offline/media_view_cache.dart';

/// Сезонный фон под интерфейсом главной: призрак за матовым стеклом
/// проявляется из размытия, прижимается к стеклу и растворяется. Лежит между
/// фоном темы и содержимым, касаний не ловит — все кнопки работают как
/// обычно. Нажатие в пустое место приложение передаёт в [press]: изнутри к
/// стеклу прижимается ладонь.
class SeasonBackdropLayer extends StatefulWidget {
  const SeasonBackdropLayer({
    super.key,
    required this.backdrop,
    required this.brightness,
    required this.accent,
    this.imageFor,
  });

  final SeasonBackdrop backdrop;
  final Brightness brightness;

  /// Цвет темы: призрак берёт его оттенок.
  final Color accent;

  /// Картинка по адресу; по умолчанию — общий дисковый кэш, тот же, что у
  /// сундука и значков.
  final ImageProvider Function(String url)? imageFor;

  @override
  State<SeasonBackdropLayer> createState() => SeasonBackdropLayerState();
}

class _Print {
  _Print(this.at, this.rot, this.born);
  final Offset at;
  final double rot;
  final Duration born;
}

class SeasonBackdropLayerState extends State<SeasonBackdropLayer> with SingleTickerProviderStateMixin {
  static const _printMs = 3600;
  static const _handSide = 92.0;

  late final Ticker _ticker = createTicker(_tick);
  Duration _now = Duration.zero;
  final List<_Print> _prints = [];
  final _rnd = math.Random();
  bool _reduce = false;

  ImageProvider _img(String url) =>
      widget.imageFor?.call(url) ?? CachedNetworkImageProvider(url, cacheManager: OfflineImageCacheManager.instance);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncTicker();
  }

  void _syncTicker() {
    final need = !_reduce || _prints.isNotEmpty;
    if (need && !_ticker.isActive) {
      _ticker.start();
    } else if (!need && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    _prints.removeWhere((p) => (elapsed - p.born).inMilliseconds > _printMs);
    setState(() {});
    if (_prints.isEmpty && _reduce) _ticker.stop();
  }

  /// Ладонь изнутри в точке [local] (координаты слоя).
  void press(Offset local) {
    if (widget.backdrop.handUrl == null) return;
    if (_prints.length >= 3) _prints.removeAt(0);
    _prints.add(_Print(local, (-14 + _rnd.nextDouble() * 28) * math.pi / 180, _now));
    _syncTicker();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Widget _mask(String url, String key, Color color) => Image(
    key: ValueKey(key),
    image: _img(url),
    fit: BoxFit.cover,
    alignment: Alignment.topCenter,
    width: double.infinity,
    height: double.infinity,
    color: color,
    colorBlendMode: BlendMode.srcIn,
    gaplessPlayback: true,
  );

  @override
  Widget build(BuildContext context) {
    final b = widget.backdrop;
    final tint = b.tint(widget.brightness, widget.accent);
    final base = b.opacity(widget.brightness);

    // «Уменьшить движение»: призрак стоит у стекла неподвижно и тише.
    final ph = _reduce ? const BackdropPhase(opacity: 1, blur: 0, scale: 1) : b.phaseAt(_now.inMilliseconds);
    final calm = _reduce ? 0.6 : 1.0;
    final layers = <Widget>[];
    if (ph.opacity > 0.004) {
      final sharpness = b.blur <= 0 ? 1.0 : 1 - ph.blur / b.blur;
      if (b.blurUrl != null) {
        final seen = math.min(1.0, ph.opacity * 1.6);
        layers.add(_mask(b.blurUrl!, 'backdrop-blur', tint.withValues(alpha: base * calm * seen * (1 - sharpness))));
        layers.add(_mask(b.maskUrl, 'backdrop-sharp', tint.withValues(alpha: base * calm * ph.opacity * sharpness)));
      } else {
        layers.add(_mask(b.maskUrl, 'backdrop-sharp', tint.withValues(alpha: base * calm * ph.opacity)));
      }
    }

    final hands = <Widget>[];
    final hand = b.handUrl;
    if (hand != null) {
      for (final p in _prints) {
        final k = ((_now - p.born).inMilliseconds / _printMs).clamp(0.0, 1.0);
        final a = k < .14
            ? k / .14
            : k < .55
            ? 1.0
            : k < .82
            ? 1 - .33 * (k - .55) / .27
            : .67 * (1 - (k - .82) / .18);
        final slide = k > .55 ? 12 * math.min(1.0, (k - .55) / .27) : 0.0;
        hands.add(Positioned(
          left: p.at.dx - _handSide * .44,
          top: p.at.dy - _handSide * .55 + slide,
          width: _handSide,
          height: _handSide,
          child: Transform.rotate(
            angle: p.rot,
            child: Image(
              key: const ValueKey('backdrop-hand'),
              image: _img(hand),
              color: tint.withValues(alpha: (base * 1.15).clamp(0.0, 1.0) * a),
              colorBlendMode: BlendMode.srcIn,
              gaplessPlayback: true,
            ),
          ),
        ));
      }
    }

    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (layers.isNotEmpty) Transform.scale(scale: ph.scale, child: Stack(fit: StackFit.expand, children: layers)),
            ...hands,
          ],
        ),
      ),
    );
  }
}

/// Ловит нажатия в пустое место поверх содержимого: внешний распознаватель
/// касания проигрывает арену любому внутреннему (кнопке, плитке, полю), так
/// что [onEmptyTap] приходит, только когда под пальцем нечего нажимать.
/// Перетаскивание и прокрутку не трогает.
///
/// Стоит на месте всегда, даже без сезона ([onEmptyTap] = null — ни одного
/// распознавателя): появись обёртка только на время сезона, Flutter
/// пересоздал бы всё содержимое главной.
class BackdropTapCatcher extends StatelessWidget {
  const BackdropTapCatcher({super.key, required this.onEmptyTap, required this.child});

  final ValueChanged<Offset>? onEmptyTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cb = onEmptyTap;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onTapUp: cb == null ? null : (d) => cb(d.globalPosition),
      child: child,
    );
  }
}
