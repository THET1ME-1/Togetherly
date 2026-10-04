import 'package:flutter/material.dart';

import '../../models/reels_source.dart';
import '../../services/locale_service.dart';
import '../app_sheet.dart';

/// Лист перед «Лентами вдвоём»: откуда смотреть. Возвращает выбранную
/// площадку или null, если лист закрыли. Макет — шаг 2 артефакта «Ленты
/// вдвоём». Значки — настоящие иконки приложений площадок
/// (`assets/images/reels/`).
Future<ReelsSource?> showReelsStartSheet(BuildContext context) {
  return showAppSheet<ReelsSource>(context, builder: (_) => const _ReelsStartSheet());
}

class _ReelsStartSheet extends StatefulWidget {
  const _ReelsStartSheet();

  @override
  State<_ReelsStartSheet> createState() => _ReelsStartSheetState();
}

class _ReelsStartSheetState extends State<_ReelsStartSheet> {
  ReelsSource _picked = ReelsSource.shorts;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;
    return SheetScaffold(
      title: s.reelsStartTitle,
      bottom: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_picked),
          icon: const Icon(Icons.swipe_up_rounded),
          label: Text(s.reelsStartWatch),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                s.reelsTogetherHint,
                style: TextStyle(fontFamily: 'Onest', fontSize: 14, height: 1.35, color: cs.onSurfaceVariant),
              ),
            ),
            for (final src in ReelsSource.values) ...[
              _SourceRow(source: src, picked: src == _picked, onTap: () => setState(() => _picked = src)),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.picked, required this.onTap});

  final ReelsSource source;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;
    final fg = picked ? cs.onPrimaryContainer : cs.onSurface;
    return Material(
      color: picked ? cs.primaryContainer : cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Image.asset(source.icon, width: 40, height: 40, filterQuality: FilterQuality.medium),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      style: TextStyle(fontFamily: 'Onest', fontSize: 15, fontWeight: FontWeight.w700, color: fg),
                    ),
                    Text(
                      source == ReelsSource.tiktok ? s.reelsTiktokHint : s.reelsShortsHint,
                      style: TextStyle(fontFamily: 'Onest', fontSize: 12.5, color: fg.withValues(alpha: .75)),
                    ),
                  ],
                ),
              ),
              if (picked) Icon(Icons.check_rounded, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
