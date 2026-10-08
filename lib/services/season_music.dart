import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

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

  static const double _level = 0.9;

  /// Мелодии страницы по очереди. Каждая играет до конца и за [_fadeMs]
  /// перетекает в следующую, после последней — снова первая (решение
  /// владельца 08.10.2026). Одна мелодия — играет по кругу.
  List<String> _list = const [];
  int _index = 0;
  int _fadeMs = 3500;
  AudioPlayer? _cur;

  /// Уходящая мелодия, пока идёт переход.
  AudioPlayer? _out;
  bool _crossing = false;
  DateTime _retryAt = DateTime(2000);
  Timer? _watch;

  /// Поколение списка: смена списка гасит переходы старого.
  int _gen = 0;
  final Expando<int> _rampOf = Expando();
  int _ramps = 0;

  bool _wanted = false;

  /// Что играть, когда звук включат обратно.
  List<String> _wantedList = const [];
  int _wantedFade = 3500;

  /// Музыка нужна, пока страница сезона на экране: [play] при входе, [stop]
  /// при уходе. Вернулся — мелодия продолжается с того же места. Выключенный
  /// звук и чужая музыка её молча отменяют.
  Future<void> play(List<String> urls, {int fadeMs = 3500}) async {
    _wanted = true;
    _wantedList = urls;
    _wantedFade = fadeMs;
    if (urls.isEmpty || !ChestSound.instance.enabled) return;
    try {
      if (!kIsWeb && Platform.isIOS && await AVAudioSession().isOtherAudioPlaying) return;
      if (!_wanted) return;
      final cur = _cur;
      if (cur != null && listEquals(urls, _list)) {
        if (!cur.playing) {
          await cur.setVolume(0);
          unawaited(cur.play());
          unawaited(_ramp(cur, 0, _level, 900));
        }
        _ensureWatch();
        return;
      }
      await _dropMusic();
      _list = List.of(urls);
      _fadeMs = fadeMs;
      final gen = ++_gen;
      await _startTrack(0, gen, fadeMs: 1200);
      _ensureWatch();
    } catch (e) {
      debugPrint('SeasonMusic: $e');
    }
  }

  Future<void> _startTrack(int i, int gen, {required int fadeMs}) async {
    final file = await OfflineImageCacheManager.instance.getSingleFile(_list[i]).timeout(const Duration(seconds: 25));
    if (gen != _gen || !_wanted) return;
    final p = AudioPlayer(handleAudioSessionActivation: false);
    try {
      await p.setFilePath(file.path);
      if (_list.length == 1) await p.setLoopMode(LoopMode.one);
    } catch (e) {
      await p.dispose();
      rethrow;
    }
    if (gen != _gen || !_wanted) {
      await p.dispose();
      return;
    }
    await p.setVolume(0);
    final old = _cur;
    _cur = p;
    _index = i;
    unawaited(p.play());
    // Следующая мелодия качается, пока играет эта: переход не ждёт сети.
    if (_list.length > 1) {
      unawaited(
        OfflineImageCacheManager.instance.getSingleFile(_list[(i + 1) % _list.length]).then((_) {}, onError: (_) {}),
      );
    }
    if (old != null) {
      _out = old;
      unawaited(
        _ramp(old, old.volume, 0, fadeMs).then((_) async {
          if (identical(_out, old)) _out = null;
          try {
            await old.dispose();
          } catch (_) {}
        }),
      );
    }
    await _ramp(p, 0, _level, fadeMs);
  }

  void _ensureWatch() {
    _watch ??= Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  /// Пора ли перетекать в следующую мелодию.
  Future<void> _tick() async {
    final p = _cur;
    if (!_wanted || p == null || _crossing || _list.length < 2 || !p.playing) return;
    if (DateTime.now().isBefore(_retryAt)) return;
    final dur = p.duration;
    if (dur == null) return;
    final ended = p.processingState == ProcessingState.completed;
    if (!ended && dur - p.position > Duration(milliseconds: _fadeMs)) return;
    _crossing = true;
    try {
      await _startTrack((_index + 1) % _list.length, _gen, fadeMs: ended ? 1200 : _fadeMs);
    } catch (e) {
      // Нет сети для следующей — попробуем позже, текущая доиграет.
      _retryAt = DateTime.now().add(const Duration(seconds: 10));
      debugPrint('SeasonMusic: $e');
    } finally {
      _crossing = false;
    }
  }

  Future<void> stop() async {
    _wanted = false;
    final p = _cur, o = _out;
    try {
      await o?.pause();
    } catch (_) {}
    if (p == null || !p.playing) return;
    await _ramp(p, p.volume, 0, 450);
    if (!_wanted && identical(_cur, p)) {
      try {
        await p.pause();
      } catch (_) {}
    }
  }

  /// Плавно сменить громкость; новый переход того же плеера отменяет старый.
  Future<void> _ramp(AudioPlayer p, double from, double to, int ms) async {
    final token = ++_ramps;
    _rampOf[p] = token;
    final steps = math.max(1, ms ~/ 50);
    for (var i = 1; i <= steps; i++) {
      if (_rampOf[p] != token) return;
      try {
        await p.setVolume(from + (to - from) * i / steps);
      } catch (_) {
        return;
      }
      await Future<void>.delayed(Duration(milliseconds: ms ~/ steps));
    }
  }

  Future<void> _dropMusic() async {
    _gen++;
    final c = _cur, o = _out;
    _cur = null;
    _out = null;
    _list = const [];
    try {
      await c?.dispose();
      await o?.dispose();
    } catch (_) {}
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
      if (!kIsWeb && Platform.isIOS && await AVAudioSession().isOtherAudioPlaying && _cur?.playing != true) return;
      if (_thunderUrl != url || _thunder == null) await prepareThunder(url);
      final p = _thunder;
      if (p == null) return;
      await p.seek(Duration.zero);
      unawaited(p.play());
    } catch (e) {
      debugPrint('SeasonMusic: $e');
    }
  }

  AudioPlayer? _crackle;
  String? _crackleUrl;

  /// Треск помех на сбое кнопки. Музыка под ним не прерывается.
  Future<void> crackle(String? url) async {
    if (url == null || !ChestSound.instance.enabled) return;
    // Не скачан — этот сбой молчит: треск, опоздавший на секунду, хуже тишины.
    if (_crackleUrl != url || _crackle == null) {
      unawaited(prepareCrackle(url));
      return;
    }
    try {
      if (!kIsWeb && Platform.isIOS && await AVAudioSession().isOtherAudioPlaying && _cur?.playing != true) return;
      final p = _crackle!;
      await p.seek(Duration.zero);
      unawaited(p.play());
    } catch (e) {
      debugPrint('SeasonMusic: $e');
    }
  }

  Future<void> prepareCrackle(String? url) async {
    if (url == null || (_crackleUrl == url && _crackle != null)) return;
    try {
      final file = await OfflineImageCacheManager.instance.getSingleFile(url).timeout(const Duration(seconds: 12));
      final p = AudioPlayer(handleAudioSessionActivation: false);
      await p.setFilePath(file.path);
      await _crackle?.dispose();
      _crackle = p;
      _crackleUrl = url;
    } catch (e) {
      debugPrint('SeasonMusic: $e');
    }
  }

  void _onSwitch() {
    if (!ChestSound.instance.enabled) {
      // Выключили звук на странице сезона: она по-прежнему на экране, и
      // включённый звук вернёт мелодию с того же места.
      final p = _cur, o = _out;
      unawaited(() async {
        try {
          await o?.pause();
          await p?.pause();
        } catch (_) {}
      }());
    } else if (_wanted && _wantedList.isNotEmpty && _cur?.playing != true) {
      unawaited(play(_wantedList, fadeMs: _wantedFade));
    }
  }

  /// Уход с экрана сундука: плееры — нативный ресурс, держать их незачем.
  Future<void> release() async {
    _wanted = false;
    _wantedList = const [];
    _watch?.cancel();
    _watch = null;
    await _dropMusic();
    final t = _thunder, k = _crackle;
    _thunder = null;
    _crackle = null;
    _thunderUrl = null;
    _crackleUrl = null;
    try {
      await t?.dispose();
      await k?.dispose();
    } catch (_) {}
  }
}
