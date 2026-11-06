import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/pair_quiz.dart';
import 'pocketbase_service.dart';

/// Результаты тестов пары: свой и партнёра по каждому тесту.
///
/// Коллекция `pair_quizzes` (заведена 06.11.2026): `group_id`, `user_uid`,
/// `quiz`, `data`. Записи «Умения любить» сюда не кладутся: их коллекцию
/// `love_tests` читают старые сборки и приняли бы новые тесты за свой.
class PairQuizResults {
  const PairQuizResults({this.mine = const {}, this.theirs = const {}, this.myRounds = const {}});
  final Map<QuizKind, QuizResult> mine;
  final Map<QuizKind, QuizResult> theirs;

  /// Ключи вопросов прошлого своего прохождения: новый набор их обходит.
  final Map<QuizKind, Set<String>> myRounds;
}

class PairQuizService {
  PairQuizService._();
  static final PairQuizService instance = PairQuizService._();

  static const String _col = 'pair_quizzes';

  PocketBase get _pb => PocketBaseService().pb;

  Future<PairQuizResults> load(String groupId, String myUid) async {
    if (groupId.isEmpty || myUid.isEmpty) return const PairQuizResults();
    try {
      final rows = await _pb
          .collection(_col)
          .getFullList(filter: _pb.filter('group_id = {:g}', {'g': groupId}))
          .timeout(const Duration(seconds: 20));
      final mine = <QuizKind, QuizResult>{};
      final theirs = <QuizKind, QuizResult>{};
      final rounds = <QuizKind, Set<String>>{};
      for (final r in rows) {
        final raw = r.data['data'];
        final res = raw is Map ? QuizResult.fromJson(Map<String, dynamic>.from(raw)) : null;
        if (res == null) continue;
        if (r.data['user_uid'] == myUid) {
          mine[res.kind] = res;
          final keys = (raw as Map)['round'];
          if (keys is List) rounds[res.kind] = {for (final k in keys) '$k'};
        } else {
          theirs[res.kind] = res;
        }
      }
      return PairQuizResults(mine: mine, theirs: theirs, myRounds: rounds);
    } catch (e) {
      debugPrint('PairQuizService.load failed: $e');
      return const PairQuizResults();
    }
  }

  /// Кладёт свой результат. Id из пары, человека и теста: повтор правит ту же
  /// запись, а не плодит новые.
  ///
  /// [round] — ключи вопросов этого прохождения: в следующий раз они уступят
  /// место другим.
  Future<bool> save(String groupId, String myUid, QuizResult result, {List<String> round = const []}) async {
    if (groupId.isEmpty || myUid.isEmpty) return false;
    final id = pairQuizRecordId(groupId, myUid, result.kind);
    final body = {
      'group_id': groupId,
      'user_uid': myUid,
      'quiz': result.kind.name,
      'data': {...result.toJson(), 'round': round},
    };
    try {
      await _pb.collection(_col).update(id, body: body).timeout(const Duration(seconds: 15));
      return true;
    } on ClientException catch (e) {
      if (e.statusCode != 404) {
        debugPrint('PairQuizService.save update failed: $e');
        return false;
      }
    } catch (e) {
      debugPrint('PairQuizService.save update failed: $e');
      return false;
    }
    try {
      await _pb.collection(_col).create(body: {'id': id, ...body}).timeout(const Duration(seconds: 15));
      return true;
    } catch (e) {
      debugPrint('PairQuizService.save create failed: $e');
      return false;
    }
  }
}
