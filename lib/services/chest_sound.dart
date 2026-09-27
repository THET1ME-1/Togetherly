import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chest.dart';

/// Звук открытия сундука — «Фанфара» (макет «Звук сундука», выбран
/// 28.09.2026). Длина файла равна анимации открытия, звук стартует с её
/// первым кадром; опоздал кадр — звук начинается с той же точки.
///
/// Чужую музыку не трогаем. На Android плеер не просит фокус звука
/// (`handleAudioSessionActivation: false`) и играет поверх. На iPhone так не
/// выйдет — сессия по умолчанию прервала бы музыку человека, — поэтому, если
/// что-то уже играет, сундук молчит. Выключатель звонка на iPhone звук глушит
/// сам: категория сессии по умолчанию его слушается.
class ChestSound extends ChangeNotifier {
  ChestSound._();

  static final ChestSound instance = ChestSound._();

  static const String asset = 'assets/sounds/chest_open.m4a';
  static const String _prefKey = 'chest_sound';

  /// Кадры, на которых телефон слегка отдаёт: замок отлетает (0,9 с) и приз
  /// выпадает — раскадровка `chestOpen` в мастерской значков.
  static const int lockFrame = 900 ~/ kChestFrameMs;

  bool _enabled = true;
  bool _loaded = false;
  AudioPlayer? _player;

  bool get enabled => _enabled;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKey) ?? true;
      notifyListeners();
    } catch (_) {}
  }

  /// Подготовить плеер заранее — зовётся на нажатии «Открыть», пока идёт
  /// реклама и розыгрыш: на экране его не держим, плеер — это нативный ресурс.
  void prepare() {
    if (_enabled) unawaited(_prepare());
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
    if (!value) await _player?.stop();
  }

  Future<AudioPlayer?>? _preparing;

  Future<AudioPlayer?> _prepare() => _preparing ??= _create();

  Future<AudioPlayer?> _create() async {
    try {
      final p = AudioPlayer(handleAudioSessionActivation: false);
      await p.setAsset(asset);
      _player = p;
    } catch (e) {
      debugPrint('ChestSound: $e');
      _preparing = null;
    }
    return _player;
  }

  /// Открытие началось: звук с [frame]-го кадра анимации.
  Future<void> start(int frame) async {
    if (!_enabled) return;
    final late = Stopwatch()..start();
    try {
      if (!kIsWeb && Platform.isIOS && await AVAudioSession().isOtherAudioPlaying) return;
      final p = await _prepare();
      if (p == null) return;
      // Пока готовился плеер, анимация ушла вперёд — догоняем её.
      await p.seek(Duration(milliseconds: frame * kChestFrameMs + late.elapsedMilliseconds));
      unawaited(p.play());
    } catch (e) {
      debugPrint('ChestSound: $e');
    }
  }

  /// Отдача на ключевых кадрах: щелчок замка — лёгкая, приз — посильнее.
  void haptic(int from, int to) {
    if (from < lockFrame && to >= lockFrame) HapticFeedback.lightImpact();
    if (from < kChestWonFrame && to >= kChestWonFrame) HapticFeedback.mediumImpact();
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
