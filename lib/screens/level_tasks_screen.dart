import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/level.dart';
import '../models/mascot.dart';
import '../services/catalog_service.dart';
import '../services/level_service.dart';
import '../services/locale_service.dart';

/// Экран «Уровень и задания»: прогресс пары, что даёт XP и какие маскоты
/// открываются на каких уровнях. Данные — целиком из [LevelService] и
/// [CatalogService], новых источников не требуется.
class LevelTasksScreen extends StatefulWidget {
  final Color accent;
  final Color accentLight;

  const LevelTasksScreen({
    super.key,
    required this.accent,
    required this.accentLight,
  });

  @override
  State<LevelTasksScreen> createState() => _LevelTasksScreenState();
}

class _LevelTasksScreenState extends State<LevelTasksScreen> {
  /// Прогресс за сегодня по каждому действию (зачтено раз).
  final Map<XpAction, int> _progress = {};

  bool _ru = true;

  @override
  void initState() {
    super.initState();
    _ru = LocaleService.instance.isRussian;
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final svc = LevelService.instance;
    for (final a in svc.actions) {
      _progress[a] = await svc.progressToday(a);
    }
    if (mounted) setState(() {});
  }

  // ── Метаданные заданий (иконка + название) ─────────────────────────────────

  ({IconData icon, String title}) _taskMeta(XpAction a) {
    switch (a) {
      case XpAction.dailyStreak:
        return (
          icon: Icons.local_fire_department_rounded,
          title: _ru ? 'Заходите в приложение каждый день' : 'Open the app every day',
        );
      case XpAction.addMemory:
        return (
          icon: Icons.photo_library_rounded,
          title: _ru ? 'Добавляйте воспоминания' : 'Add memories',
        );
      case XpAction.watchTogether:
        return (
          icon: Icons.smart_display_rounded,
          title: _ru ? 'Смотрите видео вместе' : 'Watch videos together',
        );
      case XpAction.setWidget:
        return (
          icon: Icons.widgets_rounded,
          title: _ru ? 'Поставьте виджет на экран' : 'Add the home screen widget',
        );
      case XpAction.changeMood:
        return (
          icon: Icons.mood_rounded,
          title: _ru ? 'Отмечайте настроение' : 'Track your mood',
        );
    }
  }

  String _limitLabel(XpAction a) {
    final svc = LevelService.instance;
    final reward = '+${svc.rewardFor(a)} XP';
    if (svc.isOnceEver(a)) return '$reward · ${_ru ? 'разово' : 'one-time'}';
    final cap = svc.dailyCapFor(a);
    if (cap > 0) return '$reward · ${_ru ? '$cap/день' : '$cap/day'}';
    return reward;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _ru ? 'Уровень и задания' : 'Level & tasks',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: AnimatedBuilder(
        animation: LevelService.instance,
        builder: (context, _) {
          final p = LevelService.instance.progress;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _buildHeader(p),
              const SizedBox(height: 24),
              _sectionTitle(_ru ? 'Задания — как растить уровень' : 'Tasks — how to level up'),
              const SizedBox(height: 10),
              ...LevelService.instance.actions.map(_buildTaskTile),
              const SizedBox(height: 24),
              _sectionTitle(_ru ? 'Награды — маскоты' : 'Rewards — mascots'),
              const SizedBox(height: 10),
              _buildRewards(p.level),
            ],
          );
        },
      ),
    );
  }

  // ── Header: уровень, ранг, полоса XP ───────────────────────────────────────

  Widget _buildHeader(LevelProgress p) {
    final color = p.rank.color;
    final toNext = p.xpForNext - p.xpIntoLevel;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2.5),
                ),
                child: Text(
                  '${p.level}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _ru ? 'Уровень ${p.level}' : 'Level ${p.level}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      p.rank.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: p.progress,
              minHeight: 10,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _ru
                ? 'До уровня ${p.level + 1}: ещё $toNext XP'
                : '$toNext XP to level ${p.level + 1}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
      );

  // ── Задание ────────────────────────────────────────────────────────────────

  Widget _buildTaskTile(XpAction a) {
    final meta = _taskMeta(a);
    final svc = LevelService.instance;
    final done = _progress[a] ?? 0;
    final cap = svc.isOnceEver(a) ? 1 : svc.dailyCapFor(a);
    final complete = cap > 0 && done >= cap;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.accentLight,
              shape: BoxShape.circle,
            ),
            child: Icon(meta.icon, size: 20, color: widget.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _limitLabel(a),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          if (complete)
            Icon(Icons.check_circle_rounded, color: Colors.green.shade400, size: 22)
          else if (cap > 1)
            Text(
              '$done/$cap',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
              ),
            ),
        ],
      ),
    );
  }

  // ── Награды (маскоты из каталога) ────────────────────────────────────────────

  Widget _buildRewards(int level) {
    final mascots = CatalogService.instance.mascots
        .where((m) => m.unlock.type == UnlockType.level)
        .toList()
      ..sort((a, b) =>
          a.unlock.requiredLevel.compareTo(b.unlock.requiredLevel));

    if (mascots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text(
          _ru
              ? 'Награды загружаются…'
              : 'Rewards are loading…',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
      );
    }

    return Column(
      children: [for (final m in mascots) _buildRewardTile(m, level)],
    );
  }

  Widget _buildRewardTile(Mascot m, int level) {
    final req = m.unlock.requiredLevel;
    final unlocked = level >= req;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Opacity(
              opacity: unlocked ? 1.0 : 0.4,
              child: m.catalogUrl != null
                  ? CachedNetworkImage(
                      imageUrl: m.catalogUrl!,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.face, color: Colors.grey),
                    )
                  : const Icon(Icons.face, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              m.localizedName,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (unlocked)
            Icon(Icons.check_circle_rounded, color: Colors.green.shade400, size: 22)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 13, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    _ru ? 'Ур. $req' : 'Lv $req',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
