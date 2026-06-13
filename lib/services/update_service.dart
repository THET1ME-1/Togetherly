import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Информация о доступном обновлении из публичного GitHub-репо релизов.
class GithubUpdate {
  /// versionCode новой сборки (сравнивается с текущим buildNumber).
  final int versionCode;

  /// versionName, напр. «1.12.9».
  final String versionName;

  /// Прямая ссылка на скачивание APK (latest-release asset).
  final String apkUrl;

  /// Тег релиза, напр. «v1.12.9».
  final String tag;

  const GithubUpdate({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.tag,
  });
}

/// Проверка обновлений для **сайдлоад-сборок** (установленных не из Play Store).
///
/// CI публикует APK + `version.json` в публичный репо
/// [_repo]. Play-Store-обновление (`in_app_update`) для таких установок не
/// работает, поэтому версию сверяем вручную по `version.json`, а установку
/// отдаём системному установщику через браузер (ссылка на APK).
class UpdateService {
  UpdateService._();

  /// Публичный репо с релизами (отдельный от приватных исходников).
  static const String _repo = 'THET1ME-1/togetherly_app_releases';

  /// Стабильная ссылка на манифест последней версии (редиректит на ассет).
  static const String _versionJsonUrl =
      'https://github.com/$_repo/releases/latest/download/version.json';

  /// `true`, если приложение установлено НЕ из Play Store (sideload).
  ///
  /// Для Play-установок возвращает `false` — там работает встроенное
  /// обновление через Google Play, дублировать его не нужно.
  static Future<bool> isSideloaded() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await PackageInfo.fromPlatform();
      // Play Store ставит с installerStore == 'com.android.vending'.
      return info.installerStore != 'com.android.vending';
    } catch (_) {
      return false;
    }
  }

  /// Возвращает [GithubUpdate], если в публичном репо лежит версия новее
  /// установленной, иначе `null` (нет обновления / ошибка сети / ошибка парсинга).
  static Future<GithubUpdate?> checkForUpdate() async {
    try {
      final resp = await http
          .get(Uri.parse(_versionJsonUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        debugPrint('UpdateService: version.json HTTP ${resp.statusCode}');
        return null;
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final remoteCode = (data['versionCode'] as num?)?.toInt() ?? 0;
      final apk = (data['apk'] as String?)?.trim() ?? '';
      if (remoteCode <= 0 || apk.isEmpty) return null;

      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      if (remoteCode <= currentCode) return null;

      return GithubUpdate(
        versionCode: remoteCode,
        versionName: (data['versionName'] as String?)?.trim() ?? '',
        apkUrl:
            'https://github.com/$_repo/releases/latest/download/$apk',
        tag: (data['tag'] as String?)?.trim() ?? '',
      );
    } catch (e) {
      debugPrint('UpdateService.checkForUpdate failed: $e');
      return null;
    }
  }
}
