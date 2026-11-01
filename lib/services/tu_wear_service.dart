import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart' show ClientException;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tu_wear.dart';
import 'catalog_service.dart';
import 'pocketbase_service.dart';

/// Гардероб Ту: что надето и чем человек владеет.
///
/// Владение пишет только сервер (`users.owned_wear`, сундук), поэтому здесь
/// оно складывается из записи аккаунта и того, что выпало в сундуке за этот
/// запуск (ответ открытия приходит раньше, чем обновится запись). Наряд —
/// выбор человека на этом телефоне, как пак настроений: партнёр видит своего
/// Ту в своём.
class TuWearService extends ChangeNotifier {
  TuWearService._();
  static final TuWearService instance = TuWearService._();

  static const String _outfitKey = 'tu_outfit';
  static const String _ownedKey = 'tu_owned_wear';

  Map<String, String> _outfit = const {};
  Set<String> _granted = const {};
  bool _loaded = false;

  Map<String, String> get outfit => _outfit;

  /// Вещи во владении: запись аккаунта и выпавшие за этот запуск.
  Set<String> get owned {
    final out = <String>{..._granted};
    final raw = PocketBaseService().currentUser?.data['owned_wear'];
    if (raw is List) out.addAll(raw.whereType<String>());
    return out;
  }

  bool owns(String key) => owned.contains(key);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _outfit = wearOutfitDecode(prefs.getString(_outfitKey));
      _granted = {...?prefs.getStringList(_ownedKey)};
    } catch (_) {}
    notifyListeners();
  }

  /// Надеть или снять вещь (повторное нажатие снимает).
  Future<void> toggle(TuWear item) async {
    _outfit = wearToggle(_outfit, item.cat, item.key);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_outfitKey, wearOutfitEncode(_outfit));
    } catch (_) {}
  }

  /// Сразу надеть (кнопка «Надеть» под призом сундука).
  Future<void> wear(TuWear item) async {
    if (_outfit[item.cat] == item.key) return;
    await toggle(item);
  }

  /// Ответ сервера после открытия сундука: полный список вещей человека.
  Future<void> setOwned(Iterable<String> keys) async {
    _granted = {..._granted, ...keys};
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_ownedKey, _granted.toList());
    } catch (_) {}
  }

  /// Монеты по последнему ответу магазина; до первой покупки — из записи
  /// аккаунта.
  int? _coins;
  int get coins => _coins ?? ((PocketBaseService().currentUser?.data['coins'] as num?)?.toInt() ?? 0);

  /// Покупка вещи магазина: за монеты или после досмотренного ролика ([ad]).
  /// Купленная вещь сразу надевается. Ответ — код отказа (`insufficient`,
  /// `not_for_sale`, `network`) или null, если вещь теперь своя.
  Future<String?> buy(TuWear item, {bool ad = false}) async {
    try {
      final res = await PocketBaseService().pb.send('/api/wear/buy', method: 'POST', body: {'key': item.key, 'ad': ad});
      if (res is! Map || res['ok'] != true) return 'network';
      final coins = res['coins'];
      if (coins is num) _coins = coins.toInt();
      final owned = res['ownedWear'];
      if (owned is List) await setOwned(owned.whereType<String>());
      await wear(item);
      return null;
    } on ClientException catch (e) {
      final coins = e.response['coins'];
      if (coins is num) {
        _coins = coins.toInt();
        notifyListeners();
      }
      return e.response['error'] as String? ?? 'network';
    } catch (_) {
      return 'network';
    }
  }

  /// Слои одежды для сцены облачка [art] (или эмоции пака [emotion]).
  ({List<String> back, List<String> front}) layersFor({required String art, String? emotion}) {
    final scene = wearSceneOf(art: art, emotion: emotion);
    if (scene == null || _outfit.isEmpty) return (back: const [], front: const []);
    return wearSceneLayers(_outfit, CatalogService.instance.wearItems, owned: owned, scene: scene);
  }

  @visibleForTesting
  void debugSet({Map<String, String>? outfit, Set<String>? granted}) {
    if (outfit != null) _outfit = outfit;
    if (granted != null) _granted = granted;
    _loaded = true;
    notifyListeners();
  }
}
