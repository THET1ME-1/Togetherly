import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'pocketbase_service.dart';
import 'pb_media_service.dart';
import 'offline/connectivity_service.dart';
import 'offline/media_cache.dart';

/// Медиа-загрузки приложения: WebP/видео-компрессия на устройстве + заливка
/// в PocketBase (коллекция `media`, схема `pb://`).
///
/// Вынесено из FirebaseService в рамках §4 cutover'а — call-site'ы загрузки
/// больше не зависят от Firebase-монолита. Резолв legacy `gs://`/`sb://`
/// ссылок (`getSignedUrl`/`resolveMediaUrl`) остаётся в FirebaseService до
/// §8-переноса данных. Crashlytics здесь — отдельный пакет (краш-репортинг
/// живёт до §7), не часть FirebaseService.
class MediaService {
  MediaService._();
  static final MediaService instance = MediaService._();
  factory MediaService() => instance;

  /// Доля сжатия текущего видео (0..1). null — сжатие не идёт.
  ///
  /// Сжатие минуты видео занимает десятки секунд, и всё это время плашка
  /// показывала «Синхронизация…» без движения — выглядело как зависание.
  /// Плашка (`offline_sync_banner`) слушает это значение и рисует волновую
  /// полосу с настоящей долей.
  final ValueNotifier<double?> compressProgress = ValueNotifier<double?>(null);

  /// Подписка на прогресс живёт одна на всё приложение: `subscribe` у
  /// video_compress закрывает свой StreamController при отписке, поэтому
  /// переподписываться на каждое видео дороже и рискованнее, чем держать одну.
  Subscription? _compressSub;

  void _beginCompressProgress() {
    compressProgress.value = 0;
    _compressSub ??= VideoCompress.compressProgress$.subscribe((p) {
      // Плагин отдаёт проценты (0..100), а полосе нужна доля.
      compressProgress.value = (p / 100).clamp(0.0, 1.0);
    });
  }

  void _endCompressProgress() => compressProgress.value = null;

  /// Сжать (растровая картинка → WebP, видео → H.264) и загрузить в PocketBase.
  ///
  /// [destination] = `<kind>/<groupId>/<file>` — из него берём имя файла, kind
  /// и group_id для ACL media-коллекции (createRule/viewRule по uid+group_id,
  /// см. b8d5daf). Возвращает `pb://media/<id>/<file>` или null.
  Future<String?> uploadFile(String path, String destination) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('uploadFile: File does not exist: $path');
        return null;
      }

      final fileSize = await file.length();
      debugPrint('uploadFile: Starting upload of $destination ($fileSize bytes)');

      final ext = path.split('.').last.toLowerCase();

      // Convert raster images to WebP before upload — typically 30-60% smaller
      // than JPEG at equivalent visual quality. Storage path gets .webp extension.
      File fileToUpload = file;
      var uploadDestination = destination;
      if (['jpg', 'jpeg', 'png'].contains(ext)) {
        try {
          final tempDir = await getTemporaryDirectory();
          final targetPath =
              '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_comp.webp';
          // ⚠️ Таймаут обязателен: на части устройств (напр. realme/ColorOS,
          // Android 16) нативный кодек flutter_image_compress зависает на
          // некоторых снимках и НИКОГДА не возвращает future. try/catch такой
          // «вечный» вызов НЕ ловит (зависший future не бросает) → бесконечный
          // спиннер загрузки. Таймаут превращает зависание в исключение →
          // падаем в catch ниже и грузим оригинал.
          final xFile = await FlutterImageCompress.compressAndGetFile(
            path,
            targetPath,
            quality: 87,
            format: CompressFormat.webp,
            autoCorrectionAngle: true,
            keepExif: false,
          ).timeout(const Duration(seconds: 20));
          if (xFile != null) {
            final webpFile = File(xFile.path);
            final webpSize = await webpFile.length();
            debugPrint('uploadFile: WebP conversion $fileSize → $webpSize bytes');
            if (webpSize < fileSize) {
              fileToUpload = webpFile;
              uploadDestination = destination.replaceAll(
                RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false),
                '.webp',
              );
            } else {
              // WebP turned out larger — keep the original
              debugPrint('uploadFile: WebP larger than original, uploading original $ext');
              webpFile.delete().catchError((_) => webpFile);
            }
          }
        } catch (e) {
          debugPrint('uploadFile: WebP conversion failed, uploading original: $e');
        }
      }

      // Сжатие перед загрузкой аппаратным кодеком устройства (H.264).
      //
      // Раньше стояло HighestQuality — исходное разрешение и частота кадров.
      // Для воспоминания, которое смотрят с телефона, это перебор: файл втрое
      // тяжелее, а разница на шестидюймовом экране не видна. Место при этом
      // занимается навсегда — воспоминания не удаляют, в них весь смысл.
      //
      // DefaultQuality даёт 720p: минута видео весит около 30 МБ вместо 90.
      File? compressedTempFile;
      if (!kIsWeb && ['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        _beginCompressProgress();
        try {
          // Таймаут обязателен: VideoCompress на части устройств/кодеков виснет
          // и future НИКОГДА не возвращается (как FlutterImageCompress выше) →
          // экран добавления воспоминания крутил бы спиннер вечно, видео «не
          // отражается». 3 минуты — анти-зависание (легитимное сжатие успевает),
          // по истечении бросаем → catch ниже грузит оригинал.
          final info = await VideoCompress.compressVideo(
            path,
            quality: VideoQuality.DefaultQuality,
            deleteOrigin: false,
            includeAudio: true,
          ).timeout(
            const Duration(minutes: 3),
            onTimeout: () =>
                throw TimeoutException('VideoCompress.compressVideo timed out'),
          );
          if (info?.file != null) {
            compressedTempFile = info!.file!;
            fileToUpload = compressedTempFile;
            uploadDestination = destination.replaceAll(
              RegExp(r'\.(mov|avi|mkv)$', caseSensitive: false),
              '.mp4',
            );
            debugPrint(
              'uploadFile: Video compressed $fileSize → ${await fileToUpload.length()} bytes',
            );
          }
        } catch (e) {
          debugPrint('uploadFile: Video compression failed, uploading original: $e');
          // Фиксируем в Crashlytics: сжатие зависло/упало — частая причина жалоб
          // «своё видео не добавляется». Non-fatal, дальше грузим оригинал.
          unawaited(
            Sentry.captureException(
              e,
              withScope: (s) {
                s.setExtra('reason', 'video compress failed → uploading original');
                s.level = SentryLevel.warning;
              },
            ),
          );
          // cancelCompression only on error — calling it after success on some
          // Android devices leaves the native codec spinning and freezes the UI.
          VideoCompress.cancelCompression();
        } finally {
          _endCompressProgress();
        }
      }

      // Медиа в PocketBase (коллекция `media`) — грузим уже сжатые байты,
      // возвращаем `pb://`-ссылку. Путь uploadDestination = `<kind>/<groupId>/<file>`
      // → из него берём имя файла, kind и group_id.
      final bytes = await fileToUpload.readAsBytes();
      final segments = uploadDestination.split('/');
      final filename = segments.last;
      final kind = segments.length > 1 ? segments.first : null;
      // group_id — второй сегмент пути (memories/<groupId>/file, canvas/<groupId>/…,
      // widget/<groupId>/…). КРИТИЧНО: после ACL по членству (b8d5daf) media
      // createRule/viewRule пускает запись/чтение только владельцу (uid) ИЛИ члену
      // группы (group_id). uid даёт create + self-view, group_id — просмотр
      // партнёром-членом группы. (avatars/<uid>/… — group_id окажется = uid.)
      final groupId = segments.length >= 3 ? segments[1] : null;
      // Офлайн + медиа воспоминания (memories/music) → откладываем: прячем
      // сжатый файл локально и возвращаем localfile://. Реальную заливку и
      // подмену ссылки на pb:// сделает MediaCache.flushPending при появлении
      // сети. Прочие kind (avatars/mascots/canvas) офлайн не откладываем.
      final deferrable = kind == 'memories' || kind == 'music';
      if (deferrable && !ConnectivityService.instance.isOnline) {
        final localRef = await MediaCache.instance
            .stash(bytes, filename, kind: kind, groupId: groupId);
        compressedTempFile?.delete().ignore();
        debugPrint('uploadFile → офлайн, отложено: $localRef');
        return localRef;
      }
      final pbRef = await PbMediaService().uploadBytes(
        bytes,
        filename,
        uid: PocketBaseService().userId,
        groupId: groupId,
        kind: kind,
      );
      compressedTempFile?.delete().ignore();
      debugPrint('uploadFile → PocketBase: $pbRef');
      return pbRef;
    } catch (e) {
      debugPrint('uploadFile failed: $e');
      return null;
    }
  }

  /// Загрузить изображение холста (рисунок) → `pb://`.
  Future<String?> uploadDrawingImage({
    required String groupId,
    required String localPath,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return uploadFile(localPath, 'groups/$groupId/canvas/img_$ts.jpg');
  }

  /// Загрузить сырые PNG-байты маскота → `pb://`.
  Future<String?> uploadMascotImage({
    required String groupId,
    required List<int> pngBytes,
  }) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      return await PbMediaService().uploadBytes(
        pngBytes,
        'mascot_$ts.png',
        groupId: groupId,
        kind: 'mascots',
      );
    } catch (e) {
      debugPrint('uploadMascotImage failed: $e');
      return null;
    }
  }

  /// Удаляет ранее загруженный PocketBase-файл по его `pb://`-ссылке (удаляет
  /// запись коллекции `media` вместе с самим файлом). Для не-PB ссылок (legacy
  /// `http`/`gs://`/`sb://`) и локальных путей — no-op: Firebase здесь НЕ
  /// используется. Best-effort: ошибки гасятся, чтобы не ломать вызывающий
  /// поток замены/удаления медиа.
  Future<void> deleteByUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    if (!PbMediaService().isPbRef(url)) return;
    try {
      await PbMediaService().delete(url);
    } catch (e) {
      debugPrint('MediaService.deleteByUrl failed: $e');
    }
  }
}
