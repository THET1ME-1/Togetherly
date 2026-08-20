/// Год настроений клетками: колонка — неделя, клетка — день, тон — оценка.
///
/// Прежний режим «год» показывал двенадцать плиток с числом отметок за месяц.
/// По нему видно, часто ли человек отмечался, и совсем не видно, какими были
/// дни. Сетка отвечает на второй вопрос: год целиком помещается в один экран,
/// хорошая неделя читается сплошной полосой, провал — прорехой в столбце.
///
/// Раскладка и склейка серий живут здесь, отдельно от рисования: их можно
/// проверить, не поднимая экран.
library;

/// Одна клетка сетки.
class MoodCell {
  const MoodCell({
    required this.date,
    required this.column,
    required this.weekday,
    required this.score,
    required this.startsRun,
    required this.endsRun,
  });

  final DateTime date;

  /// Номер недели в сетке (столбец слева направо).
  final int column;

  /// День недели, 1 — понедельник.
  final int weekday;

  /// Оценка дня, 1…5. `null` — в этот день не отмечались.
  final int? score;

  /// Клетка открывает вертикальную серию одинаковых оценок — скругляем сверху.
  final bool startsRun;

  /// Клетка закрывает серию — скругляем снизу.
  final bool endsRun;
}

/// Раскладывает год по неделям.
///
/// Столбец — неделя, строка — день недели (понедельник сверху). Соседние по
/// вертикали дни с одинаковой оценкой склеиваются в одно пятно; через границу
/// столбца серия не идёт — иначе пятно поехало бы поперёк сетки.
List<MoodCell> moodYearCells({
  required int year,
  required Map<DateTime, int> scores,
}) {
  final byDay = <String, int>{
    for (final e in scores.entries) _key(e.key): e.value,
  };

  final first = DateTime(year);
  final last = DateTime(year, 12, 31);
  // Столбец считаем от понедельника недели, в которую попало первое января.
  final origin = first.subtract(Duration(days: first.weekday - 1));

  final out = <MoodCell>[];
  for (var day = first;
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 1)) {
    final score = byDay[_key(day)];
    final column = day.difference(origin).inDays ~/ 7;

    final prev = DateTime(day.year, day.month, day.day - 1);
    final next = DateTime(day.year, day.month, day.day + 1);
    // Сосед считается своим, только если он в том же столбце: воскресенье и
    // понедельник стоят рядом по датам, но в сетке они в разных неделях.
    final samePrev = score != null &&
        day.weekday != DateTime.monday &&
        byDay[_key(prev)] == score;
    final sameNext = score != null &&
        day.weekday != DateTime.sunday &&
        byDay[_key(next)] == score;

    out.add(MoodCell(
      date: day,
      column: column,
      weekday: day.weekday,
      score: score,
      startsRun: !samePrev,
      endsRun: !sameNext,
    ));
  }
  return out;
}

/// Недели, в которых есть хоть одна отметка, — по порядку, каждая из семи
/// клеток.
///
/// Пустые недели из сетки выпадают: год, где отмечались три месяца, иначе на
/// три четверти состоит из пустоты, не влезает в экран и ничего не сообщает.
/// Свернуть можно только неделю целиком: убери отдельные дни — и столбцы
/// разъедутся, понедельник встанет под средой.
List<List<MoodCell>> visibleWeeks(List<MoodCell> cells) {
  final byWeek = <int, List<MoodCell>>{};
  for (final c in cells) {
    byWeek.putIfAbsent(c.column, () => []).add(c);
  }
  final keys = byWeek.keys.toList()..sort();
  final out = <List<MoodCell>>[];
  for (final k in keys) {
    final week = byWeek[k]!;
    if (week.every((c) => c.score == null)) continue;
    // Неделя на границе года короче семи дней — дополняем пустыми клетками,
    // чтобы столбцы стояли ровно.
    final row = List<MoodCell>.generate(7, (i) {
      return week.firstWhere(
        (c) => c.weekday == i + 1,
        orElse: () => MoodCell(
          date: week.first.date,
          column: k,
          weekday: i + 1,
          score: null,
          startsRun: true,
          endsRun: true,
        ),
      );
    });
    out.add(row);
  }
  return out;
}

/// Итог года под сеткой.
class MoodYearSummary {
  const MoodYearSummary({
    required this.marked,
    required this.missing,
    required this.average,
  });

  /// Сколько дней отмечено.
  final int marked;

  /// Сколько дней прошло без отметки. Будущие дни не считаются: год ещё идёт.
  final int missing;

  /// Средняя оценка по отмеченным дням. `null` — отмечать ещё нечего.
  final double? average;
}

MoodYearSummary moodYearSummary({
  required int year,
  required Map<DateTime, int> scores,
  DateTime? today,
}) {
  final byDay = <String, int>{
    for (final e in scores.entries) _key(e.key): e.value,
  };
  final last = DateTime(year, 12, 31);
  final now = today ?? DateTime.now();
  // Год ещё не кончился — считаем до сегодня: называть декабрь «днём без
  // отметки» в январе нечестно.
  final edge = now.year == year && now.isBefore(last) ? now : last;

  var marked = 0;
  var missing = 0;
  var sum = 0;
  for (var day = DateTime(year);
      !day.isAfter(edge);
      day = DateTime(day.year, day.month, day.day + 1)) {
    final score = byDay[_key(day)];
    if (score == null) {
      missing++;
    } else {
      marked++;
      sum += score;
    }
  }
  return MoodYearSummary(
    marked: marked,
    missing: missing,
    average: marked == 0 ? null : sum / marked,
  );
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
