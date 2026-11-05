import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/rank.dart';
import '../../services/app_time_service.dart';
import '../../theme/profile_theme.dart';
import 'rank_emblem.dart';

/// Экран нового звания: один раз за звание. Отметку «видел» хранит сервер
/// (`/api/user/app-time/seen`), поэтому после переустановки он не повторится.
/// Искру (0) не показываем: с неё начинают все.
Future<void> maybeShowNewRank(BuildContext context) async {
  final s = AppTimeService.instance;
  final rank = rankFor(s.seconds.value, s.hours);
  if (!s.synced || rank <= 0 || rank <= s.rankSeen || _open) return;
  _open = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (ctx) => NewRankDialog(rank: rank, seconds: s.seconds.value),
    );
    await s.markSeen(rank);
  } finally {
    _open = false;
  }
}

bool _open = false;

class NewRankDialog extends StatefulWidget {
  const NewRankDialog({super.key, required this.rank, required this.seconds});

  final int rank;
  final int seconds;

  @override
  State<NewRankDialog> createState() => _NewRankDialogState();
}

class _NewRankDialogState extends State<NewRankDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    // Эмблема выпрыгивает: из маленькой с перелётом к своему размеру.
    final scale = reduce
        ? const AlwaysStoppedAnimation(1.0)
        : TweenSequence<double>([
            TweenSequenceItem(
              tween: Tween(
                begin: 0.3,
                end: 1.12,
              ).chain(CurveTween(curve: Curves.easeOutCubic)),
              weight: 55,
            ),
            TweenSequenceItem(
              tween: Tween(
                begin: 1.12,
                end: 1.0,
              ).chain(CurveTween(curve: Curves.easeInOut)),
              weight: 45,
            ),
          ]).animate(_pop);
    return Dialog(
      backgroundColor: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              trKey('hrankNewTitle').toUpperCase(),
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 13,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 4),
            ScaleTransition(
              scale: scale,
              child: RankEmblem(widget.rank, side: 180),
            ),
            const SizedBox(height: 4),
            Text(
              hourRankName(widget.rank),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              trKey(
                'hrankNewHours',
              ).replaceAll('{0}', hourRankHours(widget.seconds)),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 15,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                minimumSize: const Size(140, 52),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(trKey('hrankNewOk')),
            ),
          ],
        ),
      ),
    );
  }
}
