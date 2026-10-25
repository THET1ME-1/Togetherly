// TOG-37, обращения 481 и 484 (iPhone, 25.10.2026): после ролика сундук
// висит на «Открываем…», приз начислен, а экран его не показывает.
//
// Причина в том, как плагин Яндекса показывает ролик на iPhone: прозрачным
// контроллером `.overCurrentContext` поверх Flutter. Приложение под ним не
// уходит с экрана (в отчётах Bugsink `away_s: 0` у всех айфонов), и конец
// ролика виден только по событию «закрыто». Когда оно терялось после
// «показано», экран ждал до 30 минут: за трое суток на iPhone 592 ролика из
// 3230 засчитаны, а сундук так и не открылся (на Android 1,1%).
//
// Здесь подменена нативная сторона плагина, которая на показ присылает
// «показано» и «награду», а «закрыто» теряет, и канал стопки контроллеров.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:love_app/services/ad_platform.dart';
import 'package:love_app/services/interstitial_ad_service.dart';
import 'package:love_app/services/pocketbase_service.dart';
import 'package:love_app/services/rewarded_ad_service.dart';

/// Натив плагина Яндекса: показ шлёт [onShow], остальное — по команде теста.
class _FakeYandex {
  _FakeYandex(this.messenger);

  final TestDefaultBinaryMessenger messenger;
  final Map<String, MockStreamHandlerEventSink> _sinks = {};
  int _nextAdId = 700;
  String? _adEvents;

  /// Что приходит сразу после «показать». По умолчанию «закрыто» теряется.
  List<String> onShow = ['onAdShown', 'onRewarded'];

  void install() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('yandex_mobileads.createAdLoader'),
      (call) async {
        final id = (call.arguments as Map)['id'] as int;
        final kind = call.method.replaceAll('Loader', '');
        final name = 'yandex_mobileads.${call.method}.$id';
        _events('$name.events');
        messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
          if (call.method != 'load') return null;
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          final adId = _nextAdId++;
          _installAd(kind, adId);
          _send('$name.events', {
            'requestId': args['requestId'],
            'name': 'onAdLoaded',
            'id': adId,
            'adInfo': {'adUnitId': args['adUnitId']},
          });
          return null;
        });
        return null;
      },
    );
  }

  void _events(String name) {
    messenger.setMockStreamHandler(
      EventChannel(name),
      MockStreamHandler.inline(onListen: (_, sink) {
        _sinks[name] = sink;
      }),
    );
  }

  void _send(String channel, Map<String, Object?> event) {
    scheduleMicrotask(() => _sinks[channel]!.success(event));
  }

  void _installAd(String kind, int id) {
    final name = 'yandex_mobileads.$kind.$id';
    _adEvents = '$name.events';
    _events(_adEvents!);
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'show') {
        for (final e in onShow) {
          emit(e);
        }
      }
      return null;
    });
  }

  void emit(String event) {
    _send(_adEvents!, {
      'name': event,
      if (event == 'onRewarded') ...{'type': 'coins', 'amount': 1},
    });
  }
}

/// Канал `love_app/ad_cover`: стопка контроллеров над Flutter по сценарию.
class _FakeCover {
  _FakeCover(this.script);

  final List<Map<String, Object?>> script;
  int polls = 0;
  int dismissed = 0;

  void install(TestDefaultBinaryMessenger messenger) {
    messenger.setMockMethodCallHandler(const MethodChannel('love_app/ad_cover'), (call) async {
      switch (call.method) {
        case 'state':
          return script[math.min(polls++, script.length - 1)];
        case 'dismissLeftover':
          dismissed++;
          return true;
      }
      return null;
    });
  }
}

const _empty = {'depth': 0, 'pluginTop': false, 'topEmpty': true};
const _pluginOnly = {'depth': 1, 'pluginTop': true, 'topEmpty': true};
const _adOnTop = {'depth': 2, 'pluginTop': false, 'topEmpty': true};

Future<void> _pump(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

Future<(_FakeYandex, RewardedAdService)> _ready(WidgetTester tester) async {
  AdPlatform.debugOverride = true;
  addTearDown(() => AdPlatform.debugOverride = null);
  PocketBaseService().debugUse(PocketBase(
    'https://togetherly.day',
    httpClientFactory: () => MockClient(
      (_) async => http.Response('{"ok":true,"coins":10}', 200, headers: {'content-type': 'application/json'}),
    ),
  ));
  await tester.pumpWidget(const SizedBox());
  final native = _FakeYandex(tester.binding.defaultBinaryMessenger)..install();
  final ads = RewardedAdService(chest: true);
  addTearDown(ads.dispose);
  unawaited(ads.load());
  await _pump(tester, const Duration(milliseconds: 300));
  expect(ads.isReady, isTrue, reason: 'ролик не загрузился');
  return (native, ads);
}

void main() {
  testWidgets(
    'iPhone: «закрыто» потерялось, ролик ушёл из стопки — показ кончается сразу',
    (tester) async {
      final cover = _FakeCover([_empty, _pluginOnly, _adOnTop, _adOnTop, _pluginOnly])
        ..install(tester.binding.defaultBinaryMessenger);
      final (_, ads) = await _ready(tester);

      bool? earned;
      unawaited(ads.show(uid: 'u', chestOpenId: 'aaaaaaaaaaaaaa1').then((v) => earned = v));
      await _pump(tester, const Duration(seconds: 5));

      expect(earned, isTrue, reason: 'экран ждёт закрытия, которого никто не пришлёт');
      expect(ads.lastCloseSignal, 'cover', reason: 'в отчёте не видно, чем кончилось ожидание');
      await _pump(tester, const Duration(seconds: 2));
      expect(cover.dismissed, 1, reason: 'пустой прозрачный слой плагина остался держать касания');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'iPhone: стопка показала ролик — награда положена и без событий Яндекса',
    (tester) async {
      _FakeCover([_empty, _adOnTop, _adOnTop, _empty]).install(tester.binding.defaultBinaryMessenger);
      final (native, ads) = await _ready(tester);
      native.onShow = [];

      bool? earned;
      unawaited(ads.show(uid: 'u').then((v) => earned = v));
      await _pump(tester, const Duration(seconds: 5));

      expect(earned, isTrue, reason: 'ролик был на экране, а награды нет');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'iPhone со старым нативом без канала стопки: показ идёт как раньше',
    (tester) async {
      final (native, ads) = await _ready(tester);
      native.onShow = ['onAdShown', 'onRewarded', 'onAdDismissed'];

      bool? earned;
      unawaited(ads.show(uid: 'u').then((v) => earned = v));
      await _pump(tester, const Duration(seconds: 3));

      expect(earned, isTrue);
      expect(ads.lastCloseSignal, 'event');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'iPhone: межстраничная реклама комнаты кончается по стопке, а не через минуту',
    (tester) async {
      final cover = _FakeCover([_empty, _pluginOnly, _adOnTop, _pluginOnly])
        ..install(tester.binding.defaultBinaryMessenger);
      AdPlatform.debugOverride = true;
      addTearDown(() => AdPlatform.debugOverride = null);
      await tester.pumpWidget(const SizedBox());
      final native = _FakeYandex(tester.binding.defaultBinaryMessenger)..install();
      native.onShow = ['onAdShown'];
      final ads = InterstitialAdService(room: true);
      addTearDown(ads.dispose);
      unawaited(ads.load());
      await _pump(tester, const Duration(milliseconds: 300));
      expect(ads.isReady, isTrue);

      bool? shown;
      unawaited(ads.show().then((v) => shown = v));
      await _pump(tester, const Duration(seconds: 4));

      expect(shown, isTrue, reason: 'экран «Смотрим» ждёт закрытия, которого никто не пришлёт');
      await _pump(tester, const Duration(seconds: 2));
      expect(cover.dismissed, 1, reason: 'пустой слой плагина остался держать касания');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('касание по приложению после «показано» значит, что ролик закрыт', (tester) async {
    final cover = _FakeCover([_empty])..install(tester.binding.defaultBinaryMessenger);
    final (_, ads) = await _ready(tester);

    bool? earned;
    unawaited(ads.show(uid: 'u').then((v) => earned = v));
    await _pump(tester, const Duration(seconds: 2));
    expect(earned, isNull);

    await tester.tapAt(const Offset(20, 20));
    await _pump(tester, const Duration(seconds: 2));
    expect(earned, isTrue, reason: 'приложение снова под пальцем, а экран всё ждёт ролик');
    expect(ads.lastCloseSignal, 'touch');
    expect(cover.polls, 0, reason: 'не на iPhone натив стопки не спрашиваем');
  });

  testWidgets('касание до показа ролика ожидание не обрывает', (tester) async {
    final (native, ads) = await _ready(tester);
    native.onShow = [];

    bool? earned;
    unawaited(ads.show(uid: 'u').then((v) => earned = v));
    await _pump(tester, const Duration(milliseconds: 500));
    await tester.tapAt(const Offset(20, 20));
    await _pump(tester, const Duration(seconds: 2));
    expect(earned, isNull, reason: 'касание до показа сочли концом ролика');

    native
      ..emit('onAdShown')
      ..emit('onRewarded');
    await _pump(tester, const Duration(milliseconds: 500));
    await tester.tapAt(const Offset(20, 20));
    await _pump(tester, const Duration(seconds: 2));
    expect(earned, isTrue);
  });

  testWidgets('награда сообщается сразу, не дожидаясь закрытия ролика', (tester) async {
    final (_, ads) = await _ready(tester);

    var told = 0;
    bool? earned;
    unawaited(ads.show(uid: 'u', onEarned: () => told++).then((v) => earned = v));
    await _pump(tester, const Duration(seconds: 1));

    expect(told, 1, reason: 'открытие сундука узнаёт о награде только после закрытия');
    expect(earned, isNull);
    await tester.tapAt(const Offset(20, 20));
    await _pump(tester, const Duration(seconds: 2));
    expect(told, 1, reason: 'о награде сказали дважды');
  });
}
