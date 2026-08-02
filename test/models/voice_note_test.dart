import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/voice_note.dart';

void main() {
  group('Огибающая громкости', () {
    test('всегда ровно 40 символов, сколько бы замеров ни пришло', () {
      for (final n in [0, 1, 7, 40, 41, 300]) {
        final peaks = VoicePeaks.encode(List.generate(n, (i) => i / (n + 1)));
        expect(peaks.length, VoicePeaks.count,
            reason: 'на $n замерах длина уехала');
      }
    });

    test('пишем только цифры — строка уходит в text-поле как есть', () {
      final peaks = VoicePeaks.encode(List.generate(120, (i) => (i % 13) / 12));
      expect(RegExp(r'^[0-9]{40}$').hasMatch(peaks), isTrue, reason: peaks);
    });

    test('громкое место выше тихого', () {
      final quiet = List.filled(20, 0.05);
      final loud = List.filled(20, 0.9);
      final peaks = VoicePeaks.decode(VoicePeaks.encode([...quiet, ...loud]));
      final firstHalf = peaks.take(20).reduce((a, b) => a + b) / 20;
      final secondHalf = peaks.skip(20).reduce((a, b) => a + b) / 20;
      expect(secondHalf, greaterThan(firstHalf + 0.3));
    });

    test('тихий голос читается так же, как громкий — нормализуем по максимуму',
        () {
      final loudTalk = [0.2, 0.9, 0.35, 0.8, 0.15];
      final quietTalk = loudTalk.map((v) => v * 0.12).toList();
      final a = VoicePeaks.decode(VoicePeaks.encode(loudTalk));
      final b = VoicePeaks.decode(VoicePeaks.encode(quietTalk));
      for (var i = 0; i < a.length; i++) {
        expect((a[i] - b[i]).abs(), lessThan(0.12),
            reason: 'столбик $i разошёлся: ${a[i]} против ${b[i]}');
      }
    });

    test('тишина остаётся тишиной, а не превращается в шум', () {
      final peaks = VoicePeaks.decode(VoicePeaks.encode(List.filled(30, 0.0)));
      expect(peaks.every((v) => v <= VoicePeaks.floor + 0.01), isTrue,
          reason: peaks.toString());
    });

    test('разбор возвращает 40 значений в границах 0..1', () {
      final peaks = VoicePeaks.decode('0123456789' * 4);
      expect(peaks.length, VoicePeaks.count);
      expect(peaks.every((v) => v >= 0 && v <= 1), isTrue);
    });

    test('пустая и битая строка дают ровную полосу, а не пустоту', () {
      for (final raw in ['', 'мусор', '12', '9' * 200]) {
        final peaks = VoicePeaks.decode(raw);
        expect(peaks.length, VoicePeaks.count, reason: 'на «$raw»');
        expect(peaks.every((v) => v > 0), isTrue, reason: 'на «$raw»');
      }
    });
  });

  group('Голосовое в записи чата', () {
    test('собирается из полей PocketBase', () {
      final note = VoiceNote.fromFields(
        url: 'pb://media/abc/voice.m4a',
        ms: 8400,
        peaks: '5' * 40,
      );
      expect(note, isNotNull);
      expect(note!.duration, const Duration(milliseconds: 8400));
      expect(note.peaks.length, 40);
    });

    test('без ссылки голосового нет', () {
      expect(VoiceNote.fromFields(url: '', ms: 8400, peaks: '5' * 40), isNull);
      expect(VoiceNote.fromFields(url: null, ms: 0, peaks: ''), isNull);
    });

    test('местная запись отличается от серверной', () {
      final local = VoiceNote.fromFields(
          url: '/data/user/0/rec/voice_1.m4a', ms: 1200, peaks: '');
      final remote = VoiceNote.fromFields(
          url: 'pb://media/abc/voice.m4a', ms: 1200, peaks: '');
      expect(local!.isLocalFile, isTrue);
      expect(remote!.isLocalFile, isFalse);
    });

    test('длительность подписывается как М:СС', () {
      expect(VoiceNote.formatDuration(const Duration(seconds: 7)), '0:07');
      expect(VoiceNote.formatDuration(const Duration(seconds: 62)), '1:02');
      expect(VoiceNote.formatDuration(const Duration(minutes: 3)), '3:00');
      expect(VoiceNote.formatDuration(Duration.zero), '0:00');
    });
  });
}
