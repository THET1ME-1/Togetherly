import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

/// Открывает системный редактор кадрирования и возвращает путь к
/// обрезанному файлу. Если пользователь нажал «Отмена» — возвращает null.
Future<String?> cropPhoto(
  String sourcePath, {
  Color accentColor = const Color(0xFFE91E8C),
}) async {
  final cropped = await ImageCropper().cropImage(
    sourcePath: sourcePath,
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
  return cropped?.path;
}
