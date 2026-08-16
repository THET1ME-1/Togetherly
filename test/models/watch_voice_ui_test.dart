import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/watch_voice_ui.dart';
import 'package:love_app/services/watch_voice_service.dart';

/// Что показывает полоса голоса в комнате.
///
/// Полоса живёт ПОД плеером и не зависит от того, включено ли видео: позвонить
/// партнёру можно в пустой комнате, ничего не запуская. Отсюда правило: кнопка
/// вызова есть всегда, а микрофон с динамиком появляются, только когда друг
/// друга уже слышно — до этого глушить нечего.
void main() {
  group('полоса голоса', () {
    test('в покое — только кнопка вызова', () {
      const bar = WatchVoiceBarModel(VoiceCallState.off);
      expect(bar.showsCallButton, isTrue);
      expect(bar.showsMicAndSpeaker, isFalse);
      expect(bar.callEndsTalk, isFalse);
    });

    test('пока соединяемся — кнопка отменяет вызов, глушилок нет', () {
      const bar = WatchVoiceBarModel(VoiceCallState.connecting);
      expect(bar.showsMicAndSpeaker, isFalse);
      expect(bar.callEndsTalk, isTrue);
      expect(bar.busy, isTrue);
    });

    test('в разговоре — микрофон и динамик на месте', () {
      const bar = WatchVoiceBarModel(VoiceCallState.live);
      expect(bar.showsMicAndSpeaker, isTrue);
      expect(bar.callEndsTalk, isTrue);
      expect(bar.busy, isFalse);
    });

    test('после обрыва — снова вызов, без глушилок', () {
      const bar = WatchVoiceBarModel(VoiceCallState.failed);
      expect(bar.showsMicAndSpeaker, isFalse);
      expect(bar.callEndsTalk, isFalse);
      expect(bar.failed, isTrue);
    });

    test('видео на полосу не влияет', () {
      // Ради этого всё и затевалось: разговор не требует включённого ролика.
      for (final state in VoiceCallState.values) {
        expect(WatchVoiceBarModel(state).showsCallButton, isTrue);
      }
    });
  });
}
