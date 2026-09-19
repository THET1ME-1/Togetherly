import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/memory.dart';
import '../../models/memory_media.dart';
import '../../services/gallery_writer.dart';
import '../../services/media_save_queue.dart';
import '../../services/media_share.dart';
import '../../services/saved_media_ledger.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import '../common/app_dialog.dart';
import 'save_options_sheet.dart';

/// Больше этого по мобильной сети спрашиваем отдельно.
const int kMobileDataAskBytes = 50 * 1024 * 1024;

/// Название задания в островке: заголовок записи, её подпись или дата.
String memorySaveTitle(Memory m) {
  final t = m.title?.trim() ?? '';
  if (t.isNotEmpty) return t;
  final c = (m.caption ?? '').trim().split('\n').first.trim();
  if (c.isNotEmpty) return c.length > 40 ? '${c.substring(0, 39)}…' : c;
  return memoryDateLabel(m.createdAt);
}

enum _AdultChoice { save, hidden }

/// Отправить файлы в галерею: общий путь для кнопки, листа вариантов, выбора
/// кадров, полного экрана, нескольких записей и всей пары.
///
/// Здесь живут вопросы, которые задаются ДО очереди: запись 18+ (в общей
/// галерее её увидит каждый), больше 50 МБ по мобильной сети, доступ к
/// галерее. Сообщения — нижними листами, а не снекбаром: большую часть времени
/// вызов идёт из листа воспоминания, и снекбар уехал бы под него.
Future<SaveJob?> saveToGallery(
  BuildContext context, {
  required String title,
  required List<SaveItem> items,
  bool adult = false,
  MediaSaveQueue? queue,
}) async {
  final q = queue ?? MediaSaveQueue.instance;
  final ledger = SavedMediaLedger.instance;
  await ledger.load();
  if (!context.mounted) return null;

  var list = items;
  // «Фото» на iPhone звук не принимает — он уходит через «Поделиться».
  if (Platform.isIOS && list.any((i) => i.file.kind == SaveKind.audio)) {
    final audio = [for (final i in list) if (i.file.kind == SaveKind.audio) i];
    list = [for (final i in list) if (i.file.kind != SaveKind.audio) i];
    if (list.isEmpty) {
      await shareMemoryMedia(
        context,
        files: [for (final a in audio) a.file],
        takenAt: audio.first.takenAt,
      );
      return null;
    }
  }

  final pending = [for (final i in list) if (!ledger.containsFile(i.file)) i];
  if (pending.isEmpty) {
    await AppDialog.info(
      context,
      title: trKey('saveNothingLeft'),
      message: trKey('saveDateNote')
          .replaceAll('{date}', memoryDateLabel(list.first.takenAt)),
      icon: Icons.download_done_rounded,
    );
    return null;
  }

  var hidden = false;
  if (adult) {
    final c = await _askAdult(context);
    if (c == null || !context.mounted) return null;
    hidden = c == _AdultChoice.hidden;
  }

  final bytes = summarizeMedia([for (final i in pending) i.file]).bytes;
  if (bytes > kMobileDataAskBytes && await _onMobileDataOnly()) {
    if (!context.mounted) return null;
    final ok = await AppDialog.confirm(
      context,
      title: trKey('mobileDataTitle')
          .replaceAll('{n}', '${(bytes / (1024 * 1024)).round()}'),
      message: trKey('mobileDataBody'),
      confirmLabel: trKey('mobileDataGo'),
      icon: Icons.signal_cellular_alt_rounded,
    );
    if (!ok || !context.mounted) return null;
  }

  if (!await GalleryWriter.instance.ensureAccess()) {
    if (context.mounted) {
      await AppDialog.info(
        context,
        title: trKey('islandNoAccess'),
        message: trKey('saveNoAccess'),
        icon: Icons.no_photography_rounded,
      );
    }
    return null;
  }

  return q.enqueue(title, pending, hidden: hidden);
}

Future<bool> _onMobileDataOnly() async {
  try {
    final r = await Connectivity().checkConnectivity();
    final fast = r.contains(ConnectivityResult.wifi) ||
        r.contains(ConnectivityResult.ethernet);
    return !fast && r.contains(ConnectivityResult.mobile);
  } catch (_) {
    return false;
  }
}

Future<_AdultChoice?> _askAdult(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return showAppSheet<_AdultChoice>(
    context,
    background: scheme.surfaceContainerLow,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return Theme(
        data: ProfileTheme.data(cs),
        child: SheetScaffold(
          title: trKey('adultTitle'),
          bottom: Row(
            children: [
              // Альбом «Скрытые» есть только у iPhone: он прячет кадр под
              // Face ID. На Android такого места нет, остаётся честное
              // предупреждение.
              if (Platform.isIOS) ...[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(ctx).pop(_AdultChoice.hidden),
                    icon: const Icon(Icons.visibility_off_rounded, size: 20),
                    label: Text(trKey('adultHidden')),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54)),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(_AdultChoice.save),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54)),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(trKey('adultSave'), maxLines: 1),
                  ),
                ),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              trKey('adultBody'),
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    },
  );
}
