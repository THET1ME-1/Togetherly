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

  // TOG-82, 07.11.2026: «загружала свою раскраску… а фон просто удалился у
  // партнёра». Контур своей раскраски партнёр скачивал только при смене
  // картинки на холсте: сорвалось скачивание или ссылка пришла позже — второй
  // попытки не было. А у автора сорвавшаяся загрузка контура не повторялась
  // вовсе: на 07.11.2026 так 58 листов, у партнёров там пустой лист навсегда.
  group('контур своей раскраски', () {
    test('партнёр забирает контур, пока его нет, даже без смены картинки', () {
      expect(coloringOutlineToAdopt(picture: 'own_1', outlineRef: 'pb://media/a/b.png', haveOutline: false), isTrue);
    });

    test('контур уже есть — второй раз не качаем', () {
      expect(coloringOutlineToAdopt(picture: 'own_1', outlineRef: 'pb://media/a/b.png', haveOutline: true), isFalse);
    });

    test('ссылки нет или раскраска встроенная — качать нечего', () {
      expect(coloringOutlineToAdopt(picture: 'own_1', outlineRef: '', haveOutline: false), isFalse);
      expect(coloringOutlineToAdopt(picture: 'own_1', outlineRef: null, haveOutline: false), isFalse);
      expect(coloringOutlineToAdopt(picture: 'metro', outlineRef: 'pb://x', haveOutline: false), isFalse);
      expect(coloringOutlineToAdopt(picture: null, outlineRef: 'pb://x', haveOutline: false), isFalse);
    });

    test('у автора контур есть, а на сервере ссылки нет — дослать', () {
      expect(coloringMetaNeedsOutline(remotePicture: 'own_1', local: 'own_1', remoteOutline: '', haveOutline: true), isTrue);
      expect(coloringMetaNeedsOutline(remotePicture: 'own_1', local: 'own_1', remoteOutline: null, haveOutline: true), isTrue);
    });

    test('ссылка на сервере есть, контура у себя нет, картинка другая или встроенная — молчим', () {
      expect(coloringMetaNeedsOutline(remotePicture: 'own_1', local: 'own_1', remoteOutline: 'pb://x', haveOutline: true), isFalse);
      expect(coloringMetaNeedsOutline(remotePicture: 'own_1', local: 'own_1', remoteOutline: '', haveOutline: false), isFalse);
      expect(coloringMetaNeedsOutline(remotePicture: 'own_2', local: 'own_1', remoteOutline: '', haveOutline: true), isFalse);
      expect(coloringMetaNeedsOutline(remotePicture: 'metro', local: 'metro', remoteOutline: '', haveOutline: true), isFalse);
    });

    test('экран спрашивает оба правила', () {
      final screen = File('lib/screens/draw_screen.dart').readAsStringSync();
      expect(screen, contains('coloringOutlineToAdopt('));
      expect(screen, contains('coloringMetaNeedsOutline('));
    });
  });
}
