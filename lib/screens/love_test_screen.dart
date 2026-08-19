import 'dart:math';

import 'package:flutter/material.dart';

import '../models/love_test.dart';
import '../dict_strings.dart';
import '../services/love_test_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../widgets/common/m3_loading.dart';
import '../widgets/love/love_shape.dart';

/// «Умение любить»: двадцать утверждений из банка на восемьдесят, шесть
/// граней, одна фигура.
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

  /// Набор этого прохождения. Утверждения тянутся из банка случайно, поэтому
  /// второй раз человек отвечает про себя, а не вспоминает прошлые ответы.
  List<LoveQuestion> _round = const [];

  /// Что он видел в прошлый раз — эти утверждения уступают место свежим.
  Set<String> _lastRound = const {};

  /// Прошлый результат: с ним сравниваем свежий.
  LoveTestResult? _previous;
  LoveProgress? _progress;
  bool _saving = false;

  AppTheme get _t => widget.theme;
  ColorScheme get _cs => ProfileTheme.themeFor(_t).colorScheme;


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
      _lastRound = pair.myLastRound;
      _previous = pair.myPrevious;
      _progress = pair.mine == null ? null : loveProgress(pair.mine!, _previous);
      _stage = pair.mine == null ? _Stage.intro : _Stage.result;
    });
  }

  /// Собирает новый набор и переводит экран к вопросам.
  void _startQuiz() {
    setState(() {
      _answers.clear();
      _index = 0;
      _round = pickLoveRound(random: Random(), exclude: _lastRound);
      _stage = _Stage.quiz;
    });
  }

  void _answer(int weight) {
    _answers[_index] = weight;
    if (_index + 1 < _round.length) {
      setState(() => _index++);
      return;
    }
    _finish();
  }

  Future<void> _finish() async {
    final result = scoreLoveRound(_round, _answers);
    if (result == null) return;
    final keys = [for (final q in _round) q.key];
    setState(() {
      _progress = loveProgress(result, _mine);
      _previous = _mine;
      _mine = result;
      _lastRound = keys.toSet();
      _stage = _Stage.result;
      _saving = true;
    });
    final saved = await LoveTestService.instance.save(
      widget.groupId,
      widget.myUid,
      result,
      roundKeys: keys,
    );
    if (!mounted) return;
    if (!saved) {
      // Отказ сервера проходил молча: человек видел свою фигуру, закрывал
      // приложение и обнаруживал, что тест снова непройден.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(trKey('love_not_saved')),
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
            trKey('love_title'),
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
            trKey('love_intro'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: _cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _startQuiz,
            child: Text(trKey('love_start')),
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
    final q = _round[_index];
    final progress = (_index + 1) / _round.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                trKey('love_progress')
                    .replaceAll('{n}', '${_index + 1}')
                    .replaceAll('{total}', '${_round.length}'),
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

  /// Вариант ответа — залитая таблетка во всю ширину, без обводки.
  ///
  /// Обводка вокруг залитой поверхности в M3 не ставится: роль контейнера уже
  /// отделяет кнопку от фона, а рамка поверх заливки читается как поле ввода.
  Widget _answerButton(String label, int weight) {
    return Material(
      color: _cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _answer(weight),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                  '${trKey('love_you')} ${mine.total} · '
                  '${widget.partnerName.isEmpty ? trKey('love_partner') : widget.partnerName} ${theirs.total}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _cs.onPrimaryContainer,
                  ),
                )
              else
                Text(
                  trKey('love_strongest')
                      .replaceAll('{facet}', mine.strongest.title.toLowerCase()),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _cs.onPrimaryContainer.withValues(alpha: .85),
                  ),
                ),
            ],
          ),
        ),
        if (_progress != null && _progress!.moved) ...[
          const SizedBox(height: 14),
          _progressCard(_progress!),
        ],
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
              trKey('love_saving'),
              style: TextStyle(color: _cs.onSurfaceVariant),
            ),
          ),
        ],
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: _startQuiz,
          child: Text(trKey('love_retake')),
        ),
      ],
    );
  }

  /// Что изменилось с прошлого раза.
  ///
  /// Показываем только когда есть с чем сравнивать и хоть что-то сдвинулось:
  /// строка «выросло на 0» ничего не сообщает, а место занимает.
  Widget _progressCard(LoveProgress p) {
    final grown = p.deltaOf(p.grown);
    final fallen = p.deltaOf(p.fallen);
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
            trKey('love_since_last')
                .replaceAll('{date}', _shortDate(p.since))
                .toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: _cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                _signed(p.totalDelta),
                style: TextStyle(
                  fontFamily: 'Unbounded',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _deltaColor(p.totalDelta),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trKey('love_total_change'),
                  style: TextStyle(color: _cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final facet in LoveFacet.values) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    facet.title,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                Text(
                  _signed(p.deltaOf(facet)),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _deltaColor(p.deltaOf(facet)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (grown > 0) ...[
            const SizedBox(height: 4),
            Text(
              trKey('love_grown').replaceAll(
                '{facet}',
                p.grown.title.toLowerCase(),
              ),
              style: TextStyle(color: _cs.onSurfaceVariant),
            ),
          ],
          if (fallen < 0) ...[
            const SizedBox(height: 6),
            Text(
              trKey('love_fallen').replaceAll(
                '{facet}',
                p.fallen.title.toLowerCase(),
              ),
              style: TextStyle(color: _cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  String _signed(int value) => value > 0 ? '+$value' : '$value';

  Color _deltaColor(int value) {
    if (value > 0) return _cs.primary;
    if (value < 0) return _cs.error;
    return _cs.onSurfaceVariant;
  }

  String _shortDate(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}.${at.month.toString().padLeft(2, '0')}.${at.year}';

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
            trKey('love_six_facets').toUpperCase(),
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
            trKey('love_closest'),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _cs.onSecondaryContainer,
            ),
          ),
          Text(line(pair.closest),
              style: TextStyle(color: _cs.onSecondaryContainer)),
          const SizedBox(height: 12),
          Text(
            trKey('love_widest'),
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
