// Виджеты не выкачивают одну и ту же картинку по кругу.
//
// Разбор 26.08.2026 по счёту хостера за трафик. Раздача файлов отдавала 123 ГБ
// в сутки, из них 94 ГБ приходилось на аватарки: один и тот же файл уходил на
// один телефон по 36 раз за три минуты, а в запросах не было ни одной пометки
// «у меня уже есть копия». Причина — `_cachePhotoFromUrl` в
// HomeWidgetService: он звал `http.get` безусловно, а сохранённый файл держал
// только на случай сбоя сети. Обновление виджетов подписано на события
// партнёра (статус, настроение, трек, дебаунс 600 мс), поэтому каждая мелочь
// вытягивала аватарки заново.
//
// Правило «качать или взять готовое» лежит в widget_photo_cache.dart и уже под
// тестами; здесь сторожим саму склейку, чтобы её не потеряли при переделке.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/services/home_widget_service.dart').readAsStringSync();

  // Тело функции: от объявления до следующего метода класса.
  final start = src.indexOf('Future<String> _cachePhotoFromUrl(');
  final body = src.substring(start, src.indexOf('\n  /// ', start));

  group('фото виджета не качается заново', () {
    test('решение принимает общее правило кэша', () {
      expect(start, isPositive, reason: 'функция загрузки фото исчезла');
      expect(body.contains('photoCacheDecision('), isTrue,
          reason: 'перед сетью должна стоять проверка готового файла');
      expect(body.contains('PhotoCacheAction.useCached'), isTrue);
    });

    test('проверка стоит РАНЬШЕ обращения на склад', () {
      final decision = body.indexOf('photoCacheDecision(');
      final network = body.indexOf('WidgetPhotoStore.instance.bytesFor(');
      expect(network, isPositive, reason: 'обращение на склад переименовали');
      expect(decision < network, isTrue,
          reason: 'сначала смотрим готовый файл, только потом идём на склад');
    });

    test('ссылка запоминается только после удачной записи', () {
      // Смотрим сетевую ветку: до неё ссылка пишется и при выдаче со склада,
      // и это правильно — файл там уже лежит.
      final net = body.indexOf('WidgetPhotoStore.instance.bytesFor(');
      final tail = body.substring(net);
      final write = tail.indexOf('writeAsBytes');
      final remember = tail.indexOf("prefs.setString('\${key}_src'");
      expect(remember, isPositive, reason: 'ссылку перестали запоминать');
      expect(write, isPositive, reason: 'файл перестали записывать');
      expect(write < remember, isTrue,
          reason: 'битая попытка не должна закрывать дорогу повторной загрузке');
    });

    test('сравнивается исходная ссылка, а не адрес с токеном', () {
      final decision = body.indexOf('photoCacheDecision(');
      final args = body.substring(decision, decision + 260);
      expect(args.contains('url: url'), isTrue,
          reason: 'file-токен меняется каждые пару минут; сверять его нельзя');
      expect(args.contains('httpUrl'), isFalse);
    });

    test('один файл на все виджеты, а не по копии каждому', () {
      // Аватар партнёра просят days_, miss_ и together_ — под разными ключами.
      // Замер на эмуляторе: без склада 7 закачек одного файла за прогон.
      expect(body.contains('widget_src_'), isTrue,
          reason: 'общий склад по ссылке пропал');
      final sharedCheck = body.indexOf('shared.existsSync()');
      final network = body.indexOf('WidgetPhotoStore.instance.bytesFor(');
      expect(sharedCheck, isPositive);
      expect(sharedCheck < network, isTrue,
          reason: 'склад смотрим до сети');
    });

    test('склад стирается вместе с данными виджетов', () {
      final wipe = src.substring(src.indexOf('Future<void> wipeWidgetData('));
      expect(wipe.substring(0, 900).contains('widget_src_'), isTrue,
          reason: 'при смене человека чужие лица должны уходить со склада');
    });
  });
}
