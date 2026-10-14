// Наклейки на пинах: подключение по исходникам.
//
// Разъезд тут молчит: блок без обёртки просто не показывает наклеек, а
// операция без ветки в очереди лежит там вечно. Тест сверяет, что каждый вид
// пина в ленте и в открытой записи несёт слой наклеек, меню знает карточку,
// очередь умеет операцию, а сервер её принимает.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Вызовы `name(memory, …)`, как бы ни были перенесены строки.
int _calls(String text, String name) =>
    RegExp('${RegExp.escape(name)}\\(\\s*memory,').allMatches(text).length;

int _count(String text, String needle) => needle.allMatches(text).length;

void main() {
  test('каждый вид пина в ленте несёт слой наклеек', () {
    final feed = _read('lib/screens/memory_lane_screen.dart');
    // Обложка фото, ролик без кадра, место, музыка, заметка, книга, кино,
    // видео по ссылке.
    expect(_calls(feed, '_stickerAnchor'), greaterThanOrEqualTo(8));
    for (final tile in [
      '_photoTile',
      '_locationTile',
      '_musicTile',
      '_textTile',
      '_bookTile',
      '_movieTile',
      '_videoLinkTile',
    ]) {
      final start = feed.indexOf('Widget $tile(');
      expect(start, isNonNegative, reason: tile);
      final end = feed.indexOf('\n  Widget _', start + 10);
      final body = feed.substring(start, end < 0 ? feed.length : end);
      final viaMedia = tile == '_photoTile' && body.contains('_momentMedia(');
      expect(body.contains('_stickerAnchor(') || viaMedia, isTrue,
          reason: '$tile без слоя наклеек');
    }
  });

  test('меню долгого нажатия получает карточку', () {
    final feed = _read('lib/screens/memory_lane_screen.dart');
    expect(feed, contains('StickerCardScope(\n'));
    expect(feed, contains('card: StickerCardScope.maybeOf(cardContext)'));
    expect(feed, contains("trKey('stickerAdd')"));
  });

  test('лист наклеек знает пару: без неё нет «Своих»', () {
    final feed = _read('lib/screens/memory_lane_screen.dart');
    final call = RegExp(r'showStickerPicker\(([^;]*)\);').firstMatch(feed);
    expect(call, isNotNull);
    expect(call!.group(1), contains('groupId: _groupId'));
  });

  test('открытая запись показывает наклейки на обложке', () {
    final detail = _read('lib/screens/memory_lane/detail.dart');
    // Заметка, ссылка, своё видео без кадра, музыка, книга, кино, место и
    // первый кадр фото.
    expect(_calls(detail, '_stickers'), greaterThanOrEqualTo(8));
  });

  test('очередь знает операцию наклейки', () {
    final outbox = _read('lib/services/offline/outbox_service.dart');
    // Ключ записи (порядок правок), склейка повторов и исполнение.
    expect(_count(outbox, "'memorySticker'"), greaterThanOrEqualTo(3));
    expect(outbox, contains('_applySticker'));
  });

  test('сервер принимает операцию и бережёт наклейки при правке', () {
    final hotpath = _read('pocketbase/hotpath/hotpath.py');
    expect(hotpath, contains('"sticker_put" in body'));
    expect(hotpath, contains('_наклейка_воспоминания'));
    expect(hotpath, contains("data ? 'stickers'"));
  });
}
