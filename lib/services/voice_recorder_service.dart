import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/voice_note.dart';

/// Готовая запись: файл на диске, длительность и огибающая громкости.
class VoiceCapture {
  final String path;
  final Duration duration;

  /// Строка из 40 цифр — то, что ляжет в `chat_messages.voice_peaks`.
  final String peaks;

  const VoiceCapture({
    required this.path,
    required this.duration,
    required this.peaks,
  });
}

/// Почему запись не началась. Экран показывает человеку разное: без разрешения
/// ведём в настройки, при занятом микрофоне просим повторить.
enum VoiceRecordError { noPermission, busy, failed }

class VoiceRecordException implements Exception {
  final VoiceRecordError reason;
  const VoiceRecordException(this.reason);
  @override
  String toString() => 'VoiceRecordException($reason)';
}

/// Запись голосового сообщения.
///
/// Пишем AAC-LC 32 кбит моно 22 050 Гц: речи хватает с запасом, а минута весит
/// около 240 КБ — столько же, сколько одно фото в ленте. Амплитуду снимаем раз
/// в 60 мс и копим: из этих замеров получается волна, которую партнёр увидит,
/// не скачивая файл (см. [VoicePeaks]).
class VoiceRecorderService {
  VoiceRecorderService._();
  static final VoiceRecorderService instance = VoiceRecorderService._();
  factory VoiceRecorderService() => instance;

  /// Дольше трёх минут — уже не сообщение, а монолог: на этом пределе запись
  /// останавливается сама и предлагает отправить записанное.
  static const Duration maxDuration = Duration(minutes: 3);

  /// Короче — случайный тап по кнопке, а не желание что-то сказать.
  static const Duration minDuration = Duration(milliseconds: 800);

  static const Duration _tick = Duration(milliseconds: 60);

  final AudioRecorder _rec = AudioRecorder();
  final List<double> _amps = [];
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _limitTimer;
  DateTime? _startedAt;
  String? _path;

  final _elapsed = StreamController<Duration>.broadcast();
  final _levels = StreamController<List<double>>.broadcast();
  final _autoStop = StreamController<void>.broadcast();

  /// Сколько уже пишем — для таймера на полосе записи.
  Stream<Duration> get elapsed => _elapsed.stream;

  /// Последние замеры громкости (0..1) для живой волны.
  Stream<List<double>> get levels => _levels.stream;

  /// Сработал трёхминутный предел: экран должен предложить отправить.
  Stream<void> get autoStopped => _autoStop.stream;

  bool get isRecording => _startedAt != null;

  Duration get elapsedNow => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  /// Начинает запись. Бросает [VoiceRecordException], если микрофон не дали
  /// или он занят — тишина в ответ здесь хуже всего: человек держит палец и не
  /// понимает, пишется ли.
  Future<void> start() async {
    if (isRecording) throw const VoiceRecordException(VoiceRecordError.busy);
    bool allowed;
    try {
      allowed = await _rec.hasPermission();
    } catch (e) {
      debugPrint('VoiceRecorder.hasPermission failed: $e');
      throw const VoiceRecordException(VoiceRecordError.failed);
    }
    if (!allowed) throw const VoiceRecordException(VoiceRecordError.noPermission);

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 22050,
          numChannels: 1,
          noiseSuppress: true,
          echoCancel: true,
        ),
        path: path,
      );
    } catch (e) {
      debugPrint('VoiceRecorder.start failed: $e');
      throw const VoiceRecordException(VoiceRecordError.failed);
    }

    _path = path;
    _amps.clear();
    _startedAt = DateTime.now();

    _ampSub = _rec.onAmplitudeChanged(_tick).listen((a) {
      _amps.add(_normalize(a.current));
      _elapsed.add(elapsedNow);
      // Полосе записи нужны только последние замеры — она рисует бегущую волну,
      // а не всю запись целиком.
      _levels.add(_amps.length <= 32
          ? List<double>.of(_amps)
          : _amps.sublist(_amps.length - 32));
    }, onError: (e) => debugPrint('VoiceRecorder amplitude: $e'));

    _limitTimer = Timer(maxDuration, () {
      if (isRecording) _autoStop.add(null);
    });
  }

  /// Останавливает запись и отдаёт файл. `null` — если запись не шла или файл
  /// не появился (редкий сбой платформы).
  Future<VoiceCapture?> stop() async {
    if (!isRecording) return null;
    final started = _startedAt!;
    final path = _path;
    await _teardown();
    String? out;
    try {
      out = await _rec.stop();
    } catch (e) {
      debugPrint('VoiceRecorder.stop failed: $e');
    }
    final file = File(out ?? path ?? '');
    if (!await file.exists()) return null;
    final ms = DateTime.now().difference(started).inMilliseconds;
    return VoiceCapture(
      path: file.path,
      duration: Duration(milliseconds: ms),
      peaks: VoicePeaks.encode(List<double>.of(_amps)),
    );
  }

  /// Отменяет запись и стирает файл: отменённое голосовое не должно оставаться
  /// на диске даже во временной папке.
  Future<void> cancel() async {
    if (!isRecording) return;
    final path = _path;
    await _teardown();
    try {
      await _rec.cancel();
    } catch (e) {
      debugPrint('VoiceRecorder.cancel failed: $e');
    }
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {/* файла нет — и хорошо */}
    }
  }

  Future<void> _teardown() async {
    _limitTimer?.cancel();
    _limitTimer = null;
    await _ampSub?.cancel();
    _ampSub = null;
    _startedAt = null;
    _path = null;
  }

  /// Пакет отдаёт громкость в дБFS (тишина около -60, максимум 0). Приводим к
  /// 0..1: ниже -50 дБ — тишина, выше — линейная шкала.
  static double _normalize(double db) {
    if (db.isNaN || db.isInfinite) return 0;
    const floorDb = -50.0;
    if (db <= floorDb) return 0;
    return math.min(1, (db - floorDb) / -floorDb);
  }

  void dispose() {
    _limitTimer?.cancel();
    _ampSub?.cancel();
    _elapsed.close();
    _levels.close();
    _autoStop.close();
    _rec.dispose();
  }
}
