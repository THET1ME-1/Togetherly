import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'locale_service.dart';

/// Куда идти за обновлением — и идти ли вообще.
enum UpdatePath {
  /// Установка из Play в порядке: спрашиваем сам Play.
  playStore,

  /// Сборка не из Play: сверяемся с version.json в публичном репо.
  sideload,

  /// Установка из Play неполная — докачиваемых частей нет. Play Core в таком
  /// состоянии показывает собственное английское окно и закрывает приложение,
  /// поэтому его не зовём и объясняем всё сами.
  brokenInstall,

  /// Обновляться нечем и спрашивать некого: на телефоне нет работающих
  /// сервисов Google. Молчим — предлагать тут нечего, а Play Core на вызов
  /// отвечает окном «Check that Google Play is enabled on your device».
  none,
}

/// Развилка запуска, вынесенная из экрана, чтобы её можно было проверить
/// тестом, не поднимая Android.
///
/// [splitsMissing] важно только для установок из Play: одиночный APK по
/// определению не имеет докачиваемых частей, и предупреждать там не о чем.
UpdatePath decideUpdatePath({
  required bool sideloaded,
  required bool splitsMissing,
  required bool playServices,
}) {
  if (sideloaded) return UpdatePath.sideload;
  // Сервисы проверяем раньше частей: на телефоне без Google Play переустановка
  // ничего не чинит, и гнать человека переустанавливать исправное приложение
  // было бы враньём.
  if (!playServices) return UpdatePath.none;
  return splitsMissing ? UpdatePath.brokenInstall : UpdatePath.playStore;
}

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

  /// Что нового в ЭТОЙ версии — то, ради чего человека зовут обновиться.
  ///
  /// Раньше попап печатал заметки установленной сборки: они лежат в ней
  /// константой, поэтому список не менялся и человек видел его раз за разом
  /// («второй или третий раз вижу», 13 августа 2026). Теперь заметки приезжают
  /// вместе с version.json нового релиза.
  final String notes;

  const GithubUpdate({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.tag,
    this.notes = '',
  });
}

/// Заметки новой версии из version.json.
///
/// Релизы до 13 августа 2026 поля не знают — там остаётся [fallback], текст из
/// самой сборки: пустой попап хуже устаревшего.
String updateNotesFrom(
  Map<String, dynamic> data, {
  required bool russian,
  required String fallback,
}) {
  final ru = (data['notes'] as String?)?.trim() ?? '';
  final en = (data['notesEn'] as String?)?.trim() ?? '';
  final wanted = russian ? ru : (en.isNotEmpty ? en : ru);
  return wanted.isNotEmpty ? wanted : fallback;
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
  static const String _repo = 'THET1ME-1/togetherly';

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

  static const MethodChannel _installChannel =
      MethodChannel('love_app/install');

  /// `true`, если приложение поставлено из Play, но его докачиваемые части
  /// (split-APK) на устройстве отсутствуют.
  ///
  /// Такая установка получается после переноса приложений на новый телефон,
  /// клонирования в «двойном пространстве» и установки APK, вытащенного из
  /// чужого телефона. Проверку делаем сами через PackageManager: спросить об
  /// этом Play Core нельзя — он в ответ показывает своё окно и закрывает
  /// приложение, а это ровно то, что мы обходим.
  static Future<bool> hasMissingSplits() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _installChannel.invokeMethod<bool>('hasMissingSplits') ??
          false;
    } catch (e) {
      // Канал недоступен (старая сборка виджета, тесты) — считаем установку
      // целой: ложное предупреждение хуже пропущенного.
      debugPrint('UpdateService.hasMissingSplits failed: $e');
      return false;
    }
  }

  /// Есть ли на телефоне работающие сервисы Google.
  ///
  /// Honor и Huawei последних лет продаются без них, и на любом телефоне Play
  /// можно отключить. Play Core там неработоспособен и на обращение отвечает
  /// окном «Something went wrong. Check that Google Play is enabled on your
  /// device», хотя приложение целое и переустановка ничего не меняет.
  ///
  /// Канал общий с пушами: тот же вопрос про те же сервисы, второй заводить
  /// незачем.
  static Future<bool> hasPlayServices() async {
    if (!Platform.isAndroid) return false;
    try {
      return await const MethodChannel('love_app/fcm')
              .invokeMethod<bool>('hasServices') ??
          false;
    } catch (e) {
      // Не смогли спросить — считаем, что сервисы есть: молча пропустить
      // обновление на исправном телефоне хуже, чем задать вопрос Play Core.
      debugPrint('UpdateService.hasPlayServices failed: $e');
      return true;
    }
  }

  /// Заметки последнего увиденного релиза.
  ///
  /// Их читает и попап Google Play: сам Play заметок приложению не отдаёт, а
  /// показывать текст из установленной сборки — значит печатать человеку то,
  /// что у него уже есть.
  static String? cachedNotes;

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
      // Читаем БАЙТЫ, а не resp.body: version.json лежит файлом релиза и
      // отдаётся без charset в Content-Type, а пакет http в этом случае
      // разбирает ответ как latin-1. Русские заметки к версии превращались в
      // «â Ð Ð¸ÐÐ¶ÐµÑ» прямо в окне «Доступно обновление» (17.08.2026).
      final data =
          json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final remoteCode = (data['versionCode'] as num?)?.toInt() ?? 0;
      // apk — сборка под arm64-v8a (основная), apkArm — под armeabi-v7a.
      // Старые релизы могли отдавать единый universal APK в поле apk.
      final apkArm64 = (data['apk'] as String?)?.trim() ?? '';
      final apkArm = (data['apkArm'] as String?)?.trim() ?? '';
      if (remoteCode <= 0 || apkArm64.isEmpty) return null;

      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      final notes = updateNotesFrom(
        data,
        russian: LocaleService.instance.isRussian,
        fallback: '',
      );
      if (notes.isNotEmpty) cachedNotes = notes;
      if (remoteCode <= currentCode) return null;

      // Под архитектуру устройства: 64-битные → arm64-v8a, чисто 32-битные → v7a.
      final apk = await _pickApkForDevice(arm64: apkArm64, arm: apkArm);

      return GithubUpdate(
        versionCode: remoteCode,
        versionName: (data['versionName'] as String?)?.trim() ?? '',
        apkUrl:
            'https://github.com/$_repo/releases/latest/download/$apk',
        tag: (data['tag'] as String?)?.trim() ?? '',
        notes: updateNotesFrom(
          data,
          russian: LocaleService.instance.isRussian,
          fallback: LocaleService.current.updateWhatsNew,
        ),
      );
    } catch (e) {
      debugPrint('UpdateService.checkForUpdate failed: $e');
      return null;
    }
  }

  /// Выбирает имя APK под архитектуру устройства.
  ///
  /// 64-битные устройства поддерживают `arm64-v8a` (и обычно ещё `armeabi-v7a`)
  /// — им отдаём arm64-сборку (производительнее). Чисто 32-битные устройства
  /// видят только `armeabi-v7a` — им отдаём v7a-сборку. Если v7a-файла нет
  /// (старый формат version.json) — всегда arm64.
  static Future<String> _pickApkForDevice({
    required String arm64,
    required String arm,
  }) async {
    if (arm.isEmpty) return arm64;
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      final abis = android.supportedAbis;
      if (abis.contains('arm64-v8a')) return arm64;
      if (abis.contains('armeabi-v7a')) return arm;
      return arm64; // x86/прочее — фолбэк на arm64
    } catch (_) {
      return arm64;
    }
  }
}
