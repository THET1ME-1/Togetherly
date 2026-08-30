import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Метка аккаунта для покупок в App Store.
///
/// Уведомление App Store Server Notifications приносит транзакцию, но НЕ
/// говорит, кто её совершил: ни почты, ни нашего uid там нет. Единственная
/// ниточка — `appAccountToken`, который приложение кладёт в покупку само.
/// Без неё сервер знает, что деньги пришли, и не знает, кому открывать доступ.
///
/// Токен обязан быть UUID (Apple другого формата не принимает), а наш uid —
/// пятнадцать символов PocketBase или прежний идентификатор Firebase. Поэтому
/// считаем UUIDv5: одно и то же значение на всех устройствах человека, без
/// хранения и без запроса к серверу. Обратно из токена uid не достать, и это
/// правильно — метка уезжает к Apple.
///
/// Пространство имён своё и постоянное. Менять его нельзя: у людей, купивших
/// раньше, метка станет другой, и возврат по старой покупке не найдёт хозяина.
const String kAppleAccountNamespace = '6f2b1c7e-9a4d-5f88-b3e1-0c7d5a2f4e91';

/// UUIDv5 от [uid] — та самая метка. Пустой uid даёт пустую строку: класть в
/// покупку выдуманный токен хуже, чем не класть никакого.
String appleAccountTokenFor(String uid) {
  if (uid.isEmpty) return '';
  final bytes = <int>[..._uuidBytes(kAppleAccountNamespace), ...utf8.encode(uid)];
  final digest = sha1.convert(bytes).bytes.sublist(0, 16);
  // Версия 5 в старшем полубайте седьмого байта, вариант RFC 4122 в девятом.
  digest[6] = (digest[6] & 0x0f) | 0x50;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

List<int> _uuidBytes(String uuid) {
  final hex = uuid.replaceAll('-', '');
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}
