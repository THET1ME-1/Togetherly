/// «Умение любить» — тест на шесть граней отношений.
///
/// Двадцать утверждений о себе, четыре градации ответа с весами 0, 33, 67, 100.
/// У каждого утверждения своя грань, оценка грани — среднее её ответов, общее
/// число — среднее по шести граням.
///
/// Результат рисуется одной фигурой на шестиугольной сетке: где грань сильнее,
/// там контур тянется наружу. Фигура запоминается, число нет — поэтому число
/// стоит рядом, а не вместо неё.
library;

enum LoveFacet {
  interest('Интерес'),
  trust('Доверие'),
  gratitude('Благодарность'),
  mutuality('Взаимность'),
  passion('Страсть'),
  acceptance('Принятие');

  const LoveFacet(this.title);

  /// Подпись у вершины и в разборе.
  final String title;

  static LoveFacet? byName(String name) {
    for (final f in LoveFacet.values) {
      if (f.name == name) return f;
    }
    return null;
  }
}

/// Веса градаций. Строго эти четыре: чужое число означает битый ответ.
const List<int> kLoveWeights = [0, 33, 67, 100];

/// Подписи градаций в том же порядке, что и веса.
const List<String> kLoveAnswers = [
  'Почти никогда',
  'Редко',
  'Часто',
  'Почти всегда',
];

class LoveQuestion {
  const LoveQuestion(this.text, this.facet);

  final String text;
  final LoveFacet facet;
}

/// Двадцать утверждений: по три-четыре на грань.
///
/// Все — про себя и про наблюдаемое поведение, а не про чувства партнёра: о
/// себе человек отвечает честнее, чем угадывает за другого.
const List<LoveQuestion> kLoveQuestions = [
  // Интерес
  LoveQuestion('Я замечаю, что партнёру тяжело, раньше, чем он об этом скажет',
      LoveFacet.interest),
  LoveQuestion('Мне любопытно, что он думает о вещах, которые меня не касаются',
      LoveFacet.interest),
  LoveQuestion('Я помню, чем он был занят на этой неделе', LoveFacet.interest),

  // Доверие
  LoveQuestion('Я рассказываю ему о своих неудачах, не смягчая', LoveFacet.trust),
  LoveQuestion('Когда он задерживается, я не выстраиваю худших версий',
      LoveFacet.trust),
  LoveQuestion('Я могу молчать рядом с ним и не чувствовать неловкости',
      LoveFacet.trust),
  LoveQuestion('Я говорю о том, что меня задело, а не коплю', LoveFacet.trust),

  // Благодарность
  LoveQuestion('Я говорю спасибо за мелочи, которые он делает каждый день',
      LoveFacet.gratitude),
  LoveQuestion('Я замечаю, что он для меня меняет', LoveFacet.gratitude),
  LoveQuestion('Мне легко сказать вслух, за что я его ценю',
      LoveFacet.gratitude),

  // Взаимность
  LoveQuestion('Мы делим бытовые дела так, что никто не тянет всё',
      LoveFacet.mutuality),
  LoveQuestion('Мои планы учитывают его планы', LoveFacet.mutuality),
  LoveQuestion('Он получает от меня столько же внимания, сколько я от него',
      LoveFacet.mutuality),
  LoveQuestion('Когда мы спорим, я ищу решение, а не победу',
      LoveFacet.mutuality),

  // Страсть
  LoveQuestion('Мне хочется прикасаться к нему без повода', LoveFacet.passion),
  LoveQuestion('Я жду наших встреч, даже когда мы виделись вчера',
      LoveFacet.passion),
  LoveQuestion('Я придумываю, чем его удивить', LoveFacet.passion),

  // Принятие
  LoveQuestion('Мне не хочется его переделывать', LoveFacet.acceptance),
  LoveQuestion('Я спокойно отношусь к его увлечениям, которых не разделяю',
      LoveFacet.acceptance),
  LoveQuestion('Его слабости не портят моего отношения к нему',
      LoveFacet.acceptance),
];

/// Результат: шесть оценок 0…100, общее число и когда проходили.
class LoveTestResult {
  LoveTestResult({required Map<LoveFacet, int> facets, required this.takenAt})
      : facets = Map.unmodifiable(facets);

  final Map<LoveFacet, int> facets;
  final DateTime takenAt;

  int of(LoveFacet facet) => facets[facet] ?? 0;

  /// Общее число — среднее по шести граням, а не по всем ответам: иначе грань
  /// с четырьмя утверждениями весила бы больше грани с тремя.
  int get total {
    if (facets.isEmpty) return 0;
    final sum = LoveFacet.values.fold<int>(0, (a, f) => a + of(f));
    return (sum / LoveFacet.values.length).round();
  }

  LoveFacet get strongest => _edge((a, b) => a >= b);
  LoveFacet get weakest => _edge((a, b) => a <= b);

  LoveFacet _edge(bool Function(int, int) better) {
    var best = LoveFacet.values.first;
    for (final f in LoveFacet.values) {
      if (better(of(f), of(best))) best = f;
    }
    return best;
  }

  Map<String, dynamic> toMap() => {
        'facets': {for (final f in LoveFacet.values) f.name: of(f)},
        'total': total,
        'takenAt': takenAt.toUtc().toIso8601String(),
      };

  /// Читает запись, сделанную любой сборкой. Битое поле — ноль, не исключение:
  /// экран статистики не должен падать из-за одной кривой записи.
  factory LoveTestResult.fromMap(Map<String, dynamic> map) {
    final raw = map['facets'];
    final facets = <LoveFacet, int>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        final facet = LoveFacet.byName(key.toString());
        final score = value is num ? value.round() : int.tryParse('$value');
        if (facet != null && score != null) {
          facets[facet] = score.clamp(0, 100);
        }
      });
    }
    return LoveTestResult(
      facets: facets,
      takenAt: DateTime.tryParse('${map['takenAt']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Считает результат по ответам «номер вопроса → вес».
///
/// Возвращает `null`, если тест не закончен или пришёл чужой вес: фигура по
/// половине ответов врёт формой, а это единственное, ради чего её рисуют.
LoveTestResult? scoreLoveTest(Map<int, int> answers) {
  if (answers.length != kLoveQuestions.length) return null;

  final sums = <LoveFacet, int>{};
  final counts = <LoveFacet, int>{};
  for (var i = 0; i < kLoveQuestions.length; i++) {
    final weight = answers[i];
    if (weight == null || !kLoveWeights.contains(weight)) return null;
    final facet = kLoveQuestions[i].facet;
    sums[facet] = (sums[facet] ?? 0) + weight;
    counts[facet] = (counts[facet] ?? 0) + 1;
  }

  final facets = <LoveFacet, int>{};
  for (final facet in LoveFacet.values) {
    final n = counts[facet] ?? 0;
    facets[facet] = n == 0 ? 0 : ((sums[facet] ?? 0) / n).round();
  }
  return LoveTestResult(facets: facets, takenAt: DateTime.now());
}

/// Что показать паре: где сошлись ближе всего, где разошлись сильнее.
class LovePairInsight {
  const LovePairInsight({
    required this.closest,
    required this.widest,
    required this.gaps,
  });

  final LoveFacet closest;
  final LoveFacet widest;
  final Map<LoveFacet, int> gaps;

  int gapOf(LoveFacet facet) => gaps[facet] ?? 0;
}

LovePairInsight comparePair(LoveTestResult mine, LoveTestResult theirs) {
  final gaps = {
    for (final f in LoveFacet.values) f: (mine.of(f) - theirs.of(f)).abs(),
  };
  var closest = LoveFacet.values.first;
  var widest = LoveFacet.values.first;
  for (final f in LoveFacet.values) {
    if (gaps[f]! < gaps[closest]!) closest = f;
    if (gaps[f]! > gaps[widest]!) widest = f;
  }
  return LovePairInsight(closest: closest, widest: widest, gaps: gaps);
}
