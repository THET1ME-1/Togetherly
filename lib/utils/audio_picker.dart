import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';

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

Future<FilePickerResult?> pickAudioFile() {
  if (Platform.isIOS) {
    return FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _audioExtensions,
    );
  }
  return FilePicker.platform.pickFiles(type: FileType.audio);
}
