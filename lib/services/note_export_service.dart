import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'pocketbase_service.dart';

/// Чем закончилось сохранение фигурки — экрану нужно сказать разное.
///
/// Отказы разведены не для красоты: «сервер не собрал файл» и «галерея не
/// приняла» чинятся в разных местах, а человек, у которого не вышло, называет
/// ровно то, что увидел на экране.
enum NoteExportResult { saved, noAccess, serverFailed, saveFailed }

/// Отказ вместе с кодом ответа сервера: без кода жалоба «не сохраняется»
/// стоит вечера разбирательств.
class NoteExportOutcome {
  final NoteExportResult result;
  final int? status;
  const NoteExportOutcome(this.result, {this.status});
}

/// Сохранение фигурки в галерею телефона.
///
/// Скачивается не тот файл, что лежит в чате, а собранный сервером: квадратный
/// ролик, внутри которого фигурка вырезана по своей форме, а в правом нижнем
/// углу стоит подпись. Так же отдаёт свой кружок Telegram — видео остаётся
/// круглым, а файл обычным квадратным, который откроет любая галерея.
///
/// Собирать это на устройстве нечем: маску и подпись накладывает ffmpeg, а его
/// в приложении нет — двенадцать мегабайт к сборке ради редкой кнопки не стоят
/// того. Сервер держит готовый файл рядом, поэтому второе сохранение той же
/// фигурки приходит сразу.
class NoteExportService {
  const NoteExportService._();

  /// Готовый ролик может собираться до пары секунд — на первой фигурке ffmpeg
  /// работает с нуля.
  static const Duration _timeout = Duration(seconds: 90);

  static Future<NoteExportOutcome> saveToGallery(String messageId) async {
    if (messageId.isEmpty) {
      return const NoteExportOutcome(NoteExportResult.saveFailed);
    }
    final pb = PocketBaseService.instance.pb;
    final token = pb.authStore.token;
    if (token.isEmpty) {
      return const NoteExportOutcome(NoteExportResult.serverFailed);
    }

    File? temp;
    try {
      final res = await http
          .get(
            Uri.parse('${pb.baseURL}/api/note/export?msg=$messageId'),
            headers: {'Authorization': token},
          )
          .timeout(_timeout);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        debugPrint('NoteExport: ${res.statusCode} ${res.body}');
        return NoteExportOutcome(NoteExportResult.serverFailed,
            status: res.statusCode);
      }

      final dir = await getTemporaryDirectory();
      temp = File('${dir.path}/togetherly_$messageId.mp4');
      await temp.writeAsBytes(res.bodyBytes);

      // Доступ спрашиваем ПЕРЕД записью в галерею: отказ — это не сбой, а
      // ответ человека, и говорить про него надо иначе.
      if (!await Gal.hasAccess(toAlbum: true)) {
        if (!await Gal.requestAccess(toAlbum: true)) {
          return const NoteExportOutcome(NoteExportResult.noAccess);
        }
      }
      await Gal.putVideo(temp.path, album: 'Togetherly');
      return const NoteExportOutcome(NoteExportResult.saved);
    } on GalException catch (e) {
      debugPrint('NoteExport gal: ${e.type}');
      return NoteExportOutcome(e.type == GalExceptionType.accessDenied
          ? NoteExportResult.noAccess
          : NoteExportResult.saveFailed);
    } catch (e) {
      debugPrint('NoteExport failed: $e');
      return const NoteExportOutcome(NoteExportResult.saveFailed);
    } finally {
      // Копия в галерее уже своя, временный файл держать незачем.
      try {
        if (temp != null && await temp.exists()) await temp.delete();
      } catch (_) {/* уберёт система */}
    }
  }
}
