import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

import 'photo_orientation.dart';

/// Нормализует EXIF-ориентацию (включая зеркальность фронтальной камеры),
/// затем открывает редактор кадрирования.
/// Возвращает путь к готовому файлу или null если пользователь отменил.
Future<String?> cropPhoto(
  String sourcePath, {
  Color accentColor = const Color(0xFFE91E8C),
}) async {
  // Сначала убираем EXIF-зеркальность: бакём все трансформации в пиксели
  final normalized = await _normalizeOrientation(sourcePath);
  final workPath = normalized ?? sourcePath;

  // Нативный кроппер может кинуть PlatformException (отмена через системный
  // диалог, нехватка памяти, пересоздание активити) — это не краш приложения,
  // трактуем как «не выбрали фото».
  CroppedFile? cropped;
  try {
    cropped = await ImageCropper().cropImage(
      sourcePath: workPath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 88,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Редактировать фото',
          toolbarColor: const Color(0xFF1A1A2E),
          toolbarWidgetColor: Colors.white,
          statusBarLight: false,
          backgroundColor: const Color(0xFF111111),
          activeControlsWidgetColor: accentColor,
          cropFrameColor: accentColor,
          cropGridColor: Colors.white24,
          dimmedLayerColor: const Color(0xCC0D0D1A),
          lockAspectRatio: false,
          initAspectRatio: CropAspectRatioPreset.original,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
        IOSUiSettings(
          title: 'Редактировать',
          doneButtonTitle: 'Готово',
          cancelButtonTitle: 'Отмена',
          aspectRatioLockEnabled: false,
          resetAspectRatioEnabled: true,
          rotateButtonsHidden: false,
          hidesNavigationBar: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
      ],
    );
  } catch (e) {
    debugPrint('cropPhoto: cropImage failed: $e');
    cropped = null;
  }

  // Удаляем временный нормализованный файл если он был создан
  if (normalized != null && normalized != sourcePath) {
    try {
      await File(normalized).delete();
    } catch (_) {}
  }

  return cropped?.path;
}

/// Применяет EXIF-трансформации (поворот И зеркальность) к пикселям
/// и возвращает путь к нормализованному файлу без EXIF.
///
/// Путей два, и это не прихоть. Нативный компрессор быстрый, но берёт из EXIF
/// ТОЛЬКО угол: `ExifInterface.rotationDegrees`, затем `matrix.setRotate`.
/// Отражение (ориентации 2, 4, 5, 7 — их ставит фронтальная камера) он не
/// применяет вовсе, а `keepExif: false` тут же выбрасывает саму пометку: кадр
/// остаётся зеркальным навсегда, и выправить его потом нечем. Отсюда жалоба
/// 20.08.2026 «фотография получается отзеркаленной». Такие кадры печём сами.
Future<String?> _normalizeOrientation(String sourcePath) async {
  try {
    final bytes = await File(sourcePath).readAsBytes();
    final orientation = readExifOrientation(bytes);
    // Снимок и так лежит правильно — лишний прогон только съел бы качество.
    // (У HEIC пометка не читается, и это не хуже прежнего: снимки с камеры
    // приезжают JPEG'ом, image_picker переводит их сам.)
    if (orientation <= 1) return null;

    final tempDir = await getTemporaryDirectory();
    final target =
        '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_norm.jpg';

    if (orientationIsMirrored(orientation)) {
      // Целый кадр в памяти — работа не для главного потока.
      final baked = await compute(bakeExifOrientation, bytes);
      if (baked == null) return null;
      await File(target).writeAsBytes(baked, flush: true);
      return target;
    }

    // Предел по времени: зависший нативный кодек future не возвращает вовсе, и
    // экран обрезки остался бы с вечным ожиданием (разбор 04.09.2026).
    final result = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      target,
      quality: 95,
      autoCorrectionAngle: true,
      keepExif: false,
    ).timeout(const Duration(seconds: 20));
    return result?.path;
  } catch (_) {
    return null;
  }
}
