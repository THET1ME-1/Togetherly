import '../models/pair_date.dart';
import 'offline/local_store.dart';
import 'offline/outbox_service.dart';
import 'offline/pb_id.dart';
import 'pb_realtime_service.dart';
import 'pocketbase_service.dart';

/// Памятные даты пары (TOG-61): пишет как остальные разделы — сначала в
/// местное хранилище, следом заданием в очередь отправки. Дата появляется в
/// календаре мгновенно и не теряется без сети, партнёру доезжает дельтой канала
/// пары, а напоминания обоим ставит сервер.
class PairDateRepository {
  PairDateRepository._();
  static final PairDateRepository instance = PairDateRepository._();
  factory PairDateRepository() => instance;

  static const String _collection = 'pair_dates';

  final PbRealtimeService _rt = PbRealtimeService();

  String get _uid => PocketBaseService().userId ?? '';

  /// Живой список дат пары: кэш плюс дельты Centrifugo. Битые (без дня) не
  /// показываются.
  Stream<List<PairDate>> watch(String groupId) => _rt.watchPairDates(groupId).map(
      (recs) => recs.map(PairDate.fromPb).where((d) => d.day != null).toList());

  /// Новая дата от своего имени. Null — нет пары или нет названия.
  Future<PairDate?> create(String groupId, PairDate draft) async {
    final uid = _uid;
    if (uid.isEmpty || groupId.isEmpty || draft.title.trim().isEmpty) return null;
    final date = PairDate(
      id: newPbId(),
      groupId: groupId,
      authorUid: uid,
      title: draft.title.trim(),
      symbol: draft.symbol,
      note: draft.note.trim(),
      day: draft.day,
      time: draft.time,
      tz: draft.tz,
      rrule: draft.rrule,
      exdates: draft.exdates,
      reminders: draft.reminders,
    );
    await save(groupId, date);
    return date;
  }

  /// Правка, выброшенный день, конец повтора — любой из пары.
  Future<void> save(String groupId, PairDate date) async {
    if (groupId.isEmpty) return;
    final map = date.toMap(groupId: groupId);
    await LocalStore.instance.upsertRaw(_collection, date.id, map);
    await OutboxService.instance.enqueue('dateUpsert', {'groupId': groupId, 'date': map});
  }

  Future<void> remove(String id) async {
    if (id.isEmpty) return;
    await LocalStore.instance.deleteRecord(_collection, id);
    await OutboxService.instance.enqueue('dateDelete', {'id': id});
  }
}
