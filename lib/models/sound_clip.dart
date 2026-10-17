import 'dart:convert';
import 'dart:math' as math;

import 'voice_note.dart';

/// Откуда звук: голос с микрофона или кусок песни из файла.
enum SoundKind { voice, song }

/// Пределы звука. Кусок песни режет телефон, поэтому на сервер едет не вся
/// песня на десять мегабайт, а полминуты в m4a.
abstract final class SoundLimits {
  static const Duration memoryVoice = Duration(minutes: 3);
  static const Duration memorySong = Duration(seconds: 60);
  static const Duration giftVoice = Duration(seconds: 60);
  static const Duration giftSong = Duration(seconds: 30);

  /// Края куска затухают, иначе он обрывается на полуслове.
  static const Duration fade = Duration(milliseconds: 400);

  /// Исходник больше этого не открываем: двухчасовой микс на сотни мегабайт
  /// телефон будет разбирать минутами.
  static const int maxSourceBytes = 300 * 1024 * 1024;
}

/// Звук, приложенный к воспоминанию или подарку «Песня».
///
/// Волна лежит в самой записи сорока цифрами, как у голосовых в чате: обе
/// стороны рисуют её сразу, а файл качается только по нажатию «слушать».
class SoundClip {
  const SoundClip({
    required this.url,
    required this.duration,
    required this.peaks,
    required this.kind,
    this.title = '',
    this.artist = '',
  });

  /// `pb://media/<id>/<файл>` у отправленного, путь на диске — пока не залит.
  final String url;
  final Duration duration;

  /// Сорок цифр `0`–`9` ([VoicePeaks]).
  final String peaks;
  final SoundKind kind;

  /// Название и исполнитель песни из тегов файла. У голоса пусто.
  final String title;
  final String artist;

  /// Значения 0..1 под столбики волны, всегда сорок штук.
  List<double> get bars => VoicePeaks.decode(peaks);

  bool get isLocalFile => !url.startsWith('pb://') && !url.startsWith('http');

  SoundClip withUrl(String next) => SoundClip(
        url: next,
        duration: duration,
        peaks: peaks,
        kind: kind,
        title: title,
        artist: artist,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'ms': duration.inMilliseconds,
        'peaks': peaks,
        'kind': kind.name,
        if (title.isNotEmpty) 'title': title,
        if (artist.isNotEmpty) 'artist': artist,
      };

  /// Звук из записи. Битое поле не роняет ленту: без ссылки звука нет вовсе.
  static SoundClip? fromJson(Object? raw) {
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    if (raw is! Map) return null;
    final url = (raw['url'] ?? '').toString().trim();
    if (url.isEmpty) return null;
    final ms = raw['ms'];
    final millis = ms is num ? ms.toInt() : int.tryParse('${ms ?? ''}') ?? 0;
    return SoundClip(
      url: url,
      duration: Duration(milliseconds: math.max(0, millis)),
      peaks: (raw['peaks'] ?? '').toString(),
      kind: raw['kind'] == 'song' ? SoundKind.song : SoundKind.voice,
      title: _cut((raw['title'] ?? '').toString().trim()),
      artist: _cut((raw['artist'] ?? '').toString().trim()),
    );
  }

  /// Звук подарка: ссылка в поле `sound`, остальное json-строкой в
  /// `sound_meta`. Битый meta не прячет звук, он играет без волны.
  static SoundClip? fromGiftRecord(Map<String, dynamic> record) {
    final url = (record['sound'] ?? '').toString().trim();
    if (url.isEmpty) return null;
    Object? meta = record['sound_meta'];
    if (meta is String) {
      try {
        meta = jsonDecode(meta);
      } catch (_) {
        meta = null;
      }
    }
    return fromJson({if (meta is Map) ...meta, 'url': url});
  }

  static String _cut(String text) =>
      text.length > 120 ? text.substring(0, 120) : text;
}
