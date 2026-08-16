import '../services/watch_voice_service.dart';

/// Что показывает полоса голоса в комнате совместного просмотра.
///
/// Правило вынесено из виджета, потому что оно про поведение, а не про
/// раскладку: полоса стоит ПОД плеером и работает без включённого видео —
/// позвонить можно в пустой комнате. Глушилки микрофона и динамика имеют смысл
/// только когда друг друга уже слышно, до этого глушить нечего.
class WatchVoiceBarModel {
  const WatchVoiceBarModel(this.state);

  final VoiceCallState state;

  /// Кнопка вызова есть всегда: в покое зовёт, в разговоре кладёт трубку.
  bool get showsCallButton => true;

  /// Микрофон и динамик — только в живом разговоре.
  bool get showsMicAndSpeaker => state == VoiceCallState.live;

  /// Нажатие на кнопку прервёт разговор, а не начнёт его.
  bool get callEndsTalk =>
      state == VoiceCallState.live || state == VoiceCallState.connecting;

  /// Ждём ответа партнёра — на кнопке крутится ожидание.
  bool get busy => state == VoiceCallState.connecting;

  /// Связь оборвалась: кнопка снова зовёт, но рядом стоит объяснение.
  bool get failed => state == VoiceCallState.failed;
}
