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

/// Доиграна ли сцена: каждый живой слой показал все свои кадры. Неподвижный
/// слой (один кадр) конца не ждёт.
bool lockstepPlayedThrough({required List<int> shown, required List<int> frames}) {
  for (var i = 0; i < frames.length; i++) {
    if (frames[i] > 1 && shown[i] < frames[i]) return false;
  }
  return true;
}

/// Виден ли слой [box] (в координатах экрана) на экране [screen]. За краем
/// кадры не разжимаются: превью Ту в блоке маскота ниже экрана делило
/// разжатие с летающим Ту, и кадры обоих шли медленнее часов.
bool lockstepOnScreen(Rect box, Size screen) => box.overlaps(Offset.zero & screen);

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
  const LockstepArt({
    super.key,
    required this.layers,
    required this.canvas,
    required this.decode,
    required this.placeholder,
    this.onPlayedThrough,
  });

  /// Снизу вверх.
  final List<LockstepLayer> layers;
  final double canvas;
  final int decode;
  final Widget placeholder;

  /// Слои показали сцену до конца, один раз за сцену; в ответ — какие
  /// слои. По этому одетый Ту заканчивает разовую сцену: три слоя
  /// разжимаются медленнее одного, и по часам кувырок обрывался раньше
  /// переворота (видео владельца, сборка 263).
  final ValueChanged<List<LockstepLayer>>? onPlayedThrough;

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

  /// Сколько кадров показал каждый слой с начала сцены, и сказали ли уже,
  /// что сцена доиграна.
  List<int> _shownCount = const [];
  bool _playedThrough = false;

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
      _shownCount = [for (final _ in codecs) 1];
      _playedThrough = false;
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
    if (due.isEmpty || !_onScreen()) return;
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
        _shownCount[i]++;
      }
      _dues = dues;
      setState(() => _frames = frames);
      for (final img in old) {
        img?.dispose();
      }
      if (!_playedThrough && lockstepPlayedThrough(shown: _shownCount, frames: [for (final c in codecs) c.frameCount])) {
        _playedThrough = true;
        widget.onPlayedThrough?.call(_shownLayers);
      }
    } catch (_) {}
  }

  /// Виден ли Ту на экране. За краем кадры не разжимаем: разжатие у всех
  /// картинок одно, и превью в блоке маскота ниже экрана отнимало его у
  /// летающего Ту. Часы при этом идут, и вернувшийся на экран слой
  /// подхватит их сдвигом, как после свёрнутого приложения.
  bool _onScreen() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return true;
    final topLeft = box.localToGlobal(Offset.zero);
    return lockstepOnScreen(topLeft & box.size, MediaQuery.sizeOf(context));
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
