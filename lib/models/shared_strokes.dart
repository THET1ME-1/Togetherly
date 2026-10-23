import 'draw_stroke.dart';
import 'stroke_record_id.dart';

/// Что сделать на сервере, когда человек убрал штрих с общего холста.
class StrokeRemoval {
  const StrokeRemoval({
    this.records = const [],
    this.cancelQueued = false,
    this.viaQueue = false,
  });

  /// Записи, которые надо удалить: сам штрих и все его копии. Удаление
  /// идемпотентно: записи, которой нет, сервер отвечает 404, и это успех.
  final List<String> records;

  /// Снять из очереди добавление, которое ещё не ушло.
  final bool cancelQueued;

  /// Удалять очередью, а не прямым запросом: добавление этого штриха уже
  /// стояло в очереди и может быть в полёте. Удаление встаёт в ту же полосу
  /// очереди и выполнится после него.
  final bool viaQueue;
}

/// Книга общего холста: что я нарисовал, что подтвердил сервер, что убрано
/// (TOG-12, 22.10.2026).
///
/// Жалоба: «ты че то нарисовал а оно удалилось или наоборот какая то фигня
/// появилась которую ты стер давно». Причины жили в том, как экран сводил свои
/// штрихи с пришедшими с сервера:
///
/// * отмена штриха, который сервер уже записал, но эхо ещё не пришло, только
///   ставила отметку «отменён»: запись оставалась, эхо возвращало штрих;
/// * отказ добавления у отменённого штриха всё равно уходил в очередь;
/// * снимок, пришедший между удалением на экране и событием удаления, клал
///   убранный штрих обратно;
/// * копии одного мазка (повторы создания) ластик снимал по одной.
///
/// Книга не ходит в сеть: она говорит экрану, что сделать, а экран делает.
class SharedStrokes {
  /// Мои штрихи, которых ещё нет в снимке сервера: id → штрих.
  final Map<String, DrawStroke> pending = {};

  /// Последний снимок сервера: без убранного и без копий.
  List<DrawStroke> remote = [];

  /// Мазки партнёра, законченные в живом канале и ещё не приехавшие записью.
  /// Ключ — clientId мазка.
  final Map<String, DrawStroke> partnerCommitted = {};
  final Map<String, DateTime> _partnerSeenAt = {};

  final Set<String> _created = {};
  final Set<String> _cancelled = {};
  final Set<String> _queued = {};

  /// Надгробия: убранное на этом экране. Снимок с ними штрих не вернёт.
  final Set<String> _removed = {};

  /// Копии штриха: id показанной записи → id остальных копий.
  final Map<String, List<String>> _copies = {};

  /// Сколько ждать запись партнёрского мазка. Обычно она приходит за доли
  /// секунды; не пришла за полминуты — партнёр отменил мазок до записи.
  static const Duration partnerGrace = Duration(seconds: 30);

  /// Всё, что видно на холсте, без сортировки.
  List<DrawStroke> get all => [
        ...remote,
        ...pending.values,
        ...partnerCommitted.values,
      ];

  /// Наибольший номер порядка среди видимого, включая живые мазки партнёра.
  /// Без них ластик поверх свежего мазка партнёра ложился ниже него, и стёртое
  /// проступало, когда приезжала запись.
  int? get maxOrderIndex {
    int? best;
    for (final s in all) {
      if (best == null || s.orderIndex > best) best = s.orderIndex;
    }
    return best;
  }

  void addPending(DrawStroke stroke) => pending[stroke.id] = stroke;

  /// Сервер принял добавление. true — штрих успели убрать, запись удалить.
  bool createSucceeded(String id) {
    if (_cancelled.contains(id)) return true;
    _created.add(id);
    return false;
  }

  /// Добавление не прошло. true — отдать штрих очереди.
  bool createFailed(String id) {
    if (_cancelled.contains(id) || !pending.containsKey(id)) return false;
    _queued.add(id);
    return true;
  }

  /// Человек убрал штрих: отмена, ластик «линия целиком», удаление картинки
  /// или слоя.
  StrokeRemoval remove(String id) {
    final group = _groupOf(id);
    _removed.addAll(group);
    for (final g in group) {
      _copies.remove(g);
    }

    if (pending.remove(id) != null) {
      _cancelled.add(id);
      return StrokeRemoval(
        // Запись могла уже лечь, а эхо — не прийти: удаляем по id сразу.
        records: [if (isStrokeRecordId(id)) id],
        cancelQueued: true,
        viaQueue: _queued.contains(id),
      );
    }
    remote = remote.where((s) => !group.contains(s.id)).toList();
    return StrokeRemoval(records: group);
  }

  /// Правка штриха уходит в одну запись. Его копии остались бы на прежнем
  /// месте и проступили бы рядом — снимаем их. Возвращает id копий, которые
  /// надо удалить на сервере.
  List<String> dropCopies(String id) {
    final copies = _copies.remove(id) ?? const <String>[];
    _removed.addAll(copies);
    return copies;
  }

  /// Пришёл снимок сервера. Возвращает переименования ожидающих штрихов
  /// (прежний id → id записи) — для истории отмены. [looksSame] — сверка на
  /// глаз для штрихов старого вида, у которых нет id записи.
  Map<String, String> applySnapshot(
    List<DrawStroke> server, {
    required bool Function(DrawStroke remote, DrawStroke local) looksSame,
  }) {
    _copies.clear();
    final shown = <DrawStroke>[];
    final firstOf = <String, DrawStroke>{};
    for (final s in server) {
      if (_removed.contains(s.id)) continue;
      final key = _copyKey(s);
      if (key != null) {
        final first = firstOf[key];
        if (first != null) {
          (_copies[first.id] ??= []).add(s.id);
          continue;
        }
        firstOf[key] = s;
      }
      shown.add(s);
    }

    final renames = <String, String>{};
    for (final r in shown) {
      final clientId = r.clientId;
      if (clientId != null) {
        partnerCommitted.remove(clientId);
        _partnerSeenAt.remove(clientId);
      }
      if (pending.remove(r.id) != null) continue;
      final match = _pendingMatch(r, looksSame);
      if (match == null) continue;
      pending.remove(match);
      renames[match] = r.id;
      _moveMarks(match, r.id);
    }
    remote = shown;
    return renames;
  }

  void addPartnerCommitted(String key, DrawStroke stroke,
      {required DateTime now}) {
    partnerCommitted[key] = stroke;
    _partnerSeenAt[key] = now;
  }

  /// Гасит мазки партнёра, чья запись не пришла за [partnerGrace].
  /// true — что-то погасло, холст надо перерисовать.
  bool expirePartner(DateTime now) {
    final stale = [
      for (final e in _partnerSeenAt.entries)
        if (now.difference(e.value) > partnerGrace) e.key,
    ];
    for (final key in stale) {
      _partnerSeenAt.remove(key);
      partnerCommitted.remove(key);
    }
    return stale.isNotEmpty;
  }

  /// Холст очистили: всё, что знала книга, больше не значит ничего.
  void reset() {
    pending.clear();
    remote = [];
    partnerCommitted.clear();
    _partnerSeenAt.clear();
    _created.clear();
    _cancelled.clear();
    _queued.clear();
    _removed.clear();
    _copies.clear();
  }

  /// Штрих и все его копии.
  List<String> _groupOf(String id) {
    final copies = _copies[id];
    if (copies != null) return [id, ...copies];
    for (final e in _copies.entries) {
      if (e.value.contains(id)) return [e.key, ...e.value];
    }
    return [id];
  }

  /// Ключ копии: один мазок, заведённый несколько раз, или одна и та же
  /// картинка на одном месте (её отмена не дошла, возврат положил вторую).
  static String? _copyKey(DrawStroke s) {
    final clientId = s.clientId;
    if (clientId != null && clientId.isNotEmpty) return 'c:$clientId';
    if (s.isImageStroke) {
      return 'i:${s.imageUrl}|${s.imageX}|${s.imageY}|${s.imageWidth}|'
          '${s.imageHeight}|${s.imageRotation}|${s.layer}';
    }
    return null;
  }

  String? _pendingMatch(
    DrawStroke remote,
    bool Function(DrawStroke remote, DrawStroke local) looksSame,
  ) {
    final clientId = remote.clientId;
    if (clientId != null) {
      for (final e in pending.entries) {
        if (e.value.clientId == clientId) return e.key;
      }
    }
    // На глаз сверяем только штрихи старого вида: у штриха с id записи его
    // запись узнаётся по id, а совпадение «автор и номер» у него случайно —
    // номера повторяются после отмены.
    for (final e in pending.entries) {
      if (!isStrokeRecordId(e.key) && looksSame(remote, e.value)) return e.key;
    }
    return null;
  }

  void _moveMarks(String from, String to) {
    for (final marks in [_created, _cancelled, _queued]) {
      if (marks.remove(from)) marks.add(to);
    }
  }
}
