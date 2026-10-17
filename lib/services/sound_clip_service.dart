import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/sound_clip.dart';
import '../models/voice_note.dart';

/// Что нашлось в файле песни: длительность и теги.
class SongProbe {
  const SongProbe({required this.duration, this.title = '', this.artist = ''});

  final Duration duration;
  final String title;
  final String artist;
}

/// Почему песню не открыть: формат не знаком системе, файл огромный или
/// сломался разбор.
enum SoundClipError { unsupported, tooLarge, failed }

class SoundClipException implements Exception {
  const SoundClipException(this.reason, [this.detail = '']);

  final SoundClipError reason;
  final String detail;

  @override
  String toString() => 'SoundClipException($reason, $detail)';
}

/// Кусок песни из файла на телефоне.
///
/// Разбирает и режет натив (`love_app/sound_clip`): на Android MediaCodec, на
/// iPhone AVFoundation. Готовый кусок — m4a в `sound_outbox` документов
/// приложения: временную папку система чистит без спроса, а запись со звуком
/// может ждать сети сутками.
class SoundClipService {
  SoundClipService._();

  static final SoundClipService instance = SoundClipService._();

  static const MethodChannel _channel = MethodChannel('love_app/sound_clip');

  Future<SongProbe> probe(String path) async {
    await _checkSource(path);
    final raw = await _call('probe', {'path': path});
    final map = raw is Map ? raw : const {};
    return SongProbe(
      duration: Duration(milliseconds: _int(map['durationMs'])),
      title: (map['title'] ?? '').toString().trim(),
      artist: (map['artist'] ?? '').toString().trim(),
    );
  }

  /// Волна всей песни для рамки выбора: [buckets] значений 0..1.
  Future<List<double>> waveform(String path, {int buckets = 72}) async {
    await _checkSource(path);
    final raw = await _call('waveform', {'path': path, 'buckets': buckets});
    final values = <double>[
      if (raw is List)
        for (final value in raw)
          value is num ? value.toDouble().clamp(0.0, 1.0) : 0.0,
    ];
    if (values.isEmpty) return List<double>.filled(buckets, 0);
    return List<double>.generate(
        buckets, (i) => values[(i * values.length ~/ buckets)]);
  }

  /// Вырезает кусок песни. Длина больше [limit] режется до предела.
  Future<SoundClip> cut(
    String path, {
    required Duration start,
    required Duration length,
    Duration limit = SoundLimits.memorySong,
    String title = '',
    String artist = '',
  }) async {
    await _checkSource(path);
    final take = length > limit ? limit : length;
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory('${documents.path}/sound_outbox');
    await folder.create(recursive: true);
    final out =
        '${folder.path}/sound_${DateTime.now().microsecondsSinceEpoch}.m4a';
    try {
      final raw = await _call('clip', {
        'path': path,
        'startMs': start.inMilliseconds,
        'endMs': (start + take).inMilliseconds,
        'fadeMs': SoundLimits.fade.inMilliseconds,
        'outPath': out,
      });
      final map = raw is Map ? raw : const {};
      final peaks = <double>[
        if (map['peaks'] is List)
          for (final value in map['peaks'] as List)
            value is num ? value.toDouble() : 0.0,
      ];
      return SoundClip(
        url: (map['path'] ?? out).toString(),
        duration: Duration(milliseconds: _int(map['durationMs'])),
        peaks: VoicePeaks.encode(peaks),
        kind: SoundKind.song,
        title: title,
        artist: artist,
      );
    } catch (_) {
      // Недописанный кусок на диске никому не нужен
      try {
        final file = File(out);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _checkSource(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const SoundClipException(SoundClipError.failed, 'нет файла');
    }
    if (await file.length() > SoundLimits.maxSourceBytes) {
      throw const SoundClipException(SoundClipError.tooLarge);
    }
  }

  Future<Object?> _call(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on PlatformException catch (error) {
      throw SoundClipException(
        error.code == 'unsupported'
            ? SoundClipError.unsupported
            : SoundClipError.failed,
        error.message ?? '',
      );
    } on MissingPluginException {
      throw const SoundClipException(SoundClipError.failed, 'нет натива');
    }
  }

  static int _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;
}
