import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/chest.dart';
import '../models/gift.dart';
import '../models/pair_jar.dart';
import 'catalog_service.dart';
import 'chest_telemetry.dart';
import 'pair_jar_service.dart';
import 'pocketbase_service.dart';

/// Итог открытия сундука.
class ChestOpenResult {
  const ChestOpenResult({
    required this.ok,
    this.prize,
    this.left,
    this.coins,
    this.plus = false,
    this.ownedFeatures,
    this.ownedIcons,
    this.plusTrialUntil,
    this.untilRare,
    this.jarBonus,
    this.jar,
    this.error,
  });

  final bool ok;
  final ChestPrize? prize;
  final int? left;
  final int? coins;
  final bool plus;

  /// Покупки человека после открытия: выпавшая рамка уже лежит здесь.
  final List<String>? ownedFeatures;

  /// Купленные и выпавшие значки после открытия: выпавший жилец уже здесь.
  final List<String>? ownedIcons;

  /// Срок недели Togetherly+ (мс), если сервер его прислал.
  final int? plusTrialUntil;

  /// Через сколько открытий редкий приз гарантирован после этого.
  final int? untilRare;

  /// Сколько открытий из копилки пары осталось после этого.
  final int? jarBonus;

  /// Копилка, если это открытие положило в неё каплю (Плюс, без ролика).
  final PairJar? jar;

  /// `chest_limit` — на сегодня всё; `network` — сервер не ответил; остальное
  /// — отказ сервера.
  final String? error;
}

/// Сундук недели: сколько открытий осталось и розыгрыш приза.
///
/// Приз разыгрывает и выдаёт сервер (`chest.pb.js`). Повтор открытия с тем же
/// [openId] — после обрыва связи — возвращает тот же приз и ничего не
/// начисляет дважды, поэтому досмотренный ролик не пропадает.
class ChestService {
  ChestService._();

  static final ChestService instance = ChestService._();

  /// Сколько ждать ответа на открытие. Дольше — «сундук не открылся,
  /// нажмите ещё раз», ролик заново смотреть не придётся.
  static const Duration openLimit = Duration(seconds: 12);

  /// Как дотянуть каталог, когда выпал подарок, которого приложение ещё не
  /// знает. Тест подменяет, чтобы не ходить в сеть.
  @visibleForTesting
  static Future<void> Function() catalogRefresh = () => CatalogService.instance.refresh();

  int get _tz => DateTime.now().timeZoneOffset.inMinutes;
  String get _platform => Platform.isIOS ? 'ios' : 'android';

  /// [chest] — ключ сезонного сундука; null — обычный.
  Future<ChestState?> state({String? groupId, String? chest}) async {
    final group = groupId ?? PairJarService.instance.groupId;
    try {
      final res = await PocketBaseService().pb.send(
        '/api/chest/state',
        query: {
          'tz': '$_tz',
          'platform': _platform,
          'frames': '1',
          if (group != null && group.isNotEmpty) 'group': group,
          'chest': ?chest,
        },
      );
      final st = ChestState.fromJson(res is Map ? Map<String, dynamic>.from(res) : null);
      PairJarService.instance.apply(st?.jar);
      return st;
    } catch (_) {
      return null;
    }
  }

  /// [fromJar] — открытие из копилки пары: без ролика и сверх трёх в день.
  ///
  /// Обрыв и молчание сети повторяются один раз сами: номер тот же, и сервер
  /// второй раз не разыгрывает. Человек видит отказ, только если не прошли
  /// обе попытки.
  /// [chest] — ключ сезонного сундука; null — обычный.
  /// [noAd] — открытие без ролика там, где рекламы нет ([ChestState.noAd]);
  /// сервер сверит страну сам и Плюс в таком открытии не разыграет.
  Future<ChestOpenResult> open({
    required String openId,
    required String groupId,
    bool fromJar = false,
    String? chest,
    bool noAd = false,
  }) async {
    var res = await _openOnce(openId: openId, groupId: groupId, fromJar: fromJar, chest: chest, noAd: noAd);
    for (var attempt = 2; attempt <= openAttempts && _retryable(res.error); attempt++) {
      ChestTelemetry.step(openId, 'open:retry', data: {'attempt': attempt, 'after': res.error});
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      res = await _openOnce(openId: openId, groupId: groupId, fromJar: fromJar, chest: chest, noAd: noAd);
    }
    return res;
  }

  /// Сколько раз пробуем открыть, прежде чем сказать человеку «не открылся».
  static const int openAttempts = 2;

  static bool _retryable(String? error) => error == 'network' || error == 'timeout';

  Future<ChestOpenResult> _openOnce({
    required String openId,
    required String groupId,
    required bool fromJar,
    String? chest,
    bool noAd = false,
  }) async {
    Map<String, dynamic>? body;
    final watch = Stopwatch()..start();
    ChestTelemetry.step(openId, 'open:send', data: {'jar': fromJar, 'chest': ?chest});
    try {
      final res = await PocketBaseService().pb.send(
        '/api/chest/open',
        method: 'POST',
        // `frames` — эта сборка умеет показать рамку аватарки: без флага сервер
        // рамки не разыгрывает, их доля остаётся в монетах.
        body: {
          'openId': openId,
          'groupId': groupId,
          'tz': _tz,
          'platform': _platform,
          'frames': true,
          if (fromJar) 'bonus': true,
          if (noAd) 'noAd': true,
          'chest': ?chest,
        },
        // Без предела ответ, потерянный по дороге, держал кнопку на
        // «Открываем…» навсегда. Повтор идёт тем же openId, а сервер
        // отвечает на него прежним призом, поэтому второй раз не разыграет.
      ).timeout(openLimit);
      body = res is Map ? Map<String, dynamic>.from(res) : null;
    } on TimeoutException {
      ChestTelemetry.step(openId, 'open:timeout', data: {'ms': watch.elapsedMilliseconds});
      return const ChestOpenResult(ok: false, error: 'timeout');
    } on ClientException catch (e) {
      // Отказ сервера (лимит, чужая пара) приходит исключением с телом ответа.
      if (e.response.isEmpty) {
        ChestTelemetry.step(openId, 'open:network', data: {
          'ms': watch.elapsedMilliseconds,
          'status': e.statusCode,
          'cause': '${e.originalError}'.split('\n').first,
        });
        return const ChestOpenResult(ok: false, error: 'network');
      }
      body = Map<String, dynamic>.from(e.response);
    } catch (e) {
      ChestTelemetry.step(openId, 'open:network', data: {'ms': watch.elapsedMilliseconds, 'cause': '$e'.split('\n').first});
      return const ChestOpenResult(ok: false, error: 'network');
    }
    var res = parseChestOpen(body);
    // Подарки сезона приложение узнаёт из каталога. Сундук открыли раньше,
    // чем каталог доехал: дотягиваем его и разбираем ответ ещё раз. Сервер
    // приз уже выдал, и «не открылся» здесь врал (19.10.2026, пять раз за сутки).
    if (res.error == 'unknown_prize') {
      try {
        await catalogRefresh().timeout(const Duration(seconds: 8));
      } catch (_) {}
      res = parseChestOpen(body);
    }
    ChestTelemetry.step(openId, res.ok ? 'open:ok' : 'open:refused', data: {
      'ms': watch.elapsedMilliseconds,
      if (!res.ok) 'error': res.error,
    });
    PairJarService.instance.apply(res.jar);
    if (res.jarBonus != null) PairJarService.instance.setBonus(res.jarBonus!);
    return res;
  }

  /// Подарок из запаса — себе на полку.
  Future<bool> keep(String openId) => _choice('/api/chest/keep', {'openId': openId});

  /// Подарок из запаса — партнёру, бесплатно. Записку сервер кладёт в подарок
  /// так же, как у купленного; пустую не шлём, старый сервер её не ждёт.
  Future<bool> give(String openId, String groupId, {String note = ''}) =>
      _choice('/api/chest/give', {
        'openId': openId,
        'groupId': groupId,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      });

  /// Подарок из запаса — продать за монеты. null — сеть или отказ сервера.
  Future<ChestSale?> sell(String openId) async {
    try {
      final res = await PocketBaseService()
          .pb
          .send('/api/chest/sell', method: 'POST', body: {'openId': openId});
      return parseChestSale(res);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _choice(String path, Map<String, dynamic> body) async {
    try {
      final res = await PocketBaseService().pb.send(path, method: 'POST', body: body);
      return res is Map && res['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Выпавшие подарки, которые ещё ждут выбора, старые первыми.
  ///
  /// Подарок сезона сборка узнаёт из каталога. Запас спросили раньше, чем
  /// каталог доехал, — дотягиваем его, иначе подарок молча пропадал из виду
  /// (TOG-10, 21.10.2026: «первый подарок из сундука не отобразился»).
  Future<List<ChestStashItem>> stash() async {
    try {
      final res = await PocketBaseService().pb.collection('chest_opens').getList(
            perPage: 100,
            filter: 'state = "stash"',
            sort: 'created',
          );
      final rows = [
        for (final r in res.items)
          (id: r.id, prize: r.getStringValue('prize'), day: r.getStringValue('day')),
      ];
      if (rows.any((r) => GiftCatalog.byKey(r.prize) == null)) {
        try {
          await catalogRefresh().timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
      return [
        for (final r in rows)
          if (GiftCatalog.byKey(r.prize) != null)
            ChestStashItem(openId: r.id, giftKey: r.prize, chest: chestKeyOfDay(r.day)),
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// Из какого сундука открытие. Сервер пишет день сезонного открытия как
/// `hw|2026-10-21` (из копилки — `+hw|…`), обычного — просто датой (из
/// копилки — `b2026-10-21`). null — обычный сундук.
String? chestKeyOfDay(String day) {
  final bar = day.indexOf('|');
  if (bar <= 0) return null;
  final key = day.substring(day.startsWith('+') ? 1 : 0, bar);
  return key.isEmpty ? null : key;
}

/// Подарок из сундука, который ждёт решения: подарить или оставить.
class ChestStashItem {
  const ChestStashItem({required this.openId, required this.giftKey, this.chest});

  final String openId;
  final String giftKey;

  /// Ключ сезонного сундука, из которого подарок выпал; null — обычный.
  final String? chest;
}

/// Продажа подарка из запаса: сколько дали и сколько стало на счету.
class ChestSale {
  const ChestSale({required this.price, required this.coins, this.repeated = false});

  final int price;
  final int coins;

  /// Повтор уже прошедшей продажи: монеты второй раз не начислены.
  final bool repeated;
}

ChestSale? parseChestSale(Object? json) {
  if (json is! Map || json['ok'] != true) return null;
  return ChestSale(
    price: (json['price'] as num?)?.toInt() ?? 0,
    coins: (json['coins'] as num?)?.toInt() ?? 0,
    repeated: json['repeated'] == true,
  );
}

/// Запас по видам для ленты: ключ подарка и его открытия, старые первыми.
List<(String, List<String>)> groupChestStash(List<ChestStashItem> items) {
  final byKey = <String, List<String>>{};
  for (final i in items) {
    (byKey[i.giftKey] ??= []).add(i.openId);
  }
  return [for (final e in byKey.entries) (e.key, e.value)];
}

ChestOpenResult parseChestOpen(Map<String, dynamic>? j) {
  if (j == null) return const ChestOpenResult(ok: false, error: 'network');
  if (j['ok'] != true) {
    return ChestOpenResult(ok: false, error: (j['error'] ?? 'internal').toString(), left: (j['left'] as num?)?.toInt());
  }
  final raw = j['prize'];
  final prize = raw is Map ? ChestPrize.fromJson({...Map<String, dynamic>.from(raw), 'weight': 0}) : null;
  return ChestOpenResult(
    ok: prize != null,
    prize: prize,
    left: (j['left'] as num?)?.toInt(),
    coins: (j['coins'] as num?)?.toInt(),
    plus: j['plus'] == true,
    ownedFeatures: j['ownedFeatures'] is List ? [for (final f in j['ownedFeatures'] as List) '$f'] : null,
    ownedIcons: j['ownedIcons'] is List ? [for (final f in j['ownedIcons'] as List) '$f'] : null,
    plusTrialUntil: (j['plusTrialUntil'] as num?)?.toInt(),
    untilRare: (j['untilRare'] as num?)?.toInt(),
    jarBonus: (j['jarBonus'] as num?)?.toInt(),
    jar: PairJar.fromJson(j['jar']),
    error: prize == null ? 'unknown_prize' : null,
  );
}
