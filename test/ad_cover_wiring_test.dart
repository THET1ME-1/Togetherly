import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/ad_cover_watch.dart';

/// TOG-37: связка наблюдателя за рекламой на iPhone. Отказ канала Dart
/// глотает молча (старый натив), поэтому разъезд имён или пропущенная
/// регистрация вернули бы получасовое «Открываем…» без единой ошибки.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('имя канала и методы одни в Dart и Swift, канал заведён при старте движка', () {
    final swift = read('ios/Runner/AppDelegate.swift');
    expect(swift.contains('name: "$adCoverChannelName"'), isTrue, reason: 'в AppDelegate нет канала $adCoverChannelName');
    for (final method in ['state', 'dismissLeftover']) {
      expect(swift.contains('case "$method"'), isTrue, reason: 'Swift не отвечает на $method');
    }
    for (final key in ['depth', 'pluginTop', 'topEmpty']) {
      expect(swift.contains('"$key":'), isTrue, reason: 'натив не кладёт в ответ $key');
    }
    final setup = RegExp(r'func didInitializeImplicitFlutterEngine[\s\S]*?\n  }').firstMatch(swift)!.group(0)!;
    expect(setup.contains('setupAdCoverChannel('), isTrue, reason: 'канал не заводится при старте движка');

    final dart = read('lib/services/ad_cover_watch.dart');
    for (final method in ["'state'", "'dismissLeftover'"]) {
      expect(dart.contains(method), isTrue);
    }
  });

  test('оба вида полноэкранной рекламы ждут закрытия и по стопке', () {
    for (final path in ['lib/services/rewarded_ad_service.dart', 'lib/services/interstitial_ad_service.dart']) {
      expect(read(path).contains('AdCoverWatch()'), isTrue, reason: '$path не смотрит стопку контроллеров');
    }
    final rewarded = read('lib/services/rewarded_ad_service.dart');
    expect(rewarded.contains('pointerRouter.addGlobalRoute('), isTrue, reason: 'касание после показа не заканчивает ожидание');
    expect(rewarded.contains('pointerRouter.removeGlobalRoute('), isTrue, reason: 'слушатель касаний остаётся после показа');
  });

  test('сундук кладёт открытие на диск, как только награда положена', () {
    final chest = read('lib/screens/chest_screen.dart');
    final call = RegExp(r'_ad\.show\([\s\S]*?\n      \);').firstMatch(chest)?.group(0) ?? '';
    expect(call.contains('onEarned:'), isTrue, reason: 'открытие ложится на диск только после закрытия ролика');
    expect(call.contains('ChestPendingStore.write('), isTrue);
  });
}
