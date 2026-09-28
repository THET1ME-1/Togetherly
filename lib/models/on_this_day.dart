import 'memory.dart';

/// Полка «В этот день» над лентой воспоминаний (макет «Лента: «В этот день»»,
/// вариант Б «Полка по годам», выбран 28.09.2026).
///
/// Плитка на каждый период, где у пары что-то было: тот же день месяц назад,
/// год назад, два года и дальше. Пустой период не показывается, пусто везде —
/// полки нет. Лента держит в памяти все записи пары ([MemoryRepository.watch]
/// синхронизирует её целиком), поэтому отдельный запрос к серверу не нужен.

/// Какой период показывает плитка.
class OnThisDayShelf {
  const OnThisDayShelf({
    required this.day,
    required this.monthsAgo,
    required this.yearsAgo,
    required this.memories,
  });

  /// Календарный день, на который пришлись записи.
  final DateTime day;

  /// 1 — «месяц назад», 0 — плитка по годам.
  final int monthsAgo;

  /// Сколько лет назад; 0 у плитки «месяц назад».
  final int yearsAgo;

  /// Записи того дня, новые первыми.
  final List<Memory> memories;

  /// Обложка плитки: первый снимок среди записей, иначе пусто.
  String get cover {
    for (final m in memories) {
      final urls = m.imageUrls;
      if (urls != null && urls.isNotEmpty && urls.first.isNotEmpty) {
        return urls.first;
      }
      for (final u in [m.imageUrl, m.musicCoverUrl, m.bookCoverUrl]) {
        if ((u ?? '').isNotEmpty) return u!;
      }
    }
    return '';
  }

  /// Подпись под плиткой: первое непустое название, подпись, место или песня.
  String get caption {
    for (final m in memories) {
      for (final t in [m.title, m.caption, m.locationName, m.musicTitle]) {
        final v = (t ?? '').trim();
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }
}

/// Тот же день на [months] месяцев раньше. Если такого числа в том месяце
/// нет (31-е, 29 февраля), берём последний день месяца.
DateTime sameDayMonthsBack(DateTime today, int months) {
  var y = today.year;
  var m = today.month - months;
  while (m < 1) {
    m += 12;
    y -= 1;
  }
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, today.day > last ? last : today.day);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Полка на [now]: «месяц назад», затем годы по возрастанию. Секретные
/// записи и нераскрытые капсулы не берём: полку видно на экране без замка.
List<OnThisDayShelf> onThisDay(
  Iterable<Memory> memories, {
  required DateTime now,
  int maxYears = 15,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final visible = memories
      .where((m) => !m.isSecret && !m.sealedNow(now))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  if (visible.isEmpty) return const [];

  List<Memory> on(DateTime day) =>
      [for (final m in visible) if (_sameDay(m.createdAt, day)) m];

  final out = <OnThisDayShelf>[];
  final monthDay = sameDayMonthsBack(today, 1);
  final month = on(monthDay);
  if (month.isNotEmpty) {
    out.add(OnThisDayShelf(
        day: monthDay, monthsAgo: 1, yearsAgo: 0, memories: month));
  }
  final oldest = visible.last.createdAt.year;
  for (var y = 1; y <= maxYears && today.year - y >= oldest; y++) {
    final day = sameDayMonthsBack(today, 12 * y);
    final list = on(day);
    if (list.isNotEmpty) {
      out.add(OnThisDayShelf(
          day: day, monthsAgo: 0, yearsAgo: y, memories: list));
    }
  }
  return out;
}

/// Форма слова «год» по-русски для «N год/года/лет назад»: `one`, `few` или
/// `many`. Остальные языки держат строки одинаковыми.
String yearsAgoForm(int n) {
  final a = n % 100;
  final b = n % 10;
  if (a >= 11 && a <= 14) return 'many';
  if (b == 1) return 'one';
  if (b >= 2 && b <= 4) return 'few';
  return 'many';
}
