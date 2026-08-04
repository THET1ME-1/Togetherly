import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'pocketbase_service.dart';

/// Живое фото в парном виджете: короткое видео или гифка вместо снимка.
///
/// Анимации внутри виджета не бывает: `RemoteViews` инфлейтит только классы из
/// белого списка, плеера там нет, а `ImageView` не проигрывает ни gif, ни
/// анимированный drawable. Кадры покадрово подсовывает нативная сторона — значит
/// ей нужны именно кадры.
///
/// Готовит их сервер (`pb_hooks/widget_anim.pb.js` + `tools/widget_anim.py`): из
/// файла собирается одна картинка-раскадровка 6×3 по 300 px и манифест к ней.
/// Телефон только скачивает результат — разбирать видео на слабом аппарате
/// нельзя, `MediaMetadataRetriever` там тратит 100–200 мс на кадр и пульс
/// рвётся. Тот же приём рисует анимированных маскотов: атлас плюс манифест.
@immutable
class WidgetAnimManifest {
  final int cols;
  final int rows;
  final int cell;
  final int frames;
  final int stepMs;
  final String source;

  const WidgetAnimManifest({
    required this.cols,
    required this.rows,
    required this.cell,
    required this.frames,
    required this.stepMs,
    required this.source,
  });

  /// Разбор ответа сервера. Числа приходят как `num`, поэтому приводим сами:
  /// json из JSVM отдаёт целые то int, то double.
  static WidgetAnimManifest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    int? pick(String key) {
      final v = raw[key];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    final cols = pick('cols');
    final rows = pick('rows');
    final cell = pick('cell');
    final frames = pick('frames');
    final step = pick('step_ms');
    if (cols == null || rows == null || cell == null) return null;
    if (cols <= 0 || rows <= 0 || cell <= 0) return null;
    return WidgetAnimManifest(
      cols: cols,
      rows: rows,
      cell: cell,
      frames: frames ?? cols * rows,
      stepMs: (step == null || step <= 0) ? 100 : step,
      source: (raw['source'] as String?) ?? 'video',
    );
  }

  Map<String, Object> toJson() => {
        'cols': cols,
        'rows': rows,
        'cell': cell,
        'frames': frames,
        'step_ms': stepMs,
        'source': source,
      };
}

class WidgetAnimService {
  WidgetAnimService._();
  static final WidgetAnimService instance = WidgetAnimService._();

  /// Предел, после которого файл не берём. Не про место на сервере: исходник
  /// там живёт минуты и удаляется после обработки, зато аплоад на мобильной
  /// сети — это ожидание с крутилкой на весь экран.
  static const int maxSourceBytes = 25 * 1024 * 1024;

  /// Ключи HomeWidget. Те же строки лежат в `WidgetAnimPlayer` на стороне
  /// Kotlin — разъедутся, и виджет молча покажет обычное фото.
  static const String keyPath = 'anim_sheet_path';
  static const String keyManifest = 'anim_manifest';

  /// Заказать раскадровку у сервера. Возвращает манифест или null.
  ///
  /// Роут идемпотентный: повторный вызов после обрыва сети не запускает вторую
  /// обработку, а отдаёт готовый манифест.
  Future<WidgetAnimManifest?> prepare(String mediaId) async {
    if (mediaId.isEmpty) return null;
    try {
      final res = await PocketBaseService().pb.send<dynamic>(
        '/api/widget/anim/prepare',
        method: 'POST',
        body: {'mediaId': mediaId},
      );
      if (res is Map && res['ok'] == true) {
        return WidgetAnimManifest.tryParse(res['manifest']);
      }
    } catch (e) {
      debugPrint('WidgetAnimService.prepare failed: $e');
    }
    return null;
  }

  /// Скачать раскадровку в файл рядом с прочими картинками виджетов.
  ///
  /// Кладём именно файлом: нативная сторона читает его сама, а гонять
  /// полтора мегабайта пикселей через канал HomeWidget нельзя — транзакция
  /// Binder ограничена мегабайтом на процесс.
  Future<File?> download(String mediaId, {bool force = false}) async {
    if (mediaId.isEmpty) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/widget_anim_$mediaId.webp');
      if (!force && await file.exists() && await file.length() > 0) return file;

      final pb = PocketBaseService().pb;
      final uri = pb.buildURL('/api/widget/anim/sheet', {'id': mediaId});
      final client = HttpClient();
      try {
        final req = await client.getUrl(uri);
        final token = pb.authStore.token;
        if (token.isNotEmpty) req.headers.set('Authorization', token);
        final res = await req.close();
        if (res.statusCode != 200) {
          debugPrint('WidgetAnimService.download: HTTP ${res.statusCode}');
          return null;
        }
        final tmp = File('${file.path}.part');
        await res.pipe(tmp.openWrite());
        // Готовый файл появляется одним движением: виджет может читать его в
        // тот же момент, и недокачанная картинка попала бы на экран.
        await tmp.rename(file.path);
      } finally {
        client.close(force: true);
      }
      return file;
    } catch (e) {
      debugPrint('WidgetAnimService.download failed: $e');
      return null;
    }
  }

  /// Всё вместе: заказать, скачать, вернуть путь и манифест строкой для
  /// нативной стороны (её удобнее кормить одним json).
  Future<({String path, String manifest})?> fetch(String mediaId) async {
    final manifest = await prepare(mediaId);
    if (manifest == null) return null;
    final file = await download(mediaId);
    if (file == null) return null;
    return (path: file.path, manifest: jsonEncode(manifest.toJson()));
  }

  /// Какой кадр показывать в момент [elapsedMs]. Держим здесь, чтобы правило
  /// было одно и под тестом: нативная сторона считает так же.
  static int frameAt(WidgetAnimManifest m, int elapsedMs) {
    final total = m.frames <= 0 ? 1 : m.frames;
    final step = m.stepMs <= 0 ? 100 : m.stepMs;
    final index = (elapsedMs ~/ step) % total;
    return index < 0 ? 0 : index;
  }

  /// Границы клетки в атласе: слева, сверху, ширина, высота.
  static ({int left, int top, int size}) cellRect(WidgetAnimManifest m, int index) {
    final i = m.cols <= 0 ? 0 : index % (m.cols * m.rows);
    return (left: (i % m.cols) * m.cell, top: (i ~/ m.cols) * m.cell, size: m.cell);
  }
}
