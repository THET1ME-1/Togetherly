import 'package:pocketbase/pocketbase.dart';

import 'local_store.dart';
import 'outbox_service.dart';
import 'record_scope.dart';

/// Сверка состава области с сервером: что есть на сервере, то и остаётся в
/// кэше.
///
/// [fetchServer] отдаёт все записи области с сервера или `null`, если сверку
/// отменили по дороге: тогда кэш не трогаем и возвращаем `false`.
///
/// Своё, что очередь ещё везёт, сверка сносить не имеет права. И того, что
/// очередь довезла, пока шёл ответ, в снятом списке тоже нет: сервер отдал
/// его раньше. Поэтому «своё» считается за всё время сверки, а не в конце.
Future<bool> reconcileWithServer({
  required LocalStore store,
  required OutboxService outbox,
  required String collection,
  required RecordScope scope,
  required Future<List<RecordModel>?> Function() fetchServer,
}) async {
  final watch = outbox.watchPending();
  try {
    final serverRecords = await fetchServer();
    if (serverRecords == null) return false;
    final own = <String>{
      for (final r in await store.getScope(collection, scope))
        if (watch.saw(collection, r.id) || outbox.isPending(collection, r.id))
          r.id,
    };
    await store.reconcileScope(collection, scope, serverRecords,
        protectIds: own);
    return true;
  } finally {
    watch.close();
  }
}
