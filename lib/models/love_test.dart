/// «Умение любить» — тест на шесть граней отношений.
///
/// Двадцать утверждений о себе за проход, четыре градации ответа с весами
/// 0, 33, 67, 100. Сами утверждения берутся из банка на восемьдесят: пока их
/// было ровно двадцать, второй проход слово в слово повторял первый, и человек
/// отвечал по памяти, а не про себя.
/// У каждого утверждения своя грань, оценка грани — среднее её ответов, общее
/// число — среднее по шести граням.
///
/// Результат рисуется одной фигурой на шестиугольной сетке: где грань сильнее,
/// там контур тянется наружу. Фигура запоминается, число нет — поэтому число
/// стоит рядом, а не вместо неё.
library;

import 'dart:math';

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

/// Сколько утверждений в одном прохождении.
const int kLoveRoundSize = 20;

/// Сколько утверждений каждой грани идёт в проход.
///
/// Раскладка та же, что была у теста из двадцати: доверие и взаимность держат
/// по четыре, остальные по три. Менять её нельзя, не пересчитав прошлые
/// результаты: общее число — среднее по граням, а не по ответам.
const Map<LoveFacet, int> kLoveRoundLayout = {
  LoveFacet.interest: 3,
  LoveFacet.trust: 4,
  LoveFacet.gratitude: 3,
  LoveFacet.mutuality: 4,
  LoveFacet.passion: 3,
  LoveFacet.acceptance: 3,
};

/// Сколько прошлых прохождений храним рядом со свежим.
const int kLoveHistoryKeep = 10;

/// Банк утверждений.
///
/// Все — про себя и про наблюдаемое поведение, а не про чувства партнёра: о
/// себе человек отвечает честнее, чем угадывает за другого.
const List<LoveQuestion> kLoveBank = [
  // Интерес (13)
  LoveQuestion('love_q1', LoveFacet.interest),
  LoveQuestion('love_q2', LoveFacet.interest),
  LoveQuestion('love_q3', LoveFacet.interest),
  LoveQuestion('love_q21', LoveFacet.interest),
  LoveQuestion('love_q22', LoveFacet.interest),
  LoveQuestion('love_q23', LoveFacet.interest),
  LoveQuestion('love_q24', LoveFacet.interest),
  LoveQuestion('love_q25', LoveFacet.interest),
  LoveQuestion('love_q26', LoveFacet.interest),
  LoveQuestion('love_q27', LoveFacet.interest),
  LoveQuestion('love_q28', LoveFacet.interest),
  LoveQuestion('love_q29', LoveFacet.interest),
  LoveQuestion('love_q30', LoveFacet.interest),

  // Доверие (15)
  LoveQuestion('love_q4', LoveFacet.trust),
  LoveQuestion('love_q5', LoveFacet.trust),
  LoveQuestion('love_q6', LoveFacet.trust),
  LoveQuestion('love_q7', LoveFacet.trust),
  LoveQuestion('love_q31', LoveFacet.trust),
  LoveQuestion('love_q32', LoveFacet.trust),
  LoveQuestion('love_q33', LoveFacet.trust),
  LoveQuestion('love_q34', LoveFacet.trust),
  LoveQuestion('love_q35', LoveFacet.trust),
  LoveQuestion('love_q36', LoveFacet.trust),
  LoveQuestion('love_q37', LoveFacet.trust),
  LoveQuestion('love_q38', LoveFacet.trust),
  LoveQuestion('love_q39', LoveFacet.trust),
  LoveQuestion('love_q40', LoveFacet.trust),
  LoveQuestion('love_q41', LoveFacet.trust),

  // Благодарность (13)
  LoveQuestion('love_q8', LoveFacet.gratitude),
  LoveQuestion('love_q9', LoveFacet.gratitude),
  LoveQuestion('love_q10', LoveFacet.gratitude),
  LoveQuestion('love_q42', LoveFacet.gratitude),
  LoveQuestion('love_q43', LoveFacet.gratitude),
  LoveQuestion('love_q44', LoveFacet.gratitude),
  LoveQuestion('love_q45', LoveFacet.gratitude),
  LoveQuestion('love_q46', LoveFacet.gratitude),
  LoveQuestion('love_q47', LoveFacet.gratitude),
  LoveQuestion('love_q48', LoveFacet.gratitude),
  LoveQuestion('love_q49', LoveFacet.gratitude),
  LoveQuestion('love_q50', LoveFacet.gratitude),
  LoveQuestion('love_q51', LoveFacet.gratitude),

  // Взаимность (15)
  LoveQuestion('love_q11', LoveFacet.mutuality),
  LoveQuestion('love_q12', LoveFacet.mutuality),
  LoveQuestion('love_q13', LoveFacet.mutuality),
  LoveQuestion('love_q14', LoveFacet.mutuality),
  LoveQuestion('love_q52', LoveFacet.mutuality),
  LoveQuestion('love_q53', LoveFacet.mutuality),
  LoveQuestion('love_q54', LoveFacet.mutuality),
  LoveQuestion('love_q55', LoveFacet.mutuality),
  LoveQuestion('love_q56', LoveFacet.mutuality),
  LoveQuestion('love_q57', LoveFacet.mutuality),
  LoveQuestion('love_q58', LoveFacet.mutuality),
  LoveQuestion('love_q59', LoveFacet.mutuality),
  LoveQuestion('love_q60', LoveFacet.mutuality),
  LoveQuestion('love_q61', LoveFacet.mutuality),
  LoveQuestion('love_q62', LoveFacet.mutuality),

  // Страсть (12)
  LoveQuestion('love_q15', LoveFacet.passion),
  LoveQuestion('love_q16', LoveFacet.passion),
  LoveQuestion('love_q17', LoveFacet.passion),
  LoveQuestion('love_q63', LoveFacet.passion),
  LoveQuestion('love_q64', LoveFacet.passion),
  LoveQuestion('love_q65', LoveFacet.passion),
  LoveQuestion('love_q66', LoveFacet.passion),
  LoveQuestion('love_q67', LoveFacet.passion),
  LoveQuestion('love_q68', LoveFacet.passion),
  LoveQuestion('love_q69', LoveFacet.passion),
  LoveQuestion('love_q70', LoveFacet.passion),
  LoveQuestion('love_q71', LoveFacet.passion),

  // Принятие (12)
  LoveQuestion('love_q18', LoveFacet.acceptance),
  LoveQuestion('love_q19', LoveFacet.acceptance),
  LoveQuestion('love_q20', LoveFacet.acceptance),
  LoveQuestion('love_q72', LoveFacet.acceptance),
  LoveQuestion('love_q73', LoveFacet.acceptance),
  LoveQuestion('love_q74', LoveFacet.acceptance),
  LoveQuestion('love_q75', LoveFacet.acceptance),
  LoveQuestion('love_q76', LoveFacet.acceptance),
  LoveQuestion('love_q77', LoveFacet.acceptance),
  LoveQuestion('love_q78', LoveFacet.acceptance),
  LoveQuestion('love_q79', LoveFacet.acceptance),
  LoveQuestion('love_q80', LoveFacet.acceptance),

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

/// Собирает набор для одного прохождения.
///
/// Из каждой грани берётся столько, сколько велит [kLoveRoundLayout], причём
/// сперва из тех, что человек ещё не видел ([exclude] — набор прошлого раза).
/// Свежих не хватило — добираем из прежних: тест обязан собраться целиком,
/// иначе человек упрётся в пустой экран.
///
/// Порядок перемешан: одна и та же последовательность узнаётся с третьего
/// утверждения, и дальше человек отвечает по памяти прошлого раза.
List<LoveQuestion> pickLoveRound({
  required Random random,
  List<LoveQuestion> bank = kLoveBank,
  Set<String> exclude = const {},
}) {
  final out = <LoveQuestion>[];
  for (final entry in kLoveRoundLayout.entries) {
    final ofFacet = bank.where((q) => q.facet == entry.key).toList();
    final fresh = ofFacet.where((q) => !exclude.contains(q.key)).toList()
      ..shuffle(random);
    final seen = ofFacet.where((q) => exclude.contains(q.key)).toList()
      ..shuffle(random);
    final take = [...fresh, ...seen].take(entry.value);
    out.addAll(take);
  }
  out.shuffle(random);
  return List.unmodifiable(out);
}

/// Считает результат прохождения: [round] — набор этого раза, [answers] —
/// «номер утверждения в наборе → вес».
///
/// Возвращает `null`, если тест не закончен или пришёл чужой вес: фигура по
/// половине ответов врёт формой, а это единственное, ради чего её рисуют.
LoveTestResult? scoreLoveRound(
  List<LoveQuestion> round,
  Map<int, int> answers,
) {
  if (round.isEmpty || answers.length != round.length) return null;

  final sums = <LoveFacet, int>{};
  final counts = <LoveFacet, int>{};
  for (var i = 0; i < round.length; i++) {
    final weight = answers[i];
    if (weight == null || !kLoveWeights.contains(weight)) return null;
    final facet = round[i].facet;
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

/// Тело записи `love_tests.data`: свежий результат плюс прошлые.
///
/// История лежит в том же json-поле, что и результат, — отдельной колонки на
/// проде заводить не пришлось, а старые сборки читают запись как раньше:
/// незнакомый ключ `history` они просто не смотрят.
Map<String, dynamic> loveTestPayload(
  LoveTestResult current,
  List<LoveTestResult> previous, {
  int keep = kLoveHistoryKeep,
  List<String> roundKeys = const [],
}) {
  final tail = previous.length > keep
      ? previous.sublist(previous.length - keep)
      : previous;
  return {
    ...current.toMap(),
    'history': [for (final r in tail) r.toMap()],
    // Набор этого раза: в следующий проход эти утверждения уходят в конец
    // очереди. Ключи, а не тексты, — перевод к тому времени может смениться.
    'round': roundKeys,
  };
}

/// Утверждения прошлого прохождения. Пусто у записи без набора.
Set<String> loveLastRoundKeys(Map<String, dynamic> map) {
  final raw = map['round'];
  if (raw is! List) return const {};
  return {for (final k in raw) if (k is String && k.isNotEmpty) k};
}

/// Прошлые прохождения из записи, от старого к свежему. Пусто у записи,
/// сделанной сборкой без истории.
List<LoveTestResult> loveHistoryFromMap(Map<String, dynamic> map) {
  final raw = map['history'];
  if (raw is! List) return const [];
  final out = <LoveTestResult>[];
  for (final item in raw) {
    if (item is Map) {
      out.add(LoveTestResult.fromMap(Map<String, dynamic>.from(item)));
    }
  }
  return out;
}

/// Что изменилось с прошлого раза.
class LoveProgress {
  const LoveProgress({
    required this.deltas,
    required this.totalDelta,
    required this.since,
    required this.grown,
    required this.fallen,
  });

  /// Насколько каждая грань выросла (плюс) или просела (минус).
  final Map<LoveFacet, int> deltas;
  final int totalDelta;

  /// Когда проходили в прошлый раз.
  final DateTime since;

  /// Где рост сильнее всего и где сильнее всего просело.
  final LoveFacet grown;
  final LoveFacet fallen;

  int deltaOf(LoveFacet facet) => deltas[facet] ?? 0;

  /// Двигалось ли хоть что-нибудь: одинаковые ответы дают ровные нули, и
  /// показывать «выросло на 0» в этом случае незачем.
  bool get moved => deltas.values.any((d) => d != 0);
}

/// Сравнение с прошлым прохождением. `null` — сравнивать не с чем.
LoveProgress? loveProgress(LoveTestResult current, LoveTestResult? previous) {
  if (previous == null) return null;
  final deltas = {
    for (final f in LoveFacet.values) f: current.of(f) - previous.of(f),
  };
  var grown = LoveFacet.values.first;
  var fallen = LoveFacet.values.first;
  for (final f in LoveFacet.values) {
    if (deltas[f]! > deltas[grown]!) grown = f;
    if (deltas[f]! < deltas[fallen]!) fallen = f;
  }
  return LoveProgress(
    deltas: deltas,
    totalDelta: current.total - previous.total,
    since: previous.takenAt,
    grown: grown,
    fallen: fallen,
  );
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
