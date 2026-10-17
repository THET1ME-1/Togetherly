import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/voice_recorder_service.dart';
import 'package:record/record.dart';

void main() {
  test('голосовое в чате пишется как раньше', () {
    final config = VoiceRecorderService.configFor(VoiceQuality.chat);
    expect(config.encoder, AudioEncoder.aacLc);
    expect(config.bitRate, 32000);
    expect(config.sampleRate, 22050);
    expect(config.numChannels, 1);
    expect(config.noiseSuppress, isTrue);
    expect(config.echoCancel, isTrue);
  });

  test('голос к записи чище и без шумодава', () {
    final config = VoiceRecorderService.configFor(VoiceQuality.memory);
    expect(config.encoder, AudioEncoder.aacLc);
    expect(config.bitRate, 64000);
    expect(config.sampleRate, 44100);
    expect(config.numChannels, 1);
    // Шум вокруг — часть атмосферы, а шумодав портит напетое
    expect(config.noiseSuppress, isFalse);
    expect(config.echoCancel, isFalse);
  });
}
