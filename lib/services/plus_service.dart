import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coin_store.dart' show kStore;
import 'pb_auth_service.dart';
import 'pb_coins_service.dart';
import 'plus_access.dart';
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
/// Флаг `users.plus` серверный и живёт на аккаунте, поэтому куплено где угодно —
/// действует везде: человек может купить в Play, а пользоваться в сборке с
/// GitHub, и наоборот.
///
/// Путей оплаты два, и выбор жёстко зависит от сборки:
/// • GitHub и RuStore — lava.top тем же вебхуком, что и монеты: совпала почта,
///   флаг ставится сам; не совпала — бот выдаёт код, он гасится [redeem];
/// • Google Play — только их биллинг, товар `togetherly_plus`. Оплата цифровых
///   товаров мимо биллинга в Play-сборке = бан, поэтому ссылку на lava.top там
///   не показываем никогда.
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

  /// Чей ответ сервера лежит в [_active]. Пусто — не читали ни разу.
  String _knownUid = '';

  /// Где лежит последний известный ответ сервера про этот аккаунт.
  static const String _cacheKey = 'plus_active';
  static const String _cacheUidKey = 'plus_active_uid';

  /// Куплен ли Togetherly+.
  bool get active => _active;

  /// Прочитан ли флаг `users.plus` ЭТОГО аккаунта — с сервера или из локальной
  /// копии.
  ///
  /// До первого чтения `_active` равен false, то есть [gate] говорит «не
  /// куплено» о человеке, который заплатил. Витрине этого хватало, чтобы
  /// выскочить на входе купившему (жалоба тестировщицы 19 августа 2026),
  /// поэтому всё, что ПРЕДЛАГАЕТ покупку, обязано сперва дождаться [known].
  /// Замки на самих фичах ждать не должны: там ошибка стоит одного лишнего
  /// касания, а не рекламы оплаченного.
  ///
  /// Считается по идентификатору аккаунта, а не флажком: сменился человек на
  /// телефоне — прежний ответ к нему не относится, и спрашивать надо заново.
  bool get known {
    final uid = PocketBaseService().userId ?? '';
    return uid.isNotEmpty && uid == _knownUid;
  }

  /// Покупка идёт через биллинг магазина, а не по ссылке на lava.top.
  ///
  /// Google Play — товар `togetherly_plus` со способом покупки `lifetime`
  /// (заведён 26 июля 2026). На iOS остаётся false: продукта в App Store
  /// Connect нет, а витрина без рабочего продукта уже стоила реджекта 2.1(b)
  /// на паках монет.
  static bool get buysInStore => kStore == 'play' && exists;

  /// Можно ли предлагать покупку в этой сборке. GitHub и RuStore ведут на
  /// lava.top, Play — в свой биллинг (мимо него платить нельзя, забанят).
  static bool get canPurchase =>
      kStore == 'github' || kStore == 'rustore' || buysInStore;

  /// Существует ли Togetherly+ на этой платформе.
  ///
  /// На iOS его нет совсем: продукта в App Store Connect не заведено, а вести
  /// на оплату мимо биллинга Apple запрещает 3.1.1. Поэтому там не показывают
  /// ни витрину, ни замки, ни само название — платного раздела не существует.
  /// Купленное это не отменяет: флаг живёт на аккаунте, и оплативший с Android
  /// заходит с iPhone на всё открытое (см. [gate]).
  ///
  /// Считается по [defaultTargetPlatform], а не по `Platform.isIOS`, чтобы
  /// тест мог подменить платформу.
  static bool get exists => defaultTargetPlatform != TargetPlatform.iOS;

  /// Что рисовать на месте платной вещи: открыто, под замком или не показывать
  /// вовсе. Правило одно на всё приложение — [PlusAccess.gate].
  PlusGate get gate => PlusAccess.gate(active: _active, exists: exists);

  /// Показывать ли платное место в интерфейсе. false — на этой платформе его
  /// не существует, и человек не должен о нём узнать.
  bool get visible => gate != PlusGate.hidden;

  /// Открыта ли возможность прямо сейчас.
  bool allows(PlusFeature feature) => _active;

  /// Поднимает последний известный ответ сервера с диска, а если его нет —
  /// ходит на сервер.
  ///
  /// Копия привязана к аккаунту: чужая (сменился человек на телефоне) не
  /// годится и игнорируется.
  Future<void> ensureLoaded() async {
    if (known) return;
    // Ответ, оставшийся от прежнего аккаунта, к этому человеку отношения не
    // имеет: пока не прочитали свой, платного не открываем.
    if (_active) {
      _active = false;
      notifyListeners();
    }
    try {
      final uid = PocketBaseService().userId ?? '';
      if (uid.isNotEmpty) {
        final p = await SharedPreferences.getInstance();
        if (p.getString(_cacheUidKey) == uid && p.containsKey(_cacheKey)) {
          _knownUid = uid;
          final cached = p.getBool(_cacheKey) ?? false;
          if (cached != _active) {
            _active = cached;
            notifyListeners();
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('PlusService.ensureLoaded failed: $e');
    }
    await refresh();
  }

  /// Перечитывает флаг с аккаунта.
  ///
  /// Флаг серверный: подделать его на устройстве нельзя, и он переезжает
  /// вместе с аккаунтом на новый телефон — восстанавливать покупку не нужно.
  ///
  /// Ходим за свежей записью на сервер, а не читаем локальный профиль: там
  /// лежит копия из `authStore`, которая обновляется только при входе. Оплата
  /// на lava.top проходит вне приложения, вебхук ставит `plus` на аккаунт — и
  /// без похода на сервер человек увидел бы покупку лишь после перезапуска.
  /// Сети нет — остаёмся на том, что знаем, и не гасим уже открытое.
  Future<void> refresh() async {
    try {
      final uid = PocketBaseService().userId ?? '';
      if (uid.isEmpty) {
        _setActive(false);
        return;
      }
      try {
        final rec = await PocketBaseService()
            .pb
            .collection('users')
            .getOne(uid)
            .timeout(const Duration(seconds: 8));
        final fresh = rec.data['plus'];
        _setActive(fresh == true || fresh == 1);
        return;
      } catch (e) {
        debugPrint('PlusService.refresh: сервер недоступен ($e), берём кэш');
      }
      final profile = PbAuthService().currentProfile();
      final value = profile?['plus'];
      _setActive(value == true || value == 1);
    } catch (e) {
      debugPrint('PlusService.refresh failed: $e');
    }
  }

  /// Просит ежемесячные монеты. Сервер сам решит, прошёл ли месяц.
  Future<int> claimMonthlyCoins() async {
    if (!_active) return 0;
    try {
      final res = await PbCoinsService().plusMonthly();
      if (res == null || res['ok'] != true) return 0;
      return (res['awarded'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('PlusService.claimMonthlyCoins failed: $e');
      return 0;
    }
  }

  /// Ссылка на оплату Togetherly+ через lava.top.
  ///
  /// Сервер создаёт СЧЁТ (`POST /api/lava/checkout`) и возвращает адрес его
  /// оплаты. Прежняя статическая ссылка вела на витрину товара, а по таким
  /// покупкам lava.top не присылает уведомлений вовсе: 31 июля две оплаты
  /// подряд не дошли до сервера при живом и правильно настроенном вебхуке,
  /// и доступ обоим выдавали руками. Со счётом уведомление приходит, а если
  /// потеряется, серверный крон добьёт покупку опросом статуса.
  ///
  /// Почту берёт сам сервер из аккаунта, поэтому исчезает и вторая беда:
  /// оплата с чужого адреса, после которой доступ приходилось искать по коду.
  ///
  /// Вернул null — падаем на статическую ссылку: покупка через витрину хуже
  /// автоматической, но лучше кнопки, которая ничего не делает.
  /// [method] `sbp` (по умолчанию для рублей) или `card`. За рубли платят
  /// через СБП: карточная форма lava российские карты не принимает, а
  /// единственная живая оплата прошла именно по СБП.
  Future<String?> checkoutUrl({
    String currency = 'RUB',
    String method = 'sbp',
  }) async {
    try {
      final res = await PocketBaseService().pb.send(
        '/api/lava/checkout',
        method: 'POST',
        body: {'currency': currency, 'method': method},
      );
      if (res is Map && res['ok'] == true) {
        final url = res['url'];
        if (url is String && url.isNotEmpty) return url;
      }
    } catch (e) {
      debugPrint('PlusService.checkoutUrl failed: $e');
    }
    return null;
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
    _knownUid = PocketBaseService().userId ?? '';
    unawaited(_remember(value));
    if (_active == value) return;
    _active = value;
    notifyListeners();
  }

  /// Кладёт ответ сервера рядом с аккаунтом, которому он принадлежит.
  Future<void> _remember(bool value) async {
    try {
      final uid = PocketBaseService().userId ?? '';
      if (uid.isEmpty) return;
      final p = await SharedPreferences.getInstance();
      await p.setBool(_cacheKey, value);
      await p.setString(_cacheUidKey, uid);
    } catch (e) {
      debugPrint('PlusService._remember failed: $e');
    }
  }
}
