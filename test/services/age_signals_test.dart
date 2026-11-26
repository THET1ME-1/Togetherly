import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/age_signals.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Возраст из магазина (Google Play Age Signals, Apple Declared Age Range).
///
/// Закон Калифорнии AB 1043 с 01.01.2027 обязывает спрашивать возраст при
/// запуске, бразильский ECA Digital запрещает подстраивать рекламу под
/// несовершеннолетних. Ошибка в разборе ответа даёт либо персональную рекламу
/// подростку, либо урезанную рекламу взрослому — обе молча, без единой ошибки.
void main() {
  group('разбор ответа магазина', () {
    test('закон не действует, возраст не пришёл — всё как раньше', () {
      final verdict = AgeVerdict.fromPlatform({'mandatory': false, 'status': 'not_asked'});
      expect(verdict.band, AgeBand.unknown);
      expect(verdict.restrictedAds, isFalse);
    });

    test('13–15 лет — подросток, реклама без подстройки', () {
      final verdict = AgeVerdict.fromPlatform({'mandatory': true, 'status': 'shared', 'lower': 13, 'upper': 15});
      expect(verdict.band, AgeBand.teen);
      expect(verdict.restrictedAds, isTrue);
    });

    test('16–17 лет — тоже подросток', () {
      final verdict = AgeVerdict.fromPlatform({'mandatory': true, 'status': 'shared', 'lower': 16, 'upper': 17});
      expect(verdict.band, AgeBand.teen);
    });

    test('0–12 лет — ребёнок', () {
      final verdict = AgeVerdict.fromPlatform({'mandatory': true, 'status': 'shared', 'lower': 0, 'upper': 12});
      expect(verdict.band, AgeBand.child);
      expect(verdict.restrictedAds, isTrue);
    });

    test('Apple отдаёт «младше 13» без нижней границы — ребёнок', () {
      final verdict = AgeVerdict.fromPlatform({'mandatory': true, 'status': 'shared', 'upper': 12});
      expect(verdict.band, AgeBand.child);
    });

    test('18+ — взрослый, реклама обычная', () {
      final verdict = AgeVerdict.fromPlatform({'mandatory': true, 'status': 'shared', 'lower': 18});
      expect(verdict.band, AgeBand.adult);
      expect(verdict.restrictedAds, isFalse);
    });

    test('открытая группа ниже 18 («15+») взрослым не считается', () {
      final verdict = AgeVerdict.fromPlatform({'mandatory': true, 'status': 'shared', 'lower': 15});
      expect(verdict.band, AgeBand.unknown);
      expect(verdict.restrictedAds, isTrue);
    });

    test('в зоне закона возраст не подтверждён — реклама без подстройки', () {
      final verdict = AgeVerdict.fromPlatform({'mandatory': true, 'status': 'verification_required'});
      expect(verdict.band, AgeBand.unknown);
      expect(verdict.restrictedAds, isTrue);
    });

    test('вне зоны закона человек не поделился возрастом — всё как раньше', () {
      final verdict = AgeVerdict.fromPlatform({'mandatory': false, 'status': 'not_shared'});
      expect(verdict.restrictedAds, isFalse);
    });

    test('пустой или битый ответ — возраст неизвестен', () {
      expect(AgeVerdict.fromPlatform(null), AgeVerdict.none);
      expect(AgeVerdict.fromPlatform({'mandatory': 'да', 'lower': 'x'}), AgeVerdict.none);
    });
  });

  test('вердикт переживает запись на диск', () {
    const verdict = AgeVerdict(mandatory: true, band: AgeBand.teen);
    expect(AgeVerdict.fromJson(verdict.toJson()), verdict);
    expect(AgeVerdict.fromJson('мусор'), AgeVerdict.none);
  });

  group('проверка при запуске', () {
    const channel = MethodChannel(ageSignalsChannelName);
    late Object? Function(MethodCall call) answer;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      answer = (_) => null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          final result = answer(call);
          if (result is PlatformException) throw result;
          return result;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('ответ магазина сохраняется и переживает перезапуск', () async {
      answer = (_) => {'mandatory': true, 'status': 'shared', 'lower': 13, 'upper': 15};
      final first = AgeSignals.forTest(supported: true);
      await first.check();
      expect(first.restrictedAds, isTrue);

      final next = AgeSignals.forTest(supported: true);
      await next.loadSaved();
      expect(next.verdict, const AgeVerdict(mandatory: true, band: AgeBand.teen));
    });

    test('сбой канала не стирает прошлый ответ', () async {
      answer = (_) => {'mandatory': true, 'status': 'shared', 'lower': 13, 'upper': 15};
      final signals = AgeSignals.forTest(supported: true);
      await signals.check();

      answer = (_) => PlatformException(code: '-3', message: 'NETWORK_ERROR');
      await signals.check();
      expect(signals.verdict.band, AgeBand.teen);

      answer = (_) => {'error': -3};
      await signals.check();
      expect(signals.verdict.band, AgeBand.teen);
    });

    test('реклама ждёт проверку, но не дольше срока', () async {
      answer = (_) => null;
      final hanging = AgeSignals.forTest(supported: true, timeout: const Duration(milliseconds: 50));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) => Future<Object?>.delayed(const Duration(seconds: 5)),
      );
      final started = DateTime.now();
      unawaited(hanging.check());
      await hanging.settled;
      expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 2)));
      expect(hanging.restrictedAds, isFalse);
    });

    test('есть сохранённый ответ — реклама не ждёт магазин', () async {
      SharedPreferences.setMockInitialValues({
        'age_signals_v1': const AgeVerdict(mandatory: true, band: AgeBand.teen).toJson(),
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      final signals = AgeSignals.forTest(supported: true, timeout: const Duration(seconds: 30));
      await signals.loadSaved();
      unawaited(signals.check());
      await signals.settled.timeout(const Duration(milliseconds: 200));
      expect(signals.restrictedAds, isTrue);
    });

    test('сборка не из Play: после первого отказа реклама больше не ждёт', () async {
      answer = (_) => {'error': -9};
      final first = AgeSignals.forTest(supported: true);
      await first.check();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      final next = AgeSignals.forTest(supported: true, timeout: const Duration(seconds: 30));
      await next.loadSaved();
      await next.settled.timeout(const Duration(milliseconds: 200));
      expect(next.restrictedAds, isFalse);
    });

    test('на ноутбуке и в вебе канал не трогается', () async {
      var asked = false;
      answer = (_) {
        asked = true;
        return null;
      };
      final signals = AgeSignals.forTest(supported: false);
      await signals.check();
      await signals.settled;
      expect(asked, isFalse);
    });
  });

  group('проводка', () {
    String read(String path) => File(path).readAsStringSync();
    // Порядок вызовов сверяется по коду: в комментариях те же имена.
    String code(String path) => read(path)
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//.*'), '');

    test('имя канала одно в Dart, Kotlin и Swift, натив заведён при старте', () {
      final kotlin = read('android/app/src/main/kotlin/com/togetherly/love/AgeSignalsBridge.kt');
      expect(kotlin.contains('"$ageSignalsChannelName"'), isTrue, reason: 'Kotlin слушает другой канал');
      final activity = read('android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt');
      expect(activity.contains('AgeSignalsBridge'), isTrue, reason: 'MainActivity не заводит канал возраста');

      final swift = read('ios/Runner/AppDelegate.swift');
      expect(swift.contains('name: "$ageSignalsChannelName"'), isTrue, reason: 'в AppDelegate нет канала $ageSignalsChannelName');
      final setup = RegExp(r'func didInitializeImplicitFlutterEngine[\s\S]*?\n  }').firstMatch(swift)!.group(0)!;
      expect(setup.contains('setupAgeSignalsChannel('), isTrue, reason: 'канал не заводится при старте движка');

      for (final key in ['"mandatory"', '"status"', '"lower"', '"upper"', '"error"']) {
        expect(kotlin.contains(key), isTrue, reason: 'Kotlin не кладёт $key');
        expect(swift.contains(key), isTrue, reason: 'Swift не кладёт $key');
      }
    });

    test('Kotlin спрашивает доступ только там, где закон обязывает', () {
      final kotlin = code('android/app/src/main/kotlin/com/togetherly/love/AgeSignalsBridge.kt');
      final features = kotlin.indexOf('getApplicableAgeFeatures(');
      final access = kotlin.indexOf('requestAgeSignalsAccess(');
      expect(features, greaterThan(-1));
      expect(access, greaterThan(features), reason: 'окно Play «поделиться возрастом» уйдёт всем подряд');
      expect(kotlin.contains('MANDATORY_SHARING'), isTrue);
      final gradle = read('android/app/build.gradle.kts');
      expect(gradle.contains('com.google.android.play:age-signals:'), isTrue);
    });

    test('у iPhone-приложения есть право спрашивать возраст', () {
      for (final path in ['ios/Runner/Runner.entitlements', 'ios/Runner/RunnerDebug.entitlements']) {
        expect(read(path).contains('<key>com.apple.developer.declared-age-range</key>'), isTrue, reason: path);
      }
      final project = read('ios/Runner.xcodeproj/project.pbxproj');
      expect(RegExp(r'"-weak_framework",\s*DeclaredAgeRange').allMatches(project).length, 3,
          reason: 'DeclaredAgeRange связан слабо не во всех сборках Runner — iOS ниже 26 не запустит приложение');
    });

    test('Swift спрашивает возраст только там, где закон обязывает', () {
      final swift = code('ios/Runner/AppDelegate.swift');
      final eligible = swift.indexOf('isEligibleForAgeFeatures');
      final request = swift.indexOf('requestAgeRange(');
      expect(eligible, greaterThan(-1));
      expect(request, greaterThan(eligible), reason: 'окно Apple «поделиться возрастом» уйдёт всем подряд');
    });

    test('ни один запрос AdMob не собирается мимо проверки возраста', () {
      for (final path in [
        'lib/services/interstitial_ad_service.dart',
        'lib/services/rewarded_ad_service.dart',
        'lib/widgets/common/ad_banner.dart',
      ]) {
        final source = read(path);
        expect(source.contains('admob.AdRequest('), isFalse, reason: '$path собирает запрос AdMob сам');
        expect(source.contains('AdPlatform.admobRequest()'), isTrue, reason: '$path не берёт запрос из AdPlatform');
        expect(source.contains('AdPlatform.yandexAllowed'), isTrue, reason: '$path зовёт Яндекс подростку');
      }
    });

    test('возраст не уходит с телефона', () {
      final source = read('lib/services/age_signals.dart');
      for (final leak in ['PocketBase', 'Sentry', 'Analytics', 'http']) {
        expect(source.contains(leak), isFalse, reason: 'age_signals.dart тянет $leak');
      }
    });

    test('проверка стартует при запуске приложения, прошлый ответ читается сразу', () {
      final main = read('lib/main.dart');
      expect(main.contains('AgeSignals.instance.check()'), isTrue);
      final start = main.indexOf('void main() async {');
      final load = main.indexOf('AgeSignals.instance.loadSaved()');
      expect(load, greaterThan(start), reason: 'прошлый ответ не читается в main()');
      expect(load, lessThan(main.indexOf('runApp(')), reason: 'прошлый ответ читается после runApp');
    });
  });
}
