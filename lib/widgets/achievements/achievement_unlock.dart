import 'dart:async';

import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/pair_achievement.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import 'achievement_art.dart';
import 'achievement_sheet.dart';

/// Чем показать только что полученное достижение.
enum UnlockSurface {
  /// Нижний лист: человек на главной, прерывать нечего.
  sheet,

  /// Островок у верхнего края: человек в чате, рисует или смотрит ролик, и
  /// лист оборвал бы дело.
  island,
}

UnlockSurface unlockSurfaceFor({required bool homeOnTop}) =>
    homeOnTop ? UnlockSurface.sheet : UnlockSurface.island;

/// Момент получения достижения.
///
/// До 12.10.2026 это был попап по центру экрана с затемнением, градиентной
/// медалью, эмодзи и дождём конфетти поверх любого экрана. Теперь — нижний
/// лист на главной и островок на остальных экранах. Достижения, пришедшие
/// разом, собираются в пачку и идут по очереди со счётчиком «1 из 3».
abstract final class AchievementUnlock {
  static const Key islandKey = ValueKey('achievement-island');

  /// Сколько островок висит, прежде чем уйти сам.
  static const Duration islandStay = Duration(seconds: 5);

  /// Достижения одного пересчёта приходят подряд в пределах кадра: ждём
  /// столько, чтобы собрать их в одну пачку.
  static const Duration _gatherFor = Duration(milliseconds: 60);

  static final List<PairAchievement> _pending = [];
  static Timer? _gather;
  static bool _busy = false;
  static OverlayEntry? _island;

  static void show(
    BuildContext context,
    PairAchievement achievement, {
    required bool Function() homeOnTop,
    required AchievementStats Function() stats,
    VoidCallback? onSeeAll,
  }) {
    _pending.add(achievement);
    _gather ??= Timer(_gatherFor, () {
      _gather = null;
      unawaited(_present(context, homeOnTop, stats, onSeeAll));
    });
  }

  static Future<void> _present(
    BuildContext context,
    bool Function() homeOnTop,
    AchievementStats Function() stats,
    VoidCallback? onSeeAll,
  ) async {
    if (_busy) return;
    _busy = true;
    try {
      while (_pending.isNotEmpty) {
        if (!context.mounted) return;
        final batch = List<PairAchievement>.of(_pending);
        _pending.clear();
        if (unlockSurfaceFor(homeOnTop: homeOnTop()) == UnlockSurface.island) {
          final opened = await _showIsland(context, batch);
          if (!opened) continue;
        }
        if (!context.mounted) return;
        await _showSheets(context, batch, stats, onSeeAll);
      }
    } finally {
      _busy = false;
    }
  }

  static Future<void> _showSheets(
    BuildContext context,
    List<PairAchievement> batch,
    AchievementStats Function() stats,
    VoidCallback? onSeeAll,
  ) async {
    for (var i = 0; i < batch.length; i++) {
      if (!context.mounted) return;
      final goOn = await showAchievementSheet(
        context,
        batch[i],
        stats: stats(),
        fresh: true,
        position: i + 1,
        total: batch.length,
        onSeeAll: onSeeAll,
      );
      // Лист смахнули — человеку сейчас не до этого, остальные не навязываем:
      // они уже лежат на экране достижений.
      if (goOn != true) return;
    }
  }

  /// Показывает островок. true — человек нажал на него и ждёт лист.
  static Future<bool> _showIsland(
    BuildContext context,
    List<PairAchievement> batch,
  ) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return Future.value(false);
    final theme = context.appTheme;
    final done = Completer<bool>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _AchievementIsland(
        theme: theme,
        first: batch.first,
        more: batch.length - 1,
        onGone: (opened) {
          if (_island == entry) _island = null;
          entry.remove();
          if (!done.isCompleted) done.complete(opened);
        },
      ),
    );
    _island = entry;
    overlay.insert(entry);
    return done.future;
  }

  /// Сброс между тестами: состояние у очереди общее на всё приложение.
  @visibleForTesting
  static void debugReset() {
    _gather?.cancel();
    _gather = null;
    _pending.clear();
    _busy = false;
    _island?.remove();
    _island = null;
  }
}

/// Островок достижения: рисунок, подпись, название и «Открыть».
///
/// Стоит у верхнего края, а не над нижней панелью: на экранах, где он
/// появляется, внизу поле ввода и клавиатура.
class _AchievementIsland extends StatefulWidget {
  const _AchievementIsland({
    required this.theme,
    required this.first,
    required this.more,
    required this.onGone,
  });

  final AppTheme theme;
  final PairAchievement first;

  /// Сколько ещё достижений в пачке, кроме [first].
  final int more;
  final void Function(bool opened) onGone;

  @override
  State<_AchievementIsland> createState() => _AchievementIslandState();
}

class _AchievementIslandState extends State<_AchievementIsland>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: Motion.entrance,
    reverseDuration: Motion.nudge,
  );
  Timer? _stay;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _slide.forward();
    _stay = Timer(AchievementUnlock.islandStay, () => _leave(false));
  }

  @override
  void dispose() {
    _stay?.cancel();
    _slide.dispose();
    super.dispose();
  }

  Future<void> _leave(bool opened) async {
    if (_leaving) return;
    _leaving = true;
    _stay?.cancel();
    await _slide.reverse();
    if (mounted) widget.onGone(opened);
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(widget.theme);
    final s = LocaleService.current;
    final top = MediaQuery.maybePaddingOf(context)?.top ?? 0;
    final label = TextStyle(
      fontFamily: 'Onest',
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: cs.inversePrimary,
    );

    return Positioned(
      left: 14,
      right: 14,
      top: top + 8,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.8),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _slide, curve: Motion.emphasizedIn),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              key: AchievementUnlock.islandKey,
              color: cs.inverseSurface,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _leave(true),
                child: GestureDetector(
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) < -80) _leave(false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    child: Row(
                      children: [
                        AchievementArt(widget.first, side: 48),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.more > 0
                                    ? '${s.achievementUnlocked} +${widget.more}'
                                    : s.achievementUnlocked,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Onest',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onInverseSurface.withValues(
                                    alpha: 0.72,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.first.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Onest',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onInverseSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: ShapeDecoration(
                            color: cs.onInverseSurface.withValues(alpha: 0.1),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(trKey('islandOpen'), style: label),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
