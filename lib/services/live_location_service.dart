import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_service.dart';
import 'locale_service.dart';

/// URL базы Realtime Database (регион europe-west1 — не дефолтный).
/// Совпадает с [TogetherSessionService] и презенсом в [FirebaseService].
const String _kRtdbUrl =
    'https://togetherly-d4856-default-rtdb.europe-west1.firebasedatabase.app';

const String _kSharingEnabledKey = 'live_location_sharing_enabled';

/// Снимок позиции участника пары. Живёт в RTDB
/// `liveLocation/{pairId}/points/{uid}` и НЕ удаляется на disconnect —
/// поэтому последняя точка партнёра видна на карте даже когда он офлайн.
@immutable
class LivePoint {
  final double lat;
  final double lng;
  final double accuracy; // метры
  final double? heading; // градусы (может отсутствовать)
  final int updatedAt; // epoch ms (ServerValue.timestamp)

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

/// Сервис live-локации пары. Транспорт — Realtime Database (как «смотрим
/// вместе» и презенс): ноль Firestore-чтений. Свою позицию мы пишем стримом
/// геолокатора (фоновый foreground-service на Android, background updates на
/// iOS), позицию партнёра — слушаем отдельным листенером.
class LiveLocationService {
  LiveLocationService._();
  static final LiveLocationService instance = LiveLocationService._();

  final FirebaseService _fb = FirebaseService();

  FirebaseDatabase get _db =>
      FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: _kRtdbUrl);

  DatabaseReference _pairRef(String channel) => _db.ref('liveLocation/$channel');

  String get _uid => _fb.uid ?? '';

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
      return true;
    } catch (e) {
      debugPrint('LiveLocationService.ensurePermission failed: $e');
      return false;
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
    final channel = _channel(pairId, partnerUid);
    if (_activePairId == channel && _posSub != null) return;

    // Сменился канал — гасим прежний стрим, точку прежнего канала оставляем.
    await _cancelStream();
    _activePairId = channel;

    // Членство (для security-rules RTDB) — каждый пишет своё в ОБЩИЙ узел пары.
    try {
      await _pairRef(channel).child('members').child(_uid).set(true);
    } catch (e) {
      debugPrint('LiveLocationService membership failed: $e');
    }

    // Немедленный первый фикс, чтобы партнёр сразу увидел точку.
    unawaited(_pushCurrent(channel));

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

  Future<void> _push(String pairId, Position pos) async {
    if (_uid.isEmpty) return;
    // RTDB отклоняет NaN/Infinity — геолокатор отдаёт такие для heading/accuracy,
    // когда значение недоступно. Пишем только конечные числа.
    final acc = pos.accuracy.isFinite ? pos.accuracy : 0.0;
    try {
      await _pairRef(pairId).child('points').child(_uid).set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': acc,
        if (pos.heading.isFinite && pos.heading >= 0) 'heading': pos.heading,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('LiveLocationService push failed: $e');
    }
  }

  Future<void> _cancelStream() async {
    await _posSub?.cancel();
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
      try {
        await _pairRef(pairId).child('points').child(_uid).remove();
      } catch (_) {}
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

  Stream<LivePoint?> _watchPoint(String channel, String uid) {
    return _pairRef(channel)
        .child('points')
        .child(uid)
        .onValue
        .handleError((e) => debugPrint('live location point error: $e'))
        .map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return null;
      return LivePoint.fromMap(v);
    });
  }

  // ── Настройки геолокации (фон) ────────────────────────────────────────────

  LocationSettings _locationSettings() {
    const accuracy = LocationAccuracy.high;
    const distanceFilter = 15; // метров — пишем только при заметном движении
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        // Foreground-service держит стрим живым в фоне. Геолокатор сам
        // объявляет сервис и его тип в своём манифесте.
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: LocaleService.current.liveLocationServiceTitle,
          notificationText: LocaleService.current.liveLocationServiceText,
          enableWakeLock: true,
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
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
        activityType: ActivityType.other,
      );
    }
    return const LocationSettings(
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
