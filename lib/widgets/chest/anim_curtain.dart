import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Занавес-анимация во весь экран (метель зимнего сундука): кадры
/// разжимаются по одному и показываются по своим длительностям, а страницу
/// под занавесом меняет тот кадр, время которого дошло до [coverMs] (экран
/// закрыт). Часы у кадров и у смены страницы одни: если телефон разжимает
/// медленно, отстаёт и метель, и смена страницы, а не только метель.
///
/// Разжатая анимация целиком заняла бы 80 МБ (76 кадров 360×720), поэтому
/// в памяти один кадр.
class AnimCurtain extends StatefulWidget {
  const AnimCurtain({
    super.key,
    required this.bytes,
    required this.coverMs,
    required this.onCover,
    required this.onDone,
  });

  final Uint8List bytes;
  final int coverMs;
  final VoidCallback onCover;
  final VoidCallback onDone;

  @override
  State<AnimCurtain> createState() => _AnimCurtainState();
}

class _AnimCurtainState extends State<AnimCurtain> {
  ui.Image? _frame;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    unawaited(_play());
  }

  void _cover() {
    if (_covered) return;
    _covered = true;
    widget.onCover();
  }

  Future<void> _play() async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(widget.bytes);
      final clock = Stopwatch()..start();
      var at = 0;
      for (var i = 0; i < codec.frameCount; i++) {
        final f = await codec.getNextFrame();
        if (!mounted) {
          f.image.dispose();
          return;
        }
        // кадр не показываем раньше его времени
        final wait = at - clock.elapsedMilliseconds;
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
        if (!mounted) {
          f.image.dispose();
          return;
        }
        final old = _frame;
        setState(() => _frame = f.image);
        old?.dispose();
        if (at >= widget.coverMs) _cover();
        final d = f.duration.inMilliseconds;
        at += d > 0 ? d : 50;
      }
      final rest = at - clock.elapsedMilliseconds;
      if (rest > 0) await Future<void>.delayed(Duration(milliseconds: rest));
    } catch (e) {
      debugPrint('AnimCurtain: $e');
    } finally {
      codec?.dispose();
    }
    if (!mounted) return;
    // анимация не разжалась или короче своей отметки — страница всё равно меняется
    _cover();
    widget.onDone();
  }

  @override
  void dispose() {
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = _frame;
    if (f == null) return const SizedBox.expand();
    return SizedBox.expand(
      child: RawImage(image: f, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
    );
  }
}
