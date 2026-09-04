// Фоновое обновление парного виджета обязано трогать картинки, а не только
// тексты.
//
// `refreshLoveWidgetFromServer` — единственный путь, по которому парный виджет
// обновляется при закрытом приложении: на iPhone сюда приводит тихий пуш
// (`widgetPushRefresh`), на Android — WorkManager и пуш `refresh`. Он писал
// ровно десять текстовых ключей своим списком: статус, настроение, сообщение и
// музыку обеих половин. Фото, аватарки, значки настроения и имена в фоне не
// обновлялись НИКОГДА — они доезжали только когда человек откроет приложение.
//
// Отсюда жалобы 01–03.09.2026, слово в слово: «в парном виджете не меняются
// фотографии, партнёр как поставил первую, так она и стоит… Меняется только
// текст» (@Sanyaklick); «загружаю фотку в виджет, на главном экране фотки из
// виджета не видно» (@alyxws, на снимке видны музыка и «Скучаю», а фото и
// аватарок нет).
//
// Сторож держит одно правило: фон собирает ключи ТЕМ ЖЕ сборщиком, что и
// передний план (`pairWidgetPayload` / `pairWidgetMedia`), а не своим списком.
// Разъедутся — половина ключей снова тихо выпадет из фонового пути.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/services/home_widget_service.dart').readAsStringSync();

  String bodyOf(String name) {
    final start = source.indexOf('Future<void> $name(');
    if (start < 0) throw StateError('метод $name пропал из сервиса');
    // Тело метода до следующего объявления верхнего уровня внутри класса.
    final next = source.indexOf('\n  /// ', start + 1);
    return source.substring(start, next > 0 ? next : source.length);
  }

  final body = bodyOf('refreshLoveWidgetFromServer');

  test('фон собирает тексты общим сборщиком, а не своим списком', () {
    expect(body.contains('pairWidgetPayload('), isTrue,
        reason: 'иначе список ключей разъедется с передним планом');
  });

  test('фон обновляет картинки половин', () {
    expect(body.contains('pairWidgetMedia('), isTrue,
        reason: 'фото, аватарки и значки настроения в фоне не обновлялись');
  });

  test('фон кладёт в контейнер файлы, а не только ссылки', () {
    for (final key in const [
      'my_photo_path',
      'partner_photo_path',
      'my_avatar_path',
      'partner_avatar_path',
      'my_mood_emoji_path',
      'partner_mood_emoji_path',
    ]) {
      expect(body.contains(key), isTrue,
          reason: 'ключ $key не наполняется в фоне — виджет рисует пустоту');
    }
  });

  // На iPhone сюда приводит тихий пуш, а он даёт считанные секунды: движок
  // гасят по таймауту вместе с недокачанной картинкой. Тексты поэтому уходят на
  // рабочий стол сразу, отдельным обновлением, и картинки уже не могут утянуть
  // их за собой. Раньше метод был мгновенным, и вопрос не стоял.
  test('тексты попадают на стол до того, как качаются картинки', () {
    final firstUpdate = body.indexOf("name: 'LoveWidgetProvider'");
    final firstImage = body.indexOf('_savePairImage(');
    expect(firstUpdate, greaterThan(0));
    expect(firstImage, greaterThan(0));
    expect(firstUpdate, lessThan(firstImage),
        reason: 'иначе оборванное пробуждение не обновит и текст');
  });

  test('картинки в фоне ограничены по времени', () {
    expect(body.contains('timeout('), isTrue,
        reason: 'без предела iOS гасит движок посреди закачки');
  });

  test('своего списка текстовых ключей в фоне больше нет', () {
    for (final key in const ['my_status', 'partner_status', 'my_music_title']) {
      expect(body.contains("'$key'"), isFalse,
          reason: 'ключ $key снова пишется вручную мимо общего сборщика');
    }
  });

  // Кэш картинок и имена файлов ведутся ПО КЛЮЧУ. Пока ключ был общий на все
  // связи (`my_photo_path`), фон, проходя по второй паре, перезаписывал запись
  // кэша первой и сносил её файл уборкой старых снимков: пары воевали за один
  // и тот же файл, и виджет первой оставался с путём в пустоту.
  test('у каждой пары своя запись кэша и свой файл', () {
    final saver = source.substring(source.indexOf('Future<void> _savePairImage'));
    expect(saver.contains('pairImagePath(pairWidgetKey(groupId, key)'), isTrue,
        reason: 'иначе вторая пара сносит файл первой');
  });
}
