import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/mascot_guide_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Приветствие и регистрация видны только без аккаунта, и решить там «кому
/// гид» не по кому: телефон помнит, что гид был включён вошедшему. Владелец
/// поставил сборку, зашёл, вышел — и увидел старое приветствие: телефон
/// запоминал гида, лишь когда кто-то спрашивал `on`, а на главной без
/// подсказки его не спрашивал никто.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MascotGuideService.instance.resetForTest();
  });

  test('конфиг пришёл вошедшему из списка — телефон запомнил сразу', () async {
    MascotGuideService.instance.who = () => (uid: 'owner', created: null);
    MascotGuideService.instance.ingest({'uids': ['owner']});
    await pumpEventQueue();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('mascot_guide_device'), isTrue);

    // Вышел из аккаунта: приветствие всё равно с облачком.
    MascotGuideService.instance.who = () => (uid: null, created: null);
    expect(MascotGuideService.instance.on, isTrue);
  });

  test('чужому телефон ничего не запоминает', () async {
    MascotGuideService.instance.who = () => (uid: 'someone', created: null);
    MascotGuideService.instance.ingest({'uids': ['owner']});
    await pumpEventQueue();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('mascot_guide_device'), isNot(true));
    MascotGuideService.instance.who = () => (uid: null, created: null);
    expect(MascotGuideService.instance.on, isFalse);
  });

  test('свежая установка: сервер ещё не ответил, а приветствие уже с Ту', () async {
    await MascotGuideService.instance.restore();
    MascotGuideService.instance.who = () => (uid: null, created: null);
    expect(MascotGuideService.instance.on, isTrue);
  });

  test('сервер выключил гида — выключен и до ответа в следующий раз', () async {
    MascotGuideService.instance.ingest(<String, Object?>{});
    await pumpEventQueue();
    MascotGuideService.instance.resetForTest();
    await MascotGuideService.instance.restore();
    MascotGuideService.instance.who = () => (uid: null, created: null);
    expect(MascotGuideService.instance.on, isFalse);
  });

  test('вход после того, как конфиг уже лежал, тоже запоминается', () async {
    MascotGuideService.instance.who = () => (uid: null, created: null);
    MascotGuideService.instance.ingest({'uids': ['owner']});
    MascotGuideService.instance.who = () => (uid: 'owner', created: null);
    MascotGuideService.instance.signedIn();
    await pumpEventQueue();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('mascot_guide_device'), isTrue);
  });
}
