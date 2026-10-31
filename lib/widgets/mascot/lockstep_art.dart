import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/offline/media_view_cache.dart';

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
  Duration _due = Duration.zero;
  bool _busy = false;
  int _generation = 0;

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
      _disposeAll();
      _codecs = codecs;
      _shownLayers = layers;
      _frames = [for (final f in first) f.image];
      _due = first.first.duration;
      _ticker.stop();
      if (codecs.first.frameCount > 1) _ticker.start();
      setState(() {});
    } catch (_) {
      // Слой не скачался — Ту остаётся без одежды, но живой.
      if (mounted && gen == _generation && _codecs.isEmpty) setState(() {});
    }
  }

  Future<void> _tick(Duration elapsed) async {
    if (_busy || elapsed < _due || _codecs.isEmpty) return;
    _busy = true;
    final gen = _generation;
    final codecs = _codecs;
    try {
      final next = await Future.wait(codecs.map((c) => c.getNextFrame()));
      if (!mounted || gen != _generation || !identical(codecs, _codecs)) {
        for (final f in next) {
          f.image.dispose();
        }
        return;
      }
      final old = _frames;
      setState(() => _frames = [for (final f in next) f.image]);
      for (final img in old) {
        img?.dispose();
      }
      final step = next.first.duration;
      _due += step == Duration.zero ? const Duration(milliseconds: 50) : step;
      // Отстали (приложение было свёрнуто) — не догоняем пачкой, идём дальше.
      if (elapsed - _due > const Duration(milliseconds: 500)) _due = elapsed;
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  void _disposeAll() {
    for (final img in _frames) {
      img?.dispose();
    }
    for (final c in _codecs) {
      c.dispose();
    }
    _frames = const [];
    _codecs = const [];
  }

  @override
  void dispose() {
    _generation++;
    _ticker.dispose();
    _disposeAll();
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
