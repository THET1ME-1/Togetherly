import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Схемы, которые вообще имеет смысл отдавать системе.
///
/// `tel`, `mailto` и `sms` тут не случайно: их открывают из поддержки и из
/// карточек мест, и на планшете без звонилки они падают тем же
/// `ACTIVITY_NOT_FOUND`, что и музыкальные ссылки.
const _knownSchemes = {'http', 'https', 'mailto', 'tel', 'sms', 'geo'};

/// Открывает ссылку, не роняя приложение.
///
/// Две причины, по которым голый `launchUrl` доходил до Bugsink 49 раз за один
/// день (разбор 10 августа 2026):
///
/// 1. Под интент нет приложения — музыкальная ссылка без клиента, `mailto` без
///    почтовой программы. `url_launcher` бросает
///    `PlatformException(ACTIVITY_NOT_FOUND)`.
/// 2. В поле адреса лежит не адрес. Через «Поделиться → Togetherly» из
///    музыкального приложения приезжает текст вида «Listen to Koyu - Sen Benim
///    Başımın…» без ссылки, он попадает в `music_url`, и `Uri.parse` отдаёт URI
///    без схемы. Система такой интент обработать не может.
///
/// Возвращает true, только если ссылку удалось открыть. Ложь тут не ошибка:
/// вызывающий код либо молчит, либо показывает свою подсказку.
Future<bool> safeLaunchUrl(
  Uri uri, {
  LaunchMode mode = LaunchMode.externalApplication,
}) async {
  // Без схемы или со схемой, которой никто не ждёт, до системы не доходим:
  // иначе это гарантированное ACTIVITY_NOT_FOUND.
  if (!_knownSchemes.contains(uri.scheme.toLowerCase())) {
    debugPrint('safeLaunchUrl: не адрес, а текст — «$uri»');
    return false;
  }
  try {
    return await launchUrl(uri, mode: mode);
  } catch (e) {
    debugPrint('safeLaunchUrl: не удалось открыть $uri: $e');
    return false;
  }
}

/// Разбирает строку и открывает её, если это действительно ссылка.
///
/// Годится там, где адрес пришёл извне: из шаринга, из метаданных трека, из
/// поля, которое человек заполнил руками.
Future<bool> safeLaunchString(
  String? raw, {
  LaunchMode mode = LaunchMode.externalApplication,
}) async {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return false;
  final uri = Uri.tryParse(text);
  if (uri == null) return false;
  return safeLaunchUrl(uri, mode: mode);
}
