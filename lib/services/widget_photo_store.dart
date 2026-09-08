import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'offline/media_view_cache.dart';
import 'widget_photo_cache.dart';

/// Один файл на телефон: качаем картинку ОДИН раз, дальше её берут все.
///
/// Раньше одну и ту же аватарку тянули порознь три хозяина: экран через
/// `StorageImage`, `widget_service` для своих виджетов и `home_widget_service`
/// для своих. У каждого был свой кэш и свои файлы, поэтому замер на эмуляторе
/// показал 13 закачек двух аватарок за один заход — по шесть-семь на файл.
///
/// Склад один и тот же для всех: это кэш [OfflineImageCacheManager], в который
/// пишет и из которого читает `StorageImage`. Ключ — ИСХОДНАЯ ссылка (`pb://`)
/// под тем же префиксом `v2|`, что у экрана: адрес с file-токеном не годится,
/// токен живёт минуты и ключ бы менялся на каждом запросе.
///
/// Отсюда следствие, ради которого всё и затевалось: показал экран аватарку —
/// виджеты возьмут её с диска; скачал первым виджет — экран не полезет в сеть.
class WidgetPhotoStore {
  WidgetPhotoStore._();

  static final WidgetPhotoStore instance = WidgetPhotoStore._();

  /// Загрузки, идущие прямо сейчас. Виджеты обновляются пачкой («дни вместе»,
  /// «скучаю», «вместе» — и каждый со своей стороной сжатия), запросы уходят
  /// вперемешку, и без этой карты все они дружно шли бы в сеть за одним и тем
  /// же файлом, пока первый ещё не дописал его на диск.
  final Map<String, Future<Uint8List?>> _inFlight = {};

  static String cacheKeyFor(String url) => 'v2|$url';

  /// Предел одному обращению к диску (база кэша, чтение и запись файла).
  static const Duration _diskStep = Duration(seconds: 8);

  /// Байты картинки [url]. [httpUrl] — тот же файл в виде адреса, по которому
  /// его можно скачать (с file-токеном). В сеть идём, только если на диске
  /// пусто.
  /// Сколько всего ждём одну картинку. Дальше — отказ, а не вечное ожидание:
  /// пока склад молчит, стоит подготовка ВСЕХ картинок виджета, и на рабочий
  /// стол уезжают одни тексты. Ни один шаг внутри не имеет права висеть дольше.
  static const Duration _loadBudget = Duration(seconds: 30);

  Future<Uint8List?> bytesFor(String url, String httpUrl) {
    final key = cacheKeyFor(url);
    final running = _inFlight[key];
    if (running != null) return running;

    // Общий предел на всю выдачу. Без него зависший шаг оставался бы в
    // `_inFlight` навсегда и раздавался бы всем следующим запросам той же
    // картинки — виджет не обновлялся до перезапуска приложения.
    final job = _load(key, httpUrl)
        .timeout(_loadBudget, onTimeout: () {
          debugPrint('WidgetPhotoStore: не уложились в ${_loadBudget.inSeconds}с — $key');
          return null;
        })
        // Тело в фигурных скобках — не стрелка. `Map.remove` отдаёт снятое
        // значение, а здесь это САМА текущая задача; стрелочный колбэк вернул
        // бы её наружу, и `whenComplete` стал бы ждать её завершения. Задача
        // ждала бы себя: байты прочитаны, а тот, кто их просил, не дожидается
        // никогда. Отсюда «на виджете меняется только текст»: тексты пишутся
        // раньше картинок, а картинка не доходит до контейнера вовсе.
        .whenComplete(() {
          _inFlight.remove(key);
        });
    _inFlight[key] = job;
    return job;
  }

  Future<Uint8List?> _load(String key, String httpUrl) async {
    // 1. Уже лежит на диске — сеть не нужна.
    //
    // База кэша живёт в sqflite и делится с экраном; когда её держит другой
    // изолят или диск занят, обращение возвращается не сразу, а иногда не
    // возвращается вовсе. Ждём ограниченно и идём в сеть: это медленнее, но
    // виджет обновится, а не застынет.
    try {
      final hit = await OfflineImageCacheManager.instance
          .getFileFromCache(key)
          .timeout(_diskStep);
      // Обрывок записи (нулевой или крошечный файл) — не кэш: отдать его
      // значило бы разложить пустоту по всем виджетам и больше никогда не
      // пойти в сеть.
      if (hit != null &&
          hit.file.existsSync() &&
          hit.file.lengthSync() >= kMinWidgetPhotoBytes) {
        // Читаем СВОИМ File по пути, а не объектом кэш-менеджера. У него файл
        // приходит из пакета `file` поверх своей файловой системы, и его
        // `readAsBytes` на Android умеет не вернуться вовсе: ни байтов, ни
        // исключения — подготовка картинки стоит, а на рабочем столе остаётся
        // прежний снимок при свежих текстах (замер на эмуляторе 08.09.2026:
        // кэш отвечает за 40 мс, дальше тишина до самого общего предела).
        final bytes =
            await File(hit.file.path).readAsBytes().timeout(_diskStep);
        return bytes;
      }
    } catch (e) {
      // Кэш недоступен (фоновый изолят, занятая база, срок вышел) — качаем.
      debugPrint('WidgetPhotoStore: кэш не прочитался — $e');
    }

    // 2. Качаем один раз.
    final Uint8List bytes;
    try {
      final response = await http
          .get(Uri.parse(httpUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        debugPrint('WidgetPhotoStore: ${response.statusCode} на $key');
        return null;
      }
      bytes = response.bodyBytes;
    } catch (e) {
      debugPrint('WidgetPhotoStore: не скачалось — $e');
      return null;
    }

    // 3. Кладём на общий склад, чтобы следующий (в том числе экран) не качал.
    // Ждём ограниченно: байты уже в руках, и запись — услуга следующему, а не
    // условие выдачи. Раньше здесь стоял голый `await`, и заминка базы кэша
    // останавливала подготовку картинки целиком.
    try {
      await OfflineImageCacheManager.instance
          .putFile(
            httpUrl,
            bytes,
            key: key,
            maxAge: const Duration(days: 3650),
          )
          .timeout(_diskStep);
    } catch (e) {
      debugPrint('WidgetPhotoStore: на склад не легло — $e');
    }
    return bytes;
  }
}
