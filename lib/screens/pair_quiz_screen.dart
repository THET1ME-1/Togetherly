import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/pair_quiz.dart';
import '../services/locale_service.dart';
import '../services/pair_quiz_service.dart';
import '../theme/profile_theme.dart';

/// Тест для пары (язык любви, привязанность, зверь): вступление, вопросы по
/// одному, результат. Как в «Умении любить», итог партнёра виден только после
/// своих ответов: иначе его ответ стал бы подсказкой.
class PairQuizScreen extends StatefulWidget {
  const PairQuizScreen({
    super.key,
    required this.kind,
    required this.scheme,
    required this.groupId,
    required this.myUid,
    this.partnerName = '',
    this.initial,
  });

  final QuizKind kind;
  final ColorScheme scheme;
  final String groupId;
  final String myUid;
  final String partnerName;

  /// Готовые результаты для теста: тогда экран не ходит в сеть.
  final PairQuizResults? initial;

  @override
  State<PairQuizScreen> createState() => _PairQuizScreenState();
}

class _PairQuizScreenState extends State<PairQuizScreen> {
  PairQuizResults _results = const PairQuizResults();
  bool _loading = true;

  /// null — вступление или результат; число — сколько вопросов уже позади.
  int? _step;

  /// Ответ на каждый вопрос в исходном порядке (-1 — ещё нет).
  List<int> _answers = [];

  /// Порядок вопросов и вариантов этого прохождения: каждый раз свой, чтобы
  /// повтор не проходился по памяти. Шкалу привязанности не мешаем —
  /// «совсем нет … точно да» должна идти по порядку.
  List<int> _order = [];
  List<List<int>> _optOrder = [];
  final Random _rand = Random();

  String get _lang => LocaleService.instance.language.code;
  QuizResult? get _mine => _results.mine[widget.kind];
  QuizResult? get _theirs => _results.theirs[widget.kind];

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _results = widget.initial!;
      _loading = false;
    } else {
      unawaited(_load());
    }
  }

  /// [keepMine] — после прохождения: свой свежий итог уже на экране, а сервер
  /// мог его ещё не получить (или связи нет), поэтому берём только партнёра.
  Future<void> _load({bool keepMine = false}) async {
    final r = await PairQuizService.instance.load(widget.groupId, widget.myUid);
    if (!mounted) return;
    setState(() {
      _results = keepMine
          ? PairQuizResults(
              mine: {...r.mine, ..._results.mine},
              theirs: r.theirs.isEmpty ? _results.theirs : r.theirs,
            )
          : r;
      _loading = false;
    });
  }

  /// [shown] — номер варианта на экране; в ответ ложится его исходный номер.
  void _answer(int shown) {
    final step = _step!;
    final q = _order[step];
    final done = step + 1 == _order.length;
    setState(() {
      _answers[q] = _optOrder[q][shown];
      if (!done) {
        _step = step + 1;
        return;
      }
      final res = scoreQuiz(widget.kind, _answers);
      _results = PairQuizResults(
        mine: {..._results.mine, widget.kind: res},
        theirs: _results.theirs,
      );
      _step = null;
    });
    if (done) {
      unawaited(PairQuizService.instance.save(widget.groupId, widget.myUid, _mine!));
      // Свежий итог партнёра мог прийти, пока человек отвечал.
      unawaited(_load(keepMine: true));
    }
  }

  void _start() {
    final qs = quizQuestions(widget.kind, _lang);
    setState(() {
      _answers = List.filled(qs.length, -1);
      _order = List.generate(qs.length, (i) => i)..shuffle(_rand);
      _optOrder = [
        for (final q in qs)
          widget.kind == QuizKind.attach
              ? List.generate(q.options.length, (i) => i)
              : (List.generate(q.options.length, (i) => i)..shuffle(_rand)),
      ];
      _step = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(
            quizTitle(widget.kind, _lang),
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _step != null
                  ? _question(cs)
                  : _mine == null
                      ? _intro(cs)
                      : _result(cs),
        ),
      ),
    );
  }

  Widget _intro(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(28)),
          child: Text(
            quizIntro(widget.kind, _lang),
            style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 16.5, height: 1.45, color: cs.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _start,
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            child: Text(quizUi('start', _lang)),
          ),
        ),
      ],
    );
  }

  Widget _question(ColorScheme cs) {
    final qs = quizQuestions(widget.kind, _lang);
    final i = _step!;
    final q = qs[_order[i]];
    final opts = _optOrder[_order[i]];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        Text(
          quizUi('step', _lang).replaceAll('{0}', '${i + 1}').replaceAll('{1}', '${qs.length}'),
          style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 13.5, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: i / qs.length,
            minHeight: 8,
            backgroundColor: cs.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          q.text,
          style: TextStyle(
            fontFamily: ProfileTheme.displayFont,
            fontSize: 22,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 20),
        for (var o = 0; o < q.options.length; o++) ...[
          if (o > 0) const SizedBox(height: 10),
          Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('quiz_option_$o'),
              onTap: () => _answer(o),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Text(
                  q.options[opts[o]].text,
                  style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 16, height: 1.3, color: cs.onSurface),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _result(ColorScheme cs) {
    final mine = _mine!;
    final theirs = _theirs;
    final partner = widget.partnerName.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _ResultCard(
          label: quizUi('mine', _lang),
          result: mine,
          lang: _lang,
          color: cs.primaryContainer,
          ink: cs.onPrimaryContainer,
        ),
        const SizedBox(height: 12),
        if (theirs != null) ...[
          _ResultCard(
            label: partner.isEmpty ? quizUi('theirs', _lang) : partner,
            result: theirs,
            lang: _lang,
            color: cs.secondaryContainer,
            ink: cs.onSecondaryContainer,
            short: true,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(28)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quizUi('together', _lang).toUpperCase(),
                  style: ProfileTheme.sectionLabel(cs, color: cs.onTertiaryContainer),
                ),
                const SizedBox(height: 8),
                Text(
                  quizPairText(widget.kind, mine.type, theirs.type, _lang),
                  style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 16, height: 1.45, color: cs.onTertiaryContainer),
                ),
              ],
            ),
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
            child: Text(
              quizUi('wait', _lang),
              style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 15, height: 1.4, color: cs.onSurfaceVariant),
            ),
          ),
        if (widget.kind == QuizKind.attach) ...[
          const SizedBox(height: 12),
          Text(
            quizUi('note', _lang),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: FilledButton.tonal(
            onPressed: _start,
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            child: Text(quizUi('again', _lang)),
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.label,
    required this.result,
    required this.lang,
    required this.color,
    required this.ink,
    this.short = false,
  });

  final String label;
  final QuizResult result;
  final String lang;
  final Color color;
  final Color ink;

  /// Карточка партнёра: без описания и шкал, только тип.
  final bool short;

  @override
  Widget build(BuildContext context) {
    final kind = result.kind;
    final emoji = kind == QuizKind.animal ? kAnimalEmoji[result.type] : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 13.5, fontWeight: FontWeight.w600, color: ink.withValues(alpha: 0.8))),
          const SizedBox(height: 4),
          Row(
            children: [
              if (emoji != null) ...[
                Text(emoji, style: TextStyle(fontSize: short ? 30 : 44)),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  quizTypeTitle(kind, result.type, lang),
                  style: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontSize: short ? 20 : 28,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          if (!short) ...[
            const SizedBox(height: 10),
            Text(
              quizTypeText(kind, result.type, lang),
              style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 15.5, height: 1.45, color: ink),
            ),
            if (kind != QuizKind.animal) ...[
              const SizedBox(height: 14),
              for (final e in _bars(kind, result, lang))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(e.$1, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 13, color: ink)),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: e.$2.clamp(0.0, 1.0),
                            minHeight: 8,
                            color: ink,
                            backgroundColor: ink.withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  static List<(String, double)> _bars(QuizKind kind, QuizResult r, String lang) => kind == QuizKind.attach
      ? [(quizUi('anx', lang), r.scores['anx'] ?? 0), (quizUi('avo', lang), r.scores['avo'] ?? 0)]
      : [for (final t in kQuizTypes[kind]!) (quizTypeTitle(kind, t, lang), r.scores[t] ?? 0)];
}

/// Экран «Тесты для пары» (06.11.2026): одна кнопка в профиле ведёт сюда, а
/// здесь все тесты — «Умение любить» первым, за ним три новых.
class PairTestsScreen extends StatefulWidget {
  const PairTestsScreen({
    super.key,
    required this.scheme,
    required this.groupId,
    required this.myUid,
    required this.partnerName,
    required this.loveTestBuilder,
    this.initial,
  });

  final ColorScheme scheme;
  final String groupId;
  final String myUid;
  final String partnerName;

  /// «Умение любить» собирает профиль: ему нужны тема и пол обоих.
  final WidgetBuilder loveTestBuilder;

  /// Готовые результаты для теста: тогда экран не ходит в сеть.
  final PairQuizResults? initial;

  @override
  State<PairTestsScreen> createState() => _PairTestsScreenState();
}

class _PairTestsScreenState extends State<PairTestsScreen> {
  PairQuizResults _results = const PairQuizResults();

  static const Map<QuizKind, IconData> _icons = {
    QuizKind.lang: Icons.chat_bubble_rounded,
    QuizKind.attach: Icons.link_rounded,
    QuizKind.animal: Icons.pets_rounded,
  };

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _results = widget.initial!;
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final r = await PairQuizService.instance.load(widget.groupId, widget.myUid);
    if (mounted) setState(() => _results = r);
  }

  Future<void> _open(WidgetBuilder builder, String name) async {
    await Navigator.of(context).push(MaterialPageRoute(settings: RouteSettings(name: name), builder: builder));
    // Вернулись из теста — отметки «Пройден» могли поменяться.
    if (widget.initial == null) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    final lang = LocaleService.instance.language.code;
    final loveTitle = switch (lang) { 'ru' => 'Умение любить', 'uk' => 'Вміння кохати', _ => 'How you love' };
    final loveHint = switch (lang) {
      'ru' => 'Двадцать вопросов и одна фигура на двоих',
      'uk' => 'Двадцять питань і одна фігура на двох',
      _ => 'Twenty questions, one shape for two',
    };
    Widget row({
      required IconData icon,
      required String title,
      required String hint,
      required bool done,
      required VoidCallback onTap,
    }) =>
        Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                    child: Icon(icon, size: 22, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: ProfileTheme.displayFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hint,
                          style: TextStyle(fontFamily: ProfileTheme.bodyFont, fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                        if (done) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.check_circle_rounded, size: 16, color: cs.primary),
                              const SizedBox(width: 4),
                              Text(
                                quizUi('done', lang),
                                style: TextStyle(
                                  fontFamily: ProfileTheme.bodyFont,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: cs.outline),
                ],
              ),
            ),
          ),
        );

    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(
            quizUi('section', lang),
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 24),
          children: [
            row(
              icon: Icons.favorite_rounded,
              title: loveTitle,
              hint: loveHint,
              done: false,
              onTap: () => _open(widget.loveTestBuilder, '/love_test'),
            ),
            for (final kind in QuizKind.values) ...[
              const SizedBox(height: 8),
              row(
                icon: _icons[kind]!,
                title: quizTitle(kind, lang),
                hint: quizHint(kind, lang),
                done: _results.mine.containsKey(kind),
                onTap: () => _open(
                  (_) => PairQuizScreen(
                    kind: kind,
                    scheme: cs,
                    groupId: widget.groupId,
                    myUid: widget.myUid,
                    partnerName: widget.partnerName,
                  ),
                  '/quiz_${kind.name}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
