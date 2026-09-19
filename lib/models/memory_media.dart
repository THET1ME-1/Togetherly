/// Какие файлы воспоминания можно положить в галерею телефона.
///
/// До 19.09.2026 кнопка скачивания брала только обложку (`imageUrl`) и считала
/// внешней ссылкой всё, что не похоже на Firebase. После переезда на свой
/// сервер так выглядел каждый файл: кнопка открывала браузер с одним кадром из
/// сотни. Правила собраны здесь, чтобы и кнопка, и выбор кадров, и вся пара
/// считали одинаково.
library;

import 'memory.dart';
import 'pb_media_ref.dart';

/// Вид файла определяет, куда он ляжет: фото и видео в папку галереи,
/// звук — в «Загрузки».
enum SaveKind { photo, video, audio }

/// Один сохраняемый файл воспоминания.
class MediaFile {
  /// Ссылка как она лежит в записи: `pb://…`, адрес сервера или
  /// `localfile://…` у ещё не отправленного файла.
  final String ref;
  final SaveKind kind;

  /// Номер среди кадров записи, с нуля. У ролика смешанной записи — после
  /// последнего кадра.
  final int index;

  /// Картинка-превью для плитки: у ролика это обложка, у кадра — сам кадр.
  final String? thumb;

  const MediaFile({
    required this.ref,
    required this.kind,
    required this.index,
    this.thumb,
  });

  String get key => mediaKey(ref);
  String get ext => mediaExt(ref, kind);

  @override
  bool operator ==(Object other) => other is MediaFile && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Файл с нашего сервера или ещё не отправленный с этого телефона.
///
/// Всё остальное — ссылки на чужие площадки (YouTube, Spotify, Яндекс Музыка):
/// файла у нас нет, их открывают, а не сохраняют. Адреса Firebase мертвы с
/// переезда и тоже не свои.
bool isOwnMediaUrl(String url) {
  final u = url.trim();
  if (u.isEmpty) return false;
  if (u.startsWith('pb://')) return true;
  if (u.startsWith('localfile://')) return true;
  return pbRefFromUrl(u) != null;
}

/// Постоянный ключ файла: у `pb://` и у готового адреса с токеном он один.
///
/// По ключу телефон помнит, что файл уже в галерее, — токен меняется каждые
/// полторы минуты, и по полной ссылке один кадр считался бы разными.
String mediaKey(String url) {
  final u = url.trim();
  final ref = pbRefFromUrl(u) ?? u;
  final q = ref.indexOf('?');
  return q == -1 ? ref : ref.substring(0, q);
}

/// Расширение из имени файла, а без него — по виду.
String mediaExt(String url, SaveKind kind) {
  var name = mediaKey(url).split('/').last;
  final hash = name.indexOf('#');
  if (hash != -1) name = name.substring(0, hash);
  final dot = name.lastIndexOf('.');
  if (dot > 0 && dot < name.length - 1) {
    final ext = name.substring(dot + 1).toLowerCase();
    if (ext.length <= 5 && RegExp(r'^[a-z0-9]+$').hasMatch(ext)) return ext;
  }
  switch (kind) {
    case SaveKind.photo:
      return 'jpg';
    case SaveKind.video:
      return 'mp4';
    case SaveKind.audio:
      return 'mp3';
  }
}

/// Файлы записи, которые можно сохранить.
///
/// Запечатанная капсула не отдаёт ничего до даты открытия: её содержимого не
/// видел и автор. Секретная запись под замком тоже пуста — иначе выбор
/// нескольких записей вынес бы в галерею то, что закрыто пином.
List<MediaFile> memoryMediaFiles(
  Memory m, {
  bool secretUnlocked = true,
  DateTime? now,
}) {
  if (m.sealedNow(now)) return const [];
  if (m.isSecret && !secretUnlocked) return const [];

  final out = <MediaFile>[];
  switch (m.type) {
    case MemoryType.photo:
      final urls = <String>[
        for (final u in m.imageUrls ?? const <String>[])
          if (u.trim().isNotEmpty) u.trim(),
      ];
      if (urls.isEmpty && (m.imageUrl?.trim().isNotEmpty ?? false)) {
        urls.add(m.imageUrl!.trim());
      }
      for (final u in urls) {
        if (!isOwnMediaUrl(u)) continue;
        out.add(MediaFile(
            ref: u, kind: SaveKind.photo, index: out.length, thumb: u));
      }
      // Смешанная запись: снимки и ролик в одном воспоминании.
      final v = m.videoUrl?.trim() ?? '';
      if (v.isNotEmpty && isOwnMediaUrl(v)) {
        out.add(MediaFile(
          ref: v,
          kind: SaveKind.video,
          index: out.length,
          thumb: urls.isNotEmpty ? urls.first : null,
        ));
      }
    case MemoryType.video:
      final v = m.videoUrl?.trim() ?? '';
      if (v.isNotEmpty && isOwnMediaUrl(v)) {
        final t = m.imageUrl?.trim();
        out.add(MediaFile(
          ref: v,
          kind: SaveKind.video,
          index: 0,
          thumb: (t != null && t.isNotEmpty) ? t : null,
        ));
      }
    case MemoryType.music:
      final a = m.musicUrl?.trim() ?? '';
      if (a.isNotEmpty && isOwnMediaUrl(a)) {
        out.add(MediaFile(
          ref: a,
          kind: SaveKind.audio,
          index: 0,
          thumb: m.musicCoverUrl,
        ));
      }
    case MemoryType.videoLink:
    case MemoryType.location:
    case MemoryType.text:
    case MemoryType.book:
    case MemoryType.movie:
      break;
  }
  return out;
}

/// Средний вес файла по виду — для строки «около N МБ» до загрузки.
///
/// Замер по бакету 19.09.2026: кадр воспоминания 336 КБ, ролик 4,2 МБ, свой
/// файл музыки 6,3 МБ. Настоящий размер до скачивания неизвестен: в записи его
/// нет, а спрашивать сервер о каждом файле ради подписи дороже самой подписи.
const Map<SaveKind, int> kAverageBytes = {
  SaveKind.photo: 336 * 1024,
  SaveKind.video: 4300 * 1024,
  SaveKind.audio: 6332 * 1024,
};

class MediaSummary {
  final int photos;
  final int videos;
  final int audio;

  /// Примерный вес в байтах по [kAverageBytes].
  final int bytes;

  const MediaSummary({
    required this.photos,
    required this.videos,
    required this.audio,
    required this.bytes,
  });

  int get total => photos + videos + audio;

  /// Мегабайты для подписи, не меньше одного.
  int get megabytes {
    final mb = (bytes / (1024 * 1024)).round();
    return mb < 1 && total > 0 ? 1 : mb;
  }
}

MediaSummary summarizeMedia(Iterable<MediaFile> files) {
  var p = 0, v = 0, a = 0, b = 0;
  for (final f in files) {
    switch (f.kind) {
      case SaveKind.photo:
        p++;
      case SaveKind.video:
        v++;
      case SaveKind.audio:
        a++;
    }
    b += kAverageBytes[f.kind]!;
  }
  return MediaSummary(photos: p, videos: v, audio: a, bytes: b);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Имя файла в галерее: `Togetherly_20260905_130507_02.webp`.
///
/// Дата — воспоминания, а не загрузки: по имени файл находится в папке рядом со
/// своими, даже если галерея не прочтёт дату из самого файла.
String galleryFileName(DateTime takenAt, MediaFile f) {
  final d = takenAt;
  final stamp = '${d.year}${_two(d.month)}${_two(d.day)}_'
      '${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';
  return 'Togetherly_${stamp}_${_two(f.index + 1)}.${f.ext}';
}
