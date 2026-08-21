import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_msg.dart';
import 'package:love_app/screens/chat/note_viewer_screen.dart';
import 'package:love_app/services/note_player_service.dart';
import 'package:video_player/video_player.dart';

/// Полноэкранный просмотр фигурки: перемотка пальцем по полосе и переход к
/// соседней фигурке переписки свайпом.
///
/// Плеер здесь подменён: настоящий поднимает `VideoPlayerController`, которого
/// в тестовой среде нет, — а проверять надо ровно то, что экран у плеера
/// просит.
class _FakePlayer extends ChangeNotifier implements NotePlayer {
  NotePlayback _state = const NotePlayback();

  /// Что просили открыть, по порядку.
  final List<String> opened = <String>[];

  /// Куда перематывали, по порядку.
  final List<double> seeks = <double>[];

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
    if (onlyIf != null && !isCurrent(onlyIf)) return;
    _state = const NotePlayback();
    notifyListeners();
  }
}

ChatMsg _note(String id) => ChatMsg(
      id: id,
      uid: 'her',
      name: 'Аня',
      text: '',
      ts: DateTime(2026, 8, 21, 14, 31).millisecondsSinceEpoch,
      noteUrl: '/tmp/$id.mp4',
      noteMs: 10000,
      noteShape: 'circle',
    );

Future<_FakePlayer> _pump(WidgetTester tester, {int index = 1}) async {
  final player = _FakePlayer();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink)),
    home: NoteViewerScreen(
      notes: [_note('a'), _note('b'), _note('c')],
      index: index,
      myUid: 'me',
      player: player,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  return player;
}

void main() {
  testWidgets('открывается та фигурка, по которой тапнули', (tester) async {
    final player = await _pump(tester);
    expect(player.opened, ['b']);
  });

  testWidgets('тяга по полосе перематывает туда, где палец', (tester) async {
    final player = await _pump(tester);
    final bar = find.byKey(const ValueKey('noteTimeline'));
    expect(bar, findsOneWidget);

    final box = tester.getRect(bar);
    await tester.dragFrom(
      Offset(box.left + box.width * 0.2, box.center.dy),
      Offset(box.width * 0.55, 0),
    );
    // pumpAndSettle тут не годится: обод крутит свой тикер постоянно, и
    // «успокоиться» дереву уже никогда не суждено.
    await tester.pump(const Duration(milliseconds: 300));

    expect(player.seeks, hasLength(1));
    expect(player.seeks.single, closeTo(0.75, 0.05));
  });

  testWidgets('свайп влево открывает следующую фигурку', (tester) async {
    final player = await _pump(tester);
    await tester.fling(find.byType(NoteViewerScreen), const Offset(-300, 0), 900);
    // pumpAndSettle тут не годится: обод крутит свой тикер постоянно, и
    // «успокоиться» дереву уже никогда не суждено.
    await tester.pump(const Duration(milliseconds: 300));
    expect(player.opened, ['b', 'c']);
  });

  testWidgets('свайп вправо открывает предыдущую', (tester) async {
    final player = await _pump(tester);
    await tester.fling(find.byType(NoteViewerScreen), const Offset(300, 0), 900);
    // pumpAndSettle тут не годится: обод крутит свой тикер постоянно, и
    // «успокоиться» дереву уже никогда не суждено.
    await tester.pump(const Duration(milliseconds: 300));
    expect(player.opened, ['b', 'a']);
  });

  testWidgets('на краю переписки свайп никуда не ведёт', (tester) async {
    final player = await _pump(tester, index: 2);
    await tester.fling(find.byType(NoteViewerScreen), const Offset(-300, 0), 900);
    // pumpAndSettle тут не годится: обод крутит свой тикер постоянно, и
    // «успокоиться» дереву уже никогда не суждено.
    await tester.pump(const Duration(milliseconds: 300));
    expect(player.opened, ['c']);
  });
}
