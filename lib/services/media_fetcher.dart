import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/memory_media.dart';
import 'media_save_queue.dart';
import 'offline/media_view_cache.dart';
import 'pb_media_service.dart';

/// Достаёт файл воспоминания для галереи.
///
/// Порядок: ещё не отправленный файл лежит на телефоне — берём его; кадр,
/// который уже открывали, лежит в кэше картинок целиком — берём оттуда без
/// сети; остальное скачиваем по ссылке с файловым токеном во временный файл.
///
/// Прежний путь скачивал через `http.get` целиком в память и до него не
/// доходил вовсе: ссылку своего сервера он принимал за внешнюю и открывал
/// браузер.
class HttpMediaFetcher implements MediaFetcher {
  HttpMediaFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String localScheme = 'localfile://';

  /// Меньше этого в кэше лежит обрывок, а не снимок: оборванная запись.
  static const int _minCachedBytes = 1024;

  @override
  Future<FetchedMedia> fetch(MediaFile f) async {
    final ref = f.ref.trim();

    if (ref.startsWith(localScheme)) {
      final file = File(ref.substring(localScheme.length));
      if (await file.exists()) return FetchedMedia(file, temporary: false);
      throw FileSystemException('Файла нет на телефоне', file.path);
    }

    if (f.kind == SaveKind.photo) {
      final cached = await _fromImageCache(ref);
      if (cached != null) return FetchedMedia(cached, temporary: false);
    }

    final url = await PbMediaService().resolveUrlAuthed(ref) ?? ref;
    final dir = Directory('${(await getTemporaryDirectory()).path}/media_save');
    if (!await dir.exists()) await dir.create(recursive: true);
    final name = sha1.convert(utf8.encode(f.key)).toString().substring(0, 16);
    final out = File('${dir.path}/$name.${f.ext}');

    final req = http.Request('GET', Uri.parse(url));
    final resp = await _client.send(req).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      // Тело не читаем, но поток обязан закрыться, иначе соединение висит.
      unawaited(resp.stream.drain<void>().catchError((_) {}));
      throw HttpException('HTTP ${resp.statusCode}', uri: Uri.tryParse(url));
    }
    final sink = out.openWrite();
    try {
      // Предел — на тишину, а не на весь файл: ролик по плохой сети качается
      // минутами, и это не ошибка, пока байты идут.
      await sink.addStream(resp.stream.timeout(const Duration(seconds: 45)));
      await sink.flush();
    } finally {
      await sink.close();
    }
    final len = await out.length();
    if (len == 0) {
      await out.delete().catchError((_) => out);
      throw const HttpException('Пустой ответ');
    }
    return FetchedMedia(out);
  }

  /// Кадр из кэша картинок ленты. Ключ тот же, что у `StorageImage`:
  /// `v2|<ссылка как в записи>`, а на диске лежит исходный файл целиком.
  Future<File?> _fromImageCache(String ref) async {
    try {
      final info = await OfflineImageCacheManager.instance
          .getFileFromCache('v2|$ref');
      final file = info?.file;
      if (file == null || !await file.exists()) return null;
      if (await file.length() < _minCachedBytes) return null;
      return file;
    } catch (_) {
      return null;
    }
  }
}
