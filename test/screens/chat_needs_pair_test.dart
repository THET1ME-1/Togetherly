import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/l10n/dict/chat.dart';

/// Чат без пары открывался и молча съедал сообщение.
///
/// Экран приглашения — тот, где код и QR, — рисовал плитку «Чат» наравне с
/// остальными. Пары в этот момент нет, `pairId` пуст, и `ChatService.send`
/// выходит на первой же строке: человек пишет, получает «Не удалось
/// отправить», а в шапке чата пустая пилюля вместо имени партнёра, и там
/// действительно нечего нажимать. Жалоба 18.08.2026 звучала дословно так:
/// «тут есть чат, но он не работает, сверху чата тоже ничо не тыкается».
void main() {
  final source =
      File('lib/screens/connect_partner_screen.dart').readAsStringSync();

  test('чат без пары не открывается', () {
    final open = RegExp(r'void _openChat\(\) \{(.*?)\n  \}', dotAll: true)
        .firstMatch(source);
    expect(open, isNotNull, reason: 'переход в чат на месте');
    expect(open!.group(1), contains('pairId.isEmpty'),
        reason: 'пустая пара до чата не доходит');
  });

  test('на экране приглашения плитка чата закрыта', () {
    final invite =
        RegExp(r'Widget _buildInviteContent\(\) \{(.*?)\n  \}\n', dotAll: true)
            .firstMatch(source);
    expect(invite, isNotNull, reason: 'ветка приглашения на месте');
    expect(invite!.group(1), contains('_chatTile(cs, locked: true)'),
        reason: 'пока пары нет, плитка объясняет, а не ведёт в пустой чат');
  });

  test('закрытая плитка объясняет, чего ждать', () {
    final line = chatStrings['chatWaitsForPartner'];
    expect(line, isNotNull, reason: 'строка заведена в словаре');
    expect(line!.keys.length, 7, reason: 'семь языков');
    expect(line['ru'], contains('партнёр'));
  });
}
