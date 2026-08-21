import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/memory_photos.dart';

/// Выбор фото для виджета берёт снимки из ленты воспоминаний. Одна запись
/// бывает и с несколькими кадрами, и без единого.
Memory _photo(String id, {String? url, List<String>? urls, String? caption}) =>
    Memory(
      id: id,
      groupId: 'g',
      authorUid: 'u',
      authorName: 'Я',
      type: MemoryType.photo,
      imageUrl: url,
      imageUrls: urls,
      caption: caption,
      createdAt: DateTime(2026, 8, 1),
    );

void main() {
  test('берём и обложку, и остальные кадры записи', () {
    final out = photosFromMemories([
      _photo('1', url: 'a.jpg', urls: ['a.jpg', 'b.jpg'], caption: 'Прогулка'),
    ]);
    expect(out.map((p) => p.url), ['a.jpg', 'b.jpg']);
    expect(out.first.caption, 'Прогулка');
  });

  test('один кадр не задваивается', () {
    final out = photosFromMemories([_photo('1', url: 'a.jpg', urls: ['a.jpg'])]);
    expect(out.length, 1);
  });

  test('записи других видов пропускаем', () {
    final note = Memory(
      id: '2',
      groupId: 'g',
      authorUid: 'u',
      authorName: 'Я',
      type: MemoryType.text,
      createdAt: DateTime(2026, 8, 1),
    );
    expect(photosFromMemories([note]), isEmpty);
  });

  test('запись без единой ссылки не даёт битой плитки', () {
    expect(photosFromMemories([_photo('3')]), isEmpty);
    expect(photosFromMemories([_photo('4', url: '')]), isEmpty);
  });
}
