import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож своей подписи для партнёра.
///
/// Подпись сама по себе никуда не девалась — `NicknameService` на месте, диалог
/// тоже. Пропала кнопка: она жила в карточке участников, а редизайн убрал эту
/// карточку с экрана. Метод остался в файле, анализатор пометил его как
/// неиспользуемый, и функция тихо исчезла из приложения — «она раньше была, но
/// при редизайне исправили».
///
/// Поэтому проверяем не наличие кода, а наличие ПУТИ к нему: плитка с именем
/// показывается на экране пары, и в ней должна быть кнопка подписи.
void main() {
  final source =
      File('lib/screens/connect_partner_screen.dart').readAsStringSync();

  test('плитка имени показывается на экране пары', () {
    expect(source, contains('_nameTile(cs, title, partner?.uid)'),
        reason: 'плитку переименовали или убрали — обновите сторожа');
  });

  test('из плитки имени можно открыть подпись', () {
    final start = source.indexOf('Widget _nameTile(');
    expect(start, isNot(-1));
    final end = source.indexOf('Widget _chipTile(', start);
    final tile = source.substring(start, end == -1 ? source.length : end);

    expect(tile, contains('_renamePartnerByUid'),
        reason: 'без кнопки подпись становится недостижимой');
  });

  test('диалог подписи сохраняет её человеку', () {
    expect(source, contains('pair.setNickname('),
        reason: 'подпись должна сохраняться, а не только показываться');
  });
}
