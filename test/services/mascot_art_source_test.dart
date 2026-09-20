import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot.dart';
import 'package:love_app/models/mascot_anim.dart';
import 'package:love_app/services/mascot/mascot_art_source.dart';

Mascot _mascot({String? imageUrl, String? defaultAsset, String? catalogUrl}) => Mascot(
      id: 'm1',
      name: 'Зверёк',
      imageUrl: imageUrl,
      defaultAsset: defaultAsset,
      catalogUrl: catalogUrl,
      createdBy: 'me',
      createdAt: DateTime(2026, 9, 20),
    );

MascotAnim _anim() => const MascotAnim(
      id: 'm1',
      nameRu: 'Пудя',
      nameEn: 'Pudya',
      sheetUrl: 'https://example.invalid/sheet.png',
      frame: 48,
      cols: 12,
      fps: 9,
      rows: ['live', 'sad'],
      levelOffsets: {3: 0, 1: 9, 2: 18},
    );

void main() {
  group('откуда брать картинку для виджета', () {
    test('анимированный атлас старше всего: иначе на стол уедет вся простыня кадров', () {
      final source = mascotArtSource(
        _mascot(catalogUrl: 'https://example.invalid/sheet.png'),
        _anim(),
      );
      expect(source.kind, MascotArtKind.atlas);
      expect(source.pixel, isTrue);
    });

    test('встроенный маскот берётся из ассетов приложения', () {
      final source = mascotArtSource(
        _mascot(defaultAsset: 'assets/mascots/bear.png'),
        null,
      );
      expect(source.kind, MascotArtKind.asset);
      expect(source.ref, 'assets/mascots/bear.png');
      expect(source.pixel, isFalse);
    });

    test('каталожная картинка берётся по публичной ссылке', () {
      final source = mascotArtSource(
        _mascot(catalogUrl: 'https://example.invalid/mascot.png'),
        null,
      );
      expect(source.kind, MascotArtKind.network);
      expect(source.ref, 'https://example.invalid/mascot.png');
    });

    test('нарисованный человеком маскот берётся из хранилища', () {
      final source = mascotArtSource(
        _mascot(imageUrl: 'pb://mascots/abc.png'),
        null,
      );
      expect(source.kind, MascotArtKind.storage);
      expect(source.ref, 'pb://mascots/abc.png');
    });

    test('ассет старше сетевой ссылки: он под рукой и не требует сети', () {
      final source = mascotArtSource(
        _mascot(defaultAsset: 'assets/mascots/bear.png', imageUrl: 'pb://mascots/abc.png'),
        null,
      );
      expect(source.kind, MascotArtKind.asset);
    });

    test('у маскота без картинки виджету нечего показывать', () {
      expect(mascotArtSource(_mascot(), null).kind, MascotArtKind.none);
    });
  });

  group('сон показываем только тем, кто умеет спать', () {
    test('у персонажа без ночной строки окно пустое', () {
      expect(mascotSleepsInWidget(_anim()), isFalse);
      expect(mascotSleepsInWidget(null), isFalse);
    });

    test('ночная строка включает окно сна', () {
      const anim = MascotAnim(
        id: 'kuku',
        nameRu: 'Ку-ку',
        nameEn: 'Cuckoo',
        sheetUrl: 'https://example.invalid/kuku.png',
        frame: 96,
        cols: 12,
        fps: 9,
        rows: ['live', 'sleep'],
        nightIdle: 'sleep',
      );
      expect(mascotSleepsInWidget(anim), isTrue);
    });
  });
}
