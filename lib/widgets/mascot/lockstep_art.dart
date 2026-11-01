import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/offline/media_view_cache.dart';

/// Какие слои пора сменить на следующий кадр: те, чьё время [dues] уже
/// подошло к [elapsed].
List<int> lockstepDue(List<Duration> dues, Duration elapsed) => [
      for (var i = 0; i < dues.length; i++)
        if (elapsed >= dues[i]) i,
    ];

/// Слой анимации: файл, сторона на экране и сдвиг середины от середины
/// холста.
class LockstepLayer {
  const LockstepLayer(this.url, {required this.side, this.shift = Offset.zero});
  final String url;
  final double side;
  final Offset shift;

  @override
  bool operator ==(Object other) => other is LockstepLayer && other.url == url && other.side == side && other.shift == shift;

  @override
  int get hashCode => Object.hash(url, side, shift);
}

/// Несколько анимаций одной длины, которые идут кадр в кадр: сцена Ту и
/// слои его одежды. Обычные `Image` крутят каждую своими часами, и слой,
/// скачанный позже, отставал бы от тела — шарф ехал бы мимо шеи. Здесь кадры
/// всех слоёв берутся разом от одного тикера.
///
/// Пока слои не готовы, стоит [placeholder] (сам Ту без одежды); при смене
/// сцены до готовности новых кадров стоят прежние, без мигания.
class LockstepArt extends StatefulWidget {
  const LockstepArt({super.key, required this.layers, required this.canvas, required this.decode, required this.placeholder});

  /// Снизу вверх.
  final List<LockstepLayer> layers;
  final double canvas;
  final int decode;
  final Widget placeholder;

  @override
  State<LockstepArt> createState() => _LockstepArtState();
}

class _LockstepArtState extends State<LockstepArt> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  List<ui.Codec> _codecs = const [];
  List<LockstepLayer> _shownLayers = const [];
  List<ui.Image?> _frames = const [];

  /// Когда каждому слою менять кадр. Часы у слоёв свои: при упаковке
  /// одинаковые кадры подряд склеиваются в один длинный, и счёт кадров у
  /// тела и одежды расходится (у взрыва 64 против 29). Время от начала
  /// анимации у всех общее, поэтому слои идут кадр в кадр.
  List<Duration> _dues = const [];
  int _generation = 0;

  /// Кадр, который тикер ждёт прямо сейчас, и от какой сцены. Закрыть
  /// распаковщики посреди этого ожидания нельзя: оно так и не кончится, и
  /// тикер встанет навсегда. Так Ту в одежде замирал намертво, если трясти
  /// телефон: сцена менялась испугом туда и обратно, и замена попадала в
  /// ожидание кадра.
  Future<void>? _inFlight;
  List<ui.Codec>? _inFlightCodecs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LockstepArt old) {
    super.didUpdateWidget(old);
    if (!_sameLayers(old.layers, widget.layers) || old.decode != widget.decode) _load();
  }

  bool _sameLayers(List<LockstepLayer> a, List<LockstepLayer> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _load() async {
    final gen = ++_generation;
    final layers = widget.layers;
    final decode = widget.decode;
    try {
      final codecs = await Future.wait(layers.map((l) async {
        final file = await OfflineImageCacheManager.instance.getSingleFile(l.url);
        final bytes = await file.readAsBytes();
        return ui.instantiateImageCodec(bytes, targetWidth: decode, targetHeight: decode);
      }));
      if (!mounted || gen != _generation) {
        for (final c in codecs) {
          c.dispose();
        }
        return;
      }
      final first = await Future.wait(codecs.map((c) => c.getNextFrame()));
      if (!mounted || gen != _generation) {
        for (final f in first) {
          f.image.dispose();
        }
        for (final c in codecs) {
          c.dispose();
        }
        return;
      }
      _retire(_codecs, _frames);
      _codecs = codecs;
      _shownLayers = layers;
      _frames = [for (final f in first) f.image];
      _dues = [for (final f in first) _frameLength(f.duration)];
      _ticker.stop();
      if (codecs.any((c) => c.frameCount > 1)) _ticker.start();
      setState(() {});
    } catch (_) {
      // Слой не скачался — Ту остаётся без одежды, но живой.
      if (mounted && gen == _generation && _codecs.isEmpty) setState(() {});
    }
  }

  static Duration _frameLength(Duration d) => d == Duration.zero ? const Duration(milliseconds: 50) : d;

  void _tick(Duration elapsed) {
    final codecs = _codecs;
    if (codecs.isEmpty || _dues.isEmpty || identical(_inFlightCodecs, codecs)) return;
    // Отстали (приложение было свёрнуто): сдвигаем часы всех слоёв разом,
    // чтобы не догонять пачкой и не разъехаться между собой.
    final earliest = _dues.reduce((a, b) => a < b ? a : b);
    if (elapsed - earliest > const Duration(milliseconds: 500)) {
      final lag = elapsed - earliest;
      _dues = [for (final d in _dues) d + lag];
    }
    final due = lockstepDue(_dues, elapsed);
    if (due.isEmpty) return;
    final step = _step(_generation, codecs, due);
    _inFlight = step;
    _inFlightCodecs = codecs;
    step.whenComplete(() {
      if (identical(_inFlight, step)) {
        _inFlight = null;
        _inFlightCodecs = null;
      }
    });
  }

  Future<void> _step(int gen, List<ui.Codec> codecs, List<int> due) async {
    try {
      final next = await Future.wait(due.map((i) => codecs[i].getNextFrame()));
      if (!mounted || gen != _generation || !identical(codecs, _codecs)) {
        for (final f in next) {
          f.image.dispose();
        }
        return;
      }
      final frames = [..._frames];
      final old = <ui.Image?>[];
      final dues = [..._dues];
      for (var k = 0; k < due.length; k++) {
        final i = due[k];
        old.add(frames[i]);
        frames[i] = next[k].image;
        dues[i] += _frameLength(next[k].duration);
      }
      _dues = dues;
      setState(() => _frames = frames);
      for (final img in old) {
        img?.dispose();
      }
    } catch (_) {}
  }

  /// Убрать прежнюю сцену. Если тикер как раз ждёт от неё кадр, закрыть
  /// после того, как кадр придёт.
  void _retire(List<ui.Codec> codecs, List<ui.Image?> frames) {
    void close() {
      for (final img in frames) {
        img?.dispose();
      }
      for (final c in codecs) {
        c.dispose();
      }
    }

    final pending = _inFlight;
    if (pending == null) {
      close();
    } else {
      pending.whenComplete(close);
    }
  }

  @override
  void dispose() {
    _generation++;
    _ticker.dispose();
    _retire(_codecs, _frames);
    _frames = const [];
    _codecs = const [];
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frames.isEmpty) return widget.placeholder;
    final c = widget.canvas;
    return SizedBox.square(
      dimension: c,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < _frames.length; i++)
            Positioned(
              left: (c - _shownLayers[i].side) / 2 + _shownLayers[i].shift.dx,
              top: (c - _shownLayers[i].side) / 2 + _shownLayers[i].shift.dy,
              width: _shownLayers[i].side,
              height: _shownLayers[i].side,
              child: RawImage(image: _frames[i], filterQuality: FilterQuality.medium),
            ),
        ],
      ),
    );
  }
}
