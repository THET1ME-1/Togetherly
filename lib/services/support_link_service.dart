import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/support_link.dart';
import 'pb_auth_service.dart';

/// Ссылка в бота поддержки с версией, телефоном и аккаунтом этого устройства.
/// Не удалось что-то узнать — эта часть уходит пустой, бот спросит сам.
Future<Uri> supportBotLink() async {
  var version = '';
  var build = '';
  try {
    final info = await PackageInfo.fromPlatform();
    version = info.version;
    build = info.buildNumber;
  } catch (_) {}

  // Модель: на iPhone машинное имя («iPhone15,3»), на Android марка и модель.
  String? device;
  try {
    if (Platform.isIOS) {
      device = (await DeviceInfoPlugin().iosInfo).utsname.machine;
    } else if (Platform.isAndroid) {
      final android = await DeviceInfoPlugin().androidInfo;
      final model = android.model;
      device = model.toLowerCase().startsWith(android.brand.toLowerCase())
          ? model
          : '${android.brand} $model';
    }
  } catch (_) {}

  String? uid;
  try {
    uid = PbAuthService().currentUid;
  } catch (_) {}

  final payload = supportStartPayload(
    app: 'tg',
    version: version,
    build: build,
    platform: Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web'),
    device: device,
    uid: uid,
  );
  return supportBotUri(payload);
}
