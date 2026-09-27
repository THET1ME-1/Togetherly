import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../services/offline/media_view_cache.dart';

/// Анимированный WebP, который крутит кадры сам, а не через [Image].
///
/// Сундуку нужен номер кадра: по нему приз идёт по дорожке и в нужный момент
/// появляется название выигрыша. [Image] номера не сообщает и не умеет
/// «проиграть один раз и сказать, что кончилось».
///
/// Файл берётся из серверного каталога через общий кэш картинок; пока он
/// едет или сети нет, стоит [still] из сборки. Не загрузилось вовсе — [onDone]
/// всё равно приходит, чтобы открытие не зависло.
class ChestFrames extends StatefulWidget {
  const ChestFrames({
    super.key,
    required this.url,
    required this.still,
    required this.side,
    this.loop = true,
    this.onFrame,
    this.onDone,
  });

  final String? url;
  final String still;
  final double side;
  final bool loop;
  final ValueChanged<int>? onFrame;
  final VoidCallback? onDone;

  /// Скачать файл заранее: открытие должно начаться сразу после ролика.
  static Future<void> prefetch(String? url) async {
    if (url == null || _bytes.containsKey(url)) return;
    try {
      final f = await OfflineImageCacheManager.instance.getSingleFile(url);
      _bytes[url] = await f.readAsBytes();
    } catch (_) {}
  }

  static final Map<String, Uint8List> _bytes = {};

  @override
  State<ChestFrames> createState() => _ChestFramesState();
}

class _ChestFramesState extends State<ChestFrames> {
  ui.Codec? _codec;
  ui.Image? _image;
  Timer? _timer;
  int _index = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final url = widget.url;
    Uint8List? bytes;
    if (url != null) {
      await ChestFrames.prefetch(url);
      bytes = ChestFrames._bytes[url];
    }
    if (_disposed) return;
    if (bytes == null) {
      widget.onDone?.call();
      return;
    }
    try {
      final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
      _codec = await ui.instantiateImageCodec(bytes, targetWidth: (widget.side * dpr).round());
    } catch (_) {
      _codec = null;
    }
    if (_disposed) return;
    if (_codec == null) {
      widget.onDone?.call();
      return;
    }
    _next();
  }

  Future<void> _next() async {
    final codec = _codec;
    if (codec == null || _disposed) return;
    final ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } catch (_) {
      widget.onDone?.call();
      return;
    }
    if (_disposed) {
      frame.image.dispose();
      return;
    }
    final old = _image;
    setState(() => _image = frame.image);
    old?.dispose();
    final i = _index;
    widget.onFrame?.call(i);
    final last = i == codec.frameCount - 1;
    if (last && !widget.loop) {
      widget.onDone?.call();
      return;
    }
    _index = last ? 0 : i + 1;
    _timer = Timer(frame.duration == Duration.zero ? const Duration(milliseconds: 60) : frame.duration, _next);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _image?.dispose();
    _codec?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return Image.asset(widget.still, width: widget.side, height: widget.side, gaplessPlayback: true);
    }
    return RawImage(image: image, width: widget.side, height: widget.side, filterQuality: FilterQuality.medium);
  }
}
