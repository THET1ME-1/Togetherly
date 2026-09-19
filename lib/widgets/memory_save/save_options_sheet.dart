import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/memory_media.dart';
import '../../services/locale_service.dart';
import '../../services/saved_media_ledger.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';

enum SaveChoice { all, photos, videos, pick, cover }

/// «5 сентября 2026» на языке приложения.
String memoryDateLabel(DateTime d) {
  final s = LocaleService.current;
  return '${d.day} ${s.cycleMonthsGenitive[d.month - 1]} ${d.year}';
}

/// Лист «Что сохранить» — правая часть разделённой кнопки.
///
/// Пункт показывается, только если ему есть что сохранить: у записи без
/// ролика нет «Только видео», у одного кадра нет «Выбрать кадры» и «Только
/// обложку».
Future<SaveChoice?> showSaveOptionsSheet(
  BuildContext context, {
  required ColorScheme scheme,
  required List<MediaFile> files,
  required String title,
  required DateTime takenAt,
}) async {
  final ledger = SavedMediaLedger.instance;
  await ledger.load();
  if (!context.mounted) return null;
  final all = summarizeMedia(files);
  final photos = files.where((f) => f.kind == SaveKind.photo).toList();
  final videos = files.where((f) => f.kind == SaveKind.video).toList();
  final saved = ledger.countSaved(files);

  String counts(MediaSummary s) => [
        if (s.photos > 0) trKey('saveCountPhotos').replaceAll('{n}', '${s.photos}'),
        if (s.videos > 0) trKey('saveCountVideos').replaceAll('{n}', '${s.videos}'),
        if (s.audio > 0) trKey('saveCountAudio').replaceAll('{n}', '${s.audio}'),
      ].join(' · ');

  return showAppSheet<SaveChoice>(
    context,
    background: scheme.surfaceContainerLow,
    builder: (ctx) {
      Widget row(
        SaveChoice c,
        IconData icon,
        String label,
        String sub, {
        String? count,
        bool accent = false,
        bool chevron = false,
      }) =>
          _OptionTile(
            icon: icon,
            label: label,
            sub: sub,
            count: count,
            accent: accent,
            chevron: chevron,
            onTap: () => Navigator.of(ctx).pop(c),
          );

      return Theme(
        data: ProfileTheme.data(scheme),
        child: SheetScaffold(
          title: trKey('saveSheetTitle'),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  [
                    title,
                    trKey('saveApproxMb').replaceAll('{n}', '${all.megabytes}'),
                    if (saved > 0) trKey('saveAlreadyIn').replaceAll('{n}', '$saved'),
                  ].where((e) => e.isNotEmpty).join(' · '),
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                row(SaveChoice.all, Icons.done_all_rounded, trKey('saveOptAll'),
                    counts(all),
                    count: '${files.length}', accent: true),
                if (photos.isNotEmpty && videos.isNotEmpty) ...[
                  row(
                    SaveChoice.photos,
                    Icons.photo_rounded,
                    trKey('saveOptPhotos'),
                    trKey('saveApproxMb').replaceAll(
                        '{n}', '${summarizeMedia(photos).megabytes}'),
                    count: '${photos.length}',
                  ),
                  row(
                    SaveChoice.videos,
                    Icons.videocam_rounded,
                    trKey('saveOptVideos'),
                    trKey('saveApproxMb').replaceAll(
                        '{n}', '${summarizeMedia(videos).megabytes}'),
                    count: '${videos.length}',
                  ),
                ],
                if (files.length > 1)
                  row(SaveChoice.pick, Icons.checklist_rounded,
                      trKey('saveOptPick'), trKey('saveOptPickSub'),
                      chevron: true),
                if (photos.length > 1)
                  row(SaveChoice.cover, Icons.image_rounded,
                      trKey('saveOptCover'), trKey('saveOptCoverSub'),
                      count: '1'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.calendar_month_rounded,
                        size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        trKey('saveDateNote')
                            .replaceAll('{date}', memoryDateLabel(takenAt)),
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
    this.count,
    this.accent = false,
    this.chevron = false,
  });

  final IconData icon;
  final String label;
  final String sub;
  final String? count;
  final bool accent;
  final bool chevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: accent ? cs.primaryContainer : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent ? cs.primary : cs.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon,
                      size: 20,
                      color: accent ? cs.onPrimary : cs.onSecondaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      if (sub.isNotEmpty)
                        Text(
                          sub,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (count != null)
                  Text(
                    count!,
                    style: TextStyle(
                      fontFamily: 'Unbounded',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                if (chevron)
                  Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
