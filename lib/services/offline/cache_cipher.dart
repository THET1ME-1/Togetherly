import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart';
import 'package:sembast/sembast.dart';

/// Шифрование офлайн-кэша (sembast) — AES-256-GCM на каждую запись.
///
/// До этого база `files/offline/pb_cache.db` лежала на диске открытым json: вся
/// переписка пары, очередь отправки и снимки записей PB. Пока файл сидит в
/// песочнице приложения, его читает рут, снятый дамп и (до правки backup_rules)
/// автобэкап Google.
///
/// Устройство кодека:
/// • ключ — 32 случайных байта, живёт в Keystore/Keychain (см. [CacheKeyStore]),
///   на диск рядом с базой НЕ попадает;
/// • каждая строка файла = base64(IV ‖ шифртекст ‖ тег), IV случайный на запись,
///   поэтому одинаковые сообщения дают разные строки;
/// • подпись базы — отпечаток ключа, поэтому чужим ключом sembast откажется
///   открывать файл сразу, не расшифровывая построчно.
///
/// Чистый Dart (pointycastle), нативного кода не добавляет — сборки iOS и
/// RuStore не трогаем, как и задумано у офлайн-стора.
class CacheCipher {
  CacheCipher._();

  /// Длина ключа AES-256.
  static const int keyLength = 32;

  /// Длина nonce GCM (стандартные 96 бит).
  static const int _ivLength = 12;

  /// Метка версии схемы шифрования: попадёт в подпись базы, поэтому смена
  /// алгоритма автоматически сделает старый файл нечитаемым (и он пересоздастся).
  static const String _scheme = 'aes-gcm-256-v1';

  /// Новый случайный ключ базы.
  static Uint8List generateKey() {
    final r = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(keyLength, (_) => r.nextInt(256)),
    );
  }

  /// Кодек sembast для этого ключа.
  static SembastCodec codec(Uint8List key) => SembastCodec(
        signature: _signature(key),
        codec: _AesGcmCodec(key),
      );

  /// Отпечаток ключа для подписи базы: по нему нельзя восстановить ключ, но
  /// подмена ключа ловится на открытии.
  static String _signature(Uint8List key) {
    final digest = crypto.sha256.convert(<int>[
      ...utf8.encode('togetherly-cache/$_scheme/'),
      ...key,
    ]);
    return '$_scheme:${base64Url.encode(digest.bytes.sublist(0, 12))}';
  }
}

class _AesGcmCodec extends Codec<Object?, String> {
  _AesGcmCodec(Uint8List key)
      : encoder = _AesGcmEncoder(key),
        decoder = _AesGcmDecoder(key);

  @override
  final Converter<Object?, String> encoder;

  @override
  final Converter<String, Object?> decoder;
}

class _AesGcmEncoder extends Converter<Object?, String> {
  _AesGcmEncoder(Uint8List key)
      : _encrypter = Encrypter(AES(Key(key), mode: AESMode.gcm));

  final Encrypter _encrypter;

  @override
  String convert(Object? input) {
    final iv = IV.fromSecureRandom(CacheCipher._ivLength);
    final body = _encrypter.encrypt(json.encode(input), iv: iv);
    return base64.encode(<int>[...iv.bytes, ...body.bytes]);
  }
}

class _AesGcmDecoder extends Converter<String, Object?> {
  _AesGcmDecoder(Uint8List key)
      : _encrypter = Encrypter(AES(Key(key), mode: AESMode.gcm));

  final Encrypter _encrypter;

  @override
  Object? convert(String input) {
    final all = base64.decode(input);
    if (all.length <= CacheCipher._ivLength) {
      throw const FormatException('строка кэша короче nonce');
    }
    final iv = IV(Uint8List.sublistView(all, 0, CacheCipher._ivLength));
    final body = Encrypted(Uint8List.sublistView(all, CacheCipher._ivLength));
    return json.decode(_encrypter.decrypt(body, iv: iv));
  }
}
