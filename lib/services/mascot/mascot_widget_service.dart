import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/mascot_anim.dart';
import '../../models/mascot_widget_data.dart';
import '../locale_service.dart';
import '../offline/media_view_cache.dart';
import 'mascot_frame_render.dart';
import 'mascot_widget_keys.dart';

/// Подписи виджета на языке человека.
///
/// Собираются здесь, а не на нативной стороне: у расширений локализации нет.
/// Обе подписи сна кладутся разом — в 23:00 приложение может и не работать.
MascotWidgetLabels buildMascotWidgetLabels(MascotWidgetData data) {
  final s = LocaleService.current;

  final stage = switch (data.stage) {
    MascotStage.baby => s.mascotStageBaby,
    MascotStage.teen => s.mascotStageTeen,
    MascotStage.adult => s.mascotStageAdult,
  };

  final next = switch (data.stage) {
    MascotStage.baby => s.mascotWidgetToTeen(data.daysToNextStage),
    MascotStage.teen => s.mascotWidgetToAdult(data.daysToNextStage),
    MascotStage.adult => s.mascotWidgetGrown,
  };

  final sleeps = data.sleep.enabled;

  return MascotWidgetLabels(
    stage: stage,
    streak: s.mascotWidgetStreakLabel(data.streakDays),
    next: next,
    sleepDay: sleeps ? s.mascotWidgetAwakeUntil(_hhmm(data.sleep.from)) : s.mascotWidgetNoSleep,
    sleepNight: sleeps ? s.mascotWidgetSleepsUntil(_hhmm(data.sleep.to)) : s.mascotWidgetNoSleep,
    record: s.mascotWidgetRecord(data.recordStreak),
  );
}

String _hhmm(int minutes) {
  final m = minutes < 0 ? 0 : minutes % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Кладёт кадры маскота туда, где их видит виджет рабочего стола.
class MascotWidgetService {
  MascotWidgetService._();

  static final MascotWidgetService instance = MascotWidgetService._();

  static const _dirName = 'mascot_widget';

  /// Последнее, что уехало на стол: повторная публикация того же состояния
  /// только гоняет диск и будит четыре провайдера впустую.
  String? _lastSignature;

  /// Режет кадры активного персонажа и будит все четыре размера.
  Future<void> publish({
    required String groupId,
    required MascotAnim anim,
    required MascotWidgetData data,
    DateTime? now,
    bool force = false,
  }) async {
    final when = now ?? DateTime.now();
    final signature = [
      groupId,
      anim.id,
      anim.sheetUrl,
      data.atlasLevel,
      data.streakDays,
      data.recordStreak,
      data.sad,
      data.sleep.from,
      data.sleep.to,
      LocaleService.instance.language.code,
      // Сезонный наряд меняется первого числа: месяц в подписи держит кадр
      // свежим, не перерисовывая виджет каждый час.
      when.month,
    ].join('|');
    if (!force && signature == _lastSignature) return;

    try {
      final sheet = await _sheetImage(anim.sheetUrl);
      if (sheet == null) return;

      Map<MascotWidgetFrame, Uint8List> frames;
      try {
        frames = await renderMascotWidgetFrames(
          sheet: sheet,
          anim: anim,
          level: data.atlasLevel,
          now: when,
        );
      } finally {
        sheet.dispose();
      }
      if (frames.isEmpty) return;

      final paths = await _writeFrames(groupId, frames);
      final keys = mascotWidgetKeys(
        groupId: groupId,
        data: data,
        labels: buildMascotWidgetLabels(data),
        framePaths: paths,
        framePx: anim.frame,
      );

      for (final e in keys.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await _wakeProviders();
      _lastSignature = signature;
    } catch (e) {
      debugPrint('MascotWidgetService.publish не справился: $e');
    }
  }

  /// Персонажа сняли: виджету больше нечего показывать.
  Future<void> clear(String groupId) async {
    final g = groupId.isEmpty ? 'solo' : groupId;
    try {
      for (final key in const ['frame_day', 'frame_night', 'frame_sad', 'id', 'name']) {
        await HomeWidget.saveWidgetData<String>('mascot_${g}_$key', '');
      }
      await _deleteGroupFiles(g);
      await _wakeProviders();
      _lastSignature = null;
    } catch (e) {
      debugPrint('MascotWidgetService.clear не справился: $e');
    }
  }

  Future<ui.Image?> _sheetImage(String url) async {
    try {
      // Тот же склад, из которого атлас берёт `PixelMascotView`: ключ — сам
      // адрес листа, поэтому второй закачки не будет.
      var hit = await OfflineImageCacheManager.instance.getFileFromCache(url);
      hit ??= await OfflineImageCacheManager.instance.downloadFile(url);
      final bytes = await hit.file.readAsBytes();
      if (bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(bytes);
      return (await codec.getNextFrame()).image;
    } catch (e) {
      debugPrint('MascotWidgetService: атлас не прочитался — $e');
      return null;
    }
  }

  Future<Map<MascotWidgetFrame, String>> _writeFrames(
    String groupId,
    Map<MascotWidgetFrame, Uint8List> frames,
  ) async {
    final g = groupId.isEmpty ? 'solo' : groupId;
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/$_dirName');
    dir.createSync(recursive: true);
    await _deleteGroupFiles(g);

    // Номер в имени: лончер держит картинку по пути и с прежним именем
    // показывал бы вчерашний кадр.
    final rev = DateTime.now().millisecondsSinceEpoch;
    final out = <MascotWidgetFrame, String>{};
    for (final e in frames.entries) {
      final file = File('${dir.path}/mascot_${g}_${e.key.name}_$rev.png');
      await file.writeAsBytes(e.value, flush: true);
      out[e.key] = file.path;
    }
    return out;
  }

  Future<void> _deleteGroupFiles(String g) async {
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/$_dirName');
      if (!dir.existsSync()) return;
      for (final f in dir.listSync()) {
        if (f is File && f.path.contains('mascot_${g}_')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('MascotWidgetService: старые кадры не убрались — $e');
    }
  }

  Future<void> _wakeProviders() async {
    for (final p in kMascotWidgetProviders) {
      await HomeWidget.updateWidget(
        name: p,
        androidName: p,
        qualifiedAndroidName: 'com.togetherly.love.$p',
      );
    }
  }
}
