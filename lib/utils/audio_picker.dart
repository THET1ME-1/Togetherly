import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Выбор аудиофайла — одинаково безопасный на обеих системах.
///
/// `FileType.audio` на iOS открывает не «Файлы», а медиатеку Apple Music
/// (`MPMediaPickerController` внутри file_picker). Система требует за это
/// объявленный `NSAppleMusicUsageDescription`, а без него убивает приложение на
/// месте — в панели крашей это SIGABRT с текстом про usage description. Да и
/// толку от медиатеки нет: треки оттуда закрыты DRM, файла всё равно не отдадут.
///
/// Поэтому на iOS просим документ с аудиорасширением: открывается системный
/// выбор файлов, откуда приезжает настоящий файл. Android оставляем как был —
/// там `FileType.audio` работает правильно.
const _audioExtensions = <String>[
  'mp3',
  'm4a',
  'aac',
  'wav',
  'flac',
  'ogg',
  'opus',
  'aiff',
  'alac',
];

/// Идёт ли выбор прямо сейчас.
///
/// Второй запрос, пока открыт первый, iOS не просто игнорирует: file_picker
/// отвечает `PlatformException(multiple_request, Cancelled by a second
/// request)` и ОТМЕНЯЕТ уже открытое окно. Человеку это выглядело как ошибка
/// на ровном месте после обычного двойного касания кнопки (жалоба 13 августа
/// 2026). Страж стоит здесь, а не на экранах: точек вызова две — форма музыки
/// и лента воспоминаний.
bool _picking = false;

/// Сбросить сторож между тестами.
@visibleForTesting
void resetAudioPickerForTest() => _picking = false;

Future<FilePickerResult?> pickAudioFile({
  Future<FilePickerResult?> Function()? open,
}) async {
  if (_picking) return null;
  _picking = true;
  try {
    if (open != null) return await open();
    if (Platform.isIOS) {
      return await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _audioExtensions,
      );
    }
    return await FilePicker.platform.pickFiles(type: FileType.audio);
  } finally {
    // Отказ системы тоже закрывает окно: без сброса кнопка осталась бы мёртвой
    // до перезапуска приложения.
    _picking = false;
  }
}
