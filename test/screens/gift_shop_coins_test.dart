import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Монеты за подарок списывались на сервере, а на экране оставались прежними.
///
/// `GiftShopScreen` держит баланс своим полем и отдаёт свежий наружу колбэком
/// `onCoins`. Профиль открывал магазин без него, поэтому новое значение
/// умирало вместе с экраном: `UserData.coins` оставался старым, а сервер уже
/// знал настоящий. Отсюда жалоба 22.08.2026 — «баланс показан 60, купила
/// медаль, монеты не снялись; потом на подарок за 15 пишет „не хватает“, а
/// баланс скачет с 60 на 10 и обратно; только через пару минут стал верным».
/// Две минуты — это следующий `refreshCoinsFromServer` при заходе в профиль.
void main() {
  test('магазин подарков возвращает баланс наружу', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final offenders = <String>[];
    for (final f in files) {
      final source = f.readAsStringSync();
      for (final m in RegExp(r'GiftShopScreen\(([\s\S]*?)\n\s*\),')
          .allMatches(source)) {
        final args = m.group(1) ?? '';
        if (!args.contains('onCoins')) offenders.add(f.path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'магазин подарков открыт без onCoins: ${offenders.join(", ")} — '
            'списанные монеты не доедут до профиля');
  });

  test('колбэк доводит баланс до UserData, а не до одного экрана', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final opened = RegExp(r'GiftShopScreen\(([\s\S]*?)\n\s*\),')
        .firstMatch(profile);
    expect(opened, isNotNull, reason: 'магазин открывается из профиля');
    expect(opened!.group(1), contains('applyServerCoins'),
        reason: 'баланс уходит в UserData, иначе его увидит только магазин');
  });

  test('UserData умеет принять серверный баланс', () {
    final user = File('lib/models/user_data.dart').readAsStringSync();
    expect(user, contains('void applyServerCoins('),
        reason: 'нужен публичный путь для баланса из чужих роутов');
  });
}
