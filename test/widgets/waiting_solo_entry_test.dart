import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож входа в «пару заранее».
///
/// Механика второго места написана и работает, но до 10 августа 2026 попасть в
/// неё мог только тот, у кого пара уже есть. Тогда вход добавили и на экран
/// приглашения, который показывается один раз, сразу после регистрации, — и
/// это дало обратную беду: новичок открывал лист, читал «Завести пару» и
/// решал, что это и есть создание пары, а не ожидание того, кого ждать
/// (19.08.2026). С экрана новичка вход убран, на экране связи остался.
///
/// Тест держит: входа на первом экране нет, на экране связи есть, развилка в
/// листе цела. Ровно так же тихо исчезала строка «Иконка приложения» при
/// переезде экрана — сервис жил, вход пропал.
void main() {
  test('на первом экране лист второго места не открывается', () {
    final source = File(
      'lib/screens/invite_partner_screen.dart',
    ).readAsStringSync();

    expect(
      source.contains('WaitingSetupSheet'),
      isFalse,
      reason: 'новичок принимает лист ожидания за создание пары',
    );
  });

  test('на экране связи вход остался', () {
    final source = File(
      'lib/screens/connect_partner_screen.dart',
    ).readAsStringSync();

    expect(
      source.contains('WaitingSetupSheet.show('),
      isTrue,
      reason: 'тем, кому есть кого ждать, путь нужен',
    );
    expect(
      source.contains('waitingSetupTitle'),
      isTrue,
      reason: 'карточка входа осталась без подписи из локали',
    );
  });

  test('в листе есть развилка «знаю кого / пока не знаю»', () {
    final source = File(
      'lib/widgets/waiting/waiting_setup_sheet.dart',
    ).readAsStringSync();

    for (final key in [
      'waitingKnowWho',
      'waitingDontKnowWho',
      'waitingUnknownName',
    ]) {
      expect(
        source.contains(key),
        isTrue,
        reason: 'развилка в листе потеряла $key',
      );
    }

    // Безымянное место обязано уезжать под словом из локали: сервер отвечает
    // 400 «Впишите имя», а карточка пары рисует по имени первую букву.
    expect(
      source.contains('_unknown ? s.waitingUnknownName'),
      isTrue,
      reason: 'без имени запрос уйдёт с пустым name и получит 400',
    );
  });

  test('строки второго места объявлены и переведены', () {
    final api = File('lib/services/locale_service.dart').readAsStringSync();
    // Значения живут в словаре, а не в классах: `lib/l10n/dict/<раздел>.dart`.
    final dict = Directory('lib/l10n/dict')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    for (final key in [
      'waitingWhoLabel',
      'waitingKnowWho',
      'waitingDontKnowWho',
      'waitingUnknownName',
      'waitingUnknownHint',
      'waitingSoloTitle',
      'waitingSoloBody',
      'waitingSoloAction',
    ]) {
      expect(
        api.contains('String get $key;'),
        isTrue,
        reason: '$key не объявлен в AppStrings',
      );
      final entry = RegExp(
        "'$key': \\{(.*?)\\}",
        dotAll: true,
      ).firstMatch(dict);
      expect(entry, isNotNull, reason: '$key отсутствует в словаре');
      for (final code in ['ru', 'en']) {
        expect(
          entry!.group(1)!.contains("'$code':"),
          isTrue,
          reason: '$key без перевода на $code',
        );
      }
    }
  });
}
