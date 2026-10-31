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
    // Рисунок облачка занимает около 70% холста: холст крупнее места, чтобы
    // само облачко было размером с прежнего маскота.
    final canvas = widget.size * 1.4;
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
