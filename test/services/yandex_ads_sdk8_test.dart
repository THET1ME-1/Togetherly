// Письмо РСЯ 17.10.2026: «Обновите версию SDK до 8.6.0, максимальная версия
// SDK в запросах из приложения: 7.18.6». В SDK 8 Яндекс поменял интерфейс:
// загрузчики роликов создаются без колбэков и возвращают объявление из
// `loadAd`, баннер грузится отдельным `load` и сообщает итог потоком.
//
// Здесь подменена телефонная сторона плагина yandex_mobileads 8.6: каналы
// повторяют его исходники (`android/src/main/kotlin/com/yandex/mobile/ads/
// flutter`). Тесты гоняют наши сервисы рекламы через эти каналы целиком.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:yandex_mobileads/mobile_ads.dart' as yandex;

import 'package:love_app/services/ad_platform.dart';
import 'package:love_app/services/interstitial_ad_service.dart';
import 'package:love_app/services/rewarded_ad_service.dart';
import 'package:love_app/widgets/common/ad_banner.dart';

/// Натив плагина Яндекса, как он отвечает на устройстве.
class _FakeYandexNative {
  _FakeYandexNative(this.messenger);

  final TestDefaultBinaryMessenger messenger;

  /// Чем ответить на загрузку: null — объявление есть, иначе отказ с этим
  /// текстом.
  String? failWith;

  /// Аргументы каждого `load`: и загрузчиков роликов, и баннеров.
  final List<Map<Object?, Object?>> loads = [];

  /// Вызовы объявлений строкой `вид:метод`, например `interstitialAd:show`.
  final List<String> calls = [];

  final Map<String, MockStreamHandlerEventSink> _sinks = {};
  int _nextAdId = 500;

  void install() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('yandex_mobileads.createAdLoader'),
      (call) async {
        final id = (call.arguments as Map)['id'] as int;
        _installLoader(call.method, id);
        return null;
      },
    );
    for (var id = 0; id < 40; id++) {
      _installBanner(id);
    }
    for (final channel in [
      SystemChannels.platform_views,
      SystemChannels.platform_views_2,
    ]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'create') return 1;
        if (call.method == 'resize') {
          final size = call.arguments as Map;
          return {'width': size['width'], 'height': size['height']};
        }
        return null;
      });
    }
  }

  void _events(String name) {
    messenger.setMockStreamHandler(
      EventChannel(name),
      MockStreamHandler.inline(onListen: (_, sink) {
        _sinks[name] = sink;
      }),
    );
  }

  void _emit(String name, Map<String, Object?> event) {
    scheduleMicrotask(() => _sinks[name]!.success(event));
  }

  void _installLoader(String kind, int id) {
    final name = 'yandex_mobileads.$kind.$id';
    final adKind = kind.replaceAll('Loader', '');
    _events('$name.events');
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method != 'load') return null;
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      loads.add(args);
      final requestId = args['requestId'];
      final unit = args['adUnitId'];
      final fail = failWith;
      if (fail != null) {
        _emit('$name.events', {
          'requestId': requestId,
          'name': 'onAdFailedToLoad',
          'code': 4,
          'description': fail,
          'adUnitId': unit,
        });
        return null;
      }
      final adId = _nextAdId++;
      _installAd(adKind, adId);
      _emit('$name.events', {
        'requestId': requestId,
        'name': 'onAdLoaded',
        'id': adId,
        'adInfo': {'adUnitId': unit},
      });
      return null;
    });
  }

  /// Объявление на весь экран: показ сразу открывается и закрывается.
  void _installAd(String kind, int id) {
    final name = 'yandex_mobileads.$kind.$id';
    _events('$name.events');
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      calls.add('$kind:${call.method}');
      if (call.method == 'show') {
        _emit('$name.events', {'name': 'onAdShown'});
        _emit('$name.events', {'name': 'onAdDismissed'});
      }
      return null;
    });
  }

  void _installBanner(int id) {
    final name = 'yandex_mobileads.bannerAd.$id';
    _events('$name.events');
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      calls.add('bannerAd:${call.method}');
      if (call.method != 'load') return null;
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      loads.add(args);
      final fail = failWith;
      _emit(
        '$name.events',
        fail == null
            ? {'name': 'onAdLoaded', 'width': 320, 'height': 50}
            : {
                'name': 'onAdFailedToLoad',
                'code': 4,
                'description': fail,
                'adUnitId': args['adUnitId'],
              },
      );
      return null;
    });
  }
}

const String _noAds =
    'Ad request completed successfully, but there are no ads available.';

/// Версия не ниже 8.6: её требует РСЯ.
bool _atLeast86(String version) {
  final parts = version.split('.').map(int.parse).toList();
  return parts[0] > 8 || (parts[0] == 8 && parts[1] >= 6);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

_FakeYandexNative _install(WidgetTester tester) {
  AdPlatform.debugOverride = true;
  addTearDown(() => AdPlatform.debugOverride = null);
  return _FakeYandexNative(tester.binding.defaultBinaryMessenger)..install();
}

void main() {
  test('плагин и нативный SDK под iPhone не старше 8.6', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final plugin = RegExp(r'\n  yandex_mobileads:\n(?:    .*\n)*?    version: "([\d.]+)"')
        .firstMatch(lock);
    expect(plugin, isNotNull, reason: 'плагина нет в pubspec.lock');
    expect(_atLeast86(plugin!.group(1)!), isTrue,
        reason: 'pubspec.lock держит yandex_mobileads ${plugin.group(1)}');

    // Podfile.lock переписывает CI на `pod install`; старая запись 7.x не
    // дала бы поставить 8.6 и уронила бы сборку под iPhone.
    final pods = File('ios/Podfile.lock').readAsStringSync();
    for (final m in RegExp(r'- YandexMobileAds \(([\d.]+)\)').allMatches(pods)) {
      expect(_atLeast86(m.group(1)!), isTrue,
          reason: 'Podfile.lock держит YandexMobileAds ${m.group(1)}');
    }
  });

  testWidgets('ролик за награду грузится запросом SDK 8.6', (tester) async {
    final native = _install(tester);
    final ads = RewardedAdService();
    addTearDown(ads.dispose);

    unawaited(ads.load());
    await _settle(tester);

    expect(ads.isReady, isTrue, reason: 'объявление не дошло до сервиса');
    final request = native.loads.single;
    expect(request['adUnitId'], 'demo-rewarded-yandex');
    expect(_atLeast86((request['parameters'] as Map)['plugin_version'] as String), isTrue);
  });

  testWidgets('отказ загрузки ролика повторяется через три секунды',
      (tester) async {
    final native = _install(tester)..failWith = _noAds;
    final ads = RewardedAdService();
    addTearDown(ads.dispose);

    unawaited(ads.load());
    await _settle(tester);
    expect(ads.isReady, isFalse);
    expect(native.loads, hasLength(1));

    native.failWith = null;
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(native.loads, hasLength(2), reason: 'повтора загрузки не было');
    expect(ads.isReady, isTrue);
  });

  testWidgets('межстраничный ролик грузится, показывается и убирается',
      (tester) async {
    final native = _install(tester);
    final ads = InterstitialAdService(room: true);
    addTearDown(ads.dispose);

    unawaited(ads.load());
    await _settle(tester);
    expect(ads.isReady, isTrue);
    expect(native.loads.single['adUnitId'], 'demo-interstitial-yandex');

    final shown = ads.show(timeout: const Duration(seconds: 5));
    await _settle(tester);
    expect(await shown, isTrue);
    expect(native.calls, containsAllInOrder(['interstitialAd:show', 'interstitialAd:destroy']));
    // Следующий ролик заказывается сразу после показа.
    expect(native.loads, hasLength(2));
  });

  group('баннер', () {
    setUp(() {
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
    });
    tearDown(() {
      VisibilityDetectorController.instance.updateInterval =
          const Duration(milliseconds: 500);
    });

    Widget slot({bool show = true}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: show ? const AdBanner() : const SizedBox(),
              ),
            ),
          ),
        );

    testWidgets('грузится запросом SDK 8.6 и стоит на экране', (tester) async {
      final native = _install(tester);
      await tester.pumpWidget(slot());
      await _settle(tester);

      expect(find.byType(yandex.AdWidget), findsOneWidget);
      final request = native.loads.single;
      expect(request['adUnitId'], 'demo-banner-yandex');
      expect(_atLeast86((request['parameters'] as Map)['plugin_version'] as String), isTrue);

      // Ушёл с экрана — баннер освобождается у натива.
      await tester.pumpWidget(slot(show: false));
      await _settle(tester);
      expect(native.calls, contains('bannerAd:destroy'));
    });

    testWidgets('без объявления места не держит', (tester) async {
      _install(tester).failWith = _noAds;
      await tester.pumpWidget(slot());
      await _settle(tester);

      expect(find.byType(yandex.AdWidget), findsNothing);
      expect(tester.getSize(find.byType(AdBanner)).height, 0);
    });
  });
}
