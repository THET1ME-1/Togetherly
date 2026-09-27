import 'dart:io' show Platform;

import 'package:pocketbase/pocketbase.dart';

import '../models/chest.dart';
import '../models/gift.dart';
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
    this.error,
  });

  final bool ok;
  final ChestPrize? prize;
  final int? left;
  final int? coins;
  final bool plus;

  /// Покупки человека после открытия: выпавшая рамка уже лежит здесь.
  final List<String>? ownedFeatures;

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

  int get _tz => DateTime.now().timeZoneOffset.inMinutes;
  String get _platform => Platform.isIOS ? 'ios' : 'android';

  Future<ChestState?> state() async {
    try {
      final res = await PocketBaseService().pb.send('/api/chest/state', query: {'tz': '$_tz', 'platform': _platform, 'frames': '1'});
      return ChestState.fromJson(res is Map ? Map<String, dynamic>.from(res) : null);
    } catch (_) {
      return null;
    }
  }

  Future<ChestOpenResult> open({required String openId, required String groupId}) async {
    Map<String, dynamic>? body;
    try {
      final res = await PocketBaseService().pb.send(
        '/api/chest/open',
        method: 'POST',
        // `frames` — эта сборка умеет показать рамку аватарки: без флага сервер
        // рамки не разыгрывает, их доля остаётся в монетах.
        body: {'openId': openId, 'groupId': groupId, 'tz': _tz, 'platform': _platform, 'frames': true},
      );
      body = res is Map ? Map<String, dynamic>.from(res) : null;
    } on ClientException catch (e) {
      // Отказ сервера (лимит, чужая пара) приходит исключением с телом ответа.
      if (e.response.isEmpty) return const ChestOpenResult(ok: false, error: 'network');
      body = Map<String, dynamic>.from(e.response);
    } catch (_) {
      return const ChestOpenResult(ok: false, error: 'network');
    }
    return parseChestOpen(body);
  }

  /// Подарок из запаса — себе на полку.
  Future<bool> keep(String openId) => _choice('/api/chest/keep', {'openId': openId});

  /// Подарок из запаса — партнёру, бесплатно.
  Future<bool> give(String openId, String groupId) =>
      _choice('/api/chest/give', {'openId': openId, 'groupId': groupId});

  Future<bool> _choice(String path, Map<String, dynamic> body) async {
    try {
      final res = await PocketBaseService().pb.send(path, method: 'POST', body: body);
      return res is Map && res['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Выпавшие подарки, которые ещё ждут выбора, старые первыми.
  Future<List<ChestStashItem>> stash() async {
    try {
      final res = await PocketBaseService().pb.collection('chest_opens').getList(
            perPage: 100,
            filter: 'state = "stash"',
            sort: 'created',
          );
      return [
        for (final r in res.items)
          if (GiftCatalog.byKey(r.getStringValue('prize')) != null)
            ChestStashItem(openId: r.id, giftKey: r.getStringValue('prize')),
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// Подарок из сундука, который ждёт решения: подарить или оставить.
class ChestStashItem {
  const ChestStashItem({required this.openId, required this.giftKey});

  final String openId;
  final String giftKey;
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
    error: prize == null ? 'unknown_prize' : null,
  );
}
