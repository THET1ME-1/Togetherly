import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'chest_sound.dart';
import 'offline/media_view_cache.dart';

/// Музыка страницы сезонного сундука и гром при открытии. Файлы приходят с
/// сервера вместе с сундуком (`music`, `thunder`), приложение своих не держит.
///
/// Слушается того же выключателя, что звук открытия ([ChestSound.enabled]), и
/// так же не трогает чужую музыку: на Android играет поверх, не прося фокус
/// звука, а на iPhone молчит, если что-то уже играет.
class SeasonMusic {
  SeasonMusic._() {
    ChestSound.instance.addListener(_onSwitch);
  }

  static final SeasonMusic instance = SeasonMusic._();

  AudioPlayer? _music;
  String? _musicUrl;
  bool _wanted = false;

  /// Что играть, когда звук включат обратно.
  String? _wantedUrl;
  int _run = 0;

  /// Музыка нужна, пока страница сезона на экране: [play] при входе, [stop]
  /// при уходе. Выключенный звук и чужая музыка её молча отменяют.
  Future<void> play(String? url) async {
    _wanted = true;
    _wantedUrl = url;
    if (url == null || !ChestSound.instance.enabled) return;
    final run = ++_run;
    try {
      if (!kIsWeb && Platform.isIOS && await AVAudioSession().isOtherAudioPlaying) return;
      final file = await OfflineImageCacheManager.instance.getSingleFile(url).timeout(const Duration(seconds: 12));
      if (run != _run || !_wanted) return;
      var p = _music;
      if (p == null || _musicUrl != url) {
        await p?.dispose();
        p = AudioPlayer(handleAudioSessionActivation: false);
        await p.setFilePath(file.path);
        await p.setLoopMode(LoopMode.one);
        _music = p;
        _musicUrl = url;
      }
      if (run != _run || !_wanted) return;
      await p.setVolume(0);
      unawaited(p.play());
      await _fade(p, 0, 0.9, run);
    } catch (e) {
      debugPrint('SeasonMusic: $e');
    }
  }

  Future<void> stop() async {
    _wanted = false;
    final run = ++_run;
    final p = _music;
    if (p == null || !p.playing) return;
    await _fade(p, p.volume, 0, run);
    if (run == _run) {
      try {
        await p.pause();
      } catch (_) {}
    }
  }

  Future<void> _fade(AudioPlayer p, double from, double to, int run) async {
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      if (run != _run) return;
      try {
        await p.setVolume(from + (to - from) * i / steps);
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 45));
    }
  }

  AudioPlayer? _thunder;
  String? _thunderUrl;

  /// Скачать гром заранее: он звучит в точный момент, когда отлетает замок.
  Future<void> prepareThunder(String? url) async {
    if (url == null || (_thunderUrl == url && _thunder != null)) return;
    try {
      final file = await OfflineImageCacheManager.instance.getSingleFile(url).timeout(const Duration(seconds: 12));
      final p = AudioPlayer(handleAudioSessionActivation: false);
      await p.setFilePath(file.path);
      await _thunder?.dispose();
      _thunder = p;
      _thunderUrl = url;
    } catch (e) {
      debugPrint('SeasonMusic: $e');
    }
  }

  Future<void> thunder(String? url) async {
    if (url == null || !ChestSound.instance.enabled) return;
    try {
      if (!kIsWeb && Platform.isIOS && await AVAudioSession().isOtherAudioPlaying && _music?.playing != true) return;
      if (_thunderUrl != url || _thunder == null) await prepareThunder(url);
      final p = _thunder;
      if (p == null) return;
      await p.seek(Duration.zero);
      unawaited(p.play());
    } catch (e) {
      debugPrint('SeasonMusic: $e');
    }
  }

  void _onSwitch() {
    if (!ChestSound.instance.enabled) {
      final wanted = _wanted;
      unawaited(stop());
      // Выключили звук на странице сезона — она по-прежнему на экране.
      _wanted = wanted;
    } else if (_wanted && _wantedUrl != null && _music?.playing != true) {
      unawaited(play(_wantedUrl));
    }
  }

  /// Уход с экрана сундука: плееры — нативный ресурс, держать их незачем.
  Future<void> release() async {
    _wanted = false;
    _wantedUrl = null;
    _run++;
    final m = _music, t = _thunder;
    _music = null;
    _thunder = null;
    _musicUrl = null;
    _thunderUrl = null;
    try {
      await m?.dispose();
      await t?.dispose();
    } catch (_) {}
  }
}
