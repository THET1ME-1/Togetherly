// Исчерпанный лимит поиска фильмов — это не «поиск сломан».
//
// Жалоба 25.08.2026 (@Venti_59) со скриншотом: «Поиск недоступен — впишите
// название вручную» на запрос «Гарри Поттер». Проверка вживую: api.poiskkino.dev
// отвечает 403 и телом «Вы израсходовали ваш суточный лимит по запросам». Ключ
// у сборки один на всех, за день он выгорает, наутро оживает. Старый код считал
// любой 403 неверным ключом и писал «недоступен» — человек понимал это как
// поломку навсегда.
//
// Заодно плашка красилась Colors.orange.shade50 поверх любой темы и на тёмной
// светилась молочным пятном.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final service =
      File('lib/services/movie_search_service.dart').readAsStringSync();
  final screen =
      File('lib/screens/memory_movie_form_screen.dart').readAsStringSync();

  group('лимит поиска отличается от сломанного ключа', () {
    test('403 поднимает признак исчерпанного лимита, а не «нет ключа»', () {
      expect(service.contains('rateLimited'), isTrue,
          reason: 'признак лимита пропал');
      final at401 = service.indexOf('resp.statusCode == 401');
      final at403 = service.indexOf('resp.statusCode == 403');
      expect(at401, isPositive);
      expect(at403, isPositive);
      expect(service.contains('statusCode == 401 || resp.statusCode == 403'),
          isFalse, reason: 'коды снова слиплись в одну ветку');
    });

    test('экран показывает свой текст про сегодняшний лимит', () {
      expect(screen.contains('_quotaOut'), isTrue);
      expect(screen.contains('s.movieQuotaOut'), isTrue);
      final dict = File('lib/l10n/dict/memory_lane.dart').readAsStringSync();
      expect(dict.contains("'movieQuotaOut'"), isTrue);
      // Семь языков: русский, английский и пять остальных.
      final block = dict.substring(dict.indexOf("'movieQuotaOut'"));
      for (final lang in ['ru', 'en', 'pt', 'it', 'es', 'fr', 'de']) {
        expect(block.substring(0, 700).contains("'$lang':"), isTrue,
            reason: 'нет перевода на $lang');
      }
    });
  });

  group('плашка живёт в теме, а не в палитре Material', () {
    test('оранжевый из Colors в этой плашке не используется', () {
      final lines = screen.split('\n');
      final offenders = <String>[];
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('Colors.orange')) {
          offenders.add('строка ${i + 1}: ${lines[i].trim()}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'на тёмной теме это светится:\n${offenders.join('\n')}');
    });

    test('цвета берутся из схемы темы', () {
      expect(screen.contains('cs?.tertiaryContainer'), isTrue);
      expect(screen.contains('cs?.onTertiaryContainer'), isTrue);
    });

    test('кнопка ручного ввода тональная, а не полупрозрачная', () {
      expect(screen.contains('FilledButton.tonalIcon'), isTrue,
          reason: 'заливка в 8% на тёмной теме читалась выключенной');
    });
  });
}
