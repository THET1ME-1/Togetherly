import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/sound_clip.dart';
import 'package:love_app/models/voice_note.dart';
import 'package:love_app/services/sound_clip_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('love_app/sound_clip');
  late Directory tmp;
  final calls = <MethodCall>[];
  late Object? Function(MethodCall call) answer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sound_clip');
    calls.clear();
    answer = (_) => null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer(call);
    });
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  File song({int bytes = 64}) =>
      File('${tmp.path}/song.mp3')..writeAsBytesSync(List.filled(bytes, 1));

  test('проба отдаёт длительность и теги', () async {
    answer = (_) =>
        {'durationMs': 255000, 'title': 'Lovely Day', 'artist': 'Bill Withers'};
    final file = song();
    final probe = await SoundClipService.instance.probe(file.path);
    expect(probe.duration, const Duration(seconds: 255));
    expect(probe.title, 'Lovely Day');
    expect(probe.artist, 'Bill Withers');
    expect(calls.single.method, 'probe');
    expect(calls.single.arguments, {'path': file.path});
  });

  test('огромный файл отклоняется до натива', () async {
    final big = File('${tmp.path}/mix.mp3');
    // Разреженный файл: размер есть, места на диске нет.
    big.openSync(mode: FileMode.write)
      ..truncateSync(SoundLimits.maxSourceBytes + 1)
      ..closeSync();
    await expectLater(
      SoundClipService.instance.probe(big.path),
      throwsA(isA<SoundClipException>()
          .having((e) => e.reason, 'reason', SoundClipError.tooLarge)),
    );
    expect(calls, isEmpty);
  });

  test('пропавший файл — ошибка, а не падение', () async {
    await expectLater(
      SoundClipService.instance.probe('${tmp.path}/нет.mp3'),
      throwsA(isA<SoundClipException>()
          .having((e) => e.reason, 'reason', SoundClipError.failed)),
    );
  });

  test('натив не знает формат — unsupported', () async {
    answer = (_) => throw PlatformException(code: 'unsupported');
    await expectLater(
      SoundClipService.instance.probe(song().path),
      throwsA(isA<SoundClipException>()
          .having((e) => e.reason, 'reason', SoundClipError.unsupported)),
    );
  });

  test('волна всегда нужной длины и в пределах 0..1', () async {
    answer = (_) => [0.2, 1.4, -0.3, 0.5];
    final bars = await SoundClipService.instance.waveform(song().path, buckets: 8);
    expect(bars, hasLength(8));
    expect(bars.every((v) => v >= 0 && v <= 1), isTrue);
    expect(calls.single.arguments, {'path': song().path, 'buckets': 8});
  });

  test('кусок песни ложится в sound_outbox с волной из сорока цифр', () async {
    answer = (call) {
      final args = call.arguments as Map;
      File(args['outPath'] as String).writeAsBytesSync([1, 2, 3]);
      return {
        'path': args['outPath'],
        'durationMs': 29950,
        'peaks': List<double>.generate(40, (i) => (i % 10) / 9),
      };
    };
    final clip = await SoundClipService.instance.cut(
      song().path,
      start: const Duration(seconds: 72),
      length: const Duration(seconds: 30),
      title: 'Lovely Day',
      artist: 'Bill Withers',
    );
    final args = calls.single.arguments as Map;
    expect(args['startMs'], 72000);
    expect(args['endMs'], 102000);
    expect(args['fadeMs'], SoundLimits.fade.inMilliseconds);
    expect((args['outPath'] as String).startsWith('${tmp.path}/sound_outbox/'),
        isTrue);
    expect(clip.url, args['outPath']);
    expect(clip.kind, SoundKind.song);
    expect(clip.duration, const Duration(milliseconds: 29950));
    expect(clip.peaks, hasLength(VoicePeaks.count));
    expect(clip.title, 'Lovely Day');
    expect(clip.isLocalFile, isTrue);
  });

  test('кусок длиннее предела режется до предела', () async {
    answer = (call) => {
          'path': (call.arguments as Map)['outPath'],
          'durationMs': 30000,
          'peaks': <double>[],
        };
    await SoundClipService.instance.cut(
      song().path,
      start: const Duration(seconds: 10),
      length: const Duration(minutes: 2),
      limit: SoundLimits.giftSong,
    );
    final args = calls.single.arguments as Map;
    expect(args['endMs'] - args['startMs'], SoundLimits.giftSong.inMilliseconds);
  });

  test('сбой вырезки стирает недописанный файл', () async {
    String? out;
    answer = (call) {
      out = (call.arguments as Map)['outPath'] as String;
      File(out!).writeAsBytesSync([9, 9]);
      throw PlatformException(code: 'failed', message: 'codec');
    };
    await expectLater(
      SoundClipService.instance.cut(song().path,
          start: Duration.zero, length: const Duration(seconds: 5)),
      throwsA(isA<SoundClipException>()),
    );
    expect(File(out!).existsSync(), isFalse);
  });
}
