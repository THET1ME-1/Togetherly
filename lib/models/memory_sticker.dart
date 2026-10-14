import 'dart:math' as math;

/// Наклейка на пине: картинка из набора настроений поверх главного блока
/// записи — фото, листа заметки или обложки.
///
/// Место хранится в долях блока, а не в точках: в ленте и в открытой записи
/// блок разного размера, и наклейка должна стоять на той же части фото.
/// Центр не выходит за блок, поэтому наклейка свисает за край самое большее
/// наполовину.
///
/// Лежит в json-поле `data` записи (`data.stickers`, карта id → наклейка),
/// а пишет её сервер отдельной операцией (`sticker_put` / `sticker_del` в
/// hotpath): так двое в паре клеят одновременно и не затирают друг друга, а
/// обычная правка записи наклейки не трогает. Правила ниже повторены на
/// сервере (`наклейка_из_тела` в `pocketbase/hotpath/hotpath.py`).
class MemorySticker {
  const MemorySticker({
    required this.id,
    required this.uid,
    required this.image,
    this.pack = '',
    this.mood = '',
    required this.x,
    required this.y,
    this.size = kStickerDefaultSize,
    this.angle = 0,
    this.at = 0,
  });

  final String id;

  /// Кто наклеил. Переставить наклейку может только он, убрать — он и автор
  /// записи.
  final String uid;

  /// Картинка: ассет сборки или адрес каталога, как `imagePath` настроения.
  final String image;

  /// Набор и настроение в нём — по ним каталог находит свежий адрес, если
  /// набор перезалили.
  final String pack;
  final String mood;

  /// Центр наклейки в долях ширины и высоты блока, 0…1.
  final double x;
  final double y;

  /// Сторона наклейки в долях ширины блока.
  final double size;

  /// Поворот, радианы.
  final double angle;

  /// Когда наклеили, мс. Порядок слоёв: новая ложится сверху.
  final int at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'img': image,
        'pack': pack,
        'mood': mood,
        'x': x,
        'y': y,
        's': size,
        'r': angle,
        't': at,
      };

  MemorySticker copyWith({double? x, double? y, double? size, double? angle}) =>
      MemorySticker(
        id: id,
        uid: uid,
        image: image,
        pack: pack,
        mood: mood,
        x: x ?? this.x,
        y: y ?? this.y,
        size: size ?? this.size,
        angle: angle ?? this.angle,
        at: at,
      );

  /// Наклейка из json или null, если она битая: запись важнее наклейки, и
  /// чужая версия приложения не должна ронять ленту.
  static MemorySticker? fromJson(dynamic raw, {String? id}) {
    if (raw is! Map) return null;
    final sid = (raw['id'] ?? id ?? '').toString();
    final uid = (raw['uid'] ?? '').toString();
    final image = (raw['img'] ?? '').toString();
    if (sid.isEmpty || uid.isEmpty || !stickerImageAllowed(image)) return null;
    double num0(Object? v, double fallback) =>
        v is num && v.isFinite ? v.toDouble() : fallback;
    return clampSticker(MemorySticker(
      id: sid,
      uid: uid,
      image: image,
      pack: (raw['pack'] ?? '').toString(),
      mood: (raw['mood'] ?? '').toString(),
      x: num0(raw['x'], .5),
      y: num0(raw['y'], .5),
      size: num0(raw['s'], kStickerDefaultSize),
      angle: num0(raw['r'], 0),
      at: raw['t'] is num ? (raw['t'] as num).toInt() : 0,
    ));
  }
}

/// Своих наклеек на одну запись. Вдвоём выходит до шести — больше на фото
/// уже не видно самого фото.
const int kStickersPerPerson = 3;

const double kStickerDefaultSize = 0.28;
const double kStickerMinSize = 0.12;
const double kStickerMaxSize = 0.7;

const int _kMaxImageLength = 300;

/// Картинка наклейки годится: ассет сборки или файл каталога на своём
/// сервере. Чужой адрес не берём — иначе запись подгружала бы картинку с
/// любого сайта у партнёра.
bool stickerImageAllowed(String path) {
  if (path.isEmpty || path.length > _kMaxImageLength) return false;
  if (path.contains('..')) return false;
  if (path.startsWith('assets/images/')) return true;
  const hosts = [
    'https://togetherly.day/api/files/catalog_items/',
    'https://togetherly.duckdns.org/api/files/catalog_items/',
  ];
  return hosts.any(path.startsWith);
}

/// Место, размер и поворот в допустимых пределах.
MemorySticker clampSticker(MemorySticker s) {
  var angle = s.angle % (2 * math.pi);
  if (angle > math.pi) angle -= 2 * math.pi;
  return s.copyWith(
    x: s.x.clamp(0.0, 1.0),
    y: s.y.clamp(0.0, 1.0),
    size: s.size.clamp(kStickerMinSize, kStickerMaxSize),
    angle: angle,
  );
}

/// Наклейки записи из `data.stickers`: старые снизу, новые сверху.
List<MemorySticker> parseStickers(dynamic raw) {
  if (raw is! Map) return const [];
  final out = <MemorySticker>[];
  raw.forEach((k, v) {
    final s = MemorySticker.fromJson(v, id: k.toString());
    if (s != null) out.add(s);
  });
  out.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return out;
}

Map<String, dynamic> stickersToJson(List<MemorySticker> list) => {
      for (final s in list) s.id: s.toJson(),
    };

int stickersBy(List<MemorySticker> list, String uid) =>
    list.where((s) => s.uid == uid).length;

bool canAddSticker(List<MemorySticker> list, String uid) =>
    uid.isNotEmpty && stickersBy(list, uid) < kStickersPerPerson;

bool canMoveSticker(MemorySticker s, String uid) =>
    uid.isNotEmpty && s.uid == uid;

/// Свою наклейку убирает тот, кто наклеил. Автор записи убирает любую со
/// своего пина: это его воспоминание.
bool canRemoveSticker(MemorySticker s,
        {required String uid, required String authorUid}) =>
    uid.isNotEmpty && (s.uid == uid || authorUid == uid);

/// Копия json-карты записи с наклейкой [s] (новой или переставленной).
Map<String, dynamic> withSticker(Map<String, dynamic> data, MemorySticker s) {
  final map = Map<String, dynamic>.from(data);
  final stickers = map['stickers'] is Map
      ? Map<String, dynamic>.from(map['stickers'] as Map)
      : <String, dynamic>{};
  stickers[s.id] = s.toJson();
  map['stickers'] = stickers;
  return map;
}

/// Копия json-карты записи без наклейки [id].
Map<String, dynamic> withoutSticker(Map<String, dynamic> data, String id) {
  final map = Map<String, dynamic>.from(data);
  if (map['stickers'] is! Map) return map;
  final stickers = Map<String, dynamic>.from(map['stickers'] as Map)
    ..remove(id);
  map['stickers'] = stickers;
  return map;
}
