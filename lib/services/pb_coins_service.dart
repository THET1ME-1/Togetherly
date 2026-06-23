import 'package:flutter/foundation.dart';

import 'pocketbase_service.dart';

/// Клиент серверной коин-логики PocketBase (миграция §6 — замена вызовов
/// Firebase Cloud Functions `callGrant*`/`callPurchase*`/`callSpendCoins`).
///
/// POST'ит на pb_hooks-роуты `/api/coins/*` с auth-токеном текущего PB-юзера
/// (SDK сам подставляет Authorization из authStore). Сервер валидирует
/// цены/кулдауны/лимиты и возвращает ту же форму, что Cloud Functions
/// (`{ok, coins, awarded?, ownedThemes?, ...}`) → `UserData._applyServerResult`
/// читает результат без изменений.
///
/// НЕ покрыто (отдельные серверные хуки, нужна валидация магазина): IAP
/// (`grantCoinsPurchase` — Play/RuStore) и AdMob SSV-callback.
class PbCoinsService {
  PbCoinsService._();
  static final PbCoinsService instance = PbCoinsService._();
  factory PbCoinsService() => instance;

  Future<Map<String, dynamic>?> _call(
    String path, [
    Map<String, dynamic> body = const {},
  ]) async {
    try {
      final res = await PocketBaseService().pb.send(
        '/api/coins/$path',
        method: 'POST',
        body: body,
      );
      return res is Map ? Map<String, dynamic>.from(res) : null;
    } catch (e) {
      debugPrint('PbCoins.$path failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> dailyBonus() => _call('daily-bonus');
  Future<Map<String, dynamic>?> memoryReward() => _call('memory-reward');
  Future<Map<String, dynamic>?> adReward() => _call('ad-reward');
  Future<Map<String, dynamic>?> devCoins() => _call('dev-coins');

  Future<Map<String, dynamic>?> partnerInvite(String partnerUid) =>
      _call('partner-invite', {'partnerUid': partnerUid});
  Future<Map<String, dynamic>?> moodStreak(String groupId) =>
      _call('mood-streak', {'groupId': groupId});

  Future<Map<String, dynamic>?> purchaseTheme(int themeId) =>
      _call('purchase-theme', {'themeId': themeId});
  Future<Map<String, dynamic>?> purchaseIcon(String iconId) =>
      _call('purchase-icon', {'iconId': iconId});
  Future<Map<String, dynamic>?> purchaseFeature(String featureId) =>
      _call('purchase-feature', {'featureId': featureId});
  Future<Map<String, dynamic>?> spend(String actionId) =>
      _call('spend', {'actionId': actionId});
}
