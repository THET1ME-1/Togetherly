import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/pb_realtime_service.dart';

/// Пустой локальный кэш выдавал себя за распущенную пару.
///
/// `watchGroup` слушает запись в кэше и одновременно тянет её с сервера.
/// Sembast на отсутствующую запись отвечает `null` сразу, ещё до ответа
/// сервера, — а `Connection` читал этот `null` как «группу распустили»: обнулял
/// связь и помечал её на удаление из карусели. Отсюда «принял код, написали
/// „вы вместе“, а в приложении Solo» и «счётчик был и исчез» при живой паре в
/// базе (22.08.2026).
///
/// Настоящее исчезновение записи приходит двумя путями: 404 на getOne и
/// delete-дельта. Только после них `null` из кэша что-то означает.
void main() {
  group('cacheAbsenceIsReal', () {
    test('пустой кэш до ответа сервера ничего не доказывает', () {
      expect(
        cacheAbsenceIsReal(sawRecord: false, serverSaysGone: false),
        isFalse,
      );
    });

    test('запись была и пропала — исчезновение настоящее', () {
      expect(
        cacheAbsenceIsReal(sawRecord: true, serverSaysGone: false),
        isTrue,
      );
    });

    test('сервер ответил 404 или прислал delete — исчезновение настоящее', () {
      expect(
        cacheAbsenceIsReal(sawRecord: false, serverSaysGone: true),
        isTrue,
      );
    });
  });
}
