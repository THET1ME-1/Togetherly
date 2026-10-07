import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../services/offline/media_view_cache.dart';

/// Анимированный WebP, который крутит кадры сам, а не через [Image].
///
/// Сундуку нужен номер кадра: по нему приз идёт по дорожке и в нужный момент
/// появляется название выигрыша. [Image] номера не сообщает и не умеет
/// «проиграть один раз и сказать, что кончилось».
///
/// Кадры двигает [Ticker], то есть сама отрисовка экрана, а не таймер. Пока
/// экран не рисуется — приложение за рекламой, окно ещё не вернулось, — кадр
/// стоит на месте. С таймером открытие сундука успевало пройти невидимым,
/// пока закрывался рекламный экран, и человек возвращался к уже закрытому
/// сундуку (жалоба 27.09.2026). За один кадр отрисовки анимация шагает не
/// больше чем на кадр, поэтому после подвисания она не перепрыгивает вперёд.
///
/// [loop] = false — проиграть один раз и остаться на последнем кадре.
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
    this.showLast = false,
    this.onFrame,
    this.onDone,
  });

  final String? url;
  final String still;
  final double side;
  final bool loop;

  /// Сразу последний кадр, без проигрывания: открытый сундук для карточки
  /// «Поделиться».
  final bool showLast;
  final ValueChanged<int>? onFrame;
  final VoidCallback? onDone;

  /// Скачать файл заранее: открытие должно начаться сразу после ролика.
  ///
  /// Ждём не дольше [prefetchLimit]: файл весит полтора мегабайта, и на
  /// медленной или зависшей сети кнопка стояла на «Открываем…» без конца
  /// (обращение 211, 29.09.2026). Не успел — сундук открывается без
  /// анимации, [onDone] приходит сразу. Экран и виджет ждут одну загрузку.
  static Future<void> prefetch(String? url) {
    if (url == null || _bytes.containsKey(url)) return Future.value();
    return _loading[url] ??= _fetch(url).whenComplete(() => _loading.remove(url));
  }

  static Future<void> _fetch(String url) async {
    try {
      final f = await OfflineImageCacheManager.instance.getSingleFile(url).timeout(prefetchLimit);
      _bytes[url] = await f.readAsBytes();
    } catch (_) {}
  }

  static const Duration prefetchLimit = Duration(seconds: 8);

  static final Map<String, Future<void>> _loading = {};

  /// Файл уже в памяти — открытие можно начинать без ожидания сети.
  static bool isReady(String? url) => url != null && _bytes.containsKey(url);

  /// Тесты: положить байты файла без сети.
  @visibleForTesting
  static void debugPut(String url, Uint8List bytes) => _bytes[url] = bytes;

  static final Map<String, Uint8List> _bytes = {};

  @override
  State<ChestFrames> createState() => _ChestFramesState();
}

class _ChestFramesState extends State<ChestFrames> with SingleTickerProviderStateMixin {
  // Создаётся в initState, а не лениво: иначе виджет, закрытый до загрузки
  // файла, создавал бы тикер впервые в dispose — на уже отцепленном элементе.
  late final Ticker _ticker;
  ui.Codec? _codec;
  ui.Image? _image;
  int _index = 0;

  /// Когда по часам тикера показывать следующий кадр.
  Duration _due = Duration.zero;
  bool _fetching = false;
  bool _stopped = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
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
    if (widget.showLast) {
      await _skipToLast(_codec!);
      return;
    }
    _ticker.start();
  }

  Future<void> _skipToLast(ui.Codec codec) async {
    ui.Image? last;
    try {
      for (var i = 0; i < codec.frameCount; i++) {
        final frame = await codec.getNextFrame();
        last?.dispose();
        last = frame.image;
        if (_disposed) break;
      }
    } catch (_) {}
    if (_disposed) {
      last?.dispose();
      return;
    }
    final old = _image;
    setState(() => _image = last);
    old?.dispose();
    widget.onDone?.call();
  }

  void _onTick(Duration elapsed) {
    if (_fetching || _stopped || elapsed < _due) return;
    _fetching = true;
    _advance(elapsed);
  }

  Future<void> _advance(Duration elapsed) async {
    final codec = _codec;
    if (codec == null) return;
    final ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } catch (_) {
      _stop();
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
      _stop();
      widget.onDone?.call();
      return;
    }
    _index = last ? 0 : i + 1;
    _due = elapsed + (frame.duration == Duration.zero ? const Duration(milliseconds: 60) : frame.duration);
    _fetching = false;
  }

  void _stop() {
    _stopped = true;
    if (_ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
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
