import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/cloud_mascot.dart';
import '../../models/shake_detector.dart';
import '../../services/catalog_service.dart';
import '../../models/mascot_anim.dart';
import '../common/guide_mascot.dart';

/// События главной, на которые облачко отвечает сценой: «Скучаю» ушло или
/// пришло, телефон встряхнули. Кто угодно зовёт [fire], облачко слушает.
class CloudEvents extends ChangeNotifier {
  CloudEvents._();

  static final CloudEvents instance = CloudEvents._();

  CloudEvent? _last;
  CloudEvent? get last => _last;

  void fire(CloudEvent event) {
    _last = event;
    notifyListeners();
  }
}

/// Слушает датчик движения, пока облачко на главной, и зовёт встряску.
/// Приложение свернули — датчик отпускается: батарея дороже испуга.
class CloudShakeWatch {
  StreamSubscription<UserAccelerometerEvent>? _sub;
  AppLifecycleListener? _life;
  final ShakeDetector _detector = ShakeDetector();
  final Stopwatch _clock = Stopwatch()..start();

  void start() {
    _life ??= AppLifecycleListener(onResume: _listen, onPause: _mute, onHide: _mute);
    _listen();
  }

  void _listen() {
    if (_sub != null) return;
    try {
      _sub = userAccelerometerEventStream(samplingPeriod: const Duration(milliseconds: 40)).listen(
        (e) {
          if (_detector.add(_clock.elapsed, e.x, e.y, e.z)) CloudEvents.instance.fire(CloudEvent.shake);
        },
        // Датчика нет (часть планшетов) — облачко просто не пугается.
        onError: (_) => _mute(),
        cancelOnError: true,
      );
    } catch (_) {
      _sub = null;
    }
  }

  void _mute() {
    _sub?.cancel();
    _sub = null;
  }

  void stop() {
    _mute();
    _life?.dispose();
    _life = null;
  }
}

/// Готовит сцены облачка заранее, чтобы касание, полёт за пальцем и смена
/// настроения шли сразу, а не после загрузки: покой во всех цветах и все
/// реакции в цвете [tint]. Повторный вызов с тем же цветом и размером ничего
/// не делает.
void warmCloud(String tint, {required double size, required double dpr}) {
  final canvas = size * _kCloudCanvas;
  final mark = '$tint@${artDecodeBucket(canvas * dpr)}';
  if (_warmed.contains(mark)) return;
  _warmed.add(mark);
  warmCatalogArt([
    for (final t in kCloudTints) 'cloud_idle_$t',
    for (final scene in const ['tap', 'drag', 'miss_send', 'miss_get', 'joy', 'flip']) 'cloud_${scene}_$tint',
    'cloud_sleep_base',
    'cloud_sick_base',
  ], side: canvas, dpr: dpr);
}

final Set<String> _warmed = {};

/// Рисунок облачка занимает около 70% холста: холст крупнее места, чтобы
/// само облачко было размером с прежнего маскота.
const double _kCloudCanvas = 1.4;

/// Облачко на главной и в галерее. Сцену выбирает `cloudArt`, сама анимация
/// приходит из каталога: рисунок не перерисовывается в приложении.
class CloudMascotView extends StatefulWidget {
  const CloudMascotView({
    super.key,
    required this.size,
    this.anim = MascotAnimState.live,
    this.tint = 'base',
    this.night = false,
    this.sick = false,
    this.mood,
    this.listenEvents = false,
    this.onOneShotDone,
  });

  /// Сторона места под маскота. Холст анимации с запасом под полёт и
  /// предметы вокруг, поэтому он рисуется крупнее и выходит за края.
  final double size;
  final MascotAnimState anim;
  final String tint;
  final bool night;
  final bool sick;

  /// Id настроения, которым живёт облачко: в покое играет эта эмоция из
  /// пака «Облачко», если она там есть.
  final String? mood;

  /// Слушать ли «Скучаю» и встряску. В галерее облачко их не играет.
  final bool listenEvents;
  final VoidCallback? onOneShotDone;

  @override
  State<CloudMascotView> createState() => _CloudMascotViewState();
}

class _CloudMascotViewState extends State<CloudMascotView> {
  CloudEvent? _event;
  Timer? _eventTimer;
  Timer? _oneShotTimer;
  CloudShakeWatch? _shake;

  @override
  void initState() {
    super.initState();
    if (widget.listenEvents) {
      CloudEvents.instance.addListener(_onEvent);
      _shake = CloudShakeWatch()..start();
    }
    _armOneShot();
  }

  @override
  void didUpdateWidget(CloudMascotView old) {
    super.didUpdateWidget(old);
    if (old.anim != widget.anim) _armOneShot();
  }

  @override
  void dispose() {
    CloudEvents.instance.removeListener(_onEvent);
    _shake?.stop();
    _eventTimer?.cancel();
    _oneShotTimer?.cancel();
    super.dispose();
  }

  void _onEvent() {
    final event = CloudEvents.instance.last;
    if (event == null || !mounted) return;
    setState(() => _event = event);
    _eventTimer?.cancel();
    final art = cloudArt(anim: widget.anim, tint: widget.tint, event: event);
    _eventTimer = Timer(cloudOneShot(art) ?? const Duration(seconds: 3), () {
      if (mounted) setState(() => _event = null);
    });
  }

  /// Разовая сцена рук или серии (касание, радость, кувырок) сама
  /// возвращает облачко к обычной жизни.
  void _armOneShot() {
    _oneShotTimer?.cancel();
    final length = cloudOneShot(cloudArt(anim: widget.anim, tint: widget.tint));
    if (length == null) return;
    _oneShotTimer = Timer(length, () => widget.onOneShotDone?.call());
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (widget.listenEvents) warmCloud(widget.tint, size: widget.size, dpr: dpr);
    return ListenableBuilder(listenable: CatalogService.instance, builder: (context, _) => _art(dpr));
  }

  /// Сцена маскота или эмоция пака — одной и той же картинкой на одном месте
  /// дерева: смена между ними идёт без мигания, прежний кадр стоит до
  /// готовности нового.
  Widget _art(double dpr) {
    final canvas = widget.size * _kCloudCanvas;
    final calm = _event == null &&
        (widget.anim == MascotAnimState.live || widget.anim == MascotAnimState.freeze) &&
        !widget.night;
    final emotion = calm ? cloudEmotionUrl(CatalogService.instance.allPacks, widget.mood) : null;
    final String? url;
    final double side;
    Offset shift = Offset.zero;
    if (emotion != null) {
      // Эмоции пака обрезаны плотно (квадрат 24..458 × 38..472 кадра 480):
      // ставим так, чтобы облачко совпало по размеру и месту со сценами.
      url = emotion;
      side = canvas * _kPackCrop;
      shift = _kPackShift * canvas;
    } else {
      side = canvas;
      url = catalogArtUrl(
        cloudArt(anim: widget.anim, tint: widget.tint, night: widget.night, sick: widget.sick, event: _event),
        artDecodeBucket(side * dpr),
        fallbackKey: 'cloud_idle_base',
      );
    }
    return OverflowBox(
      maxWidth: canvas,
      maxHeight: canvas,
      child: SizedBox.square(
        dimension: canvas,
        child: Transform.translate(
          offset: shift,
          child: Center(
            child: url == null ? const SizedBox.shrink() : catalogArtImage(url, side: side, decode: artDecodeBucket(side * dpr)),
          ),
        ),
      ),
    );
  }
}

/// Доля холста сцены, которую занимает кадр эмоции пака (434 из 480), и
/// сдвиг его середины от середины холста (на 1 и 15 пикселей из 480).
const double _kPackCrop = 434 / 480;
const Offset _kPackShift = Offset(1 / 480, 15 / 480);
