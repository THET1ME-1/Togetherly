import 'mood_entry.dart';

/// Одна доля кольца настроений.
class MoodSlice {
  const MoodSlice({
    required this.id,
    required this.count,
    required this.percent,
  });

  final String id;
  final int count;

  /// Целые проценты: сумма долей ровно сто, дробей в интерфейсе нет.
  final int percent;

  MoodOption? get option => MoodOption.byId(id);
}

/// Сводка настроений за период — то, что показывает кольцо в календаре.
///
/// Прежний блок выкладывал девять долей подряд, семь из них по девять
/// процентов: цвет там ничего не кодировал, а читать было нечего. Кольцу
/// нужны три вещи — доли по убыванию, тройка лидеров и одно число в центре.
class MoodSummary {
  const MoodSummary({
    required this.total,
    required this.slices,
    required this.brightPercent,
  });

  final int total;

  /// Все доли по убыванию; при равенстве — по идентификатору, иначе кольцо
  /// перекрашивается на каждой перерисовке.
  final List<MoodSlice> slices;

  /// Сколько отметок пришлось на светлые настроения (тир 4 и выше).
  final int brightPercent;

  bool get isEmpty => total == 0;

  List<MoodSlice> get top => slices.take(3).toList();

  int get restCount => slices.length <= 3 ? 0 : slices.length - 3;

  factory MoodSummary.of(Map<String, int> counts) {
    final total = counts.values.fold(0, (a, b) => a + b);
    if (total == 0) {
      return const MoodSummary(total: 0, slices: [], brightPercent: 0);
    }

    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

    final slices = <MoodSlice>[];
    var used = 0;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      // Последней доле отдаём остаток: три трети иначе дают 99 процентов и
      // щель в кольце.
      final percent = i == entries.length - 1
          ? 100 - used
          : (e.value / total * 100).round();
      used += percent;
      slices.add(MoodSlice(id: e.key, count: e.value, percent: percent));
    }

    final bright = entries
        .where((e) => (MoodOption.byId(e.key)?.score ?? 3) >= 4)
        .fold(0, (sum, e) => sum + e.value);

    return MoodSummary(
      total: total,
      slices: slices,
      brightPercent: (bright / total * 100).round(),
    );
  }
}
