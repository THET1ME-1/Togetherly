import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Канал к нативу: Android — `AgeSignalsBridge.kt` (Google Play Age Signals),
/// iPhone — `setupAgeSignalsChannel` в `AppDelegate.swift` (Declared Age Range).
const ageSignalsChannelName = 'love_app/age_signals';

/// Возрастная группа по ответу магазина.
enum AgeBand { unknown, child, teen, adult }

/// Что магазин сказал о возрасте человека.
///
/// [mandatory] — человек там, где закон обязывает магазин отдавать возраст
/// приложениям (Калифорния и Бразилия с января 2027, Техас, Юта, Луизиана).
/// Сам возраст хранится только на телефоне: условия Google и Apple разрешают
/// им пользоваться лишь внутри приложения, для возрастных ограничений.
@immutable
class AgeVerdict {
  const AgeVerdict({required this.mandatory, required this.band});

  final bool mandatory;
  final AgeBand band;

  static const none = AgeVerdict(mandatory: false, band: AgeBand.unknown);

  /// Реклама без подстройки под интересы: ребёнку и подростку её запрещают
  /// COPPA и бразильский ECA Digital. В зоне закона, где возраст так и не
  /// пришёл (не подтверждён, не поделились), — тоже: взрослым его не считать.
  bool get restrictedAds =>
      band == AgeBand.child ||
      band == AgeBand.teen ||
      (mandatory && band == AgeBand.unknown);

  /// Ответ натива: `{mandatory, status, lower, upper}` или `{error}`.
  ///
  /// Границы включительные. Google отдаёт 0–12, 13–15, 16–17 и 18 без
  /// верхней; Apple у младшей группы может не дать нижнюю. Открытая группа
  /// ниже 18 («15+» при своих порогах в консоли) взрослым не считается.
  factory AgeVerdict.fromPlatform(Map<Object?, Object?>? answer) {
    if (answer == null) return none;
    final mandatory = answer['mandatory'];
    if (mandatory is! bool) return none;
    final lower = answer['lower'];
    final upper = answer['upper'];
    if ((lower != null && lower is! int) || (upper != null && upper is! int)) {
      return none;
    }
    return AgeVerdict(
      mandatory: mandatory,
      band: _bandOf(lower as int?, upper as int?),
    );
  }

  static AgeBand _bandOf(int? lower, int? upper) {
    if (upper != null && upper < 13) return AgeBand.child;
    if (upper != null && upper < 18) return AgeBand.teen;
    if (lower != null && lower >= 18) return AgeBand.adult;
    return AgeBand.unknown;
  }

  String toJson() => jsonEncode({'mandatory': mandatory, 'band': band.name});

  static AgeVerdict fromJson(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return none;
      final mandatory = map['mandatory'];
      final band = AgeBand.values.where((b) => b.name == map['band']);
      if (mandatory is! bool || band.isEmpty) return none;
      return AgeVerdict(mandatory: mandatory, band: band.first);
    } catch (_) {
      return none;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AgeVerdict && other.mandatory == mandatory && other.band == band;

  @override
  int get hashCode => Object.hash(mandatory, band);

  @override
  String toString() => 'AgeVerdict(mandatory: $mandatory, band: ${band.name})';
}

/// Возраст человека из магазина, спрошенный при запуске.
///
/// Закон Калифорнии AB 1043 с 01.01.2027 обязывает приложение спрашивать
/// возраст у магазина, когда его скачали и запустили. Спрашиваем на каждом
/// холодном старте после первого кадра (окну Play нужна живая активность),
/// окно «поделиться возрастом» магазин показывает только там, где закон
/// обязывает, — это решает натив.
///
/// Ответ живёт в prefs и доступен с первой секунды следующего запуска. Сбой
/// (нет сети, сборка не из Play, старый Play) прошлый ответ не стирает.
class AgeSignals {
  AgeSignals._({required bool supported, required Duration timeout})
      : _supported = supported,
        _timeout = timeout {
    // Где спрашивать некого (ноутбук, веб), реклама ждать не должна.
    if (!supported) _settled.complete();
  }

  static final instance = AgeSignals._(
    supported: !kIsWeb && (Platform.isAndroid || Platform.isIOS),
    timeout: const Duration(seconds: 12),
  );

  @visibleForTesting
  factory AgeSignals.forTest({
    required bool supported,
    Duration timeout = const Duration(seconds: 12),
  }) =>
      AgeSignals._(supported: supported, timeout: timeout);

  static const _prefsKey = 'age_signals_v1';
  static const _channel = MethodChannel(ageSignalsChannelName);

  final bool _supported;
  final Duration _timeout;
  final Completer<void> _settled = Completer<void>();
  bool _loaded = false;

  AgeVerdict _verdict = AgeVerdict.none;
  AgeVerdict get verdict => _verdict;

  bool get restrictedAds => _verdict.restrictedAds;

  /// Ответом уже можно пользоваться. Реклама ждёт его перед запросом, но
  /// ждать магазин приходится лишь на самом первом запуске: дальше сразу
  /// годится сохранённый ответ, а свежий заменит его, когда придёт.
  Future<void> get settled => _settled.future;

  /// Прошлый ответ с диска. Звать как можно раньше при запуске.
  Future<void> loadSaved() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        _verdict = AgeVerdict.fromJson(raw);
        _settle();
      }
    } catch (e) {
      debugPrint('AgeSignals: prefs не прочитались — $e');
    }
  }

  void _settle() {
    if (!_settled.isCompleted) _settled.complete();
  }

  /// Сохранить текущий ответ. После отказа магазина на первом запуске
  /// пишется «неизвестно»: иначе сборки из RuStore и с сайта, которым Play
  /// отказывает всегда, ждали бы магазин на каждом запуске.
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _verdict.toJson());
    } catch (e) {
      debugPrint('AgeSignals: prefs не записались — $e');
    }
  }

  /// Спросить магазин. Ошибок наружу не бросает.
  Future<void> check() async {
    await loadSaved();
    if (!_supported) return;
    final hadSaved = _settled.isCompleted;
    var answered = false;
    try {
      final answer = await _channel
          .invokeMethod<Map<Object?, Object?>>('check')
          .timeout(_timeout);
      if (answer == null || answer['error'] != null) {
        debugPrint('AgeSignals: магазин не ответил — ${answer?['error']}');
      } else {
        _verdict = AgeVerdict.fromPlatform(answer);
        answered = true;
      }
    } on TimeoutException {
      debugPrint('AgeSignals: магазин молчит дольше ${_timeout.inSeconds} с');
    } catch (e) {
      debugPrint('AgeSignals: проверка сорвалась — $e');
    }
    // Сбой прошлый ответ не трогает; без прошлого ответа пишется «неизвестно».
    if (answered || !hadSaved) await _save();
    _settle();
  }
}
