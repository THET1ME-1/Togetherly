import 'pair_date.dart';

/// Что сделать с календарём телефона, чтобы в нём были ровно наши даты.
///
/// Правка даты — замена события целиком (удалить и создать заново): так
/// повтор, выброшенные дни и время всегда совпадают с датой, а правки редки.
class PhoneCalendarPlan {
  const PhoneCalendarPlan({required this.create, required this.replace, required this.remove});

  final List<PairDate> create;
  final List<PairDate> replace;

  /// id даты → id события: этих дат больше нет.
  final Map<String, String> remove;
}

/// [links] — id даты → id события в календаре телефона, [sigs] — подпись даты
/// на момент записи. Готовые даты (годовщина, дни рождения) не идут: у них в
/// телефоне свои источники.
PhoneCalendarPlan phoneCalendarPlan({
  required List<PairDate> dates,
  required Map<String, String> links,
  required Map<String, String> sigs,
}) {
  final own = [for (final d in dates) if (!d.isAuto && d.day != null) d];
  final ids = {for (final d in own) d.id};
  return PhoneCalendarPlan(
    create: [for (final d in own) if (!links.containsKey(d.id)) d],
    replace: [for (final d in own) if (links.containsKey(d.id) && sigs[d.id] != phoneCalendarSig(d)) d],
    remove: {for (final e in links.entries) if (!ids.contains(e.key)) e.key: e.value},
  );
}

/// Подпись того, что видно в календаре телефона. Напоминаний там нет (их
/// шлёт сервер, иначе звонило бы дважды), поэтому они в подпись не входят.
String phoneCalendarSig(PairDate d) {
  final ex = d.exdates.toList()..sort();
  return [d.title, d.note, d.toMap()['day'], d.time ?? '', d.tz, d.rrule, ex.join(',')].join('|');
}

const String _tag = 'togetherly:';

/// Описание события: заметка и метка даты. По метке повторное включение
/// находит свои события и не плодит копий.
String phoneCalendarNote(PairDate d) =>
    d.note.trim().isEmpty ? '$_tag${d.id}' : '${d.note.trim()}\n\n$_tag${d.id}';

/// id даты из описания события или null, если событие не наше.
String? dateIdFromNote(String? note) {
  final m = RegExp('$_tag(\\w+)').firstMatch(note ?? '');
  return m?.group(1);
}
