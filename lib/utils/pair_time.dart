/// Время события пары: как его отправлять и как показывать.
///
/// До 13 августа 2026 клиент отправлял ЛОКАЛЬНЫЕ часы, а PocketBase принимал
/// строку без зоны за UTC и дописывал `Z`. У себя всё сходилось (записал криво,
/// прочитал так же криво), а время партнёра уезжало ровно на разницу поясов:
/// «он выложил только что, а мне показывает два часа назад». Замер на проде за
/// август: 10 732 отметки настроения со сдвигом ровно +3 часа, 3814 на +5,
/// 1687 на +7 — карта часовых поясов, а не разброс.
///
/// Теперь время уходит в UTC, а рядом лежит пояс автора (поле `tz`, строка
/// вида `+03:00`). Старые записи узнаём по пустому `tz` и читаем по-прежнему —
/// 148 234 отметки и 55 326 воспоминаний задним числом не двигаются.
///
/// Почему `tz` строкой, а не числом минут: у необязательного числового поля
/// PocketBase отдаёт ноль, и «автор в Гринвиче» стало бы неотличимо от «старая
/// запись».
class PairTime {
  const PairTime._();

  /// Пояс этого устройства для поля `tz`.
  static String zoneNow([DateTime? now]) =>
      zoneOf((now ?? DateTime.now()).timeZoneOffset);

  /// Смещение → `±HH:MM`.
  static String zoneOf(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final total = offset.inMinutes.abs();
    final h = (total ~/ 60).toString().padLeft(2, '0');
    final m = (total % 60).toString().padLeft(2, '0');
    return '$sign$h:$m';
  }

  /// `±HH:MM` → смещение. Мусор и пустота дают null: ноль означал бы Гринвич.
  static Duration? zoneToDuration(String? zone) {
    if (zone == null) return null;
    final m = RegExp(r'^([+-])(\d{2}):(\d{2})$').firstMatch(zone.trim());
    if (m == null) return null;
    final hours = int.parse(m.group(2)!);
    final minutes = int.parse(m.group(3)!);
    final span = Duration(hours: hours, minutes: minutes);
    return m.group(1) == '-' ? -span : span;
  }

  /// Время события для отправки на сервер — всегда UTC.
  static String write(DateTime moment) => moment.toUtc().toIso8601String();

  /// Время события для показа.
  ///
  /// Пояс задан — запись новая, время абсолютное: отдаём его в поясе читателя.
  /// Пояса нет — запись старая, в строке лежат часы автора: отдаём их как есть.
  static DateTime? read(dynamic raw, String? zone) {
    final parsed = _parse(raw);
    if (parsed == null) return null;
    // Миллисекунды — это момент, а не часы: зона к ним отношения не имеет.
    // Так пишет `gifts.pb.js`, и так лежат даты у мигрированных из Firebase.
    if (raw is num) return parsed;
    if (zoneToDuration(zone) != null) return parsed.toLocal();
    final u = parsed.toUtc();
    return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second,
        u.millisecond);
  }

  /// Сутки, в которые событие произошло У АВТОРА.
  ///
  /// Отметку настроения человек ставит «за сегодня», поэтому в календаре
  /// партнёра она обязана лежать в дне автора, даже когда у читателя уже завтра.
  static DateTime? authorDay(dynamic raw, String? zone) {
    final parsed = _parse(raw);
    if (parsed == null) return null;
    final offset = zoneToDuration(zone);
    final atAuthor = offset == null
        ? parsed.toUtc()
        : parsed.toUtc().add(offset);
    return DateTime(atAuthor.year, atAuthor.month, atAuthor.day);
  }

  /// Разбор того, что лежит в поле: строка ISO или миллисекунды числом (так
  /// пишет `gifts.pb.js`, на этом уже падала лента воспоминаний).
  static DateTime? _parse(dynamic raw) {
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    if (raw is DateTime) return raw;
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
