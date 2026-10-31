import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/cloud_mascot.dart';
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

  @override
  void initState() {
    super.initState();
    if (widget.listenEvents) CloudEvents.instance.addListener(_onEvent);
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
    final art = cloudArt(
      anim: widget.anim,
      tint: widget.tint,
      night: widget.night,
      sick: widget.sick,
      event: _event,
    );
    if (widget.listenEvents) {
      warmCloud(widget.tint, size: widget.size, dpr: MediaQuery.devicePixelRatioOf(context));
    }
    final canvas = widget.size * _kCloudCanvas;
    return OverflowBox(
      maxWidth: canvas,
      maxHeight: canvas,
      child: CatalogArtAnim(
        art,
        side: canvas,
        fallbackKey: 'cloud_idle_base',
      ),
    );
  }
}
