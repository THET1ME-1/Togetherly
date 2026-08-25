import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/mood_entry.dart';
import '../services/couple_stats_service.dart';
import '../services/locale_service.dart';
import '../services/plus_access.dart';
import '../services/plus_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../utils/couple_days.dart';
import '../utils/memory_type_label.dart';
import '../utils/relationship_tips.dart';
import '../widgets/common/m3_loading.dart';
import 'plus_screen.dart';

/// Полная статистика пары: итоги, динамика за год, сравнение участников,
/// ритмы, настроения и прогнозы.
///
/// Все числа приходят одним ответом `/api/couple/stats` — сервер считает их
/// агрегатами SQL. Здесь только раскладка и графики: если считать заново на
/// клиенте, экран разойдётся с достижениями и виджетами, а это дороже любой
/// красивой метрики.
///
/// Подписи разделов живут прямо здесь, а не в `LocaleService`: они нужны
/// только этому экрану, а два языка держит короткая пара строк рядом с местом
/// использования — искать их по общему словарю из тысячи геттеров дольше.
class CoupleStatsScreen extends StatefulWidget {
  const CoupleStatsScreen({
    super.key,
    required this.theme,
    required this.groupId,
    required this.myUid,
    this.startDate,
    this.anniversaryDate,
  });

  final AppTheme theme;
  final String groupId;
  final String myUid;
  final DateTime? startDate;
  final DateTime? anniversaryDate;

  @override
  State<CoupleStatsScreen> createState() => _CoupleStatsScreenState();
}

class _CoupleStatsScreenState extends State<CoupleStatsScreen> {
  CoupleStats? _stats;
  bool _loading = true;

  AppTheme get _t => widget.theme;
  ColorScheme get _cs => ProfileTheme.themeFor(_t).colorScheme;
  bool get _ru => LocaleService.instance.isRussian;

  String _tr(String ru, String en) => _ru ? ru : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final data = await CoupleStatsService.load(widget.groupId, force: force);
    if (!mounted) return;
    setState(() {
      _stats = data;
      _loading = false;
    });
  }

  // ── Данные ────────────────────────────────────────────────────────────────

  String get _partnerUid {
    final s = _stats;
    if (s == null) return '';
    for (final uid in s.members.keys) {
      if (uid != widget.myUid) return uid;
    }
    return '';
  }

  String _nameOf(String uid) {
    final n = _stats?.members[uid] ?? '';
    if (n.trim().isNotEmpty) return n.trim();
    return uid == widget.myUid ? _tr('Вы', 'You') : _tr('Партнёр', 'Partner');
  }

  /// Оценка настроения 1…5 по каталогу — тем же способом, что считают
  /// достижения. Настроение из пака, которого нет, даёт нейтральную тройку.
  int _score(String moodId) {
    for (final m in MoodOption.all) {
      if (m.id == moodId) return m.score;
    }
    for (final m in MoodOption.pinkPack) {
      if (m.id == moodId) return m.score;
    }
    return 3;
  }

  String _moodLabel(String moodId) {
    for (final m in MoodOption.all) {
      if (m.id == moodId) return m.localizedLabel;
    }
    for (final m in MoodOption.pinkPack) {
      if (m.id == moodId) return m.localizedLabel;
    }
    return moodId;
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      backgroundColor: _cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _tr('Статистика пары', 'Couple stats'),
          style: TextStyle(
            fontFamily: ProfileTheme.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _cs.onSurface,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _tr('Обновить', 'Refresh'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _loading = true);
              _load(force: true);
            },
          ),
        ],
      ),
      body: _loading
          ? M3PageLoading(color: _t.primaryLight)
          : s == null
              ? _empty()
              : RefreshIndicator(
                  onRefresh: () => _load(force: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                    children: _sections(s),
                  ),
                ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _tr('Пока нечего показать — данные появятся, когда вы начнёте вести дневник вдвоём.',
                'Nothing to show yet — stats appear once you start together.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontSize: 15,
              color: _cs.onSurfaceVariant,
            ),
          ),
        ),
      );

  List<Widget> _sections(CoupleStats s) => [
        _hero(s),
        const SizedBox(height: 16),
        _totalsGrid(s),
        const SizedBox(height: 16),
        _yearChart(s),
        const SizedBox(height: 16),
        _versus(s),
        const SizedBox(height: 16),
        _weekRhythm(s),
        const SizedBox(height: 16),
        _dayRhythm(s),
        const SizedBox(height: 16),
        _moodTrend(s),
        const SizedBox(height: 16),
        _moodFavourites(s),
        const SizedBox(height: 16),
        _memoryTypes(s),
        const SizedBox(height: 16),
        _forecast(s),
        const SizedBox(height: 16),
        _tips(s),
      ];

  // ── 11. Советы ────────────────────────────────────────────────────────────

  Widget _tips(CoupleStats s) {
    final latest = <String, String>{};
    for (final p in s.moodDaily) {
      if (p.day == null) continue;
      latest.putIfAbsent(p.uid, () => p.moodId);
    }
    final tips = RelationshipTips.forToday(TipContext(
      myMoodScore: latest[widget.myUid] == null
          ? null
          : _score(latest[widget.myUid]!),
      partnerMoodScore:
          latest[_partnerUid] == null ? null : _score(latest[_partnerUid]!),
      daysTogether: coupleDaysTogether(
        groupStart: widget.startDate ?? s.startDate,
        anniversary: widget.anniversaryDate,
        timerStart: null,
      ),
      daysToAnniversary: _daysToAnniversary(),
    ));
    if (tips.isEmpty) return const SizedBox.shrink();

    return _card(
      title: _tr('Советы на сегодня', 'Tips for today'),
      subtitle: _tr('Подобраны по вашим числам', 'Picked from your numbers'),
      child: Column(
        children: [
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    decoration: BoxDecoration(
                      color: _cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tip.title,
                          style: TextStyle(
                            fontFamily: ProfileTheme.displayFont,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _cs.onSurface,
                          ),
                        ),
                        Text(
                          tip.body,
                          style: TextStyle(
                            fontFamily: ProfileTheme.bodyFont,
                            fontSize: 12.5,
                            height: 1.35,
                            color: _cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Общие кирпичи ─────────────────────────────────────────────────────────

  Widget _card({
    required String title,
    String? subtitle,
    required Widget child,
    Widget? legend,
  }) =>
      Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: _cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _cs.onSurface,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 12.5,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ],
            if (legend != null) ...[const SizedBox(height: 10), legend],
            const SizedBox(height: 14),
            child,
          ],
        ),
      );

  Widget _legendRow(List<(String, Color)> items) => Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          for (final (label, color) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
        ],
      );

  TextStyle get _axisStyle => TextStyle(
        fontFamily: ProfileTheme.bodyFont,
        fontSize: 10,
        color: _cs.onSurfaceVariant,
      );

  FlGridData _grid(double interval) => FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval <= 0 ? 1 : interval,
        getDrawingHorizontalLine: (_) => FlLine(
          color: _cs.outlineVariant,
          strokeWidth: 1,
          dashArray: const [5, 6],
        ),
      );

  // ── 1. Шапка ──────────────────────────────────────────────────────────────

  Widget _hero(CoupleStats s) {
    final days = coupleDaysTogether(
          groupStart: widget.startDate ?? s.startDate,
          anniversary: widget.anniversaryDate,
          timerStart: null,
        ) ??
        0;

    Widget chip(IconData icon, String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: _cs.surface.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: _cs.onPrimaryContainer),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: _cs.onPrimaryContainer,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 11.5,
                    color: _cs.onPrimaryContainer.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cs.primaryContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$days',
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 54,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -2,
              color: _cs.onPrimaryContainer,
            ),
          ),
          Text(
            _tr('Дней вместе', 'Days together'),
            style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _cs.onPrimaryContainer.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              chip(Icons.local_fire_department_rounded, '${s.streak}',
                  _tr('Дней подряд', 'Day streak')),
              const SizedBox(width: 10),
              chip(Icons.auto_awesome_rounded, '${s.xp}',
                  _tr('Опыта пары', 'Couple XP')),
              const SizedBox(width: 10),
              chip(Icons.event_available_rounded, '${_daysToAnniversary()}',
                  _tr('До годовщины', 'To anniversary')),
            ],
          ),
        ],
      ),
    );
  }

  int _daysToAnniversary() {
    final date = widget.anniversaryDate ?? widget.startDate ?? _stats?.startDate;
    if (date == null) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var next = DateTime(now.year, date.month, date.day);
    if (next.isBefore(today)) next = DateTime(now.year + 1, date.month, date.day);
    return next.difference(today).inDays;
  }

  // ── 2. Итоги ──────────────────────────────────────────────────────────────

  Widget _totalsGrid(CoupleStats s) {
    final items = <(IconData, int, String)>[
      (Icons.photo_library_rounded, s.total('memories'), _tr('Воспоминаний', 'Memories')),
      (Icons.image_rounded, s.total('photos'), _tr('Фотографий', 'Photos')),
      (Icons.videocam_rounded, s.total('videos'), _tr('Видео', 'Videos')),
      (Icons.forum_rounded, s.total('messages'), _tr('Сообщений', 'Messages')),
      (Icons.mood_rounded, s.total('moods'), _tr('Отметок настроения', 'Mood marks')),
      (Icons.favorite_rounded, s.total('missYou'), _tr('«Скучаю»', 'Miss-yous')),
      (Icons.brush_rounded, s.total('strokes'), _tr('Штрихов на холсте', 'Brush strokes')),
      (Icons.comment_rounded, s.total('comments'), _tr('Комментариев', 'Comments')),
      (Icons.card_giftcard_rounded, s.total('gifts'), _tr('Подарков', 'Gifts')),
      (Icons.pets_rounded, s.total('mascots'), _tr('Маскотов', 'Mascots')),
      (Icons.play_circle_rounded, s.total('watch'), _tr('Совместных включений', 'Watch sessions')),
      (Icons.palette_rounded, s.total('canvases'), _tr('Холстов', 'Canvases')),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth > 520 ? 4 : 3;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.92,
          children: [
            for (final (icon, value, label) in items)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, size: 18, color: _cs.primary),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _compact(value),
                          style: TextStyle(
                            fontFamily: ProfileTheme.displayFont,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            color: _cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: ProfileTheme.bodyFont,
                            fontSize: 11,
                            height: 1.15,
                            color: _cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _compact(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '$v';
  }

  // ── 3. Год по месяцам ─────────────────────────────────────────────────────

  Widget _yearChart(CoupleStats s) {
    final months = <String>{
      ...s.timeline['memories']!.keys,
      ...s.timeline['messages']!.keys,
      ...s.timeline['moods']!.keys,
    }.toList()
      ..sort();

    if (months.isEmpty) {
      return _card(
        title: _tr('Год вместе', 'The year together'),
        child: _noData(),
      );
    }

    // Сообщения на порядок многочисленнее воспоминаний, поэтому ряд приведён
    // к общей шкале долей: две оси на одном графике врали бы о сравнении.
    double maxOf(String key) {
      final v = s.timeline[key]!.values;
      return v.isEmpty ? 0 : v.reduce(math.max).toDouble();
    }

    final maxMem = math.max(1.0, maxOf('memories'));
    final maxMsg = math.max(1.0, maxOf('messages'));
    final maxMood = math.max(1.0, maxOf('moods'));

    List<FlSpot> spots(String key, double norm) => [
          for (var i = 0; i < months.length; i++)
            FlSpot(i.toDouble(), (s.timeline[key]![months[i]] ?? 0) / norm * 100),
        ];

    final colors = [_cs.primary, _cs.tertiary, _cs.secondary];

    return _card(
      title: _tr('Год вместе', 'The year together'),
      subtitle: _tr('Доля от лучшего месяца по каждому ряду',
          'Share of each series best month'),
      legend: _legendRow([
        (_tr('Воспоминания', 'Memories'), colors[0]),
        (_tr('Сообщения', 'Messages'), colors[1]),
        (_tr('Настроения', 'Moods'), colors[2]),
      ]),
      child: SizedBox(
        height: 210,
        child: LineChart(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          LineChartData(
            minY: 0,
            maxY: 108,
            gridData: _grid(25),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: 25,
                  getTitlesWidget: (v, _) =>
                      Text('${v.toInt()}%', style: _axisStyle),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: math.max(1, (months.length / 5).floorToDouble()),
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= months.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(months[i].substring(5), style: _axisStyle),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => _cs.inverseSurface,
                getTooltipItems: (spots) => [
                  for (final spot in spots)
                    LineTooltipItem(
                      _tooltipFor(spot.barIndex, months[spot.x.toInt()], s),
                      TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _cs.onInverseSurface,
                      ),
                    ),
                ],
              ),
            ),
            lineBarsData: [
              for (final (i, key, norm) in [
                (0, 'memories', maxMem),
                (1, 'messages', maxMsg),
                (2, 'moods', maxMood),
              ])
                LineChartBarData(
                  spots: spots(key, norm),
                  isCurved: true,
                  curveSmoothness: 0.25,
                  color: colors[i],
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: months.length <= 8,
                    getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                      radius: 3.5,
                      color: colors[i],
                      strokeWidth: 2,
                      strokeColor: _cs.surfaceContainerLow,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _tooltipFor(int series, String month, CoupleStats s) {
    final key = ['memories', 'messages', 'moods'][series.clamp(0, 2)];
    final label = [
      _tr('Воспоминаний', 'Memories'),
      _tr('Сообщений', 'Messages'),
      _tr('Настроений', 'Moods'),
    ][series.clamp(0, 2)];
    return '$month · ${s.timeline[key]![month] ?? 0} $label';
  }

  // ── 4. Кто сколько ────────────────────────────────────────────────────────

  Widget _versus(CoupleStats s) {
    final partner = _partnerUid;
    final rows = <(String, int, int)>[
      (_tr('Воспоминания', 'Memories'),
          s.forMember('memories', widget.myUid), s.forMember('memories', partner)),
      (_tr('Сообщения', 'Messages'),
          s.forMember('messages', widget.myUid), s.forMember('messages', partner)),
      (_tr('Настроения', 'Moods'),
          s.forMember('moods', widget.myUid), s.forMember('moods', partner)),
      (_tr('«Скучаю»', 'Miss-yous'),
          s.forMember('missYou', widget.myUid), s.forMember('missYou', partner)),
      (_tr('Подарки', 'Gifts'),
          s.forMember('gifts', widget.myUid), s.forMember('gifts', partner)),
    ];

    return _card(
      title: _tr('Кто сколько', 'Side by side'),
      subtitle: _tr('Вклад каждого за всё время', 'Each partner all-time'),
      legend: _legendRow([
        (_nameOf(widget.myUid), _cs.primary),
        (_nameOf(partner), _cs.tertiary),
      ]),
      child: Column(
        children: [
          for (final (label, mine, theirs) in rows) ...[
            _versusRow(label, mine, theirs),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _versusRow(String label, int mine, int theirs) {
    final total = mine + theirs;
    final myShare = total == 0 ? 0.5 : mine / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '$mine',
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _cs.primary,
              ),
            ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              '$theirs',
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _cs.tertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        // Одна полоса на двоих: доля видна без чтения чисел, а пустой случай
        // делится ровно пополам, чтобы не выглядеть победой одного.
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Row(
            children: [
              Expanded(
                flex: math.max(1, (myShare * 1000).round()),
                child: Container(height: 10, color: _cs.primary),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: math.max(1, ((1 - myShare) * 1000).round()),
                child: Container(height: 10, color: _cs.tertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 5. Ритм недели ────────────────────────────────────────────────────────

  Widget _weekRhythm(CoupleStats s) {
    // Сервер отдаёт неделю с воскресенья (strftime('%w')), а читаем мы её с
    // понедельника.
    const order = [1, 2, 3, 4, 5, 6, 0];
    final names = _ru
        ? ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final msg = [for (final d in order) s.weekdayMessages[d]];
    final mem = [for (final d in order) s.weekdayMemories[d]];
    final maxV = math.max(1, [...msg, ...mem].reduce(math.max));

    if (maxV <= 1 && msg.every((v) => v == 0) && mem.every((v) => v == 0)) {
      return _card(title: _tr('Ритм недели', 'Weekly rhythm'), child: _noData());
    }

    return _card(
      title: _tr('Ритм недели', 'Weekly rhythm'),
      subtitle: _tr('В какие дни вы активнее', 'Which days you are busiest'),
      legend: _legendRow([
        (_tr('Сообщения', 'Messages'), _cs.primary),
        (_tr('Воспоминания', 'Memories'), _cs.tertiary),
      ]),
      child: SizedBox(
        height: 190,
        child: BarChart(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          BarChartData(
            maxY: maxV * 1.15,
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: _grid(maxV / 3),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => _cs.inverseSurface,
                getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                  '${names[group.x]} · ${rod.toY.round()}',
                  TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _cs.onInverseSurface,
                  ),
                ),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: math.max(1, (maxV / 3).floorToDouble()),
                  getTitlesWidget: (v, _) =>
                      Text(_compact(v.toInt()), style: _axisStyle),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= names.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(names[i], style: _axisStyle),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < 7; i++)
                BarChartGroupData(
                  x: i,
                  barsSpace: 3,
                  barRods: [
                    BarChartRodData(
                      toY: msg[i].toDouble(),
                      color: _cs.primary,
                      width: 9,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    BarChartRodData(
                      toY: mem[i].toDouble(),
                      color: _cs.tertiary,
                      width: 9,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 6. Часы суток ─────────────────────────────────────────────────────────

  Widget _dayRhythm(CoupleStats s) {
    final hours = s.hourMessages;
    final maxV = math.max(1, hours.reduce(math.max));
    if (hours.every((v) => v == 0)) {
      return _card(title: _tr('Часы суток', 'Hours of the day'), child: _noData());
    }

    final peak = hours.indexOf(maxV);
    final night = hours.sublist(0, 6).fold<int>(0, (a, b) => a + b);
    final total = hours.fold<int>(0, (a, b) => a + b);

    return _card(
      title: _tr('Часы суток', 'Hours of the day'),
      subtitle: _tr(
        'Пик в $peak:00 · ночью с 0 до 6 — ${(night / math.max(1, total) * 100).round()}% сообщений',
        'Peak at $peak:00 · ${(night / math.max(1, total) * 100).round()}% between 0 and 6',
      ),
      child: SizedBox(
        height: 150,
        child: BarChart(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          BarChartData(
            maxY: maxV * 1.15,
            alignment: BarChartAlignment.spaceBetween,
            borderData: FlBorderData(show: false),
            gridData: _grid(maxV / 2),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => _cs.inverseSurface,
                getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                  '${group.x}:00 · ${rod.toY.round()}',
                  TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _cs.onInverseSurface,
                  ),
                ),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: 6,
                  getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${v.toInt()}', style: _axisStyle),
                  ),
                ),
              ),
            ),
            barGroups: [
              for (var h = 0; h < 24; h++)
                BarChartGroupData(
                  x: h,
                  barRods: [
                    BarChartRodData(
                      toY: hours[h].toDouble(),
                      // Один тон, насыщенность по величине: это одна метрика,
                      // разные цвета намекали бы на разные сущности.
                      color: _cs.primary.withValues(
                        alpha: 0.35 + 0.65 * (hours[h] / maxV),
                      ),
                      width: 7,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 7. Настроение ─────────────────────────────────────────────────────────

  Widget _moodTrend(CoupleStats s) {
    final partner = _partnerUid;
    final mine = _dailyAverage(s, widget.myUid);
    final theirs = _dailyAverage(s, partner);
    if (mine.isEmpty && theirs.isEmpty) {
      return _card(title: _tr('Настроение', 'Mood'), child: _noData());
    }

    final days = <DateTime>{...mine.keys, ...theirs.keys}.toList()..sort();
    final first = days.first;

    List<FlSpot> spots(Map<DateTime, double> src) => [
          for (final d in days)
            if (src[d] != null)
              FlSpot(d.difference(first).inDays.toDouble(), src[d]!),
        ];

    final span = math.max(1, days.last.difference(first).inDays);

    return _card(
      title: _tr('Настроение за 90 дней', 'Mood over 90 days'),
      subtitle: _tr('Средняя оценка дня, от 1 до 5', 'Daily average, 1 to 5'),
      legend: _legendRow([
        (_nameOf(widget.myUid), _cs.primary),
        (_nameOf(partner), _cs.tertiary),
      ]),
      child: SizedBox(
        height: 190,
        child: LineChart(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          LineChartData(
            minY: 1,
            maxY: 5,
            minX: 0,
            maxX: span.toDouble(),
            gridData: _grid(1),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  interval: 1,
                  getTitlesWidget: (v, _) =>
                      Text('${v.toInt()}', style: _axisStyle),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: math.max(1, (span / 4).floorToDouble()),
                  getTitlesWidget: (v, _) {
                    final d = first.add(Duration(days: v.toInt()));
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${d.day}.${d.month}', style: _axisStyle),
                    );
                  },
                ),
              ),
            ),
            lineBarsData: [
              for (final (src, color) in [
                (mine, _cs.primary),
                (theirs, _cs.tertiary),
              ])
                LineChartBarData(
                  spots: spots(src),
                  isCurved: true,
                  curveSmoothness: 0.2,
                  color: color,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.08),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// День → средняя оценка настроения этого участника.
  Map<DateTime, double> _dailyAverage(CoupleStats s, String uid) {
    final sum = <DateTime, int>{};
    final count = <DateTime, int>{};
    for (final p in s.moodDaily) {
      if (p.uid != uid || p.day == null) continue;
      final d = DateTime(p.day!.year, p.day!.month, p.day!.day);
      sum[d] = (sum[d] ?? 0) + _score(p.moodId) * p.count;
      count[d] = (count[d] ?? 0) + p.count;
    }
    return {
      for (final d in sum.keys) d: sum[d]! / math.max(1, count[d]!),
    };
  }

  // ── 8. Любимые настроения ─────────────────────────────────────────────────

  Widget _moodFavourites(CoupleStats s) {
    final partner = _partnerUid;
    List<(String, int)> topFor(String uid) {
      final acc = <String, int>{};
      for (final p in s.moodTop) {
        if (p.uid != uid) continue;
        acc[p.moodId] = (acc[p.moodId] ?? 0) + p.count;
      }
      final list = acc.entries.map((e) => (e.key, e.value)).toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));
      return list.take(4).toList();
    }

    final mineTop = topFor(widget.myUid);
    final theirsTop = topFor(partner);
    if (mineTop.isEmpty && theirsTop.isEmpty) {
      return _card(title: _tr('Любимые настроения', 'Favourite moods'), child: _noData());
    }

    Widget column(String name, List<(String, int)> items, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Text('—', style: TextStyle(color: _cs.onSurfaceVariant))
              else
                for (final (id, count) in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _moodLabel(id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: ProfileTheme.bodyFont,
                              fontSize: 12.5,
                              color: _cs.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '$count',
                          style: TextStyle(
                            fontFamily: ProfileTheme.displayFont,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );

    return _card(
      title: _tr('Любимые настроения', 'Favourite moods'),
      subtitle: _tr('Что вы отмечаете чаще всего', 'What you mark most often'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          column(_nameOf(widget.myUid), mineTop, _cs.primary),
          const SizedBox(width: 16),
          column(_nameOf(partner), theirsTop, _cs.tertiary),
        ],
      ),
    );
  }

  // ── 9. Из чего собраны воспоминания ───────────────────────────────────────

  Widget _memoryTypes(CoupleStats s) {
    final entries = s.memoryTypes.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return _card(
          title: _tr('Из чего собраны воспоминания', 'What memories are made of'),
          child: _noData());
    }

    final total = entries.fold<int>(0, (a, e) => a + e.value);
    final palette = [
      _cs.primary,
      _cs.tertiary,
      _cs.secondary,
      _cs.primaryContainer,
      _cs.tertiaryContainer,
    ];

    return _card(
      title: _tr('Из чего собраны воспоминания', 'What memories are made of'),
      subtitle: '$total ${_recordsWord(total)}',
      legend: _legendRow([
        for (var i = 0; i < entries.length && i < palette.length; i++)
          (memoryTypeLabel(entries[i].key), palette[i]),
      ]),
      child: SizedBox(
        height: 180,
        child: PieChart(
          PieChartData(
            sectionsSpace: 3,
            centerSpaceRadius: 46,
            sections: [
              for (var i = 0; i < entries.length; i++)
                PieChartSectionData(
                  value: entries[i].value.toDouble(),
                  color: palette[i % palette.length],
                  radius: 38,
                  title: '${(entries[i].value / total * 100).round()}%',
                  titleStyle: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: i == 0 ? _cs.onPrimary : _cs.onSurface,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 10. Прогнозы ──────────────────────────────────────────────────────────

  Widget _forecast(CoupleStats s) {
    final perWeek = (s.pace['memories30'] ?? 0) / 30 * 7;
    final perDay = (s.pace['memories30'] ?? 0) / 30;
    final memories = s.total('memories');

    // Следующая круглая отметка: сотня, потом полтысячи, потом тысячи.
    int nextRound(int v) {
      if (v < 100) return 100;
      if (v < 500) return 500;
      if (v < 1000) return 1000;
      return ((v ~/ 1000) + 1) * 1000;
    }

    final target = nextRound(memories);
    final left = target - memories;
    final daysToTarget = perDay <= 0 ? null : (left / perDay).ceil();

    // Тренд настроения: последние 30 дней против предыдущих 30.
    final trend = _moodTrendValue(s);

    final activeDays = s.pace['activeDays30'] ?? 0;
    final yearProjection = (perDay * 365).round();

    final items = <(IconData, String, String)>[
      (
        Icons.speed_rounded,
        perWeek < 1
            ? _tr('Меньше одного', 'Under one')
            : perWeek.toStringAsFixed(1),
        _tr('Воспоминаний в неделю сейчас', 'Memories per week now'),
      ),
      (
        Icons.flag_rounded,
        daysToTarget == null
            ? '—'
            : _tr('Через $daysToTarget дн.', 'In $daysToTarget days'),
        _tr('До отметки $target воспоминаний', 'To $target memories'),
      ),
      (
        Icons.trending_up_rounded,
        '$yearProjection',
        _tr('Столько наберётся за год при этом темпе',
            'Projected for a year at this pace'),
      ),
      (
        Icons.calendar_month_rounded,
        '$activeDays ${_tr('из 30', 'of 30')}',
        _tr('Дней с активностью за месяц', 'Active days last month'),
      ),
      (
        trend == null
            ? Icons.remove_rounded
            : trend >= 0.1
                ? Icons.sentiment_satisfied_rounded
                : trend <= -0.1
                    ? Icons.sentiment_dissatisfied_rounded
                    : Icons.sentiment_neutral_rounded,
        trend == null
            ? '—'
            : '${trend > 0 ? '+' : ''}${trend.toStringAsFixed(1)}',
        _tr('Настроение к прошлому месяцу', 'Mood versus last month'),
      ),
    ];

    return _card(
      title: _tr('Что дальше', 'What is next'),
      subtitle: _tr('Прогноз по темпу последних тридцати дней',
          'Projection from the last thirty days'),
      child: Column(
        children: [
          for (final (icon, value, label) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _cs.primaryContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, size: 19, color: _cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontFamily: ProfileTheme.displayFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _cs.onSurface,
                          ),
                        ),
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: ProfileTheme.bodyFont,
                            fontSize: 12,
                            color: _cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Насколько среднее настроение последних тридцати дней отличается от
  /// предыдущих тридцати. null — сравнивать нечего.
  double? _moodTrendValue(CoupleStats s) {
    final now = DateTime.now();
    final edge = now.subtract(const Duration(days: 30));
    final older = now.subtract(const Duration(days: 60));

    var recentSum = 0, recentCount = 0, prevSum = 0, prevCount = 0;
    for (final p in s.moodDaily) {
      final d = p.day;
      if (d == null) continue;
      final score = _score(p.moodId) * p.count;
      if (d.isAfter(edge)) {
        recentSum += score;
        recentCount += p.count;
      } else if (d.isAfter(older)) {
        prevSum += score;
        prevCount += p.count;
      }
    }
    if (recentCount == 0 || prevCount == 0) return null;
    return recentSum / recentCount - prevSum / prevCount;
  }

  /// «44 записи», а не «44 записей»: число рядом со словом склоняется.
  String _recordsWord(int n) {
    if (!_ru) return n == 1 ? 'Entry in total' : 'Entries in total';
    final a = n % 100, b = n % 10;
    if (a >= 11 && a <= 19) return 'Записей всего';
    if (b == 1) return 'Запись всего';
    if (b >= 2 && b <= 4) return 'Записи всего';
    return 'записей всего';
  }

  Widget _noData() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          _tr('Пока пусто', 'Nothing yet'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: ProfileTheme.bodyFont,
            fontSize: 13,
            color: _cs.onSurfaceVariant,
          ),
        ),
      );
}

/// Открывает полную статистику, если куплен Togetherly+, иначе ведёт на его
/// страницу: прятать раздел нельзя, иначе о нём никто не узнает. Там, где
/// Плюса не существует (iOS), вход к некупившему просто не ведёт — ни экрана,
/// ни предложения.
Future<void> openCoupleStats(
  BuildContext context, {
  required AppTheme theme,
  required String groupId,
  required String myUid,
  DateTime? startDate,
  DateTime? anniversaryDate,
}) async {
  switch (PlusService.instance.gate) {
    case PlusGate.hidden:
      return;
    case PlusGate.locked:
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              PlusScreen(scheme: ProfileTheme.themeFor(theme).colorScheme),
          settings: const RouteSettings(name: '/plus'),
        ),
      );
      return;
    case PlusGate.open:
      break;
  }
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => CoupleStatsScreen(
        theme: theme,
        groupId: groupId,
        myUid: myUid,
        startDate: startDate,
        anniversaryDate: anniversaryDate,
      ),
      settings: const RouteSettings(name: '/couple_stats'),
    ),
  );
}
