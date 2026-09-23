/// Почему не залился файл и что сказать человеку.
///
/// До 23.09.2026 заливка сводила любую ошибку к null, а лента показывала
/// «Убедитесь, что Firebase Storage включён», хотя Firebase давно выключен и
/// файлы идут в PocketBase. Причину не видели ни человек, ни панель крашей.
library;

import 'dart:async';
import 'dart:io';

import 'package:pocketbase/pocketbase.dart';

import '../services/crash_noise.dart';
import '../services/locale_service.dart';

/// Причина сбоя заливки, различимая для человека.
enum UploadFailure {
  /// Обрыв, молчание сети, истёкший срок заливки. Повтор обычно помогает.
  network,

  /// Сессия протухла или человек не вошёл: лечится входом заново.
  sessionExpired,

  /// Файл больше предела поля `media.file` или прокси.
  tooLarge,

  /// Всё остальное: ответ сервера 5xx, отказ правил, сбой на телефоне.
  other,
}

/// Причина по ошибке, пойманной при заливке.
///
/// [loggedIn] — есть ли живая сессия PocketBase. Без неё любой отказ сервера
/// означает «войдите заново», но обрыв сети остаётся обрывом: входить заново
/// бесполезно, пока нет связи.
UploadFailure classifyUploadError(Object error, {bool loggedIn = true}) {
  if (_isNetwork(error)) return UploadFailure.network;
  if (!loggedIn) return UploadFailure.sessionExpired;
  if (error is ClientException) {
    final code = error.statusCode;
    if (code == 401) return UploadFailure.sessionExpired;
    if (code == 413) return UploadFailure.tooLarge;
    if (_mentionsSizeLimit(error.response)) return UploadFailure.tooLarge;
  }
  return UploadFailure.other;
}

bool _isNetwork(Object error) {
  if (error is SocketException ||
      error is HandshakeException ||
      error is TimeoutException) {
    return true;
  }
  if (error is ClientException && error.statusCode == 0) return true;
  return isNetworkNoise(error);
}

/// PocketBase отвечает 400 с `data.<поле>.code = validation_file_size_limit`,
/// когда файл больше `maxSize` поля.
bool _mentionsSizeLimit(Map<String, dynamic> response) =>
    response.toString().contains('validation_file_size_limit');

/// Стоит ли ошибку заливки отправлять в Bugsink.
///
/// Обрыв сети и протухшая сессия — не баги приложения: первое лечится
/// повтором, второе входом. Истёкший срок заливки шлём: по размеру файла в
/// событии видно, хватает ли срока (`uploadTimeoutFor`).
bool uploadErrorWorthReporting(Object error) {
  if (isCrashNoise(error)) return false;
  if (error is ClientException && error.statusCode == 401) return false;
  return true;
}

/// Текст для человека. [video] различает только «прочее»: остальные причины
/// звучат одинаково для фото и для видео.
String uploadFailureText(
  UploadFailure failure,
  AppStrings s, {
  required bool video,
}) {
  switch (failure) {
    case UploadFailure.network:
      return s.uploadFailedNetwork;
    case UploadFailure.sessionExpired:
      return s.uploadFailedSession;
    case UploadFailure.tooLarge:
      return s.uploadFailedTooLarge;
    case UploadFailure.other:
      return video ? s.failedUploadVideo : s.failedUploadPhotos;
  }
}

/// Итог заливки: ссылка или причина отказа.
class UploadOutcome {
  const UploadOutcome.ok(String this.ref) : failure = null;
  const UploadOutcome.failed(UploadFailure this.failure) : ref = null;

  /// `pb://…` или `localfile://…`; null — не залилось.
  final String? ref;

  /// Почему не залилось; null — залилось.
  final UploadFailure? failure;

  bool get ok => ref != null;
}
