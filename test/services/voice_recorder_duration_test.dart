import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/voice_recorder_service.dart';
import 'package:record/record.dart';

/// Телефонная сторона пакета `record`. [stop] пишет готовый файл и отвечает
/// с задержкой: на Android кодировщик дописывает хвост, и 26.10.2026 ответ
/// пришёл через 29 секунд после того, как палец отпустили.
class _FakeRecord extends RecordPlatform {
  _FakeRecord({required this.source, required this.stopDelay});

  /// Что окажется в файле записи. null — файл пустой, без заголовка.
  final String? source;
  final Duration stopDelay;
  String? _path;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;

  @override
  Future<void> start(String recorderId, RecordConfig config,
      {required String path}) async {
    _path = path;
  }

  @override
  Future<String?> stop(String recorderId) async {
    await Future<void>.delayed(stopDelay);
    final out = File(_path!);
    if (source == null) {
      out.writeAsBytesSync(Uint8List.fromList(List<int>.filled(512, 0)));
    } else {
      File(source!).copySync(out.path);
    }
    return out.path;
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -20, max: -10);

  @override
  Future<bool> isRecording(String recorderId) async => _path != null;

  @override
  Future<void> cancel(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      Stream.value(RecordState.record);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('voice_dur');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    tmp.deleteSync(recursive: true);
  });

  test('длительность берётся из файла, а не по часам', () async {
    // Записали 11,6 секунды, а остановка шла долго: в чате было 0:40
    // при десяти секундах звука (комментарий в канале 26.10.2026).
    RecordPlatform.instance = _FakeRecord(
      source: 'test/fixtures/voice/tone_11_6s_moov_start.m4a',
      stopDelay: const Duration(milliseconds: 400),
    );
    final rec = VoiceRecorderService.instance;
    await rec.start();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final capture = await rec.stop();
    expect(capture, isNotNull);
    expect(capture!.duration.inMilliseconds, closeTo(11600, 50));
  });

  test('без заголовка в файле ожидание остановки не идёт в длительность',
      () async {
    RecordPlatform.instance = _FakeRecord(
      source: null,
      stopDelay: const Duration(milliseconds: 1200),
    );
    final rec = VoiceRecorderService.instance;
    await rec.start();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final capture = await rec.stop();
    expect(capture, isNotNull);
    // Палец отпустили через 200 мс; ещё 1200 мс ответа плагина — не звук.
    expect(capture!.duration.inMilliseconds, lessThan(700));
    expect(capture.duration.inMilliseconds, greaterThanOrEqualTo(150));
  });
}
