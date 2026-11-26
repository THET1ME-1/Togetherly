import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/xmas_tree.dart';
import 'centrifugo_service.dart';
import 'pocketbase_service.dart';

/// Ёлка открытой пары (26.11.2026): состояние с сервера (`tree.pb.js`),
/// правки партнёра — каналом пары, свои — сразу на экране, а сервер решает,
/// остаются ли они (на отказе экран возвращается к прежнему).
class XmasTreeService extends ChangeNotifier {
  XmasTreeService._();

  static final XmasTreeService instance = XmasTreeService._();

  String? _group;
  int? _season;
  String _me = '';
  TreeState? _state;
  bool _loading = false;
  RtUnsub? _unsubToys, _unsubTree;
  DateTime? _seenAt;
  int _tmp = 0;

  String? get groupId => _group;
  int? get season => _season;
  String get myUid => _me;
  TreeState? get state => _state;
  bool get loading => _loading;

  /// Сколько игрушек партнёр повесил с тех пор, как я в последний раз открывал
  /// эту ёлку: плитка на главной пишет «Дима +N».
  int get newFromPartner {
    final s = _state, seen = _seenAt;
    if (s == null) return 0;
    return s.toys.where((t) => t.author != _me && t.author.isNotEmpty && (seen == null || (t.created?.isAfter(seen) ?? false))).length;
  }

  Map<String, int> get freeToys => _state == null ? const {} : xtFreeToys(_state!.owned, _state!.toys, _me);

  /// Сменить пару или сезон. Повтор того же — ничего не делает.
  Future<void> bind(String groupId, int season, String myUid) async {
    if (_group == groupId && _season == season && _me == myUid && _state != null) return;
    await _unsubscribe();
    _group = groupId;
    _season = season;
    _me = myUid;
    _state = null;
    _seenAt = await _readSeen();
    notifyListeners();
    await refresh();
    final ch = 'pair:$groupId';
    bool mine(RecordModel r) => r.data['group_id'] == groupId && (r.data['season'] as num?)?.toInt() == season;
    try {
      _unsubToys = await CentrifugoService.instance.subscribeDelta(ch, 'tree_toys', _onToy, match: mine);
      _unsubTree = await CentrifugoService.instance.subscribeDelta(ch, 'pair_trees', _onTree, match: mine);
    } catch (e) {
      debugPrint('xmas tree: subscribe failed $e');
    }
  }

  Future<void> refresh() async {
    final g = _group, s = _season;
    if (g == null || s == null) return;
    _loading = true;
    notifyListeners();
    try {
      final res = await PocketBaseService().pb.send('/api/tree/state', query: {'group': g, 'season': '$s'});
      if (_group == g && _season == s && res is Map) _state = TreeState.fromJson(res.cast<String, dynamic>());
    } catch (e) {
      debugPrint('xmas tree: state failed $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Экран ёлки открыт: новые игрушки партнёра больше не «новые».
  Future<void> markSeen() async {
    _seenAt = DateTime.now().toUtc();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_seenKey, _seenAt!.toIso8601String());
    } catch (_) {}
  }

  String get _seenKey => 'xt_seen_${_group}_$_season';

  Future<DateTime?> _readSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      return DateTime.tryParse(p.getString(_seenKey) ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Повесить игрушку в точку холста ёлки. Возвращает null при успехе или код
  /// отказа сервера (`not_owned`, `full`, `offline`).
  Future<String?> hang(String toy, double x, double y) async {
    final s = _state, g = _group, season = _season;
    if (s == null || g == null || season == null) return 'offline';
    final tmp = TreeToy(id: 'tmp${_tmp++}', toy: toy, x: x, y: y, author: _me, created: DateTime.now().toUtc());
    _state = s.copyWith(toys: [...s.toys, tmp]);
    notifyListeners();
    try {
      final res = await PocketBaseService().pb.send('/api/tree/hang', method: 'POST', body: {'group': g, 'season': season, 'toy': toy, 'x': x, 'y': y});
      final got = res is Map && res['toy'] is Map ? TreeToy.fromJson((res['toy'] as Map).cast<String, dynamic>()) : null;
      _replace(tmp.id, got);
      return null;
    } on ClientException catch (e) {
      _replace(tmp.id, null);
      return (e.response['error'] as String?) ?? 'offline';
    } catch (_) {
      _replace(tmp.id, null);
      return 'offline';
    }
  }

  void _replace(String tmpId, TreeToy? real) {
    final s = _state;
    if (s == null) return;
    final toys = [for (final t in s.toys) if (t.id != tmpId) t];
    // канал мог принести эту же игрушку раньше ответа
    if (real != null && !toys.any((t) => t.id == real.id)) toys.add(real);
    _state = s.copyWith(toys: toys);
    notifyListeners();
  }

  Future<bool> move(String id, double x, double y) async {
    final s = _state;
    if (s == null) return false;
    final before = s.toys;
    _state = s.copyWith(toys: [for (final t in before) t.id == id ? t.moved(x, y) : t]);
    notifyListeners();
    try {
      await PocketBaseService().pb.send('/api/tree/move', method: 'POST', body: {'id': id, 'x': x, 'y': y});
      return true;
    } catch (_) {
      _state = _state?.copyWith(toys: before);
      notifyListeners();
      return false;
    }
  }

  Future<bool> remove(String id) async {
    final s = _state;
    if (s == null) return false;
    final before = s.toys;
    _state = s.copyWith(toys: [for (final t in before) if (t.id != id) t]);
    notifyListeners();
    try {
      await PocketBaseService().pb.send('/api/tree/remove', method: 'POST', body: {'id': id});
      return true;
    } catch (_) {
      _state = _state?.copyWith(toys: before);
      notifyListeners();
      return false;
    }
  }

  /// Стиль, звезда, гирлянда. null при успехе, иначе код отказа.
  Future<String?> setTree({String? kind, bool? star, bool? garland}) async {
    final s = _state, g = _group, season = _season;
    if (s == null || g == null || season == null) return 'offline';
    final before = s.tree;
    _state = s.copyWith(tree: before.copyWith(kind: kind, star: star, garland: garland));
    notifyListeners();
    try {
      await PocketBaseService().pb.send('/api/tree/set', method: 'POST', body: {
        'group': g, 'season': season,
        'kind': ?kind,
        'star': ?star,
        'garland': ?garland,
      });
      return null;
    } on ClientException catch (e) {
      _state = _state?.copyWith(tree: before);
      notifyListeners();
      return (e.response['error'] as String?) ?? 'offline';
    }
  }

  /// Купить игрушку за монеты. Возвращает новый баланс или код отказа.
  Future<({int? coins, String? error})> buy(String key) async {
    try {
      final res = await PocketBaseService().pb.send('/api/toys/buy', method: 'POST', body: {'key': key});
      final m = (res as Map).cast<String, dynamic>();
      final s = _state;
      if (s != null) {
        _state = s.copyWith(owned: xtOwned(m['owned']));
        notifyListeners();
      }
      return (coins: (m['coins'] as num?)?.toInt(), error: null);
    } on ClientException catch (e) {
      return (coins: (e.response['coins'] as num?)?.toInt(), error: (e.response['error'] as String?) ?? 'offline');
    }
  }

  void _onToy(RtEvent ev) {
    final s = _state, r = ev.record;
    if (s == null || r == null) return;
    final toys = [for (final t in s.toys) if (t.id != r.id) t];
    if (ev.action != 'delete') {
      final t = TreeToy.fromJson({...r.data, 'id': r.id});
      if (t != null) {
        // моя же игрушка пришла каналом раньше ответа сервера — убрать её черновик
        if (t.author == _me) {
          final i = toys.indexWhere((o) => o.id.startsWith('tmp') && o.toy == t.toy && (o.x - t.x).abs() < 0.2 && (o.y - t.y).abs() < 0.2);
          if (i >= 0) toys.removeAt(i);
        }
        toys.add(t);
      }
    }
    _state = s.copyWith(toys: toys);
    notifyListeners();
  }

  void _onTree(RtEvent ev) {
    final s = _state, r = ev.record;
    if (s == null || r == null) return;
    _state = s.copyWith(tree: PairTree.fromJson(r.data), seasons: {...s.seasons, _season!}.toList());
    notifyListeners();
  }

  Future<void> _unsubscribe() async {
    final a = _unsubToys, b = _unsubTree;
    _unsubToys = _unsubTree = null;
    try {
      await a?.call();
      await b?.call();
    } catch (_) {}
  }

  @visibleForTesting
  void debugSet({required String group, required int season, required String me, TreeState? state, DateTime? seenAt}) {
    _group = group;
    _season = season;
    _me = me;
    _state = state;
    _seenAt = seenAt;
    notifyListeners();
  }
}
