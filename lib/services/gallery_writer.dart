import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

import '../models/memory_media.dart';
import 'media_save_queue.dart';

/// Запись в галерею телефона своим каналом `love_app/gallery`.
///
/// Пакет `gal` кладёт файл в папку, но дату съёмки и место не ставит, а
/// Togetherly срезает их у снимков при загрузке: 94 летних кадра встали бы в
/// галерее «сегодня». Поэтому пишем сами:
///
/// * Android (`GallerySaver.kt`) — MediaStore с `DATE_TAKEN` в
///   `Pictures/Togetherly`, в снимок — EXIF с датой, поясом и координатами.
///   Звук — `Download/Togetherly`.
/// * iPhone (`AppDelegate.swift`) — PhotoKit с `creationDate` и `location`,
///   альбом «Togetherly». WebP перед импортом пережимается в JPEG.
///
/// От `gal` берём только разрешения: он знает, какое спрашивать на каждой
/// версии системы (Android 9 и ниже — запись в хранилище, iPhone — полный
/// доступ к медиатеке, без него альбом не завести).
class GalleryWriter implements GalleryTarget {
  GalleryWriter._();
  static final GalleryWriter instance = GalleryWriter._();

  static const MethodChannel channel = MethodChannel('love_app/gallery');

  /// Коды отказа нативной стороны.
  static const String accessDeniedCode = 'ACCESS_DENIED';

  /// Спросить доступ к галерее до постановки в очередь. `false` — человек
  /// отказал, сохранять некуда.
  Future<bool> ensureAccess() async {
    try {
      if (await Gal.hasAccess(toAlbum: true)) return true;
      return await Gal.requestAccess(toAlbum: true);
    } catch (e) {
      debugPrint('GalleryWriter.ensureAccess: $e');
      return false;
    }
  }

  @override
  Future<String?> save(GallerySaveRequest r) async {
    try {
      return await channel.invokeMethod<String>('save', <String, Object?>{
        'path': r.path,
        'kind': r.kind.name,
        'takenAt': r.takenAt.millisecondsSinceEpoch,
        // Пояс нужен EXIF: там дата пишется местным временем со смещением.
        'offsetMinutes': r.takenAt.timeZoneOffset.inMinutes,
        'latitude': r.latitude,
        'longitude': r.longitude,
        'name': r.name,
        'album': r.album,
        'hidden': r.hidden,
      });
    } on PlatformException catch (e) {
      if (e.code == accessDeniedCode) throw const GalleryAccessDenied();
      rethrow;
    } on MissingPluginException {
      // Сборка без своего канала (не должно быть, но лучше файл без даты,
      // чем никакого).
      return _viaGal(r);
    }
  }

  Future<String?> _viaGal(GallerySaveRequest r) async {
    try {
      if (r.kind == SaveKind.video) {
        await Gal.putVideo(r.path, album: r.album);
      } else if (r.kind == SaveKind.photo) {
        await Gal.putImage(r.path, album: r.album);
      } else {
        throw const FileSystemException('Звук без своего канала не сохранить');
      }
      return null;
    } on GalException catch (e) {
      if (e.type == GalExceptionType.accessDenied) {
        throw const GalleryAccessDenied();
      }
      rethrow;
    }
  }

  /// Открыть галерею на сохранённом файле, а без него — просто галерею.
  Future<void> open([String? uri]) async {
    try {
      await channel.invokeMethod<void>('open', {'uri': uri});
    } catch (_) {
      try {
        await Gal.open();
      } catch (_) {}
    }
  }

  /// Платформа, где звук ложится в «Загрузки»: на iPhone галерея звук не
  /// принимает, там он уходит через «Поделиться».
  static bool get audioToDownloads => Platform.isAndroid;
}
