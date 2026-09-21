import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/canvas_meta.dart';
import '../../models/draw_stroke.dart';
import '../../widgets/draw/canvas_preview.dart';
import 'canvas_widget_keys.dart';

/// Готовит картинки холстов для виджета «Рисунок на столе».
///
/// Виджет не умеет ни ходить в сеть, ни собирать штрихи: рисунок ему отдаётся
/// готовым PNG — тем же приёмом, что карта «Где мы». Рисует их тот же
/// художник, что и плитки галереи (`CanvasPreviewPainter`), поэтому виджет и
/// приложение показывают одно и то же.
class CanvasWidgetService {
  CanvasWidgetService._();

  static final CanvasWidgetService instance = CanvasWidgetService._();

  static const _dirName = 'canvas_widget';

  /// Сколько холстов держим для экрана выбора. Больше десятка человек на стол
  /// всё равно не поставит, а каждый лишний — это рендер и файл.
  static const int maxCanvases = 8;

  /// Длинная сторона картинки. Виджет 4×4 на плотном экране просит около
  /// тысячи точек, но Binder держит немного: на больших битмапах виджеты
  /// пустели (разбор 05.09.2026).
  static const int longSide = 640;

  static const _channel = MethodChannel('love_app/widgets');

  String? _lastSignature;

  /// Просит систему положить виджет с этим холстом на рабочий стол.
  ///
  /// Дальше человек сам выбирает место, а система открывает экран выбора
  /// холста — там нужный уже отмечен, потому что перед вызовом он записан
  /// активным. false — лончер закрепление не умеет (такие есть), тогда виджет
  /// добавляют руками из списка.
  Future<bool> pinToHomeScreen(String canvasId, {String size = '2x3'}) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('pinCanvasWidget', {'size': size});
      return ok ?? false;
    } catch (e) {
      debugPrint('CanvasWidgetService: закрепление не вышло — $e');
      return false;
    }
  }

  /// Рисует холсты и кладёт их туда, где виджет их видит.
  ///
  /// [strokesOf] отдаёт штрихи холста: сервис не знает, откуда они берутся
  /// (пара — из базы, одиночка — с телефона), и не тащит за собой репозиторий.
  Future<void> publish({
    required String groupId,
    required List<CanvasMeta> canvases,
    required Future<List<DrawStroke>> Function(CanvasMeta meta) strokesOf,
    String? activeId,
    bool force = false,
  }) async {
    if (canvases.isEmpty) {
      await clear(groupId);
      return;
    }

    final picked = canvases.take(maxCanvases).toList();
    final active = activeId?.isNotEmpty == true ? activeId! : picked.first.id;
    final signature = [
      groupId,
      active,
      for (final c in picked) '${c.id}:${c.updatedAt.millisecondsSinceEpoch}',
    ].join('|');
    if (!force && signature == _lastSignature) return;

    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/$_dirName');
      dir.createSync(recursive: true);
      final rev = DateTime.now().millisecondsSinceEpoch;

      final items = <CanvasWidgetItem>[];
      for (final meta in picked) {
        final png = await _render(meta, await strokesOf(meta));
        if (png == null) continue;
        final file = File('${dir.path}/canvas_${_safe(meta.id)}_$rev.png');
        await file.writeAsBytes(png, flush: true);
        items.add(CanvasWidgetItem(
          id: meta.id,
          name: meta.name,
          path: file.path,
          updatedMs: meta.updatedAt.millisecondsSinceEpoch,
        ));
      }
      if (items.isEmpty) return;

      await _deleteOld(dir, keep: items.map((i) => i.path).toSet());

      final keys = canvasWidgetKeys(
        groupId: groupId,
        items: items,
        activeId: items.any((i) => i.id == active) ? active : items.first.id,
      );
      for (final e in keys.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await _wake();
      _lastSignature = signature;
    } catch (e) {
      debugPrint('CanvasWidgetService.publish не справился: $e');
    }
  }

  /// Рисунков не осталось: виджету нечего показывать.
  Future<void> clear(String groupId) async {
    final g = groupId.isEmpty ? 'solo' : groupId;
    try {
      await HomeWidget.saveWidgetData<String>('canvas_${g}_list', '');
      await HomeWidget.saveWidgetData<String>('canvas_${g}_active', '');
      await HomeWidget.saveWidgetData<String>('canvas_${g}_count', '0');
      await _wake();
      _lastSignature = null;
    } catch (e) {
      debugPrint('CanvasWidgetService.clear не справился: $e');
    }
  }

  /// Холст в PNG: тот же художник, что рисует плитку в галерее.
  Future<Uint8List?> _render(CanvasMeta meta, List<DrawStroke> strokes) async {
    if (strokes.isEmpty) return null;
    final ratio = meta.effectiveRatio ?? 0.8;
    final height = ratio >= 1 ? (longSide / ratio).round() : longSide;
    final width = ratio >= 1 ? longSide : (longSide * ratio).round();
    final size = Size(width.toDouble(), height.toDouble());

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // Лист белый, как в галерее: цвет фона холста живёт на сервере, а
      // виджету важнее показать рисунок, чем угадать подложку.
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
      CanvasPreviewPainter(strokes: strokes, meta: meta).paint(canvas, size);

      final image = await recorder.endRecording().toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } catch (e) {
      debugPrint('CanvasWidgetService: холст ${meta.id} не нарисовался — $e');
      return null;
    }
  }

  /// Имя файла из идентификатора холста: он приходит с сервера и может нести
  /// что угодно, а путь уезжает в натив строкой.
  String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<void> _deleteOld(Directory dir, {required Set<String> keep}) async {
    try {
      for (final f in dir.listSync()) {
        if (f is File && !keep.contains(f.path)) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('CanvasWidgetService: старые холсты не убрались — $e');
    }
  }

  Future<void> _wake() async {
    for (final p in kCanvasWidgetProviders) {
      await HomeWidget.updateWidget(
        name: p,
        androidName: p,
        qualifiedAndroidName: 'com.togetherly.love.$p',
      );
    }
  }
}
