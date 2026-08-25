import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/live_location_tuning.dart';
import 'locale_service.dart';
import 'centrifugo_service.dart';
import 'pb_data_service.dart';
import 'pb_realtime_service.dart';
import 'pocketbase_service.dart';

const String _kSharingEnabledKey = 'live_location_sharing_enabled';

/// Снимок позиции участника пары. Живёт в PocketBase (коллекция `live_location`,
/// json `data` в канале пары) и НЕ удаляется на disconnect — поэтому последняя
/// точка партнёра видна на карте даже когда он офлайн.
@immutable
class LivePoint {
  final double lat;
  final double lng;
  final double accuracy; // метры
  final double? heading; // градусы (может отсутствовать)
  final int updatedAt; // epoch ms (клиентское время записи точки)

  const LivePoint({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.updatedAt,
    this.heading,
  });

  LatLng get latLng => LatLng(lat, lng);

  factory LivePoint.fromMap(Map<dynamic, dynamic> m) {
    return LivePoint(
      lat: (m['lat'] as num?)?.toDouble() ?? 0,
      lng: (m['lng'] as num?)?.toDouble() ?? 0,
      accuracy: (m['accuracy'] as num?)?.toDouble() ?? 0,
      heading: (m['heading'] as num?)?.toDouble(),
      updatedAt: (m['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Сервис live-локации пары. Транспорт — PocketBase (миграция §3, коллекция
/// `live_location`): свою позицию пишем стримом геолокатора (фоновый
/// foreground-service на Android, background updates на iOS), позицию партнёра —
/// слушаем live-подпиской PB.
class LiveLocationService with WidgetsBindingObserver {
  LiveLocationService._();
  static final LiveLocationService instance = LiveLocationService._();

  final PbDataService _data = PbDataService();
  final PbRealtimeService _rt = PbRealtimeService();

  String get _uid => PocketBaseService().userId ?? '';

  /// Общий для ОБОИХ партнёров узел live-локации: детерминированный ключ из
  /// пары uid, отсортированных лексикографически. В отличие от pairId он НЕ
  /// зависит от того, какой из (возможно дублирующихся) групповых документов
  /// сейчас активен на конкретном телефоне — оба партнёра всегда вычисляют
  /// один и тот же узел и потому видят друг друга. Фолбэк на pairId, если
  /// партнёр неизвестен (например, группа из 3+ участников).
  String _channel(String pairId, String partnerUid) {
    if (_uid.isEmpty || partnerUid.isEmpty) return pairId;
    final ids = [_uid, partnerUid]..sort();
    return 'pair_${ids[0]}_${ids[1]}';
  }

  StreamSubscription<Position>? _posSub;
  String? _activePairId;

  /// С каким профилем сейчас крутится поток. По нему видно, что пора
  /// перезапуститься: экономный профиль в фоне и точный на экране.
  bool? _streamForeground;
  bool _observing = false;

  /// Включён ли шеринг (персистентно, между запусками). UI слушает этот флаг.
  final ValueNotifier<bool> sharingEnabled = ValueNotifier<bool>(false);

  /// true, пока крутится стрим позиции.
  bool get isSharing => _posSub != null;

  /// Загружает сохранённое состояние флага. Вызывать на старте приложения.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      sharingEnabled.value = prefs.getBool(_kSharingEnabledKey) ?? false;
    } catch (_) {}
  }

  // ── Разрешения ──────────────────────────────────────────────────────────

  /// Запрашивает разрешение на геолокацию. Возвращает true, если выдан хотя бы
  /// whileInUse. На Android при уже выданном whileInUse повторный запрос
  /// предлагает «разрешить всегда» (фон), что нужно для трекинга в фоне.
  Future<bool> ensurePermission() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return false;
      }
      // Фон: на Android просим «Allow all the time» вторым запросом.
      if (Platform.isAndroid && perm == LocationPermission.whileInUse) {
        await Geolocator.requestPermission();
      }
      // На iPhone geolocator «Всегда» не спрашивает вовсе — только свой канал.
      if (Platform.isIOS && perm == LocationPermission.whileInUse) {
        await requestAlwaysIOS();
      }
      return true;
    } catch (e) {
      debugPrint('LiveLocationService.ensurePermission failed: $e');
      return false;
    }
  }

  /// Канал разрешения «Всегда» (`AppDelegate.setupLocationAlwaysChannel`).
  static const MethodChannel _alwaysChannel =
      MethodChannel('love_app/location_always');

  /// Просит на iPhone «Разрешить всегда».
  ///
  /// `Geolocator.requestPermission()` на iOS зовёт только
  /// `requestWhenInUseAuthorization`, поэтому фон жил ровно столько, сколько
  /// жил процесс: человек убил приложение — метка партнёра стоит до следующего
  /// открытия. Диалог показывается поверх уже выданного «При использовании» и
  /// ровно один раз: система на повторный запрос ничего не рисует, поэтому
  /// отказ здесь не ошибка — шеринг работает и без «Всегда», просто без
  /// пробуждения закрытого приложения.
  ///
  /// Возвращает состояние словом: `always`, `whenInUse`, `denied`,
  /// `notDetermined`, `unknown`.
  Future<String> requestAlwaysIOS() async {
    if (!Platform.isIOS) return 'unknown';
    try {
      return await _alwaysChannel.invokeMethod<String>('request') ?? 'unknown';
    } on MissingPluginException {
      // Нативной части нет — так бывает у сборок до 1.29.6.
      return 'unknown';
    } catch (e) {
      debugPrint('LiveLocationService: «Всегда» не запросилось: $e');
      return 'unknown';
    }
  }

  // ── Включение/выключение шеринга ──────────────────────────────────────────

  /// Переключает шеринг и сохраняет выбор. При включении запрашивает
  /// разрешение и стартует стрим; при выключении — гасит стрим и удаляет
  /// свою точку из RTDB. Возвращает фактическое состояние (false при отказе
  /// в разрешении).
  Future<bool> setSharingEnabled(
    bool enabled, {
    required String pairId,
    String partnerUid = '',
  }) async {
    if (enabled) {
      final granted = await ensurePermission();
      if (!granted) {
        await _persist(false);
        return false;
      }
      await _persist(true);
      await startSharing(pairId, partnerUid: partnerUid);
      return true;
    } else {
      await _persist(false);
      await stopSharing(removePoint: true);
      return false;
    }
  }

  Future<void> _persist(bool v) async {
    sharingEnabled.value = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSharingEnabledKey, v);
    } catch (_) {}
  }

  /// Запускает стрим позиции и пишет её в RTDB. Идемпотентно для того же
  /// pairId. Не делает ничего, если шеринг выключен флагом.
  Future<void> startSharing(String pairId, {String partnerUid = ''}) async {
    if (pairId.isEmpty || _uid.isEmpty) return;
    if (!sharingEnabled.value) return;
    // Android 12+ запрещает старт foreground-сервиса из фона, а geolocator
    // поднимает location-FGS внутри getPositionStream → из фона это роняет
    // ForegroundServiceStartNotAllowedException (летит мимо try/catch и onError).
    // Поднимаем стрим только на переднем плане; из фона выходим — подхватит
    // resumeIfEnabled при следующем открытии приложения.
    if (Platform.isAndroid && !_appInForeground()) {
      debugPrint('LiveLocationService: старт из фона пропущен (FGS запрещён)');
      return;
    }
    final channel = _channel(pairId, partnerUid);
    if (_activePairId == channel && _posSub != null) return;

    // Сменился канал — гасим прежний стрим, точку прежнего канала оставляем.
    await _cancelStream();
    _activePairId = channel;

    // Немедленный первый фикс, чтобы партнёр сразу увидел точку.
    unawaited(_pushCurrent(channel));

    _watchLifecycle();
    _streamForeground = _appInForeground();
    try {
      _posSub = Geolocator.getPositionStream(
        locationSettings: _locationSettings(),
      ).listen(
        (pos) => _push(channel, pos),
        onError: (e) => debugPrint('live location stream error: $e'),
      );
    } catch (e) {
      debugPrint('LiveLocationService.startSharing failed: $e');
    }
  }

  /// Подхватывает шеринг на старте приложения / при привязке к группе, если
  /// пользователь его раньше включал. Безопасно вызывать многократно.
  Future<void> resumeIfEnabled(String pairId, {String partnerUid = ''}) async {
    if (sharingEnabled.value) await startSharing(pairId, partnerUid: partnerUid);
  }

  void _watchLifecycle() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Ушли с экрана — перезапускаем поток экономным профилем, вернулись —
  /// точным. Настройки `getPositionStream` на лету не меняются, поэтому
  /// именно перезапуск.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_posSub == null) return;
    final foreground = _appInForeground();
    if (_streamForeground == foreground) return;
    final channel = _activePairId;
    if (channel == null) return;
    // На Android поток не трогаем ни в какую сторону: он живёт
    // foreground-сервисом, и перезапуск заново показывает уведомление
    // «Геопозиция включена» — на это и жаловались. Профиль там один.
    if (Platform.isAndroid) return;
    unawaited(_restartStream(channel, foreground));
  }

  Future<void> _restartStream(String channel, bool foreground) async {
    await _cancelStream();
    _activePairId = channel;
    _streamForeground = foreground;
    try {
      _posSub = Geolocator.getPositionStream(
        locationSettings: _locationSettings(),
      ).listen(
        (pos) => _push(channel, pos),
        onError: (e) => debugPrint('live location stream error: $e'),
      );
    } catch (e) {
      debugPrint('LiveLocationService: перезапуск потока не вышел: $e');
    }
  }

  /// Приложение на переднем плане? Нужен, чтобы не стартовать location-FGS из
  /// фона (Android 12+ это запрещает и роняет ForegroundServiceStartNotAllowed).
  bool _appInForeground() {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null ||
        s == AppLifecycleState.resumed ||
        s == AppLifecycleState.inactive;
  }

  Future<void> _pushCurrent(String pairId) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      await _push(pairId, pos);
    } catch (e) {
      debugPrint('LiveLocationService initial fix failed: $e');
    }
  }

  /// Как часто точка ложится на диск.
  ///
  /// Живая точка идёт в канал и хранения не требует. Запись нужна только тому,
  /// кто откроет карту позже, и виджету на рабочем столе — им хватает свежести
  /// в пару минут. Пока каждая точка писалась в базу, геопозиция стояла в общей
  /// очереди единственного писателя вместе с сообщениями и настроениями.
  static const Duration _storeEvery = Duration(minutes: 2);
  int? _storedAtMs;

  Future<void> _push(String channel, Position pos) async {
    if (_uid.isEmpty) return;
    // Пишем только конечные числа (heading/accuracy бывают NaN/Infinity, когда
    // значение недоступно).
    final acc = pos.accuracy.isFinite ? pos.accuracy : 0.0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final point = {
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy': acc,
      if (pos.heading.isFinite && pos.heading >= 0) 'heading': pos.heading,
      'updatedAt': now,
    };

    // Партнёру — сразу через канал, минуя диск.
    await CentrifugoService()
        .publish('loc:$channel', {'t': 'point', 'uid': _uid, ...point});

    final stored = _storedAtMs;
    if (stored == null || now - stored >= _storeEvery.inMilliseconds) {
      _storedAtMs = now;
      await _data.setLivePoint(channel, _uid, point);
    }
  }

  Future<void> _cancelStream() async {
    try {
      await _posSub?.cancel();
    } catch (e) {
      // geolocator бросает «No active stream to cancel», если нативный стрим
      // уже снят системой — это не повод падать.
      debugPrint('LiveLocationService: отмена стрима: $e');
    }
    _posSub = null;
  }

  /// Останавливает стрим. [removePoint] — удалить ли свою последнюю точку из
  /// RTDB (true при явном выключении шеринга; false при простом анбинде, чтобы
  /// партнёр видел последнее местоположение).
  Future<void> stopSharing({bool removePoint = false}) async {
    await _cancelStream();
    final pairId = _activePairId;
    _activePairId = null;
    if (removePoint && pairId != null && _uid.isNotEmpty) {
      // pairId здесь — канал пары (_activePairId).
      await _data.clearLivePoint(pairId, _uid);
    }
  }

  // ── Чтение позиции партнёра ───────────────────────────────────────────────

  /// Поток последней точки партнёра. null — точки ещё нет. Читает из ОБЩЕГО
  /// узла пары (канонический ключ), а не из pairId активной группы.
  Stream<LivePoint?> watchPartner(String pairId, String partnerUid) {
    if (pairId.isEmpty || partnerUid.isEmpty) {
      return Stream<LivePoint?>.value(null);
    }
    return _watchPoint(_channel(pairId, partnerUid), partnerUid);
  }

  /// Поток своей последней точки в том же общем узле пары (чтобы своя аватарка
  /// рисовалась из RTDB ровно из того узла, куда мы пишем). [partnerUid] нужен
  /// для вычисления канонического ключа канала.
  Stream<LivePoint?> watchSelf(String pairId, String partnerUid) {
    if (_uid.isEmpty) return Stream<LivePoint?>.value(null);
    return _watchPoint(_channel(pairId, partnerUid), _uid);
  }

  /// Точка участника: сначала канал, база — как опора и совместимость.
  ///
  /// Живые точки летят публикацией в `loc:<канал>` и на диск не попадают, но
  /// партнёр может сидеть на сборке постарше — она по-прежнему пишет их в
  /// коллекцию. Читаем оба источника и показываем тот, что свежее; заодно
  /// запись из базы отдаёт последнюю точку тому, кто открыл карту только что.
  Stream<LivePoint?> _watchPoint(String channel, String uid) {
    late StreamController<LivePoint?> ctrl;
    StreamSubscription? dbSub;
    RtUnsub? unsub;
    LivePoint? fromDb;
    LivePoint? fromChannel;

    void emit() {
      final a = fromChannel;
      final b = fromDb;
      LivePoint? best;
      if (a == null) {
        best = b;
      } else if (b == null) {
        best = a;
      } else {
        best = a.updatedAt >= b.updatedAt ? a : b;
      }
      if (!ctrl.isClosed) ctrl.add(best);
    }

    ctrl = StreamController<LivePoint?>(
      onListen: () async {
        dbSub = _rt
            .watchLivePoint(channel, uid)
            .handleError((e) => debugPrint('live location point error: $e'))
            .listen((rec) {
          final v = rec?.data['data'];
          fromDb = v is Map ? LivePoint.fromMap(v) : null;
          emit();
        });

        unsub = await CentrifugoService().subscribeRaw('loc:$channel', (data) {
          if (data['t'] != 'point') return;
          if ((data['uid'] ?? '').toString() != uid) return;
          fromChannel = LivePoint.fromMap(data);
          emit();
        });
      },
      onCancel: () async {
        await dbSub?.cancel();
        await unsub?.call();
      },
    );
    return ctrl.stream;
  }

  // ── Настройки геолокации (фон) ────────────────────────────────────────────

  LocationSettings _locationSettings() {
    // Профиль зависит от того, смотрит ли человек на экран: в фоне метку
    // видят изредка, а GPS будится постоянно — отсюда и стрелка на iPhone, и
    // уведомление на Android, и разряд батареи (три жалобы 21.08.2026).
    final tune = liveLocationTuning(
      foreground: _appInForeground(),
      android: Platform.isAndroid,
    );
    final accuracy =
        tune.highAccuracy ? LocationAccuracy.high : LocationAccuracy.medium;
    final distanceFilter = tune.distanceFilter;
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        // Как часто система вообще спрашивает координату. Редкий опрос — та
        // самая экономия, ради которой раньше снимали wake lock; со снятым
        // замком фон переставал работать вовсе.
        intervalDuration: tune.interval,
        // Foreground-service держит стрим живым в фоне. Геолокатор сам
        // объявляет сервис и его тип в своём манифесте.
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: LocaleService.current.liveLocationServiceTitle,
          notificationText: LocaleService.current.liveLocationServiceText,
          enableWakeLock: tune.wakeLock,
          setOngoing: false,
          // Та же монохромная иконка, что у всех уведомлений приложения
          // (FCM/локальные). Без неё geolocator ставит свой дефолт — отсюда
          // была «не та» иконка на уведомлении.
          notificationIcon: const AndroidResource(
            name: 'ic_notification',
            defType: 'drawable',
          ),
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: tune.pauseAutomatically,
        // Индикатор система показывает сама, когда действительно берёт
        // координаты в фоне. Принудительный показ держал стрелку в чужих
        // приложениях круглые сутки.
        showBackgroundLocationIndicator: tune.forceIndicator,
        allowBackgroundLocationUpdates: true,
        activityType: ActivityType.other,
      );
    }
    return LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  // ── Утилиты ───────────────────────────────────────────────────────────────

  /// Расстояние между двумя точками в метрах.
  static double distanceMeters(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Meter, a, b);

  /// Человекочитаемая дистанция: см / м / км.
  static String formatDistance(double meters) {
    if (meters < 1) return '${(meters * 100).round()} ${LocaleService.current.unitCm}';
    if (meters < 1000) return '${meters.round()} ${LocaleService.current.unitM}';
    final km = meters / 1000;
    final str = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
    return '$str ${LocaleService.current.unitKm}';
  }
}
