import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'pb_media_service.dart';
import 'offline/media_file_fetch.dart';

/// Что сейчас с голосовым: какое играет, где бегунок, с какой скоростью.
class VoicePlayback {
  /// id сообщения, которое звучит. Пусто — не играет ничего.
  final String messageId;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool loading;
  final double speed;

  const VoicePlayback({
    this.messageId = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.loading = false,
    this.speed = 1.0,
  });

  /// Доля прослушанного 0..1 — по ней наливаются столбики волны.
  double get progress => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
}

/// Проигрывание голосовых в чате.
///
/// Играет одно сообщение за раз: запуск второго глушит первое. Иначе два голоса
/// накладываются друг на друга — это первое, что случается, когда в переписке
/// подряд лежат три голосовых и по ним тыкают.
class VoicePlayerService extends ChangeNotifier {
  VoicePlayerService._() {
    _player.positionStream.listen((p) {
      if (_state.messageId.isEmpty) return;
      _set(_state.copy(position: p));
    });
    _player.playerStateStream.listen((s) {
      if (_state.messageId.isEmpty) return;
      if (s.processingState == ProcessingState.completed) {
        // Дослушали до конца: бегунок в начало, кнопка снова «слушать».
        _player.pause();
        _player.seek(Duration.zero);
        _set(const VoicePlayback());
      } else {
        _set(_state.copy(
          playing: s.playing,
          loading: s.processingState == ProcessingState.loading ||
              s.processingState == ProcessingState.buffering,
        ));
      }
    });
    _player.durationStream.listen((d) {
      if (d != null && _state.messageId.isNotEmpty) {
        _set(_state.copy(duration: d));
      }
    });
  }

  static final VoicePlayerService instance = VoicePlayerService._();
  factory VoicePlayerService() => instance;

  /// Скорости по кругу: обычная, полуторная, двойная.
  static const List<double> speeds = [1.0, 1.5, 2.0];

  final AudioPlayer _player = AudioPlayer();
  VoicePlayback _state = const VoicePlayback();
  double _speed = 1.0;

  VoicePlayback get state => _state;

  /// Играет ли именно это сообщение (в чате их много, кнопка нужна одна).
  bool isCurrent(String messageId) =>
      _state.messageId.isNotEmpty && _state.messageId == messageId;

  Future<void> toggle({
    required String messageId,
    required String url,
    Duration? knownDuration,
  }) async {
    if (isCurrent(messageId)) {
      if (_state.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }
    await stop();
    _set(VoicePlayback(
      messageId: messageId,
      loading: true,
      duration: knownDuration ?? Duration.zero,
      speed: _speed,
    ));
    try {
      // Локальная запись играет с диска (сообщение ещё в очереди отправки),
      // серверная — по ссылке с токеном: файлы `media` защищены, и голая
      // ссылка без токена отдала бы 403 (`resolveUrlAuthed`, как у видео ленты).
      final src = url.startsWith('pb://')
          ? await PbMediaService.instance.resolveUrlAuthed(url)
          : url;
      if (src == null || src.isEmpty) {
        _set(const VoicePlayback());
        return;
      }
      if (src.startsWith('http')) {
        // Голосовое просят в среднем четыре раза, и раньше каждое включение
        // качало его заново. Ключ кэша — исходная pb://-ссылка: адрес с
        // file-токеном меняется каждые пару минут и кэш бы промахивался.
        final local = await cachedMediaPath(url, src);
        if (local != null) {
          await _player.setFilePath(local);
        } else {
          await _player.setUrl(src);
        }
      } else {
        await _player.setFilePath(src);
      }
      await _player.setSpeed(_speed);
      await _player.play();
    } catch (e) {
      debugPrint('VoicePlayer.toggle($messageId) failed: $e');
      _set(const VoicePlayback());
    }
  }

  /// Перемотка тапом по волне: доля 0..1 от длительности.
  Future<void> seekFraction(String messageId, double fraction) async {
    if (!isCurrent(messageId)) return;
    final d = _state.duration;
    if (d <= Duration.zero) return;
    await _player.seek(d * fraction.clamp(0.0, 1.0));
  }

  /// Следующая скорость по кругу. Держим её для всех голосовых сразу: выбрал
  /// «быстрее» — значит быстрее, а не только у одного сообщения.
  Future<double> cycleSpeed() async {
    final i = speeds.indexOf(_speed);
    _speed = speeds[(i + 1) % speeds.length];
    await _player.setSpeed(_speed);
    if (_state.messageId.isNotEmpty) _set(_state.copy(speed: _speed));
    return _speed;
  }

  double get speed => _speed;

  Future<void> stop() async {
    if (_state.messageId.isEmpty) return;
    try {
      await _player.stop();
    } catch (_) {/* уже остановлен */}
    _set(const VoicePlayback());
  }

  void _set(VoicePlayback s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

extension on VoicePlayback {
  VoicePlayback copy({
    String? messageId,
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? loading,
    double? speed,
  }) =>
      VoicePlayback(
        messageId: messageId ?? this.messageId,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        playing: playing ?? this.playing,
        loading: loading ?? this.loading,
        speed: speed ?? this.speed,
      );
}
