import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'pb_media_service.dart';

/// Что сейчас с фигуркой: какая играет, где бегунок, включён ли звук.
class NotePlayback {
  /// id сообщения, которое играет. Пусто — не играет ничего.
  final String messageId;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool loading;
  final bool muted;

  const NotePlayback({
    this.messageId = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.loading = false,
    this.muted = true,
  });

  double get progress => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  NotePlayback copy({
    String? messageId,
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? loading,
    bool? muted,
  }) =>
      NotePlayback(
        messageId: messageId ?? this.messageId,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        playing: playing ?? this.playing,
        loading: loading ?? this.loading,
        muted: muted ?? this.muted,
      );
}

/// Проигрывание фигурок в чате.
///
/// Играет одна за раз — как и голосовые. Дело не только в звуке: каждый живой
/// `VideoPlayerController` держит декодер, и три фигурки подряд в ленте уже
/// роняют кадры на слабом телефоне.
///
/// Позиция берётся не из потока плагина напрямую: он присылает её примерно раз
/// в сто миллисекунд, и обод дёргался бы ступеньками. [smoothProgress]
/// достраивает недостающие кадры по времени с последнего обновления, поэтому
/// обод едет ровно, а правду по-прежнему говорит плеер.
class NotePlayerService extends ChangeNotifier {
  NotePlayerService._();
  static final NotePlayerService instance = NotePlayerService._();
  factory NotePlayerService() => instance;

  VideoPlayerController? _controller;
  NotePlayback _state = const NotePlayback();
  Duration _lastPosition = Duration.zero;
  DateTime _lastStamp = DateTime.now();

  /// Кто последним отдал звук: если человек включил звук на одной фигурке,
  /// следующая тоже играет со звуком — иначе приходится тапать каждую.
  bool _soundOn = false;

  NotePlayback get state => _state;
  VideoPlayerController? get controller => _controller;

  bool isCurrent(String messageId) =>
      _state.messageId.isNotEmpty && _state.messageId == messageId;

  /// Доля проигранного с досчётом между обновлениями плагина.
  double smoothProgress() {
    final total = _state.duration.inMilliseconds;
    if (total <= 0) return 0;
    var ms = _lastPosition.inMilliseconds;
    if (_state.playing) {
      ms += DateTime.now().difference(_lastStamp).inMilliseconds;
    }
    return (ms / total).clamp(0.0, 1.0);
  }

  /// Открывает фигурку и начинает играть.
  ///
  /// [auto] — запуск при появлении в кадре, а не по тапу: такой запуск всегда
  /// беззвучный и уступает дорогу тому, что человек включил руками.
  Future<void> open({
    required String messageId,
    required String url,
    Duration? knownDuration,
    bool auto = false,
    bool? sound,
  }) async {
    if (isCurrent(messageId)) {
      if (!_state.playing) await _controller?.play();
      return;
    }
    if (auto && _state.playing && !_state.muted) return; // не рвём звук
    await stop();

    // Само запустилось — молча (лента не должна заговорить сама). Открыли
    // руками — со звуком: за этим тап и делают. Если звук выключали руками,
    // следующая фигурка тоже молчит — привычка держится на _soundOn.
    final wantSound = sound ?? (auto ? false : _soundOn || !auto);
    _soundOn = wantSound;
    _set(NotePlayback(
      messageId: messageId,
      loading: true,
      duration: knownDuration ?? Duration.zero,
      muted: !wantSound,
    ));

    final src = url.startsWith('pb://')
        ? await PbMediaService.instance.resolveUrlAuthed(url)
        : url;
    if (src == null || src.isEmpty) {
      _set(const NotePlayback());
      return;
    }
    // Пока резолвился адрес, человек мог уйти к другой фигурке.
    if (_state.messageId != messageId) return;

    final c = src.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(src))
        : VideoPlayerController.file(_fileOf(src));
    _controller = c;
    c.addListener(_onTick);
    try {
      await c.initialize();
      if (_state.messageId != messageId) {
        await _disposeController(c);
        return;
      }
      await c.setVolume(_state.muted ? 0 : 1);
      await c.setLooping(false);
      await c.play();
      _lastPosition = Duration.zero;
      _lastStamp = DateTime.now();
      _set(_state.copy(
        loading: false,
        playing: true,
        duration: c.value.duration,
      ));
    } catch (e) {
      debugPrint('NotePlayer.open($messageId) failed: $e');
      await _disposeController(c);
      if (_state.messageId == messageId) _set(const NotePlayback());
    }
  }

  Future<void> togglePlay() async {
    final c = _controller;
    if (c == null) return;
    if (_state.playing) {
      await c.pause();
    } else {
      // Досмотренную запускаем сначала — иначе тап по ней ничего не делает.
      if (_state.progress > 0.995) await c.seekTo(Duration.zero);
      await c.play();
    }
  }

  /// Тап по фигурке даёт звук. Второй тап — снова тишина. Выбор запоминается
  /// на сеанс: перещёлкивать каждую фигурку никто не станет.
  Future<void> toggleSound() async {
    final c = _controller;
    if (c == null) return;
    final on = _state.muted;
    _soundOn = on;
    await c.setVolume(on ? 1 : 0);
    _set(_state.copy(muted: !on));
  }

  Future<void> seekFraction(double fraction) async {
    final c = _controller;
    final total = _state.duration;
    if (c == null || total <= Duration.zero) return;
    final to = total * fraction.clamp(0.0, 1.0);
    await c.seekTo(to);
    _lastPosition = to;
    _lastStamp = DateTime.now();
  }

  /// Останавливает то, что играет сейчас. [onlyIf] — не трогать чужую фигурку.
  Future<void> stop({String? onlyIf}) async {
    if (onlyIf != null && !isCurrent(onlyIf)) return;
    final c = _controller;
    _controller = null;
    _set(const NotePlayback());
    if (c != null) await _disposeController(c);
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final v = c.value;
    final pos = v.position;
    if (pos != _lastPosition) {
      _lastPosition = pos;
      _lastStamp = DateTime.now();
    }
    final finished = v.duration > Duration.zero &&
        pos >= v.duration - const Duration(milliseconds: 80);
    if (finished && !v.isPlaying) {
      // Досмотрели: бегунок в начало, обод гаснет, кадр остаётся последним.
      _lastPosition = Duration.zero;
      _set(_state.copy(
          playing: false, position: Duration.zero, duration: v.duration));
      return;
    }
    _set(_state.copy(
      position: pos,
      duration: v.duration,
      playing: v.isPlaying,
      loading: v.isBuffering,
    ));
  }

  Future<void> _disposeController(VideoPlayerController c) async {
    try {
      c.removeListener(_onTick);
      await c.pause();
      await c.dispose();
    } catch (e) {
      debugPrint('NotePlayer.dispose: $e');
    }
  }

  void _set(NotePlayback s) {
    _state = s;
    notifyListeners();
  }

  static File _fileOf(String path) => File(path);

  @override
  void dispose() {
    final c = _controller;
    _controller = null;
    if (c != null) unawaited(_disposeController(c));
    super.dispose();
  }
}
