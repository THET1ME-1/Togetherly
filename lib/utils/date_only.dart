/// Календарная дата без времени: день рождения, годовщина, первый поцелуй.
///
/// Жалоба пары 14 августа 2026: «у нас перепутались именно дни, месяцы и годы
/// те же. Было 18.07.2001 и 17.01.2003, стало 17.07.2001 и 18.01.2003». На
/// сервере такие даты лежат моментами времени — например
/// `2004-10-25T20:54:00.000Z`, где 20:54 это просто час, в который человек
/// нажал «сохранить». Момент, стоящий у самой полуночи, в соседнем часовом
/// поясе оказывается другим днём: у одних дата уезжает вперёд, у других назад.
/// Правка 13 августа, переведшая время событий в UTC, сделала это заметным
/// сразу у многих.
///
/// День рождения не имеет ни часа, ни пояса: 18 июля остаётся 18 июля и в
/// Кишинёве, и во Владивостоке. Поэтому храним его строкой `ГГГГ-ММ-ДД`.
library;

class DateOnly {
  /// Как класть дату на сервер: только год, месяц и день.
  static String? store(DateTime? date) {
    if (date == null) return null;
    final d = date.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Как читать то, что уже лежит в базе.
  ///
  /// Новый формат — `ГГГГ-ММ-ДД`, старый — момент времени в UTC или локальные
  /// часы без зоны. У старого берём КАЛЕНДАРНЫЙ день прямо из строки, без
  /// пересчёта в чей-либо пояс.
  ///
  /// Пересчёт в местное время читающего и был ошибкой: 21.08.2026 пришла пара
  /// со скриншотами обоих экранов — она поставила 12.04.2001, партнёр видел
  /// 13.04.2001. Момент, записанный поздним вечером, восточнее переваливает за
  /// полночь, и одна и та же дата рождения показывалась разными числами. Часа
  /// у дня рождения нет вовсе, поэтому и разворачивать нечего.
  static DateTime? parse(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return _dayOf(value);

    if (value is Map) {
      // Firestore Timestamp из мигрированных данных.
      final sec = value['_seconds'] ?? value['seconds'];
      if (sec is num) {
        return _dayOf(
          DateTime.fromMillisecondsSinceEpoch((sec * 1000).round()),
        );
      }
      return null;
    }

    final s = value.toString().trim();
    if (s.isEmpty) return null;

    // Чистая дата: ни часов, ни пояса — берём как есть.
    final plain = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (plain != null) {
      return DateTime(
        int.parse(plain.group(1)!),
        int.parse(plain.group(2)!),
        int.parse(plain.group(3)!),
      );
    }

    // Момент времени: год, месяц и день берём как написано. Хвост со
    // временем и зоной отбрасываем — он про минуту сохранения, а не про дату.
    final stamp = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ]').firstMatch(s);
    if (stamp != null) {
      return DateTime(
        int.parse(stamp.group(1)!),
        int.parse(stamp.group(2)!),
        int.parse(stamp.group(3)!),
      );
    }

    final parsed = DateTime.tryParse(s);
    return parsed == null ? null : _dayOf(parsed);
  }

  /// Полночь того дня, в котором момент оказался по местному времени.
  static DateTime _dayOf(DateTime value) {
    final local = value.isUtc ? value.toLocal() : value;
    return DateTime(local.year, local.month, local.day);
  }

  /// Один ли это календарный день. Сравнивать даты рождения через `==`
  /// нельзя: у старых записей внутри лежит время.
  static bool sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    final x = _dayOf(a);
    final y = _dayOf(b);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}
