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

import '../dict_strings.dart';

enum LoveFacet {
  interest,
  trust,
  gratitude,
  mutuality,
  passion,
  acceptance;

  /// Подпись у вершины и в разборе. Живёт в словаре (`love_facet_<грань>`), а
  /// не в поле: пока названия лежали здесь строками, немец и испанец читали
  /// русское слово.
  String get title => trKey('love_facet_$name');

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
List<String> get kLoveAnswers => [
      for (var i = 0; i < kLoveWeights.length; i++) trKey('love_answer_$i'),
    ];

class LoveQuestion {
  const LoveQuestion(this.key, this.facet);

  /// Ключ словаря (`love_q1`…`love_q20`); сам текст приходит переводом.
  final String key;
  final LoveFacet facet;

  String get text => trKey(key);
}

/// Двадцать утверждений: по три-четыре на грань.
///
/// Все — про себя и про наблюдаемое поведение, а не про чувства партнёра: о
/// себе человек отвечает честнее, чем угадывает за другого.
const List<LoveQuestion> kLoveQuestions = [
  // Интерес
  LoveQuestion('love_q1', LoveFacet.interest),
  LoveQuestion('love_q2', LoveFacet.interest),
  LoveQuestion('love_q3', LoveFacet.interest),

  // Доверие
  LoveQuestion('love_q4', LoveFacet.trust),
  LoveQuestion('love_q5', LoveFacet.trust),
  LoveQuestion('love_q6', LoveFacet.trust),
  LoveQuestion('love_q7', LoveFacet.trust),

  // Благодарность
  LoveQuestion('love_q8', LoveFacet.gratitude),
  LoveQuestion('love_q9', LoveFacet.gratitude),
  LoveQuestion('love_q10', LoveFacet.gratitude),

  // Взаимность
  LoveQuestion('love_q11', LoveFacet.mutuality),
  LoveQuestion('love_q12', LoveFacet.mutuality),
  LoveQuestion('love_q13', LoveFacet.mutuality),
  LoveQuestion('love_q14', LoveFacet.mutuality),

  // Страсть
  LoveQuestion('love_q15', LoveFacet.passion),
  LoveQuestion('love_q16', LoveFacet.passion),
  LoveQuestion('love_q17', LoveFacet.passion),

  // Принятие
  LoveQuestion('love_q18', LoveFacet.acceptance),
  LoveQuestion('love_q19', LoveFacet.acceptance),
  LoveQuestion('love_q20', LoveFacet.acceptance),
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
