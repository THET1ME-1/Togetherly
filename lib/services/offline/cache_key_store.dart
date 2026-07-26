import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cache_cipher.dart';

/// Ключ шифрования офлайн-кэша: Keystore на Android, Keychain на iOS.
///
/// Почему не SharedPreferences (где лежит токен сессии): ключ рядом с базой —
/// это замок, повешенный на дверь вместе с ключом. Keystore хранит его так, что
/// из снятого дампа файловой системы ключ не достать.
///
/// Настройки выбраны под фон: `first_unlock_this_device` на iOS даёт фоновым
/// изолятам (workmanager, обновление виджетов) читать ключ после первой
/// разблокировки и при этом не пускает его ни в iCloud, ни на новый телефон.
/// На Android v10 по умолчанию оборачивает ключ RSA-OAEP из Keystore и не
/// кладёт своё хранилище в бэкап.
class CacheKeyStore {
  CacheKeyStore._();

  static const String _entry = 'offline_cache_key_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Ключ базы: читает сохранённый, а при первом запуске заводит новый.
  /// null — секретное хранилище недоступно (кэш тогда живёт только в памяти,
  /// см. [LocalStore.init]).
  static Future<Uint8List?> readOrCreate() async {
    try {
      final existing = await _storage.read(key: _entry);
      if (existing != null && existing.isNotEmpty) {
        final bytes = base64.decode(existing);
        if (bytes.length == CacheCipher.keyLength) return bytes;
        debugPrint('CacheKeyStore: ключ повреждён, завожу новый');
      }
      final fresh = CacheCipher.generateKey();
      await _storage.write(key: _entry, value: base64.encode(fresh));
      return fresh;
    } catch (e) {
      debugPrint('CacheKeyStore: секретное хранилище недоступно ($e)');
      return null;
    }
  }

}
