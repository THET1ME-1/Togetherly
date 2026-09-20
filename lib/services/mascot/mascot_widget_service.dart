import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/mascot.dart';
import '../../models/mascot_anim.dart';
import '../../models/mascot_widget_data.dart';
import '../locale_service.dart';
import '../offline/media_view_cache.dart';
import '../pb_media_service.dart';
import 'mascot_art_source.dart';
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
    // Ночная сцена есть у восьмерых из тридцати с лишним, а у рисованных её
    // нет вовсе. Пустая подпись значащая: натив прячет пилюлю целиком, чтобы
    // не врать «не ложится спать» про картинку, которая одна на все часы.
    sleepDay: sleeps ? s.mascotWidgetAwakeUntil(_hhmm(data.sleep.from)) : '',
    sleepNight: sleeps ? s.mascotWidgetSleepsUntil(_hhmm(data.sleep.to)) : '',
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

  /// Сторона картинки непиксельного маскота. Больше не нужно: виджет 4×4 на
  /// плотном экране просит около 420 точек, а Binder держит немного.
  static const int _kSingleFrameSide = 432;

  /// Последнее, что уехало на стол: повторная публикация того же состояния
  /// только гоняет диск и будит четыре провайдера впустую.
  String? _lastSignature;

  /// Готовит картинку активного персонажа и будит все четыре размера.
  ///
  /// Работает с любым маскотом: пиксельный атлас режется на кадры, встроенный
  /// берётся из ассетов, каталожный и нарисованный человеком — из сети и
  /// хранилища. Подробности выбора — в `mascot_art_source.dart`.
  Future<void> publish({
    required String groupId,
    required Mascot mascot,
    MascotAnim? anim,
    required MascotWidgetData data,
    DateTime? now,
    bool force = false,
  }) async {
    final when = now ?? DateTime.now();
    final art = mascotArtSource(mascot, anim);
    if (art.kind == MascotArtKind.none) {
      await clear(groupId);
      return;
    }
    final signature = [
      groupId,
      mascot.id,
      art.kind.name,
      art.ref,
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
      var frames = <MascotWidgetFrame, Uint8List>{};
      var strips = <MascotWidgetFrame, MascotFrameStrip>{};
      if (anim != null) {
        // Атлас открывается ОДИН раз: и кадры, и полосы режутся за проход.
        // Вторая загрузка промахивалась мимо кэша, и виджет оставался без
        // полос — то есть без движения.
        final sheet = await _sheetImage(anim.sheetUrl);
        if (sheet == null) return;
        try {
          frames = await renderMascotWidgetFrames(
            sheet: sheet,
            anim: anim,
            level: data.atlasLevel,
            now: when,
          );
          for (final kind in MascotWidgetFrame.values) {
            final strip = await renderMascotStrip(
              sheet: sheet,
              anim: anim,
              level: data.atlasLevel,
              now: when,
              frame: kind,
            );
            if (strip != null) strips[kind] = strip;
          }
        } finally {
          sheet.dispose();
        }
      } else {
        frames = await _singleFrame(art);
      }
      if (frames.isEmpty) return;

      final paths = await _writeFrames(groupId, frames);
      final stripPaths = await _writeStrips(groupId, strips);

      final keys = mascotWidgetKeys(
        groupId: groupId,
        data: data,
        labels: buildMascotWidgetLabels(data),
        framePaths: paths,
        framePx: anim?.frame ?? 0,
        pixel: art.pixel,
        stripDay: stripPaths[MascotWidgetFrame.day] ?? '',
        stripNight: stripPaths[MascotWidgetFrame.night] ?? '',
        stripSad: stripPaths[MascotWidgetFrame.sad] ?? '',
        animManifest: strips.isEmpty ? '' : jsonEncode(strips.values.first.manifest),
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

  /// Кладёт полосы кадров на диск. Манифест у них общий: строки одного
  /// атласа одинаковы и по размеру кадра, и по скорости.
  Future<Map<MascotWidgetFrame, String>> _writeStrips(
    String groupId,
    Map<MascotWidgetFrame, MascotFrameStrip> strips,
  ) async {
    if (strips.isEmpty) return {};
    final g = groupId.isEmpty ? 'solo' : groupId;
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/$_dirName');
    dir.createSync(recursive: true);
    final rev = DateTime.now().millisecondsSinceEpoch;

    final out = <MascotWidgetFrame, String>{};
    for (final e in strips.entries) {
      final file = File('${dir.path}/mascot_${g}_strip_${e.key.name}_$rev.png');
      await file.writeAsBytes(e.value.png, flush: true);
      out[e.key] = file.path;
    }
    return out;
  }

  /// Одна картинка на все часы: встроенный, каталожный или нарисованный
  /// маскот. Ночной и грустной сцены у них нет — рисунок один.
  Future<Map<MascotWidgetFrame, Uint8List>> _singleFrame(MascotArtSource art) async {
    final bytes = switch (art.kind) {
      MascotArtKind.asset => await _assetBytes(art.ref),
      MascotArtKind.network => await _cachedBytes(art.ref, art.ref),
      MascotArtKind.storage => await _storageBytes(art.ref),
      _ => null,
    };
    if (bytes == null || bytes.isEmpty) return {};
    final small = await _fitTo(bytes, _kSingleFrameSide);
    return small == null ? {} : {MascotWidgetFrame.day: small};
  }

  Future<Uint8List?> _assetBytes(String asset) async {
    try {
      final data = await rootBundle.load(asset);
      return data.buffer.asUint8List();
    } catch (e) {
      debugPrint('MascotWidgetService: ассет $asset не прочитался — $e');
      return null;
    }
  }

  Future<Uint8List?> _cachedBytes(String key, String url) async {
    try {
      var hit = await OfflineImageCacheManager.instance.getFileFromCache(key);
      hit ??= await OfflineImageCacheManager.instance.downloadFile(url, key: key);
      return await hit.file.readAsBytes();
    } catch (e) {
      debugPrint('MascotWidgetService: картинка $key не скачалась — $e');
      return null;
    }
  }

  /// Нарисованный маскот лежит в хранилище пары, и ссылка на него живёт
  /// минуты. Ключ кэша — исходный `pb://`, иначе каждый показ качал бы заново.
  Future<Uint8List?> _storageBytes(String ref) async {
    final url = await PbMediaService().resolveUrlAuthed(ref) ?? ref;
    return _cachedBytes(ref, url);
  }

  /// Вписывает картинку в квадрат [side] точек, сохраняя пропорции.
  ///
  /// Рисунок человека приезжает мегапиксельным, а RemoteViews упирается в
  /// Binder: на этом уже пустели виджеты с фотографиями.
  Future<Uint8List?> _fitTo(Uint8List bytes, int side) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final longest = image.width > image.height ? image.width : image.height;
      if (longest <= side) {
        image.dispose();
        return bytes;
      }
      final k = side / longest;
      final w = (image.width * k).round().clamp(1, side);
      final h = (image.height * k).round().clamp(1, side);
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      image.dispose();
      final small = await recorder.endRecording().toImage(w, h);
      try {
        final data = await small.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        small.dispose();
      }
    } catch (e) {
      debugPrint('MascotWidgetService: картинка не ужалась — $e');
      return null;
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
