import 'package:flutter/foundation.dart';

import 'coin_store.dart' show kStore;
import 'pb_auth_service.dart';
import 'pb_coins_service.dart';
import 'pocketbase_service.dart';

/// Что открывает Togetherly+.
///
/// Разовая покупка, не подписка: человек платит один раз и получает то, что
/// иначе стоило бы монет или было бы недоступно.
enum PlusFeature {
  /// Все платные темы оформления разом.
  themes,

  /// Календарь цикла с прогнозом и статистикой.
  cycle,

  /// Новый каталог виджетов: «Вместе», «Скучаю», «Настроение», «До встречи».
  widgets,
}

/// Доступ к Togetherly+.
///
/// Оплата идёт через lava.top тем же вебхуком, что и покупка монет: совпала
/// почта — флаг ставится сам, не совпала — бот выдаёт код, и он гасится тем же
/// роутом, что коды пополнения. Своей платёжной логики в приложении нет.
///
/// Покупка доступна только в сборках, которые ставятся мимо Google Play
/// (GitHub и RuStore): в Play нельзя проводить оплату цифровых товаров мимо
/// их биллинга, и такая сборка получила бы бан. В Play-сборке раздел просто не
/// показывается, а купленный доступ всё равно действует — флаг живёт на
/// аккаунте, а не в сборке.
class PlusService extends ChangeNotifier {
  PlusService._();
  static final PlusService instance = PlusService._();
  factory PlusService() => instance;

  /// Страница покупки на lava.top.
  static const String purchaseUrl = String.fromEnvironment(
    'PLUS_URL',
    defaultValue: 'https://app.lava.top/products/'
        'ec861b44-a4b7-49e3-aa0e-e4608abdb0f0',
  );

  bool _active = false;

  /// Куплен ли Togetherly+.
  bool get active => _active;

  /// Можно ли предлагать покупку в этой сборке.
  static bool get canPurchase => kStore == 'github' || kStore == 'rustore';

  /// Открыта ли возможность прямо сейчас.
  bool allows(PlusFeature feature) => _active;

  /// Перечитывает флаг с аккаунта.
  ///
  /// Флаг серверный: подделать его на устройстве нельзя, и он переезжает
  /// вместе с аккаунтом на новый телефон — восстанавливать покупку не нужно.
  Future<void> refresh() async {
    try {
      final uid = PocketBaseService().userId ?? '';
      if (uid.isEmpty) {
        _setActive(false);
        return;
      }
      final profile = PbAuthService().currentProfile();
      final value = profile?['plus'];
      _setActive(value == true || value == 1);
    } catch (e) {
      debugPrint('PlusService.refresh failed: $e');
    }
  }

  /// Гасит код, выданный ботом. Возвращает true, если доступ открылся.
  Future<bool> redeem(String code) async {
    try {
      final res = await PbCoinsService().redeem(code);
      final ok = res != null && (res['ok'] == true);
      if (ok && (res['plus'] == true)) {
        _setActive(true);
        return true;
      }
      // Код оказался кодом пополнения — доступ не открылся, но и ошибки нет.
      return false;
    } catch (e) {
      debugPrint('PlusService.redeem failed: $e');
      return false;
    }
  }

  void _setActive(bool value) {
    if (_active == value) return;
    _active = value;
    notifyListeners();
  }
}
