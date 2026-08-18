import 'package:flutter/material.dart';

import '../models/love_test.dart';
import '../services/locale_service.dart';
import '../services/love_test_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../widgets/common/m3_loading.dart';
import '../widgets/love/love_shape.dart';

/// «Умение любить»: двадцать утверждений, шесть граней, одна фигура.
///
/// Экран держит три состояния подряд — вступление, вопросы, результат — и не
/// разводит их по маршрутам: человек проходит тест за две минуты и возвращаться
/// назад ему некуда. Фигура партнёра появляется в результате и только после
/// своих ответов: иначе его цифры становятся подсказкой.
class LoveTestScreen extends StatefulWidget {
  const LoveTestScreen({
    super.key,
    required this.theme,
    required this.groupId,
    required this.myUid,
    required this.partnerName,
  });

  final AppTheme theme;
  final String groupId;
  final String myUid;
  final String partnerName;

  @override
  State<LoveTestScreen> createState() => _LoveTestScreenState();
}

enum _Stage { loading, intro, quiz, result }

class _LoveTestScreenState extends State<LoveTestScreen> {
  final Map<int, int> _answers = {};
  int _index = 0;
  _Stage _stage = _Stage.loading;
  LoveTestResult? _mine;
  LoveTestResult? _theirs;
  bool _saving = false;

  AppTheme get _t => widget.theme;
  ColorScheme get _cs => ProfileTheme.themeFor(_t).colorScheme;
  bool get _ru => LocaleService.instance.isRussian;

  String _tr(String ru, String en) => _ru ? ru : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pair = await LoveTestService.instance.load(
      widget.groupId,
      widget.myUid,
    );
    if (!mounted) return;
    setState(() {
      _mine = pair.mine;
      _theirs = pair.theirs;
      _stage = pair.mine == null ? _Stage.intro : _Stage.result;
    });
  }

  void _answer(int weight) {
    _answers[_index] = weight;
    if (_index + 1 < kLoveQuestions.length) {
      setState(() => _index++);
      return;
    }
    _finish();
  }

  Future<void> _finish() async {
    final result = scoreLoveTest(_answers);
    if (result == null) return;
    setState(() {
      _mine = result;
      _stage = _Stage.result;
      _saving = true;
    });
    final saved =
        await LoveTestService.instance.save(widget.groupId, widget.myUid, result);
    if (!mounted) return;
    if (!saved) {
      // Отказ сервера проходил молча: человек видел свою фигуру, закрывал
      // приложение и обнаруживал, что тест снова непройден.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(
            'Результат не сохранился — попробуйте пройти ещё раз позже',
            'Result was not saved — try again a bit later',
          )),
        ),
      );
    }
    // Фигуру партнёра забираем уже после сохранения: до этой минуты она была
    // под замком, и показывать её раньше собственного результата незачем.
    final pair = await LoveTestService.instance.load(
      widget.groupId,
      widget.myUid,
    );
    if (!mounted) return;
    setState(() {
      _theirs = pair.theirs;
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ProfileTheme.data(_cs),
      child: Scaffold(
        backgroundColor: _cs.surface,
        appBar: AppBar(
          backgroundColor: _cs.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            _tr('Умение любить', 'How you love'),
            style: const TextStyle(
              fontFamily: 'Unbounded',
              fontWeight: FontWeight.w500,
              fontSize: 20,
            ),
          ),
        ),
        body: SafeArea(
          child: switch (_stage) {
            _Stage.loading => Center(child: M3PageLoading(color: _cs.primary)),
            _Stage.intro => _intro(),
            _Stage.quiz => _quiz(),
            _Stage.result => _result(),
          },
        ),
      ),
    );
  }

  // ── Вступление ────────────────────────────────────────────────────────────

  Widget _intro() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: LoveShape(
                mine: _sample,
                showLabels: true,
                mineColor: _cs.primary,
                gridColor: _cs.outlineVariant,
                labelColor: _cs.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            _tr(
              'Двадцать утверждений о себе. Ответы складываются в шесть граней '
                  'и в одну фигуру — она вытянута туда, где отношения сильнее.',
              'Twenty statements about yourself. The answers add up to six '
                  'facets and one shape, stretched where your bond is stronger.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => setState(() => _stage = _Stage.quiz),
            child: Text(_tr('Начать · две минуты', 'Start · two minutes')),
          ),
        ],
      ),
    );
  }

  /// Фигура на вступлении — ровная, без чужих цифр: она объясняет форму, а не
  /// показывает чей-то результат.
  LoveTestResult get _sample => LoveTestResult(
        facets: const {
          LoveFacet.interest: 78,
          LoveFacet.trust: 64,
          LoveFacet.gratitude: 86,
          LoveFacet.mutuality: 60,
          LoveFacet.passion: 72,
          LoveFacet.acceptance: 55,
        },
        takenAt: DateTime.now(),
      );

  // ── Вопросы ───────────────────────────────────────────────────────────────

  Widget _quiz() {
    final q = kLoveQuestions[_index];
    final progress = (_index + 1) / kLoveQuestions.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _tr(
                  'Вопрос ${_index + 1} из ${kLoveQuestions.length}',
                  'Question ${_index + 1} of ${kLoveQuestions.length}',
                ),
                style: TextStyle(fontSize: 13, color: _cs.onSurfaceVariant),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  q.facet.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: _cs.surfaceContainerHighest,
              color: _cs.primary,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
            decoration: BoxDecoration(
              color: _cs.primaryContainer,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Text(
              q.text,
              style: TextStyle(
                fontFamily: 'Unbounded',
                fontSize: 20,
                height: 1.32,
                fontWeight: FontWeight.w500,
                color: _cs.onPrimaryContainer,
              ),
            ),
          ),
          const Spacer(),
          for (var i = 0; i < kLoveWeights.length; i++) ...[
            _answerButton(kLoveAnswers[i], kLoveWeights[i]),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _answerButton(String label, int weight) {
    return Material(
      color: _cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _answer(weight),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: _cs.outlineVariant),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: _cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // ── Результат ─────────────────────────────────────────────────────────────

  Widget _result() {
    final mine = _mine;
    if (mine == null) return _intro();
    final theirs = _theirs;
    final pair = theirs == null ? null : comparePair(mine, theirs);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
          decoration: BoxDecoration(
            color: _cs.primaryContainer,
            borderRadius: BorderRadius.circular(36),
          ),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: LoveShape(
                  mine: mine,
                  theirs: theirs,
                  center: theirs == null ? '${mine.total}' : null,
                  centerColor: _cs.onPrimaryContainer,
                  mineColor: _cs.primary,
                  theirsColor: _cs.tertiary,
                  gridColor: _cs.onPrimaryContainer.withValues(alpha: .35),
                  labelColor: _cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 8),
              if (theirs != null)
                Text(
                  '${_tr('Вы', 'You')} ${mine.total} · '
                  '${widget.partnerName.isEmpty ? _tr('Партнёр', 'Partner') : widget.partnerName} ${theirs.total}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _cs.onPrimaryContainer,
                  ),
                )
              else
                Text(
                  _tr(
                    'Держится на грани «${mine.strongest.title.toLowerCase()}»',
                    'Strongest facet: ${mine.strongest.title.toLowerCase()}',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _cs.onPrimaryContainer.withValues(alpha: .85),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _facetsCard(mine, theirs),
        if (pair != null) ...[
          const SizedBox(height: 14),
          _pairCard(mine, theirs!, pair),
        ],
        if (_saving) ...[
          const SizedBox(height: 14),
          Center(
            child: Text(
              _tr('Сохраняем…', 'Saving…'),
              style: TextStyle(color: _cs.onSurfaceVariant),
            ),
          ),
        ],
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: () => setState(() {
            _answers.clear();
            _index = 0;
            _stage = _Stage.quiz;
          }),
          child: Text(_tr('Пройти заново', 'Take it again')),
        ),
      ],
    );
  }

  Widget _facetsCard(LoveTestResult mine, LoveTestResult? theirs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _tr('ШЕСТЬ ГРАНЕЙ', 'SIX FACETS'),
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: _cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          for (final facet in LoveFacet.values) ...[
            _facetRow(facet, mine.of(facet), theirs?.of(facet)),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _facetRow(LoveFacet facet, int mineValue, int? theirsValue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                facet.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              theirsValue == null ? '$mineValue' : '$mineValue · $theirsValue',
              style: TextStyle(
                color: _cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: mineValue / 100,
            minHeight: 10,
            backgroundColor: _cs.surfaceContainerHighest,
            color: _cs.primary,
          ),
        ),
      ],
    );
  }

  Widget _pairCard(
    LoveTestResult mine,
    LoveTestResult theirs,
    LovePairInsight pair,
  ) {
    String line(LoveFacet facet) =>
        '${facet.title}: ${mine.of(facet)} · ${theirs.of(facet)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: _cs.secondaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr('Где сошлись', 'Closest'),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _cs.onSecondaryContainer,
            ),
          ),
          Text(line(pair.closest),
              style: TextStyle(color: _cs.onSecondaryContainer)),
          const SizedBox(height: 12),
          Text(
            _tr('Где разошлись', 'Widest gap'),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _cs.onSecondaryContainer,
            ),
          ),
          Text(line(pair.widest),
              style: TextStyle(color: _cs.onSecondaryContainer)),
        ],
      ),
    );
  }
}
