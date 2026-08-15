import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/l10n/dict/connect_partner.dart';

/// Пару нельзя потерять одним удержанием пальца.
///
/// 14 августа 2026 человек за одиннадцать секунд снёс три живые пары — в одной
/// лежали 102 сообщения и 53 воспоминания — и был уверен, что ничего не удалял.
/// Он и правда не собирался: удаление висело прямо на удержании центральной
/// пилюли карусели, без подписи, а лист подтверждения не называл ни партнёра,
/// ни того, что пропадёт. Теперь удержание открывает список действий, удаление
/// стоит вторым шагом, и в заголовке — имя того, кого теряешь.
void main() {
  final source =
      File('lib/screens/connect_partner_screen.dart').readAsStringSync();

  test('удержание пилюли не удаляет связь сразу', () {
    final longPress = RegExp(r'onLongPress:\s*\(\)\s*\{(.*?)\n\s{24}\},',
        dotAll: true);
    final matches = longPress.allMatches(source);
    expect(matches, isNotEmpty, reason: 'обработчик удержания на месте');
    for (final m in matches) {
      expect(m.group(1), isNot(contains('_confirmDeleteConnection')),
          reason: 'удержание открывает список действий, а не удаление');
    }
  });

  test('подтверждение называет партнёра по имени', () {
    expect(source, contains('deleteConnectionWith'),
        reason: 'в заголовке подтверждения стоит имя связи');

    final withName = connectPartnerStrings['deleteConnectionWith']!;
    for (final entry in withName.entries) {
      expect(entry.value, contains('{name}'),
          reason: 'подстановка имени есть в языке ${entry.key}');
    }
  });

  test('подтверждение говорит, что теряет и партнёр тоже', () {
    final body = connectPartnerStrings['deleteConnectionDesc']!;
    expect(body.keys.length, 7, reason: 'семь языков');
    expect(body['ru'], contains('партнёр'));
  });
}
