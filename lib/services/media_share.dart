import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../dict_strings.dart';
import '../models/memory_media.dart';
import '../utils/share_origin.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/m3_loading.dart';
import 'media_fetcher.dart';
import 'media_save_queue.dart';

/// «Отправить» из меню воспоминания и из сетки выбора: сами файлы, а не
/// ссылки, — ссылка на защищённый файл без сессии не открывается ни у кого.
///
/// Файлы берутся тем же загрузчиком, что у сохранения (кэш картинок, потом
/// сеть), и уходят в системный лист «Поделиться» с понятными именами.
Future<void> shareMemoryMedia(
  BuildContext context, {
  required List<MediaFile> files,
  required DateTime takenAt,
  String? text,
  MediaFetcher? fetcher,
}) async {
  if (files.isEmpty) return;
  // Якорь для iPad снимается до первого await: после него контекст мог уйти.
  final origin = shareOriginFromContext(context);
  final nav = Navigator.of(context, rootNavigator: true);
  final cs = Theme.of(context).colorScheme;
  final loader = fetcher ?? HttpMediaFetcher();

  var loading = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                M3Loading(color: cs.primary),
                const SizedBox(height: 12),
                Text(
                  trKey('sharePreparing'),
                  style: TextStyle(fontFamily: 'Onest', color: cs.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  void close() {
    if (loading) {
      loading = false;
      nav.pop();
    }
  }

  try {
    final dir = Directory('${(await getTemporaryDirectory()).path}/share_media');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final out = <XFile>[];
    for (final f in files) {
      final got = await loader.fetch(f);
      final dest = File('${dir.path}/${galleryFileName(takenAt, f)}');
      await got.file.copy(dest.path);
      if (got.temporary) {
        try {
          await got.file.delete();
        } catch (_) {}
      }
      out.add(XFile(dest.path));
    }
    close();
    await Share.shareXFiles(out, text: text, sharePositionOrigin: origin);
  } catch (e) {
    debugPrint('shareMemoryMedia: $e');
    close();
    if (context.mounted) {
      await AppDialog.info(
        context,
        title: trKey('menuShare'),
        message: trKey('shareFailed'),
      );
    }
  }
}
