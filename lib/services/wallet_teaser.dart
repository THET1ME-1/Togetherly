import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/safe_launch.dart';

import 'coin_store.dart' show kStore;
import 'pocketbase_service.dart';

/// Где Togetherly Wallet вышел и куда вести человека.
///
/// Приезжает с сервера полем `app_config.wallet` — вместе с остальным конфигом
/// на главной и в ответе `/api/wallet/waitlist`. Флаг выхода раздельный по
/// платформам: App Store может задержать сборку на ревью, и iPhone тогда
/// продолжает видеть стену ожидания, пока Android уже открывает приложение.
/// Переключает его `pocketbase/wallet_release.py`, обновлять Togetherly для
/// этого не нужно.
@immutable
class WalletLinks {
  const WalletLinks({
    this.package = 'com.togetherly.money',
    this.android = false,
    this.ios = false,
    this.play = 'https://play.google.com/store/apps/details?id=com.togetherly.money',
    this.rustore = '',
    this.github = '',
    this.appstore = '',
  });

  final String package;
  final bool android;
  final bool ios;
  final String play;
  final String rustore;
  final String github;
  final String appstore;

  /// Разбор поля конфига. Принимает и карту, и строку JSON: SDK отдаёт json-поле
  /// картой, а в настройках устройства оно лежит строкой. Всё непонятное даёт
  /// значения по умолчанию, то есть стену ожидания: лучше лишний раз показать
  /// стену, чем кнопку, которая ведёт в никуда.
  factory WalletLinks.fromJson(Object? raw) {
    Object? data = raw;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        data = null;
      }
    }
    if (data is! Map) return const WalletLinks();
    final map = data;
    String s(String key, String fallback) {
      final value = map[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
    }

    const d = WalletLinks();
    return WalletLinks(
      package: s('package', d.package),
      android: map['android'] == true,
      ios: map['ios'] == true,
      play: s('play', d.play),
      rustore: s('rustore', ''),
      github: s('github', ''),
      appstore: s('appstore', ''),
    );
  }

  Map<String, Object> toJson() => {
        'package': package,
        'android': android,
        'ios': ios,
        'play': play,
        'rustore': rustore,
        'github': github,
        'appstore': appstore,
      };

  /// Вышел ли Wallet там, где запущен Togetherly.
  bool releasedFor({required bool isIOS}) => isIOS ? ios : android;

  /// Страница Wallet в том магазине, откуда пришла эта сборка Togetherly.
  /// Человек из RuStore получает RuStore, со сборки с GitHub — релизы на
  /// GitHub; где своей ссылки нет, остаётся Google Play.
  String storeUrl({required bool isIOS, required String store}) {
    if (isIOS) return appstore;
    return switch (store) {
      'rustore' when rustore.isNotEmpty => rustore,
      'github' when github.isNotEmpty => github,
      _ => play,
    };
  }
}

/// Состояние очереди с сервера.
@immutable
class WaitlistState {
  const WaitlistState({
    required this.count,
    required this.joined,
    required this.place,
    required this.links,
  });

  /// Сколько людей нажали «Добавить в ожидание».
  final int count;

  /// Этот человек уже в очереди.
  final bool joined;

  /// Его номер в очереди, с единицы; 0 — пока не записан.
  final int place;
  final WalletLinks links;

  factory WaitlistState.fromJson(Map<String, dynamic> json) {
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return WaitlistState(
      count: n(json['count']),
      joined: json['joined'] == true,
      place: n(json['place']),
      links: WalletLinks.fromJson(json['wallet']),
    );
  }
}

/// Кнопка Wallet на главной: флаг выхода, очередь и запуск приложения.
abstract final class WalletTeaser {
  static const String _prefsKey = 'wallet_links';

  /// Последний известный конфиг. На старте — из настроек устройства, дальше
  /// его освежает каждый ответ сервера.
  static final ValueNotifier<WalletLinks> links =
      ValueNotifier(const WalletLinks());

  static bool _restored = false;

  static bool get _isIOS => !kIsWeb && Platform.isIOS;

  /// Вышел ли Wallet на этой платформе — по последнему известному конфигу.
  static bool get released => links.value.releasedFor(isIOS: _isIOS);

  /// Поднимает сохранённый конфиг. Вызов дешёвый и повторяемый.
  static Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) links.value = WalletLinks.fromJson(raw);
    } catch (_) {}
  }

  /// Принимает поле `wallet` из записи `app_config`. Пустое значение не
  /// трогает известное: старый сервер без поля не должен откатывать флаг.
  static void ingest(Object? raw) {
    if (raw == null || (raw is String && raw.isEmpty)) return;
    final next = WalletLinks.fromJson(raw);
    links.value = next;
    SharedPreferences.getInstance()
        .then((p) => p.setString(_prefsKey, jsonEncode(next.toJson())))
        .catchError((_) => false);
  }

  /// Очередь и конфиг с сервера. null — сети нет или сервер не ответил.
  static Future<WaitlistState?> fetch() => _call('GET');

  /// Записать в очередь. Повторный вызов ничего не накручивает: запись на
  /// сервере одна на человека.
  static Future<WaitlistState?> join() =>
      _call('POST', body: {'platform': _isIOS ? 'ios' : 'android'});

  static Future<WaitlistState?> _call(String method,
      {Map<String, dynamic>? body}) async {
    try {
      final res = await PocketBaseService()
          .pb
          .send('/api/wallet/waitlist', method: method, body: body ?? const {})
          .timeout(const Duration(seconds: 12));
      if (res is! Map) return null;
      final state = WaitlistState.fromJson(Map<String, dynamic>.from(res));
      ingest(state.links.toJson());
      return state;
    } catch (e) {
      debugPrint('WalletTeaser.$method failed: $e');
      return null;
    }
  }

  static const MethodChannel _install = MethodChannel('love_app/install');

  /// Открывает Wallet: на Android сам, если он стоит, иначе его страницу в
  /// магазине. На iPhone чужое приложение по имени пакета не запустить, и
  /// App Store сам показывает «Открыть», если Wallet уже установлен.
  static Future<bool> open() async {
    final l = links.value;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final ok = await _install
            .invokeMethod<bool>('launchPackage', {'package': l.package});
        if (ok == true) return true;
      } catch (_) {}
      if (kStore == 'play' &&
          await safeLaunchUrl(Uri.parse('market://details?id=${l.package}'))) {
        return true;
      }
    }
    return safeLaunchString(l.storeUrl(isIOS: _isIOS, store: kStore));
  }
}
