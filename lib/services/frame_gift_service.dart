import 'package:pocketbase/pocketbase.dart';

import 'offline/pb_id.dart';
import 'pocketbase_service.dart';

/// Что сервер сказал о рамке до передачи: цена, есть ли она у партнёра и
/// сколько роликов осталось на сегодня.
class FrameGiftQuote {
  const FrameGiftQuote({
    required this.price,
    required this.owns,
    required this.partnerHas,
    required this.adLeft,
    required this.coins,
  });

  final int price;
  final bool owns;
  final bool partnerHas;
  final int adLeft;
  final int coins;

  static FrameGiftQuote? fromJson(Object? raw) {
    if (raw is! Map || raw['ok'] != true) return null;
    int n(Object? v) => v is num ? v.toInt() : 0;
    return FrameGiftQuote(
      price: n(raw['price']),
      owns: raw['owns'] == true,
      partnerHas: raw['partnerHas'] == true,
      adLeft: n(raw['adLeft']),
      coins: n(raw['coins']),
    );
  }
}

/// Итог передачи рамки.
class FrameGiftResult {
  const FrameGiftResult({
    required this.ok,
    this.error,
    this.coins,
    this.ownedFeatures,
    this.frame,
  });

  final bool ok;

  /// Код отказа сервера: `insufficient`, `ad_limit`, `partner_has`,
  /// `not_owned`, `not_member`, `network` и прочие.
  final String? error;

  /// Баланс дарителя после передачи.
  final int? coins;

  /// Покупки дарителя без отданной рамки.
  final List<String>? ownedFeatures;

  /// Надетая рамка дарителя: отданная снимается.
  final String? frame;

  static FrameGiftResult fromJson(Object? raw) {
    if (raw is! Map) return const FrameGiftResult(ok: false, error: 'network');
    final owned = raw['ownedFeatures'];
    final coins = raw['coins'];
    final frame = raw['frame'];
    return FrameGiftResult(
      ok: raw['ok'] == true,
      error: raw['ok'] == true ? null : '${raw['error'] ?? 'server'}',
      coins: coins is num ? coins.toInt() : null,
      ownedFeatures: owned is List ? owned.whereType<String>().toList() : null,
      frame: frame is String ? frame : null,
    );
  }
}

/// Передача своей рамки аватарки партнёру (`pb_hooks/frame_gift.pb.js`).
/// Рамка переходит целиком: у дарителя её больше нет.
class FrameGiftService {
  FrameGiftService._();
  static final FrameGiftService instance = FrameGiftService._();

  /// Ключ подарка-рамки в записи `gifts`.
  static String giftKeyOf(String frameKey) => 'frame_$frameKey';

  /// Ключ рамки из `gift_key` записи `gifts` или null, если это не рамка.
  static String? frameKeyOf(String giftKey) =>
      giftKey.startsWith('frame_') && giftKey.length > 6
          ? giftKey.substring(6)
          : null;

  Future<FrameGiftQuote?> quote({
    required String key,
    required String groupId,
  }) async {
    try {
      final res = await PocketBaseService().pb.send(
        '/api/frames/gift-quote',
        method: 'GET',
        query: {'key': key, 'groupId': groupId},
      );
      return FrameGiftQuote.fromJson(res);
    } catch (_) {
      return null;
    }
  }

  Future<FrameGiftResult> give({
    required String key,
    required String groupId,
    bool byAd = false,
  }) async {
    try {
      final res = await PocketBaseService().pb.send(
        '/api/frames/give',
        method: 'POST',
        body: {
          'giftId': newPbId(),
          'groupId': groupId,
          'key': key,
          if (byAd) 'ad': true,
        },
      );
      return FrameGiftResult.fromJson(res);
    } on ClientException catch (e) {
      if (e.response.isEmpty) {
        return const FrameGiftResult(ok: false, error: 'network');
      }
      return FrameGiftResult.fromJson(e.response);
    } catch (_) {
      return const FrameGiftResult(ok: false, error: 'network');
    }
  }
}
