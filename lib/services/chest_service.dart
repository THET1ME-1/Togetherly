import 'dart:io' show Platform;

import 'package:pocketbase/pocketbase.dart';

import '../models/chest.dart';
import 'pocketbase_service.dart';

/// Итог открытия сундука.
class ChestOpenResult {
  const ChestOpenResult({required this.ok, this.prize, this.left, this.coins, this.plus = false, this.error});

  final bool ok;
  final ChestPrize? prize;
  final int? left;
  final int? coins;
  final bool plus;

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
      final res = await PocketBaseService().pb.send('/api/chest/state', query: {'tz': '$_tz', 'platform': _platform});
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
        body: {'openId': openId, 'groupId': groupId, 'tz': _tz, 'platform': _platform},
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
    error: prize == null ? 'unknown_prize' : null,
  );
}
