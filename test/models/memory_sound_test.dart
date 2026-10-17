// Звук к фото- и видео-воспоминанию (обращение 244): голос или кусок песни
// лежит в json `data` записи полем `sound`.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/memory_media.dart';
import 'package:love_app/models/sound_clip.dart';
import 'package:love_app/services/offline/media_cache.dart';
import 'package:pocketbase/pocketbase.dart';

const _song = SoundClip(
  url: 'pb://media/abcdefghij12345/sound_1.m4a',
  duration: Duration(milliseconds: 30000),
  peaks: '1234567890123456789012345678901234567890',
  kind: SoundKind.song,
  title: 'Lovely Day',
  artist: 'Bill Withers',
);

Memory _photo({SoundClip? sound, MemoryType type = MemoryType.photo}) => Memory(
      id: 'm1',
      groupId: 'g1',
      authorUid: 'u1',
      authorName: 'Аня',
      type: type,
      createdAt: DateTime(2026, 9, 12, 19, 40),
      imageUrls: const [
        'pb://media/aaaaaaaaaaaaaaa/a.webp',
        'pb://media/bbbbbbbbbbbbbbb/b.webp',
      ],
      videoUrl: type == MemoryType.video ? 'pb://media/vvvvvvvvvvvvvvv/v.mp4' : null,
      sound: sound,
    );

void main() {
  test('звук переживает круг json записи', () {
    final back = Memory.fromJson(_photo(sound: _song).toJson());
    expect(back.sound, isNotNull);
    expect(back.sound!.url, _song.url);
    expect(back.sound!.kind, SoundKind.song);
    expect(back.sound!.title, 'Lovely Day');
    expect(back.sound!.duration, const Duration(seconds: 30));
  });

  test('запись без звука читается как раньше', () {
    expect(Memory.fromJson(_photo().toJson()).sound, isNull);
  });

  test('звук из записи базы', () {
    final rec = RecordModel({
      'id': 'm31vr0s1bt0vecn',
      'group_id': 'g1',
      'data': jsonEncode({
        'type': 'photo',
        'authorUid': 'u1',
        'createdAt': '2026-09-12T19:40:00.000Z',
        'imageUrls': ['pb://media/aaaaaaaaaaaaaaa/a.webp'],
        'sound': {'url': 'pb://media/x/s.m4a', 'ms': 24000, 'kind': 'voice', 'peaks': ''},
      }),
    });
    final memory = Memory.fromPb(rec);
    expect(memory.sound!.kind, SoundKind.voice);
    expect(memory.sound!.duration, const Duration(seconds: 24));
  });

  test('битое поле звука не роняет запись', () {
    final json = _photo().toJson()..['sound'] = 'мусор';
    final memory = Memory.fromJson(json);
    expect(memory.sound, isNull);
    expect(memory.imageUrls, hasLength(2));
  });

  test('сохранить: кадры и звук отдельным файлом', () {
    final files = memoryMediaFiles(_photo(sound: _song));
    expect(files.where((f) => f.kind == SaveKind.photo), hasLength(2));
    final audio = files.where((f) => f.kind == SaveKind.audio).toList();
    expect(audio, hasLength(1));
    expect(audio.single.ref, _song.url);
    expect(audio.single.index, 2);
  });

  test('у видео звук тоже сохраняется', () {
    final files = memoryMediaFiles(_photo(sound: _song, type: MemoryType.video));
    expect(files.any((f) => f.kind == SaveKind.audio), isTrue);
  });

  test('звук по чужой ссылке в галерею не идёт', () {
    final foreign = _song.withUrl('https://example.com/song.m4a');
    final files = memoryMediaFiles(_photo(sound: foreign));
    expect(files.any((f) => f.kind == SaveKind.audio), isFalse);
  });

  test('после заливки без сети ссылка звука подменяется', () {
    final data = _photo(sound: _song.withUrl('localfile:///p/s.m4a')).toJson();
    final changed = MediaCache.deepReplaceRefs(
        data, 'localfile:///p/s.m4a', 'pb://media/zzzzzzzzzzzzzzz/s.m4a');
    expect(changed, isTrue);
    expect(Memory.fromJson(data).sound!.url, 'pb://media/zzzzzzzzzzzzzzz/s.m4a');
  });
}
