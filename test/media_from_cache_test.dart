// Ничего не качается дважды: картинки, звук и ролики берутся с диска.
//
// Разбор 26.08.2026 по счёту хостера. Раздача файлов отдавала 126 ГБ в сутки,
// и замер по типам показал, сколько раз просят ОДИН файл: аватарку 170 раз,
// фото 10,9, ролик 5,7, голосовое 4,2. Причины были разные, но корень общий:
// у каждого хозяина был свой кэш или не было никакого.
//
// • Картинки: часть экранов рисовала мимо общего кэша, на умолчании
//   cached_network_image (200 файлов, 30 дней) — маскоты и настроения
//   вытеснялись и качались снова.
// • Звук и видео игрались прямо из сети: `setUrl`, `networkUrl`.
// • Виджеты качали своё, мимо всех (см. widget_photo_no_refetch_test).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Все исходники приложения, кроме сгенерированных.
List<File> _sources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  group('картинки идут через общий кэш', () {
    test('ни один экран не рисует мимо OfflineImageCacheManager', () {
      final bad = <String>[];
      for (final f in _sources()) {
        final src = f.readAsStringSync();
        final calls = RegExp(r'CachedNetworkImage(Provider)?\(').allMatches(src).length;
        if (calls == 0) continue;
        final withManager =
            RegExp(r'OfflineImageCacheManager\.instance').allMatches(src).length;
        if (withManager < calls) {
          bad.add('${f.path}: вызовов $calls, с общим кэшем $withManager');
        }
      }
      expect(bad, isEmpty,
          reason: 'кэш по умолчанию вытесняет после 200 картинок:\n${bad.join('\n')}');
    });
  });

  group('звук и ролики берутся с диска', () {
    test('голосовое в чате сперва ищет локальную копию', () {
      final src = File('lib/services/voice_player_service.dart').readAsStringSync();
      final cache = src.indexOf('cachedMediaPath(');
      final net = src.indexOf('_player.setUrl(');
      expect(cache, isPositive, reason: 'кэш голосовых пропал');
      expect(cache < net, isTrue, reason: 'сеть должна быть запасным путём');
    });

    test('звук в ленте сперва ищет локальную копию', () {
      final src = File('lib/screens/memory_lane/players.dart').readAsStringSync();
      expect(src.contains('cachedMediaPath('), isTrue);
    });

    test('ролик воспоминания играется из файла, если он есть', () {
      final src =
          File('lib/screens/memory_lane/media_widgets.dart').readAsStringSync();
      final cache = src.indexOf('cachedMediaPath(');
      final ctrl = src.indexOf('VideoPlayerController.file(');
      expect(cache, isPositive, reason: 'кэш роликов пропал');
      expect(ctrl, isPositive, reason: 'проигрывание из файла пропало');
    });

    test('фигурка играется из файла, если он есть', () {
      final src = File('lib/services/note_player_service.dart').readAsStringSync();
      expect(src.contains('cachedMediaPath('), isTrue);
    });

    test('ключом кэша служит исходная ссылка, а не адрес с токеном', () {
      // Токен живёт минуты. Ключ по нему — тот же промах, что был с аватарками.
      final fetch =
          File('lib/services/offline/media_file_fetch.dart').readAsStringSync();
      expect(fetch.contains('stableKey'), isTrue);
      for (final p in [
        'lib/services/voice_player_service.dart',
        'lib/services/note_player_service.dart',
        'lib/screens/memory_lane/media_widgets.dart',
      ]) {
        final src = File(p).readAsStringSync();
        final call = RegExp(r'cachedMediaPath\(\s*([A-Za-z_.]+)\s*,').firstMatch(src);
        expect(call, isNotNull, reason: '$p перестал звать кэш');
        expect(call!.group(1), isNot(contains('resolved')),
            reason: '$p: первым аргументом должна идти исходная ссылка');
      }
    });
  });
}
