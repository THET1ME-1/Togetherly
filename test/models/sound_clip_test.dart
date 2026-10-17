import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/sound_clip.dart';

void main() {
  test('звук переживает круг json', () {
    const clip = SoundClip(
      url: 'pb://media/abcdefghij12345/sound.m4a',
      duration: Duration(milliseconds: 23400),
      peaks: '0123456789012345678901234567890123456789',
      kind: SoundKind.song,
      title: 'Lovely Day',
      artist: 'Bill Withers',
    );
    final back = SoundClip.fromJson(clip.toJson())!;
    expect(back.url, clip.url);
    expect(back.duration, clip.duration);
    expect(back.peaks, clip.peaks);
    expect(back.kind, SoundKind.song);
    expect(back.title, 'Lovely Day');
    expect(back.artist, 'Bill Withers');
  });

  test('мусор вместо звука даёт null, а не падение', () {
    expect(SoundClip.fromJson(null), isNull);
    expect(SoundClip.fromJson('не json'), isNull);
    expect(SoundClip.fromJson({'ms': 100}), isNull);
    expect(SoundClip.fromJson({'url': '   '}), isNull);
    expect(SoundClip.fromJson(42), isNull);
  });

  test('длительность строкой и неизвестный вид читаются', () {
    final clip = SoundClip.fromJson(
        {'url': 'pb://media/x/y.m4a', 'ms': '1500', 'kind': 'опера'})!;
    expect(clip.duration, const Duration(milliseconds: 1500));
    expect(clip.kind, SoundKind.voice);
    expect(clip.bars, hasLength(40));
  });

  test('отрицательная длительность становится нулём', () {
    final clip = SoundClip.fromJson({'url': 'pb://media/x/y.m4a', 'ms': -5})!;
    expect(clip.duration, Duration.zero);
  });

  test('json-строкой тоже читается', () {
    final clip = SoundClip.fromJson(
        '{"url":"pb://media/x/y.m4a","ms":900,"kind":"song"}')!;
    expect(clip.kind, SoundKind.song);
    expect(clip.duration, const Duration(milliseconds: 900));
  });

  test('длинное название обрезается до 120 знаков', () {
    final clip = SoundClip.fromJson({'url': 'pb://m/x', 'title': 'а' * 500})!;
    expect(clip.title.length, 120);
  });

  test('пустые название и исполнитель не пишутся в json', () {
    const clip = SoundClip(
        url: 'pb://m/x',
        duration: Duration(seconds: 2),
        peaks: '',
        kind: SoundKind.voice);
    expect(clip.toJson().containsKey('title'), isFalse);
    expect(clip.toJson().containsKey('artist'), isFalse);
    expect(clip.toJson()['kind'], 'voice');
  });

  test('неотправленный звук — путь на диске', () {
    SoundClip at(String url) => SoundClip(
        url: url, duration: Duration.zero, peaks: '', kind: SoundKind.voice);
    expect(at('/data/x.m4a').isLocalFile, isTrue);
    expect(at('localfile:///x.m4a').isLocalFile, isTrue);
    expect(at('pb://media/a/b').isLocalFile, isFalse);
    expect(at('https://togetherly.day/x').isLocalFile, isFalse);
  });

  test('заменить ссылку после заливки', () {
    const local = SoundClip(
        url: '/data/x.m4a',
        duration: Duration(seconds: 3),
        peaks: '1111111111111111111111111111111111111111',
        kind: SoundKind.song,
        title: 'T');
    final sent = local.withUrl('pb://media/abc/x.m4a');
    expect(sent.url, 'pb://media/abc/x.m4a');
    expect(sent.duration, local.duration);
    expect(sent.peaks, local.peaks);
    expect(sent.title, 'T');
  });

  test('пределы звука', () {
    expect(SoundLimits.memoryVoice, const Duration(minutes: 3));
    expect(SoundLimits.memorySong, const Duration(seconds: 60));
    expect(SoundLimits.giftVoice, const Duration(seconds: 60));
    expect(SoundLimits.giftSong, const Duration(seconds: 30));
  });
}
