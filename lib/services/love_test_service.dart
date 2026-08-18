import 'package:flutter/foundation.dart';

import '../models/love_test.dart';
import 'pb_data_service.dart';

/// Результаты «Умения любить» у пары.
///
/// Записей две — своя и партнёрская, — и обе лежат в коллекции `love_tests`.
/// Realtime тут не нужен: экран открывают руками, а фигура партнёра всё равно
/// показывается только после собственных ответов.
class LoveTestPair {
  const LoveTestPair({this.mine, this.theirs});

  final LoveTestResult? mine;
  final LoveTestResult? theirs;

  bool get partnerReady => theirs != null;
  bool get bothReady => mine != null && theirs != null;
}

class LoveTestService {
  LoveTestService._();

  static final LoveTestService instance = LoveTestService._();

  final PbDataService _data = PbDataService();

  /// Короткая память на время сеанса: карточка на главной спрашивает то же
  /// самое, что и экран, а лишний запрос за той же парой записей ни к чему.
  final Map<String, LoveTestPair> _cache = {};

  Future<LoveTestPair> load(
    String groupId,
    String myUid, {
    bool fresh = false,
  }) async {
    if (groupId.isEmpty || myUid.isEmpty) return const LoveTestPair();
    final key = '$groupId:$myUid';
    if (!fresh && _cache.containsKey(key)) return _cache[key]!;

    try {
      final records = await _data.loadLoveTests(groupId);
      LoveTestResult? mine;
      LoveTestResult? theirs;
      for (final rec in records) {
        final raw = rec.data['data'];
        final map = raw is Map ? Map<String, dynamic>.from(raw) : null;
        if (map == null) continue;
        final result = LoveTestResult.fromMap(map);
        if ((rec.data['user_uid'] ?? '').toString() == myUid) {
          mine = result;
        } else {
          theirs = result;
        }
      }
      final pair = LoveTestPair(mine: mine, theirs: theirs);
      _cache[key] = pair;
      return pair;
    } catch (e) {
      debugPrint('LoveTestService.load($groupId) failed: $e');
      return _cache[key] ?? const LoveTestPair();
    }
  }

  Future<bool> save(
    String groupId,
    String myUid,
    LoveTestResult result,
  ) async {
    final ok = await _data.saveLoveTest(groupId, myUid, result.toMap());
    // Своя запись известна и без сервера: показываем фигуру сразу, а промах
    // сети правится следующим открытием экрана.
    final key = '$groupId:$myUid';
    _cache[key] = LoveTestPair(mine: result, theirs: _cache[key]?.theirs);
    return ok;
  }

  void forget() => _cache.clear();
}
