import 'dart:async';

import '../models/miss_you_state.dart';
import 'analytics_service.dart';
import 'pb_data_service.dart';
import 'pb_realtime_service.dart';
import 'pocketbase_service.dart';

/// Репозиторий «Я скучаю» / вайбов поверх PocketBase (миграция §3).
///
/// Заменяет RTDB-счётчик + Firestore `missYouEvents` (push-триггер). На PB всё
/// живёт в коллекции `miss_you` (count + last_vibe + last_vibe_text), а пуш
/// партнёру шлёт [PbPushService] по SSE-дельте этой строки (рост count).
///
/// ВАЖНОЕ ПОВЕДЕНЧЕСКОЕ ОТЛИЧИЕ от Firebase: вайбы (thinking_of_you/want_hug/
/// custom) ТЕПЕРЬ инкрементят счётчик. Раньше sendVibe был push-only и счётчик
/// не трогал. На PB пуш дедуплицируется по росту count, поэтому инкремент —
/// именно то, что заставляет уведомление повторно сработать.
class MissYouRepository {
  MissYouRepository._();
  static final MissYouRepository instance = MissYouRepository._();
  factory MissYouRepository() => instance;

  final PbDataService _data = PbDataService();
  final PbRealtimeService _rt = PbRealtimeService();

  String? get _uid => PocketBaseService().userId;

  /// Живой словарь {uid: count} по группе.
  Stream<Map<String, int>> watchCounts(String groupId) =>
      _rt.watchMissYou(groupId);

  /// То же живьём, но целыми записями: счётчик, последний импульс с его
  /// временем и карта дней недели. Свою запись отделяет от партнёрской.
  Stream<MissYouState> watchState(String groupId) =>
      _rt.watchMissYouRows(groupId).map(
            (rows) => MissYouState.fromRows(rows, myUid: _uid ?? ''),
          );

  /// Тап «Я скучаю»: +1 в счётчик. Без рейт-лимита (как было). Аналитика.
  ///
  /// Отвечает, дошёл ли импульс: кнопка рисует тап раньше сервера и без этого
  /// ответа не знает, что отправка сорвалась (`incrementMissYou` возвращает
  /// false и при таймауте, и при отказе роута). Раньше надбавка в такой
  /// ситуации оставалась висеть — число «жило своей жизнью».
  Future<bool> sendMissYou(String groupId) async {
    final uid = _uid;
    if (uid == null || groupId.isEmpty) return false;
    final ok = await _data.incrementMissYou(groupId, uid, vibe: 'miss_you');
    if (ok) unawaited(AnalyticsService.instance.logMissYouSent());
    return ok;
  }

  /// Вайб (думаю о тебе / хочу обнять / custom). Без рейт-лимита, как и тап
  /// «Я скучаю». Инкрементит счётчик (см. док класса) + пишет
  /// last_vibe/last_vibe_text для текста пуша.
  Future<bool> sendVibe({
    required String groupId,
    required String vibeType,
    String? customText,
  }) async {
    final uid = _uid;
    if (uid == null || groupId.isEmpty) return false;
    final ok = await _data.incrementMissYou(
      groupId,
      uid,
      vibe: vibeType,
      text: customText,
    );
    if (ok) {
      unawaited(AnalyticsService.instance.logVibeSent(vibeType: vibeType));
    }
    return ok;
  }
}
