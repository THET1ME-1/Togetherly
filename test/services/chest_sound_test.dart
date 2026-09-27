import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chest.dart';
import 'package:love_app/services/chest_sound.dart';

// Звук открытия сундука («Фанфара»): файл лежит в сборке, по длине равен
// анимации открытия, отдача — на щелчке замка и на призе.
void main() {
  test('файл звука в сборке и объявлен в pubspec', () {
    expect(File(ChestSound.asset).existsSync(), isTrue);
    expect(File('pubspec.yaml').readAsStringSync().contains('- assets/sounds/'), isTrue);
  });

  test('замок щёлкает раньше, чем выпадает приз', () {
    expect(ChestSound.lockFrame, 15);
    expect(ChestSound.lockFrame, lessThan(kChestWonFrame));
  });

  test('чужую музыку плеер не прерывает', () {
    final src = File('lib/services/chest_sound.dart').readAsStringSync();
    expect(src.contains('handleAudioSessionActivation: false'), isTrue);
    expect(src.contains('isOtherAudioPlaying'), isTrue);
  });
}
