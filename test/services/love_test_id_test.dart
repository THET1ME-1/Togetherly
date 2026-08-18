import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/love_test_id.dart';

/// Id записи «Умения любить» обязан подходить под маску коллекции.
///
/// У `love_tests` маска `^[a-z0-9]+$` и ровно 15 символов. Пока id собирался
/// из хвостов пары и человека, у мигрированных из Firebase аккаунтов туда
/// попадали заглавные буквы и дефисы, и PocketBase отвечал
/// `400 {"id":"Invalid value format."}` — результат не сохранялся ВООБЩЕ, а
/// человек видел это как «при перезапуске тест надо проходить заново»
/// (жалоба 18.08.2026; на проде ноль записей и отказ в журнале).
void main() {
  final mask = RegExp(r'^[a-z0-9]{15}$');

  test('id из обычных идентификаторов PocketBase подходит под маску', () {
    final id = loveTestRecordId('a1b2c3d4e5f6g7h', 'z9y8x7w6v5u4t3s');
    expect(mask.hasMatch(id), isTrue, reason: id);
  });

  test('id из мигрированных Firebase-идентификаторов тоже подходит', () {
    // Такие лежат на проде с переезда: смешанный регистр, дефисы, длина 20+.
    final id = loveTestRecordId('4on59EoEPMVLqcW7SSfA', 'Ab-Cd_12XY');
    expect(mask.hasMatch(id), isTrue, reason: id);
  });

  test('короткие и пустые хвосты не ломают длину', () {
    expect(mask.hasMatch(loveTestRecordId('g', 'u')), isTrue);
    expect(mask.hasMatch(loveTestRecordId('', '')), isTrue);
  });

  test('один и тот же человек в той же паре — тот же id', () {
    expect(
      loveTestRecordId('4on59EoEPMVLqcW7SSfA', 'Ab-Cd_12XY'),
      loveTestRecordId('4on59EoEPMVLqcW7SSfA', 'Ab-Cd_12XY'),
    );
  });

  test('партнёры в одной паре получают РАЗНЫЕ записи', () {
    expect(
      loveTestRecordId('pair0000000000', 'uid1111111111'),
      isNot(loveTestRecordId('pair0000000000', 'uid2222222222')),
    );
  });

  test('один человек в разных парах не затирает свой прошлый результат', () {
    expect(
      loveTestRecordId('pairAAAAAAAAAA', 'uid1111111111'),
      isNot(loveTestRecordId('pairBBBBBBBBBB', 'uid1111111111')),
    );
  });
}
