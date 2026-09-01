import 'package:flutter/foundation.dart';

import '../models/wish.dart';
import '../models/wish_reservation.dart';
import '../models/wish_category.dart';
import 'offline/local_store.dart';
import 'offline/outbox_service.dart';
import 'offline/pb_id.dart';
import 'pb_data_service.dart';
import 'pb_realtime_service.dart';
import 'pocketbase_service.dart';

/// Общие желания пары — раздел «Хочу с тобой».
///
/// Пишет как остальные разделы: сначала в местное хранилище, следом заданием в
/// очередь отправки. Желание появляется в списке мгновенно и не теряется без
/// сети, а партнёру доезжает дельтой канала пары.
class WishRepository {
  WishRepository._();
  static final WishRepository instance = WishRepository._();
  factory WishRepository() => instance;

  static const String _collection = 'wishes';
  static const String _categories = 'wish_categories';
  static const String _reservations = 'wish_reservations';

  final PbDataService _data = PbDataService();
  final PbRealtimeService _rt = PbRealtimeService();

  String? get _uid => PocketBaseService().userId;

  /// Живой список желаний пары: кэш плюс дельты Centrifugo.
  Stream<List<Wish>> watch(String groupId) =>
      _rt.watchWishes(groupId).map((recs) => recs.map(Wish.fromPb).toList());

  /// Разовая выборка — для карточки на главной, которой поток не нужен.
  Future<List<Wish>> load(String groupId) async {
    if (groupId.isEmpty) return const [];
    try {
      final cached = await LocalStore.instance.allRecords(_collection);
      final local = cached.map(Wish.fromPb).toList();

      final recs = await _data.loadWishes(groupId);
      if (recs.isEmpty) return local;

      final fresh = recs.map(Wish.fromPb).toList();
      for (final w in fresh) {
        await LocalStore.instance
            .upsertRaw(_collection, w.id, w.toMap(groupId: groupId));
      }
      return fresh;
    } catch (e) {
      debugPrint('WishRepository.load failed: $e');
      return const [];
    }
  }

  /// Живой список своих категорий пары.
  Stream<List<WishKind>> watchCategories(String groupId) => _rt
      .watchWishCategories(groupId)
      .map((recs) => recs.map(WishKind.fromPb).toList());

  /// Заводит желание. Возвращает созданную запись или null, если группы нет.
  Future<Wish?> add({
    required String groupId,
    required String title,
    required WishKind kind,
    String note = '',
    bool isItem = false,
    int price = 0,
    String currency = '',
    String url = '',
    String image = '',
    String shop = '',
  }) async {
    final uid = _uid;
    final text = title.trim();
    if (uid == null || uid.isEmpty || groupId.isEmpty || text.isEmpty) {
      return null;
    }

    final wish = Wish(
      id: newPbId(),
      title: text,
      note: note.trim(),
      categoryId: kind.id,
      symbol: kind.symbol,
      authorUid: uid,
      isItem: isItem,
      price: price,
      currency: currency,
      url: url,
      image: image,
      shop: shop,
      createdAt: DateTime.now(),
    );
    await _save(groupId, wish);
    return wish;
  }

  /// Правка своего желания.
  Future<void> edit({
    required String groupId,
    required Wish wish,
    required String title,
    required WishKind kind,
    String note = '',
    bool? isItem,
    int? price,
    String? currency,
    String? url,
    String? image,
    String? shop,
  }) async {
    final text = title.trim();
    if (groupId.isEmpty || text.isEmpty) return;
    await _save(
      groupId,
      wish.copyWith(
        title: text,
        note: note.trim(),
        categoryId: kind.id,
        symbol: kind.symbol,
        isItem: isItem,
        price: price,
        currency: currency,
        url: url,
        image: image,
        shop: shop,
      ),
    );
  }

  /// Заводит свою категорию пары. Доступ решает вызывающий: создание закрыто
  /// Togetherly+, но уже созданными категориями пользуются оба.
  Future<WishKind?> addCategory({
    required String groupId,
    required String title,
    required String symbol,
    String note = '',
  }) async {
    final uid = _uid;
    final text = title.trim();
    if (uid == null || uid.isEmpty || groupId.isEmpty || text.isEmpty) {
      return null;
    }

    final kind = WishKind(
      id: newPbId(),
      symbol: symbol.isEmpty ? 'star' : symbol,
      titleRu: text,
      titleEn: text,
      note: note.trim(),
      custom: true,
      authorUid: uid,
    );
    await _saveCategory(groupId, kind);
    return kind;
  }

  Future<void> editCategory({
    required String groupId,
    required WishKind kind,
    required String title,
    required String symbol,
    String note = '',
  }) async {
    final text = title.trim();
    if (groupId.isEmpty || text.isEmpty) return;
    await _saveCategory(
      groupId,
      kind.copyWith(title: text, symbol: symbol, note: note.trim()),
    );
  }

  /// Убирает свою категорию. Желания с ней остаются: значок у них сохранён
  /// в самой записи, а подпись становится общей — «Своё».
  Future<void> removeCategory(String id) async {
    if (id.isEmpty) return;
    await LocalStore.instance.deleteRecord(_categories, id);
    await OutboxService.instance.enqueue('wishCategoryDelete', {'id': id});
  }

  Future<void> _saveCategory(String groupId, WishKind kind) async {
    final map = kind.toMap(groupId: groupId);
    await LocalStore.instance.upsertRaw(_categories, kind.id, map);
    await OutboxService.instance.enqueue('wishCategoryUpsert', {
      'groupId': groupId,
      'kind': map,
    });
  }

  /// Отмечает желание сбывшимся. Отметить может любой из пары — [Wish.doneBy]
  /// запоминает, кто именно.
  Future<Wish?> markDone({
    required String groupId,
    required Wish wish,
  }) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty || groupId.isEmpty) return null;
    final marked = wish.markDone(by: uid);
    await _save(groupId, marked);
    return marked;
  }

  /// Снимает отметку — кнопка «Отменить» в снекбаре и повторный тап по галочке.
  Future<Wish> undone({
    required String groupId,
    required Wish wish,
  }) async {
    final back = wish.undone();
    if (groupId.isNotEmpty) await _save(groupId, back);
    return back;
  }

  /// Правит дату исполнения.
  ///
  /// Галочку ставят не в тот же день, когда всё случилось: «в списке желаний
  /// отмечается дата нажатия галочки, но галочку не всегда ставят сразу»
  /// (просьба от 01.09.2026). Дату правит любой из пары — список общий.
  Future<Wish> setDoneAt({
    required String groupId,
    required Wish wish,
    required DateTime at,
  }) async {
    final moved = wish.copyWith(doneAt: at);
    if (groupId.isNotEmpty) await _save(groupId, moved);
    return moved;
  }

  /// Заметка «как прошло» у сбывшегося желания.
  Future<void> setDoneNote({
    required String groupId,
    required Wish wish,
    required String note,
  }) async {
    if (groupId.isEmpty) return;
    await _save(groupId, wish.copyWith(doneNote: note.trim()));
  }

  Future<void> remove(String wishId) async {
    if (wishId.isEmpty) return;
    await LocalStore.instance.deleteRecord(_collection, wishId);
    await OutboxService.instance.enqueue('wishDelete', {'id': wishId});
  }

  // ── «дарю»: отметки, которых автор не видит ──

  /// Свои отметки. Чужих не бывает: правило коллекции отдаёт только записи
  /// с `uid = auth.id`, поэтому сюрприз не доедет до автора ни выборкой, ни
  /// дельтой канала пары.
  Future<List<WishReservation>> loadReservations(String groupId) async {
    if (groupId.isEmpty) return const [];
    final uid = _uid ?? '';
    try {
      final recs = await _data.loadWishReservations(groupId);
      final fresh = recs.map(WishReservation.fromPb).toList();
      for (final r in fresh) {
        await LocalStore.instance
            .upsertRaw(_reservations, r.id, r.toMap(groupId: groupId));
      }
      return fresh;
    } catch (e) {
      debugPrint('WishRepository.loadReservations failed: $e');
      // Без сети показываем то, что уже брали: кнопка «Дарю» не должна
      // сбрасываться в исходное только потому, что связи нет.
      final cached = await LocalStore.instance.allRecords(_reservations);
      return cached
          .map(WishReservation.fromPb)
          .where((r) => uid.isEmpty || r.uid == uid)
          .toList();
    }
  }

  /// Берёт вещь на себя. Возвращает созданную отметку.
  Future<WishReservation?> reserve({
    required String groupId,
    required String wishId,
  }) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty || groupId.isEmpty || wishId.isEmpty) {
      return null;
    }
    final res = WishReservation(
      id: newPbId(),
      wishId: wishId,
      uid: uid,
      createdAt: DateTime.now(),
    );
    final map = res.toMap(groupId: groupId);
    await LocalStore.instance.upsertRaw(_reservations, res.id, map);
    await OutboxService.instance.enqueue('wishReserve', {
      'groupId': groupId,
      'res': map,
    });
    return res;
  }

  /// Передумал дарить.
  Future<void> release(String reservationId) async {
    if (reservationId.isEmpty) return;
    await LocalStore.instance.deleteRecord(_reservations, reservationId);
    await OutboxService.instance
        .enqueue('wishReserveDelete', {'id': reservationId});
  }

  /// Кладёт запись местно и ставит задание в очередь.
  ///
  /// Чужое желание уходит на сервер урезанным заданием: страж
  /// `wishes_guard.pb.js` пускает не-автора только в поля отметки, а полное
  /// тело он отвергнет — вместе с обычной галочкой «сбылось».
  Future<void> _save(String groupId, Wish wish) async {
    final map = wish.toMap(groupId: groupId);
    await LocalStore.instance.upsertRaw(_collection, wish.id, map);

    if (wish.authorUid.isNotEmpty && wish.authorUid != _uid) {
      await OutboxService.instance.enqueue('wishMark', {
        'id': wish.id,
        'fields': {
          'done': wish.done,
          'done_at': wish.doneAt?.toIso8601String(),
          'done_by': wish.doneBy,
          'done_note': wish.doneNote,
        },
      });
      return;
    }

    await OutboxService.instance.enqueue('wishUpsert', {
      'groupId': groupId,
      'wish': map,
    });
  }
}
