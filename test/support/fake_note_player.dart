import 'package:flutter/foundation.dart';
import 'package:love_app/services/note_player_service.dart';
import 'package:video_player/video_player.dart';

/// Плеер фигурок для тестов.
///
/// Настоящий поднимает `VideoPlayerController`, которого в тестовой среде нет
/// вовсе, — а проверять надо ровно то, что экран и лента у плеера просят:
/// что открыли, куда перемотали, у кого забрали.
class FakeNotePlayer extends ChangeNotifier implements NotePlayer {
  NotePlayback _state = const NotePlayback();

  /// Что просили открыть, по порядку.
  final List<String> opened = <String>[];

  /// Куда перематывали, по порядку.
  final List<double> seeks = <double>[];

  /// Кого просили остановить (null — «останови что играет»).
  final List<String?> stops = <String?>[];

  int toggles = 0;

  @override
  NotePlayback get state => _state;

  @override
  VideoPlayerController? get controller => null;

  @override
  bool isCurrent(String messageId) =>
      _state.messageId.isNotEmpty && _state.messageId == messageId;

  @override
  double smoothProgress() => _state.progress;

  @override
  Future<void> open({
    required String messageId,
    required String url,
    Duration? knownDuration,
    bool auto = false,
    bool? sound,
  }) async {
    opened.add(messageId);
    _state = NotePlayback(
      messageId: messageId,
      duration: knownDuration ?? const Duration(seconds: 10),
      playing: true,
    );
    notifyListeners();
  }

  @override
  Future<void> togglePlay() async => toggles++;

  @override
  Future<void> toggleSound() async {}

  @override
  Future<void> seekFraction(double fraction) async => seeks.add(fraction);

  @override
  Future<void> stop({String? onlyIf}) async {
    stops.add(onlyIf);
    if (onlyIf != null && !isCurrent(onlyIf)) return;
    _state = const NotePlayback();
    notifyListeners();
  }
}
