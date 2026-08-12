import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож краша на выборе музыки.
///
/// `FileType.audio` на iOS открывает не «Файлы», а медиатеку Apple Music
/// (`MPMediaPickerController` внутри file_picker). Система требует за это
/// `NSAppleMusicUsageDescription` и без него убивает приложение мгновенно —
/// SIGABRT прилетал из выпущенной сборки. Медиатека нам и не нужна: треки
/// оттуда закрыты DRM. Выбор аудио идёт только через `pickAudioFile()`, где для
/// iOS подставлен документный выбор.
void main() {
  test('FileType.audio нигде не вызывается напрямую', () {
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // Сам хелпер — единственное законное место: там ветка по платформе.
      if (file.path.endsWith('utils/audio_picker.dart')) continue;
      final source = file.readAsStringSync();
      final at = source.indexOf('FileType.audio');
      if (at == -1) continue;
      final line = '\n'.allMatches(source.substring(0, at)).length + 1;
      offenders.add('${file.path}:$line');
    }

    expect(
      offenders,
      isEmpty,
      reason: 'На iOS это открывает медиатеку Apple Music и роняет приложение. '
          'Берите pickAudioFile(): ${offenders.join(', ')}',
    );
  });
}
