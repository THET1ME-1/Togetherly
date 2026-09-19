// Меню «три точки» в листе воспоминания.
//
// До 19.09.2026 в нём было два пункта — «Указать место» и «Удалить» своей
// записи, — и у чужой записи с уже отмеченным местом код молча выходил:
// кнопка выглядела декорацией («три точки — пока декорация, не работает»).
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/memory_menu.dart';

Memory _m({
  MemoryType type = MemoryType.photo,
  String? caption,
  double? lat,
  double? lng,
  String? videoUrl,
  String? musicUrl,
  List<String>? imageUrls,
}) =>
    Memory(
      id: 'm1',
      groupId: 'g1',
      authorUid: 'partner',
      authorName: 'Лиза',
      type: type,
      createdAt: DateTime(2026, 9, 5),
      caption: caption,
      latitude: lat,
      longitude: lng,
      videoUrl: videoUrl,
      musicUrl: musicUrl,
      imageUrls: imageUrls,
      imageUrl: imageUrls?.first,
    );

void main() {
  test('чужая запись с местом: сохранить, выбрать, отправить, карта', () {
    final a = memoryMenuActions(
      _m(
        imageUrls: ['pb://media/a/1.webp', 'pb://media/a/2.webp'],
        caption: 'Лето на Днестре',
        lat: 46.9,
        lng: 29.1,
      ),
      isOwner: false,
      canSetPlace: false,
    );
    expect(a, [
      MemoryMenuAction.saveAll,
      MemoryMenuAction.pick,
      MemoryMenuAction.share,
      MemoryMenuAction.copyCaption,
      MemoryMenuAction.openMap,
    ]);
  });

  test('один кадр: выбирать нечего, сохранить и отправить есть', () {
    final a = memoryMenuActions(_m(imageUrls: ['pb://media/a/1.webp']),
        isOwner: false, canSetPlace: false);
    expect(a, contains(MemoryMenuAction.saveAll));
    expect(a, isNot(contains(MemoryMenuAction.pick)));
    expect(a, contains(MemoryMenuAction.share));
  });

  test('своя запись без места: указать место и удалить', () {
    final a = memoryMenuActions(_m(imageUrls: ['pb://media/a/1.webp']),
        isOwner: true, canSetPlace: true);
    expect(a, containsAllInOrder(
        [MemoryMenuAction.setPlace, MemoryMenuAction.delete]));
    expect(a.last, MemoryMenuAction.delete);
  });

  test('ролик по ссылке: открыть ссылку вместо сохранения', () {
    final a = memoryMenuActions(
      _m(type: MemoryType.videoLink, videoUrl: 'https://youtu.be/x'),
      isOwner: false,
      canSetPlace: false,
    );
    expect(a, contains(MemoryMenuAction.openLink));
    expect(a, isNot(contains(MemoryMenuAction.saveAll)));
  });

  test('заметка партнёра с подписью: скопировать подпись', () {
    final a = memoryMenuActions(
        _m(type: MemoryType.text, caption: 'Скучаю'),
        isOwner: false,
        canSetPlace: false);
    expect(a, [MemoryMenuAction.copyCaption]);
  });

  test('ни одной записи с пустым меню у собравшейся пары не бывает', () {
    // Самая бедная запись: чужая заметка без текста и без места — место
    // можно указать, и меню не пустое.
    final a = memoryMenuActions(_m(type: MemoryType.text),
        isOwner: false, canSetPlace: true);
    expect(a, isNotEmpty);
  });
}
