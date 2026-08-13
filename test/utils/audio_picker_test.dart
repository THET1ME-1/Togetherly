import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/audio_picker.dart';

void main() {
  setUp(resetAudioPickerForTest);

  test('пока открыт выбор файла, второй запрос не уходит в систему', () async {
    // На iPhone file_picker отбивает второй запрос и ОТМЕНЯЕТ первый:
    // «PlatformException(multiple_request, Cancelled by a second request)».
    // Человек видел это после обычного двойного касания кнопки.
    var calls = 0;
    final gate = Completer<FilePickerResult?>();

    final first = pickAudioFile(open: () {
      calls++;
      return gate.future;
    });
    final second = pickAudioFile(open: () {
      calls++;
      return Future.value(null);
    });

    expect(await second, isNull);
    expect(calls, 1);

    gate.complete(null);
    await first;
  });

  test('после закрытия выбора кнопка снова работает', () async {
    var calls = 0;
    Future<FilePickerResult?> open() {
      calls++;
      return Future.value(null);
    }

    await pickAudioFile(open: open);
    await pickAudioFile(open: open);

    expect(calls, 2);
  });

  test('отказ системы не запирает кнопку навсегда', () async {
    var calls = 0;

    await expectLater(
      pickAudioFile(open: () {
        calls++;
        return Future<FilePickerResult?>.error(Exception('нет доступа'));
      }),
      throwsException,
    );

    await pickAudioFile(open: () {
      calls++;
      return Future.value(null);
    });

    expect(calls, 2);
  });
}
