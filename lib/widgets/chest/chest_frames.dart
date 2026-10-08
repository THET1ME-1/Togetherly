import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
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
    this.height,
    this.fit = BoxFit.contain,
    this.stillUrl,
    this.loop = true,
    this.holdLast = false,
    this.showLast = false,
    this.onFrame,
    this.onPosition,
    this.onDone,
  });

  final String? url;

  /// Неподвижный кадр из сборки, пока файл едет; null — пусто (сезонные
  /// сундуки в сборке не лежат, у них [stillUrl] с сервера).
  final String? still;

  /// Ширина; высота — [height] или та же, что ширина.
  final double side;
  final double? height;
  final BoxFit fit;

  /// Неподвижный кадр с сервера — для сундука, которого нет в сборке.
  final String? stillUrl;
  final bool loop;

  /// При [loop] = false дождаться конца длительности последнего кадра и только
  /// тогда сказать [onDone]. Сундук говорит сразу: последний кадр открытия
  /// стоит на экране, пока не нажмут снова.
  final bool holdLast;

  /// Сразу последний кадр, без проигрывания: открытый сундук для карточки
  /// «Поделиться».
  final bool showLast;
  final ValueChanged<int>? onFrame;

  /// Время от начала файла, с которого стоит показанный кадр. Номер кадра
  /// для этого не годится: одинаковые кадры при запекании склеиваются в один
  /// длинный, и номер перестаёт быть мерой времени (занавес).
  final ValueChanged<Duration>? onPosition;
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

  /// С какого времени файла стоит текущий кадр.
  Duration _pos = Duration.zero;

  /// Последний кадр показан и досиживает свою длительность ([holdLast]).
  bool _finishing = false;
  bool _fetching = false;
  bool _stopped = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _start();
  }

  /// Номер запуска: смена файла начинает новый, а опоздавший ответ старого
  /// запуска ничего не трогает.
  int _gen = 0;

  @override
  void didUpdateWidget(ChestFrames old) {
    super.didUpdateWidget(old);
    // Файл из каталога часто приезжает уже после того, как экран открылся.
    // Без перезапуска на месте анимации навсегда оставался неподвижный кадр
    // (жалоба 08.10.2026: «у сундука нет анимации»).
    if (old.url != widget.url) {
      if (_ticker.isActive) _ticker.stop();
      _codec?.dispose();
      _codec = null;
      _index = 0;
      _due = Duration.zero;
      _pos = Duration.zero;
      _fetching = false;
      _stopped = false;
      _finishing = false;
      _start();
    }
  }

  Future<void> _start() async {
    final gen = ++_gen;
    final url = widget.url;
    Uint8List? bytes;
    if (url != null) {
      await ChestFrames.prefetch(url);
      bytes = ChestFrames._bytes[url];
    }
    if (_disposed || gen != _gen) return;
    if (bytes == null) {
      widget.onDone?.call();
      return;
    }
    ui.Codec? codec;
    try {
      final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
      // Предел ставится по ширине: у вытянутого кадра (занавес) пропорции
      // сохраняются, а у квадратного выходит прежний размер.
      codec = await ui.instantiateImageCodec(bytes, targetWidth: (widget.side * dpr).round());
    } catch (_) {
      codec = null;
    }
    if (_disposed || gen != _gen) {
      codec?.dispose();
      return;
    }
    _codec = codec;
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
    if (_finishing) {
      _stop();
      widget.onDone?.call();
      return;
    }
    _fetching = true;
    _advance(elapsed);
  }

  Future<void> _advance(Duration elapsed) async {
    final codec = _codec, gen = _gen;
    if (codec == null) return;
    final ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } catch (_) {
      // Декодер закрыли сменой файла — новый запуск уже идёт сам.
      if (gen != _gen) return;
      _stop();
      widget.onDone?.call();
      return;
    }
    if (_disposed || gen != _gen) {
      frame.image.dispose();
      return;
    }
    final old = _image;
    setState(() => _image = frame.image);
    old?.dispose();
    final i = _index;
    widget.onFrame?.call(i);
    widget.onPosition?.call(_pos);
    final last = i == codec.frameCount - 1;
    final step = frame.duration == Duration.zero ? const Duration(milliseconds: 60) : frame.duration;
    if (last && !widget.loop) {
      if (!widget.holdLast) {
        _stop();
        widget.onDone?.call();
        return;
      }
      // Последний кадр стоит свою длительность, и только потом «кончилось»:
      // у занавеса это хвост, уходящий за край экрана.
      _due = elapsed + step;
      _finishing = true;
      _fetching = false;
      return;
    }
    _index = last ? 0 : i + 1;
    _pos = last ? Duration.zero : _pos + step;
    _due = elapsed + step;
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
    final w = widget.side, h = widget.height ?? widget.side;
    if (image == null) {
      final still = widget.still;
      if (still != null) return Image.asset(still, width: w, height: h, fit: widget.fit, gaplessPlayback: true);
      final stillUrl = widget.stillUrl;
      if (stillUrl != null) {
        return Image(
          image: CachedNetworkImageProvider(stillUrl, cacheManager: OfflineImageCacheManager.instance),
          width: w,
          height: h,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => SizedBox(width: w, height: h),
        );
      }
      return SizedBox(width: w, height: h);
    }
    return RawImage(image: image, width: w, height: h, fit: widget.fit, filterQuality: FilterQuality.medium);
  }
}
