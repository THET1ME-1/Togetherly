// Какие файлы воспоминания можно положить в галерею.
//
// Прежняя кнопка брала только обложку (`imageUrl`) и считала внешней ссылкой
// всё, что не похоже на Firebase, — после переезда на свой сервер это каждый
// файл, и кнопка открывала браузер (жалоба 19.09.2026). Правила отбора теперь
// живут здесь и проверяются без телефона.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/memory_media.dart';

Memory _m({
  MemoryType type = MemoryType.photo,
  String? imageUrl,
  List<String>? imageUrls,
  String? videoUrl,
  String? musicUrl,
  bool sealed = false,
  DateTime? openAt,
  bool isSecret = false,
}) =>
    Memory(
      id: 'm1',
      groupId: 'g1',
      authorUid: 'u1',
      authorName: 'Саша',
      type: type,
      createdAt: DateTime(2026, 9, 5, 13, 5),
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      musicUrl: musicUrl,
      sealed: sealed,
      openAt: openAt,
      isSecret: isSecret,
    );

void main() {
  group('memoryMediaFiles', () {
    test('воспоминание из многих кадров отдаёт все кадры по порядку', () {
      final urls = [for (var i = 0; i < 93; i++) 'pb://media/r$i/f$i.webp'];
      final files = memoryMediaFiles(_m(imageUrl: urls.first, imageUrls: urls));
      expect(files, hasLength(93));
      expect(files.map((f) => f.ref), urls);
      expect(files.map((f) => f.index), List.generate(93, (i) => i));
      expect(files.every((f) => f.kind == SaveKind.photo), isTrue);
    });

    test('один кадр без списка берётся из imageUrl', () {
      final files = memoryMediaFiles(_m(imageUrl: 'pb://media/a/b.jpg'));
      expect(files.single.ref, 'pb://media/a/b.jpg');
    });

    test('смешанная запись отдаёт и кадры, и ролик', () {
      final files = memoryMediaFiles(_m(
        imageUrls: ['pb://media/a/1.webp', 'pb://media/a/2.webp'],
        videoUrl: 'pb://media/v/clip.mp4',
      ));
      expect(files.map((f) => f.kind),
          [SaveKind.photo, SaveKind.photo, SaveKind.video]);
    });

    test('у видео-записи обложка не считается отдельным кадром', () {
      final files = memoryMediaFiles(_m(
        type: MemoryType.video,
        imageUrl: 'pb://media/t/thumb.jpg',
        videoUrl: 'pb://media/v/clip.mp4',
      ));
      expect(files.single.kind, SaveKind.video);
      expect(files.single.thumb, 'pb://media/t/thumb.jpg');
    });

    test('ролик по ссылке на площадку не скачивается', () {
      expect(
          memoryMediaFiles(_m(
            type: MemoryType.videoLink,
            videoUrl: 'https://youtu.be/dQw4w9WgXcQ',
          )),
          isEmpty);
    });

    test('музыка: свой файл сохраняется, ссылка на площадку — нет', () {
      final own = memoryMediaFiles(
          _m(type: MemoryType.music, musicUrl: 'pb://media/s/song.mp3'));
      expect(own.single.kind, SaveKind.audio);
      final link = memoryMediaFiles(_m(
          type: MemoryType.music,
          musicUrl: 'https://music.yandex.ru/album/1/track/2'));
      expect(link, isEmpty);
    });

    test('запечатанная капсула не отдаёт ничего до даты открытия', () {
      final m = _m(
        imageUrl: 'pb://media/a/b.jpg',
        sealed: true,
        openAt: DateTime(2026, 11, 12),
      );
      expect(memoryMediaFiles(m, now: DateTime(2026, 9, 19)), isEmpty);
      expect(memoryMediaFiles(m, now: DateTime(2026, 11, 13)), hasLength(1));
    });

    test('секретная запись под замком не отдаёт ничего', () {
      final m = _m(imageUrl: 'pb://media/a/b.jpg', isSecret: true);
      expect(memoryMediaFiles(m, secretUnlocked: false), isEmpty);
      expect(memoryMediaFiles(m, secretUnlocked: true), hasLength(1));
    });

    test('заметка и место без медиа — пусто', () {
      expect(memoryMediaFiles(_m(type: MemoryType.text)), isEmpty);
      expect(memoryMediaFiles(_m(type: MemoryType.location)), isEmpty);
    });

    test('пустые строки в списке кадров пропускаются', () {
      final files = memoryMediaFiles(
          _m(imageUrls: ['', 'pb://media/a/1.webp', ' ']));
      expect(files.single.ref, 'pb://media/a/1.webp');
      expect(files.single.index, 0);
    });
  });

  group('свой файл и ключ', () {
    test('свои: pb://, адрес нашего сервера, ещё не отправленный файл', () {
      expect(isOwnMediaUrl('pb://media/a/b.jpg'), isTrue);
      expect(
          isOwnMediaUrl('https://togetherly.day/api/files/media/a/b.jpg?token=x'),
          isTrue);
      expect(isOwnMediaUrl('localfile:///data/user/0/x/f.jpg'), isTrue);
      expect(isOwnMediaUrl('https://youtu.be/xyz'), isFalse);
      expect(isOwnMediaUrl('https://firebasestorage.googleapis.com/x.jpg'),
          isFalse);
    });

    test('ключ одинаков у pb:// и у готового адреса с токеном', () {
      expect(
        mediaKey('https://togetherly.day/api/files/media/a/b.jpg?token=abc'),
        mediaKey('pb://media/a/b.jpg'),
      );
    });

    test('расширение берётся из имени файла, запасное — по виду', () {
      expect(mediaExt('pb://media/a/IMG_1.HEIC', SaveKind.photo), 'heic');
      expect(mediaExt('pb://media/a/b.webp?x=1', SaveKind.photo), 'webp');
      expect(mediaExt('pb://media/a/noext', SaveKind.video), 'mp4');
      expect(mediaExt('pb://media/a/noext', SaveKind.photo), 'jpg');
      expect(mediaExt('pb://media/a/noext', SaveKind.audio), 'mp3');
    });
  });

  group('имя в галерее и сводка', () {
    test('имя: Togetherly, дата воспоминания, номер кадра', () {
      final f = memoryMediaFiles(_m(imageUrls: [
        'pb://media/a/1.webp',
        'pb://media/a/2.webp',
      ]))[1];
      expect(galleryFileName(DateTime(2026, 9, 5, 13, 5, 7), f),
          'Togetherly_20260905_130507_02.webp');
    });

    test('сводка считает виды и примерный вес', () {
      final s = summarizeMedia(memoryMediaFiles(_m(
        imageUrls: [for (var i = 0; i < 93; i++) 'pb://media/r$i/f.webp'],
        videoUrl: 'pb://media/v/clip.mp4',
      )));
      expect(s.photos, 93);
      expect(s.videos, 1);
      expect(s.total, 94);
      // 93 × 336 КБ + 4,2 МБ ≈ 35 МБ — та же цифра стоит в макете.
      expect((s.bytes / (1024 * 1024)).round(), 35);
    });
  });
}
