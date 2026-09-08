// Запрос файлового токена обязан быть ограничен по времени.
//
// `POST /api/files/token` открывает доступ к защищённым файлам media: без него
// ни одна картинка не резолвится в адрес, который сервер отдаст. Вызов идёт из
// `PbMediaService._ensureFileToken`, и его результат кладётся в `_tokenInflight`
// — общий для всех, кто просит токен в этот момент.
//
// Отсюда цена зависания. Прогон на эмуляторе 08.09.2026: запрос токена не
// вернулся ни за три минуты, и подготовка КАЖДОЙ картинки парного виджета
// (фото обеих половин, аватарки, значки настроения) встала на первой же строке.
// Тексты уходят на рабочий стол раньше картинок, поэтому виджет обновлялся
// наполовину: статус и сообщение свежие, фотографии прежние. Ровно так это и
// описывают: «в парном виджете не меняются фотографии… меняется только текст».
//
// Фоновый путь (`refreshLoveWidgetFromServer`) обрывает ожидание своим
// таймаутом в 20 секунд и пишет «картинки не успели», но залипший
// `_tokenInflight` живёт дальше и уносит следующие проходы — до перезапуска
// приложения.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('каждый запрос файлового токена ограничен по времени', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final offenders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      var from = 0;
      while (true) {
        final at = source.indexOf('files.getToken(', from);
        if (at < 0) break;
        from = at + 1;
        final tail = source.substring(at, (at + 200).clamp(0, source.length));
        if (tail.contains('.timeout(')) continue;
        final line = '\n'.allMatches(source.substring(0, at)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'без таймаута зависший запрос токена останавливает все картинки: '
          '${offenders.join(', ')}',
    );
  });
}
