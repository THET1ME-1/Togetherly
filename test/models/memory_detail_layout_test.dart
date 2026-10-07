import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/memory_detail_layout.dart';

/// Какие записи открываются экраном «как фото»: шапка с автором, крупная
/// обложка, реакции, комментарии и плавающий тулбар (07.10.2026).
void main() {
  test('фото с кадрами — экраном', () {
    expect(opensAsMoment(MemoryType.photo, hasPhotos: true), isTrue);
  });

  test('фото без кадров — листом: показывать крупно нечего', () {
    expect(opensAsMoment(MemoryType.photo, hasPhotos: false), isFalse);
  });

  test('своё видео — экраном и без обложки', () {
    expect(opensAsMoment(MemoryType.video, hasPhotos: false), isTrue);
    expect(opensAsMoment(MemoryType.video, hasPhotos: true), isTrue);
  });

  test('видео по ссылке и заметка — экраном', () {
    expect(opensAsMoment(MemoryType.videoLink, hasPhotos: false), isTrue);
    expect(opensAsMoment(MemoryType.text, hasPhotos: false), isTrue);
  });

  test('книга, кино, музыка, место — по-прежнему листом', () {
    for (final t in [
      MemoryType.book,
      MemoryType.movie,
      MemoryType.music,
      MemoryType.location,
    ]) {
      expect(opensAsMoment(t, hasPhotos: false), isFalse, reason: t.name);
    }
  });

  test('подпись шапки считает кадры только у фото', () {
    expect(momentCountsPhotos(MemoryType.photo), isTrue);
    expect(momentCountsPhotos(MemoryType.video), isFalse,
        reason: 'обложка видео — не фото, «1 фото» у ролика врёт');
    expect(momentCountsPhotos(MemoryType.text), isFalse);
    expect(momentCountsPhotos(MemoryType.videoLink), isFalse);
  });
}
