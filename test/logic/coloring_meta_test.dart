import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/coloring_meta.dart';

/// Картинка раскраски уходит на сервер одной записью при заведении листа, а
/// «Готово» и смена половин пишут мету через «обновить, а нет — создать».
/// Первая запись не дошла — «Готово» завело мету без картинки, и телефон
/// партнёра открывал лист обычным холстом: без контура и половин (обращение
/// 344, 19.10.2026, лист «Метро», 65 заливок партнёра).
void main() {
  group('когда дописать картинку раскраски', () {
    test('мета есть, картинки в ней нет, а телефон её знает', () {
      expect(
        coloringMetaNeedsPicture(remoteExists: true, remote: '', local: 'metro'),
        isTrue,
      );
      expect(
        coloringMetaNeedsPicture(remoteExists: true, remote: null, local: 'metro'),
        isTrue,
      );
    });

    test('картинка на сервере уже есть', () {
      expect(
        coloringMetaNeedsPicture(remoteExists: true, remote: 'metro', local: 'metro'),
        isFalse,
      );
    });

    test('меты ещё нет: картинку как раз пишет заведение листа', () {
      expect(
        coloringMetaNeedsPicture(remoteExists: false, remote: null, local: 'metro'),
        isFalse,
      );
    });

    test('обычный холст, не раскраска', () {
      expect(
        coloringMetaNeedsPicture(remoteExists: true, remote: '', local: null),
        isFalse,
      );
    });
  });

  group('записи меты несут картинку', () {
    final screen = File('lib/screens/draw_screen.dart').readAsStringSync();

    test('«Готово» и смена половин заводят мету вместе с картинкой', () {
      expect(screen, contains('setColoringDone(_groupId, _canvasId, next, pictureId: _coloringId)'));
      expect(RegExp(r'setColoringSwap\([^;]*pictureId: _coloringId').hasMatch(screen), isTrue);
    });

    test('экран дописывает картинку, если мета пришла без неё', () {
      expect(screen, contains('coloringMetaNeedsPicture('));
      expect(screen, contains('remoteExists: meta.exists'));
    });

    test('сервер отдаёт признак, что мета есть', () {
      final repo = File('lib/services/canvas_repository.dart').readAsStringSync();
      expect(repo, contains('exists: true'));
    });
  });
}
