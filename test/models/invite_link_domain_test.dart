import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/connection.dart';

/// Ссылка-приглашение — лицо приложения: её человек отправляет партнёру в
/// мессенджер, и она попадает в чужую переписку целиком, вместе с доменом.
///
/// До 17.08.2026 там стоял `togetherly.duckdns.org` — служебный поддомен
/// динамического DNS, оставшийся с переезда с Firebase Hosting. Свой домен к
/// тому моменту уже обслуживал и лендинг `/invite/*`, и `assetlinks.json`, и
/// AASA — не хватало только одной строки в модели.
///
/// Разбор входящих ссылок duckdns при этом трогать нельзя: разосланное живёт в
/// чужих переписках (см. `invite_code_normalize_test.dart`).
void main() {
  test('приглашение выдаётся со своим доменом', () {
    final link = Connection(id: 'g1', inviteCode: 'HQ792S').inviteLink;
    expect(link, 'https://togetherly.day/invite/HQ792S');
  });

  test('нигде в lib не осталось выдачи ссылок с duckdns', () {
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Ссылку МЫ выдаём только строковым литералом с /invite/. Разбор
        // входящих (сравнение host) остаётся легаси и здесь не считается.
        if (!line.contains('duckdns')) continue;
        if (!line.contains('/invite/')) continue;
        offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Эти строки выдают приглашение со служебным поддоменом: '
          '$offenders. Домен приглашения — togetherly.day.',
    );
  });

  /// Пустой код превращал ссылку в `https://togetherly.day/invite/`, и партнёр
  /// упирался в 404: за 18–19 августа 2026 на такую ссылку зашли 30 раз с
  /// настоящих устройств. Отправитель поломки не видит — у него ссылка
  /// выглядит как обычно, — поэтому жалоба звучит как «партнёр не может
  /// перейти по пригласительной ссылке».
  ///
  /// Код бывает пустым штатно: сервер выдаёт его не мгновенно, а до ответа
  /// экран показывает пустое поле (`generateInviteCode` не стирает прежний код
  /// раньше, чем ляжет новый, и при отказе оставляет пусто).
  group('пустой код не превращается в ссылку', () {
    test('веб-ссылки нет вовсе', () {
      expect(Connection(id: 'g1', inviteCode: '').inviteLink, isEmpty);
      expect(Connection(id: 'g1', inviteCode: '   ').inviteLink, isEmpty);
    });

    test('прямой ссылки для QR тоже нет', () {
      expect(Connection(id: 'g1', inviteCode: '').inviteDeepLink, isEmpty);
    });

    test('у готового кода всё по-прежнему', () {
      final c = Connection(id: 'g1', inviteCode: 'HQ792S');
      expect(c.inviteLink, 'https://togetherly.day/invite/HQ792S');
      expect(c.inviteDeepLink, 'loveapp://invite/HQ792S');
    });
  });
}
