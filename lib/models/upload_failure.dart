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

  /// Файл пустой: облачный ролик не скачался на телефон или кодек отдал
  /// пустоту. Повтор не поможет, нужно выбрать файл заново.
  emptyFile,

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
    case UploadFailure.emptyFile:
      return s.uploadFailedEmpty;
    case UploadFailure.other:
      return video ? s.failedUploadVideo : s.failedUploadPhotos;
  }
}

/// Снимки, которые перед заливкой переводятся в WebP.
///
/// До 07.11.2026 переводились только jpg, jpeg и png, остальное уходило как
/// есть: три снимка .dng по 25 МБ легли в воспоминание, и лента у обоих в паре
/// висла и вылетала (TOG-77, обращение 527). RAW и HEIC кодек телефона
/// разбирает. GIF и WebP не трогаем — в них бывает анимация.
const Set<String> _rasterToWebp = {'jpg', 'jpeg', 'png', 'heic', 'heif', 'dng', 'bmp'};

bool convertsToWebp(String ext) => _rasterToWebp.contains(ext.toLowerCase());

/// Имя файла после перевода в WebP: меняется только расширение.
String webpDestination(String destination) =>
    destination.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '.webp');

/// Какой файл заливать: исходный или его сжатую копию.
enum UploadSource { original, compressed }

/// Выбор файла для заливки; null — заливать нечего.
///
/// До 05.10.2026 сжатый результат брался без взгляда на размер, и семь
/// видео-воспоминаний легли в бакет по 0 байт: обложки у них нет и не будет.
/// Пустое сжатие уступает исходнику, пустой исходник не заливается вовсе —
/// байты, которые кодек «сжал» из пустоты, видео не являются.
/// [onlyIfSmaller] — для WebP: копия тяжелее исходника не нужна.
UploadSource? pickUploadSource({
  required int originalBytes,
  int? compressedBytes,
  bool onlyIfSmaller = false,
}) {
  if (originalBytes <= 0) return null;
  final c = compressedBytes;
  if (c != null && c > 0 && (!onlyIfSmaller || c < originalBytes)) {
    return UploadSource.compressed;
  }
  return UploadSource.original;
}

/// Итог заливки: ссылка или причина отказа.
class UploadOutcome {
  const UploadOutcome.ok(String this.ref)
      : failure = null,
        deferrable = false;
  const UploadOutcome.failed(UploadFailure this.failure,
      {this.deferrable = false})
      : ref = null;

  /// Отказ не по вине файла: сервер или хранилище не приняли его, позже он
  /// пройдёт (`uploadWorthDeferring`). Файл воспоминания с таким отказом
  /// откладывается и доезжает сам.
  final bool deferrable;

  /// `pb://…` или `localfile://…`; null — не залилось.
  final String? ref;

  /// Почему не залилось; null — залилось.
  final UploadFailure? failure;

  bool get ok => ref != null;
}
