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
}
