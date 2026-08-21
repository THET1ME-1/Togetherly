import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

/// Готовая фигурка: файл, длительность и кадр-обложка.
class NoteCapture {
  final String path;
  final Duration duration;

  /// Кадр из середины ролика (jpg на устройстве). Пусто — обложки не вышло,
  /// фигурка покажет заливку темы и дождётся видео.
  final String thumbPath;

  const NoteCapture({
    required this.path,
    required this.duration,
    required this.thumbPath,
  });
}

/// Почему не получилось снимать. Экран показывает разное: без разрешения ведём
/// в настройки, при занятой камере просим повторить.
enum NoteRecordError { noPermission, noCamera, busy, failed }

class NoteRecordException implements Exception {
  final NoteRecordError reason;
  const NoteRecordException(this.reason);
  @override
  String toString() => 'NoteRecordException($reason)';
}

/// Съёмка фигурки — видеосообщения в форме.
///
/// Пишем 720p с фронталки: на экране фигурка занимает около 240 dp, а это до
/// 720 физических пикселей на плотных экранах — 480p там мылит. Тяжесть файла
/// снимает не разрешение, а короткая длительность и сжатие перед отправкой.
///
/// Камерой владеет сервис, а не экран: превью должно пережить смену формы,
/// поворот и открытие клавиатуры, но обязано умереть, как только человек вышел
/// из режима съёмки — иначе фонарик и индикатор камеры остаются гореть.
class NoteRecorderService {
  NoteRecorderService._();
  static final NoteRecorderService instance = NoteRecorderService._();
  factory NoteRecorderService() => instance;

  /// Полминуты. Столько живёт мысль, ради которой достают камеру; всё длиннее
  /// у пары и так уходит в голосовые (там предел три минуты).
  static const Duration maxDuration = Duration(seconds: 30);

  /// Короче — случайный тап по кнопке, а не желание что-то показать.
  static const Duration minDuration = Duration(milliseconds: 900);

  static const Duration _tick = Duration(milliseconds: 60);

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;

  Timer? _ticker;
  DateTime? _segmentStart;
  Duration _accumulated = Duration.zero;
  bool _recording = false;
  bool _paused = false;
  bool _torch = false;

  final _elapsed = StreamController<Duration>.broadcast();
  final _autoStop = StreamController<void>.broadcast();

  /// Сколько уже снято — для таймера и обода.
  Stream<Duration> get elapsed => _elapsed.stream;

  /// Уткнулись в предел: экран должен отправить снятое, а не оборвать молча.
  Stream<void> get autoStopped => _autoStop.stream;

  CameraController? get controller => _controller;
  bool get isRecording => _recording;
  bool get isPaused => _paused;
  bool get torchOn => _torch;

  /// Камера смотрит на человека — тогда превью зеркалим.
  bool get isFront =>
      _cameras.isNotEmpty &&
      _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

  bool get hasSecondCamera => _cameras.length > 1;

  Duration get elapsedNow => _segmentStart == null
      ? _accumulated
      : _accumulated + DateTime.now().difference(_segmentStart!);

  /// Поднимает камеру и держит её до [release]. Возвращает готовый контроллер.
  ///
  /// Бросает [NoteRecordException] — тишина здесь худший исход: человек видит
  /// чёрный квадрат и не понимает, снимает он или нет.
  Future<CameraController> prepare() async {
    final ready = _controller;
    if (ready != null && ready.value.isInitialized) return ready;
    try {
      _cameras = await availableCameras();
    } on CameraException catch (e) {
      debugPrint('NoteRecorder.availableCameras: $e');
      throw NoteRecordException(_reasonOf(e));
    }
    if (_cameras.isEmpty) {
      throw const NoteRecordException(NoteRecordError.noCamera);
    }
    // Фигурку почти всегда снимают на себя, поэтому начинаем с фронтальной.
    final front =
        _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    _cameraIndex = front >= 0 ? front : 0;
    return _open(_cameras[_cameraIndex]);
  }

  Future<CameraController> _open(CameraDescription camera) async {
    final old = _controller;
    _controller = null;
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {/* уже мёртв */}
    }
    final c = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await c.initialize();
      // Готовим кодек заранее: без этого первая запись стартует с задержкой в
      // полсекунды, и начало фразы теряется.
      await c.prepareForVideoRecording();
    } on CameraException catch (e) {
      debugPrint('NoteRecorder.initialize: $e');
      try {
        await c.dispose();
      } catch (_) {}
      throw NoteRecordException(_reasonOf(e));
    }
    _controller = c;
    _torch = false;
    return c;
  }

  /// Начинает съёмку. Камера должна быть уже поднята [prepare].
  Future<void> start() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw const NoteRecordException(NoteRecordError.failed);
    }
    if (_recording) throw const NoteRecordException(NoteRecordError.busy);
    try {
      await c.startVideoRecording();
    } on CameraException catch (e) {
      debugPrint('NoteRecorder.start: $e');
      throw NoteRecordException(_reasonOf(e));
    }
    _recording = true;
    _paused = false;
    _accumulated = Duration.zero;
    _segmentStart = DateTime.now();
    _startTicker();
  }

  /// Пауза без потери снятого: камера ждёт, таймер стоит.
  Future<void> pause() async {
    final c = _controller;
    if (!_recording || _paused || c == null) return;
    try {
      await c.pauseVideoRecording();
    } on CameraException catch (e) {
      debugPrint('NoteRecorder.pause: $e');
      return;
    }
    _accumulated = elapsedNow;
    _segmentStart = null;
    _paused = true;
    _ticker?.cancel();
    _ticker = null;
    _elapsed.add(_accumulated);
  }

  Future<void> resume() async {
    final c = _controller;
    if (!_recording || !_paused || c == null) return;
    try {
      await c.resumeVideoRecording();
    } on CameraException catch (e) {
      debugPrint('NoteRecorder.resume: $e');
      return;
    }
    _paused = false;
    _segmentStart = DateTime.now();
    _startTicker();
  }

  /// Останавливает съёмку и отдаёт файл с обложкой. `null` — если снимать было
  /// нечего или платформа не отдала файл.
  Future<NoteCapture?> stop() async {
    final c = _controller;
    if (!_recording || c == null) return null;
    final total = elapsedNow;
    _teardownTimers();
    XFile? file;
    try {
      file = await c.stopVideoRecording();
    } on CameraException catch (e) {
      debugPrint('NoteRecorder.stop: $e');
    }
    _recording = false;
    _paused = false;
    if (file == null) return null;
    // Переносим из кэша камеры во временную папку приложения под своим именем:
    // так путь предсказуем, а файл не удалит система на первом же сжатии.
    final path = await _moveToTemp(file.path);
    if (path == null) return null;
    final thumb = await _grabThumb(path, total);
    return NoteCapture(path: path, duration: total, thumbPath: thumb);
  }

  /// Бросает снятое и стирает файл: отменённая фигурка не должна оставаться на
  /// диске даже во временной папке.
  Future<void> cancel() async {
    final c = _controller;
    if (!_recording || c == null) {
      _teardownTimers();
      _recording = false;
      _paused = false;
      return;
    }
    _teardownTimers();
    _recording = false;
    _paused = false;
    try {
      final f = await c.stopVideoRecording();
      final file = File(f.path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('NoteRecorder.cancel: $e');
    }
  }

  /// Переключает фронтальную и основную. Во время записи не работает: смена
  /// сенсора рвёт поток, и файл получается битым.
  Future<CameraController?> switchCamera() async {
    if (_recording && !_paused) return _controller;
    if (_cameras.length < 2) return _controller;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    try {
      return await _open(_cameras[_cameraIndex]);
    } on NoteRecordException catch (e) {
      debugPrint('NoteRecorder.switchCamera: $e');
      return _controller;
    }
  }

  /// Фонарик. На фронтальной камере его нет — молча отказываемся.
  Future<bool> toggleTorch() async {
    final c = _controller;
    if (c == null || isFront) return false;
    try {
      _torch = !_torch;
      await c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
    } on CameraException catch (e) {
      debugPrint('NoteRecorder.torch: $e');
      _torch = false;
    }
    return _torch;
  }

  /// Гасит камеру. Обязательно при выходе из режима: иначе индикатор камеры
  /// продолжает гореть, а на части устройств залипает и фонарик.
  Future<void> release() async {
    _teardownTimers();
    _recording = false;
    _paused = false;
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      if (_torch) await c.setFlashMode(FlashMode.off);
      await c.dispose();
    } catch (e) {
      debugPrint('NoteRecorder.release: $e');
    }
    _torch = false;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tick, (_) {
      final now = elapsedNow;
      _elapsed.add(now);
      if (now >= maxDuration) {
        _ticker?.cancel();
        _ticker = null;
        _autoStop.add(null);
      }
    });
  }

  void _teardownTimers() {
    _ticker?.cancel();
    _ticker = null;
    _segmentStart = null;
    _accumulated = Duration.zero;
  }

  Future<String?> _moveToTemp(String src) async {
    try {
      final dir = await getTemporaryDirectory();
      final dst =
          '${dir.path}/note_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final moved = await File(src).rename(dst);
      return moved.path;
    } catch (e) {
      debugPrint('NoteRecorder._moveToTemp: $e');
      return src; // остался в кэше камеры — работать всё равно можно
    }
  }

  /// Кадр из середины ролика. Обложка приезжает партнёру вместе с сообщением,
  /// поэтому фигурка не бывает пустой, пока тянется видео.
  Future<String> _grabThumb(String path, Duration total) async {
    try {
      final at = (total.inMilliseconds ~/ 2).clamp(0, 1 << 30);
      final f = await VideoCompress.getFileThumbnail(
        path,
        quality: 62,
        position: at,
      ).timeout(const Duration(seconds: 8));
      return f.path;
    } catch (e) {
      debugPrint('NoteRecorder._grabThumb: $e');
      return '';
    }
  }

  static NoteRecordError _reasonOf(CameraException e) {
    final code = e.code.toLowerCase();
    if (code.contains('denied') || code.contains('permission')) {
      return NoteRecordError.noPermission;
    }
    if (code.contains('inuse') || code.contains('busy')) {
      return NoteRecordError.busy;
    }
    return NoteRecordError.failed;
  }

  void dispose() {
    _teardownTimers();
    _elapsed.close();
    _autoStop.close();
    _controller?.dispose();
    _controller = null;
  }
}
