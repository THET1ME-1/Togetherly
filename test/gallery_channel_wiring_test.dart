// Канал `love_app/gallery` живёт в трёх языках: Dart зовёт, Kotlin и Swift
// пишут в галерею. Разъезд имени, метода или ключа аргумента ничем себя не
// выдаёт — кнопка просто молча перестаёт сохранять, а на ноутбуке без macOS
// Swift даже не компилируется. Сверяем исходники.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/gallery_writer.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  final dart = _read('lib/services/gallery_writer.dart');
  final kotlin =
      _read('android/app/src/main/kotlin/com/togetherly/love/GallerySaver.kt');
  final activity =
      _read('android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt');
  final swift = _read('ios/Runner/AppDelegate.swift');
  final gradle = _read('android/app/build.gradle.kts');
  final executor = _read('lib/services/native_save_executor.dart');
  final queue = _read('lib/services/media_save_queue.dart');
  final engine = _read(
      'android/app/src/main/kotlin/com/togetherly/love/MediaSaveEngine.kt');
  final service = _read(
      'android/app/src/main/kotlin/com/togetherly/love/MediaSaveService.kt');
  final manifest = _read('android/app/src/main/AndroidManifest.xml');

  test('имя канала одно во всех трёх местах', () {
    expect(GalleryWriter.channel.name, 'love_app/gallery');
    expect(kotlin, contains('const val CHANNEL = "love_app/gallery"'));
    expect(swift, contains('name: "love_app/gallery"'));
  });

  test('канал зарегистрирован на обеих платформах', () {
    expect(activity, contains('GallerySaver.CHANNEL'));
    expect(activity, contains('setMethodCallHandler(GallerySaver('));
    expect(swift, contains('setupGalleryChannel(engineBridge.pluginRegistry)'));
  });

  test('методы save и open понимают обе стороны', () {
    for (final m in ['save', 'open']) {
      expect(dart, contains("'$m'"));
      expect(kotlin, contains('"$m" ->'));
      expect(swift, contains('case "$m":'));
    }
  });

  test('каждый ключ аргумента, который шлёт Dart, читает натив', () {
    final keys = RegExp(r"'(\w+)': r\.")
        .allMatches(dart)
        .map((m) => m.group(1)!)
        .toSet();
    expect(keys, containsAll(<String>[
      'path', 'kind', 'takenAt', 'offsetMinutes', 'latitude', 'longitude',
      'name', 'album', 'hidden',
    ]));
    // Скрытие — только iPhone: на Android альбома «Скрытые» нет. Пояс —
    // только Android: он нужен EXIF, а PhotoKit принимает абсолютную дату.
    const iosOnly = {'hidden'};
    const androidOnly = {'offsetMinutes'};
    for (final k in keys) {
      if (!androidOnly.contains(k)) {
        expect(swift, contains('args["$k"]'), reason: 'Swift не читает $k');
      }
      if (!iosOnly.contains(k)) {
        expect(kotlin, contains('("$k")'), reason: 'Kotlin не читает $k');
      }
    }
  });

  test('Android сам говорит, нужен ли доступ: с десятой версии — нет', () {
    // gal на Android 10 просит WRITE_EXTERNAL_STORAGE, а оно в манифесте
    // только до Android 9: спроси мы через него, система отказала бы сразу.
    expect(dart, contains("invokeMethod<bool>('hasAccess')"));
    expect(kotlin, contains('"hasAccess" ->'));
    expect(kotlin, contains('Build.VERSION_CODES.Q'));
    expect(manifest,
        contains('WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"'));
  });

  test('отказ в доступе называется одинаково', () {
    expect(GalleryWriter.accessDeniedCode, 'ACCESS_DENIED');
    expect(kotlin, contains('const val ACCESS_DENIED = "ACCESS_DENIED"'));
    expect(swift, contains('code: "ACCESS_DENIED"'));
  });

  test('Android: папка Pictures/Togetherly, дата съёмки и EXIF', () {
    expect(kotlin, contains('Environment.DIRECTORY_PICTURES'));
    expect(kotlin, contains(r'"$dir/$album"'));
    expect(kotlin, contains('"datetaken"'));
    expect(kotlin, contains('TAG_DATETIME_ORIGINAL'));
    expect(kotlin, contains('TAG_OFFSET_TIME_ORIGINAL'));
    expect(kotlin, contains('setLatLong'));
    expect(kotlin, contains('IS_PENDING'));
    expect(gradle, contains('androidx.exifinterface:exifinterface'));
  });

  test('iPhone: дата, место и альбом при импорте, WebP в JPEG', () {
    expect(swift, contains('import Photos'));
    expect(swift, contains('request.creationDate'));
    expect(swift, contains('request.location'));
    expect(swift, contains('creationRequestForAssetCollection(withTitle:'));
    expect(swift, contains('jpegData('));
    expect(swift, contains('performChangesAndWait'));
    // Поиск альбома ждёт PhotoKit синхронно — не на главном потоке.
    expect(swift, contains('GallerySaver.queue.async'));
  });

  // ── Фоновая запись (19.09.2026) ──
  // Качает и кладёт в галерею натив, Dart только отдаёт файлы и забирает
  // готовое. Метод, который не узнала одна из сторон, отвечает «не реализован»
  // — и сохранение встаёт целиком, причём на Android и iPhone по-разному.

  test('методы фоновой записи понимают Dart, Kotlin и Swift', () {
    for (final m in [
      'engineSubmit', 'engineStatus', 'engineAck', 'engineCancel',
    ]) {
      expect(executor, contains("'$m'"), reason: 'Dart не зовёт $m');
      expect(kotlin, contains('"$m" ->'), reason: 'Kotlin не знает $m');
      expect(swift, contains('case "$m":'), reason: 'Swift не знает $m');
    }
  });

  test('каждый ключ файла, который отдаёт Dart, читает натив', () {
    final keys = RegExp(r"^\s+'(\w+)':", multiLine: true)
        .allMatches(executor.substring(executor.indexOf("'engineSubmit'")))
        .map((m) => m.group(1)!)
        .takeWhile((k) => k != 'saving')
        .toSet();
    expect(keys, containsAll(<String>[
      'key', 'kind', 'takenAt', 'offsetMinutes', 'latitude', 'longitude',
      'name', 'album', 'hidden', 'title', 'labels',
    ]));
    const iosOnly = {'hidden'};
    const androidOnly = {'offsetMinutes'};
    for (final k in keys) {
      if (!androidOnly.contains(k)) {
        expect(swift, contains('["$k"]'), reason: 'Swift не читает $k');
      }
      if (!iosOnly.contains(k)) {
        expect(engine, matches(RegExp('\\b(a|args)\\["$k"\\]')),
            reason: 'Kotlin не читает $k');
      }
    }
    // Источник файла: путь или ссылка, и копию из кэша натив убирает сам.
    for (final k in ['path', 'url', 'deleteAfter']) {
      expect(executor, contains("'$k'"));
      expect(engine, contains('a["$k"]'));
      expect(swift, contains('["$k"]'));
    }
  });

  test('коды итогов одинаковы на трёх сторонах', () {
    for (final c in ['OK', 'ACCESS_DENIED', 'CANCELLED']) {
      expect(executor, contains("case '$c':"));
      expect(engine, contains('const val $c = "$c"'));
    }
    for (final c in ['OK', 'FAILED', 'ACCESS_DENIED']) {
      expect(swift, contains('"$c"'));
    }
  });

  test('на обеих платформах очередь работает через натив', () {
    expect(queue, contains('NativeSaveExecutor.instance'));
    expect(queue, contains('Platform.isAndroid'));
    expect(queue, contains('Platform.isIOS'));
  });

  test('Android: служба переднего плана dataSync с кнопкой «Остановить»', () {
    expect(manifest, contains('android:name=".MediaSaveService"'));
    final decl = manifest.substring(manifest.indexOf('.MediaSaveService'));
    expect(decl.substring(0, decl.indexOf('/>')),
        contains('android:foregroundServiceType="dataSync"'));
    expect(manifest, contains('FOREGROUND_SERVICE_DATA_SYNC'));
    expect(manifest, contains('POST_NOTIFICATIONS'));
    expect(service, contains('FOREGROUND_SERVICE_TYPE_DATA_SYNC'));
    // Android 15 даёт dataSync шесть часов в сутки и зовёт onTimeout: без
    // него служба падает, а очередь теряет всё, что не успела.
    expect(service, contains('override fun onTimeout(startId: Int, fgsType: Int)'));
    expect(service, contains('ACTION_STOP'));
    expect(engine, contains('MediaSaveService.ensureRunning'));
  });

  test('iPhone: фоновая сессия будит приложение и отдаёт события', () {
    expect(swift, contains('URLSessionConfiguration.background(withIdentifier:'));
    expect(swift, contains('sessionSendsLaunchEvents = true'));
    expect(swift, contains('handleEventsForBackgroundURLSession identifier'));
    expect(swift, contains('func urlSessionDidFinishEvents'));
    expect(swift, contains('didFinishDownloadingTo location'));
    // Сессию надо поднять при каждом запуске, иначе события загрузок,
    // начатых до перезапуска, не придут.
    final setup = swift.substring(swift.indexOf('func setupGalleryChannel'));
    expect(setup.substring(0, setup.indexOf('\n  }\n')),
        contains('BackgroundSaveEngine.shared.reconnect()'));
  });

  test('недоделанное продолжается при запуске, а не в ленте', () {
    final home = _read('lib/screens/home_screen.dart');
    expect(home, contains('MediaSaveQueue.instance.resume()'));
  });
}
