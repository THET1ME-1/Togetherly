import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/mlkit_module_service.dart';

/// Состояния установки модели распознавания — без телефона.
///
/// Саму загрузку проверить тут нечем: её ведут сервисы Google на устройстве.
/// Зато можно проверить СВОЮ сторону — что ответ канала разбирается верно и
/// экран не залипнет в «Готовим сканер», если сервисов нет или установка
/// сорвалась. Ровно на этом ломаются такие экраны.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('love_app/mlkit_module');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  // Сервис спрашивает платформу у Flutter: на хосте она linux, и без подмены
  // все вызовы уходили бы в короткое замыкание «не Android — значит готово».
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('модель на месте — сразу готово', () async {
    answer((_) => 'ready');
    expect(await MlkitModuleService.status(), MlkitModuleState.ready);
  });

  test('модели нет — просим установку', () async {
    answer((_) => 'needsInstall');
    expect(await MlkitModuleService.status(), MlkitModuleState.needsInstall);
  });

  test('сервисов Google нет — состояние unavailable, а не зависание', () async {
    answer((_) => 'unavailable');
    expect(await MlkitModuleService.status(), MlkitModuleState.unavailable);
  });

  test('незнакомый ответ считаем отказом, а не готовностью', () async {
    answer((_) => 'что-то новое');
    expect(await MlkitModuleService.status(), MlkitModuleState.unavailable);
  });

  test('канал бросил исключение — экран уходит в запасной путь', () async {
    answer((_) => throw PlatformException(code: 'boom'));
    expect(await MlkitModuleService.status(), MlkitModuleState.unavailable);
  });

  test('старая сборка без канала не ломает сканер', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await MlkitModuleService.status(), MlkitModuleState.ready);
  });

  test('отказ установки возвращает false, а не исключение', () async {
    answer((call) => call.method == 'install' ? false : 'needsInstall');
    expect(await MlkitModuleService.install(), isFalse);
  });

  test('прогрев молчит даже при ошибке канала', () async {
    answer((_) => throw PlatformException(code: 'boom'));
    await expectLater(MlkitModuleService.warmUp(), completes);
  });
}
