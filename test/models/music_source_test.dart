import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/music_source.dart';

/// Откуда трек: свой файл играет в приложении, ссылка открывается в сервисе.
void main() {
  test('стриминговые сервисы узнаются по адресу', () {
    expect(musicSourceOf('https://music.yandex.ru/album/1/track/2').name,
        'Яндекс Музыка');
    expect(musicSourceOf('https://open.spotify.com/track/x').name, 'Spotify');
    expect(musicSourceOf('https://music.youtube.com/watch?v=1').name,
        'YouTube Music');
    expect(musicSourceOf('https://youtu.be/abc').name, 'YouTube');
    expect(musicSourceOf('https://vk.com/audio123').name, 'VK Музыка');
  });

  test('любая ссылка снаружи открывается в браузере', () {
    final s = musicSourceOf('https://example.com/song');
    expect(s.external, isTrue);
    expect(s.name, isNull);
  });

  test('свой файл играет в приложении', () {
    expect(musicSourceOf('pb://media/abc/track.m4a').external, isFalse);
    expect(musicSourceOf('localfile:///data/x.mp3').external, isFalse);
  });

  test('пустой адрес — играть нечего', () {
    expect(musicSourceOf(null).playable, isFalse);
    expect(musicSourceOf('').playable, isFalse);
    expect(musicSourceOf('pb://media/a/b.mp3').playable, isTrue);
  });
}
