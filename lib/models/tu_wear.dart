import 'dart:convert';

/// Вещь гардероба Ту (маскота-облачка): запись каталога вида `wear`.
///
/// Рисунок вещи не перерисовывается в приложении: мастерская (`bake_wear.py`)
/// запекает её на каждую сцену облачка и каждую эмоцию пака двумя прозрачными
/// слоями — «сзади» (за телом) и «спереди» (поверх). Слои лежат в каталоге
/// картинками (`art`), а здесь только карта «сцена → слои» и правила наряда.
class TuWear {
  const TuWear({
    required this.key,
    required this.cat,
    required this.src,
    required this.nameRu,
    required this.nameEn,
    required this.iconKey,
    required this.layers,
    this.set = '',
    this.rarity = '',
    this.price = 0,
    this.sort = 500,
    this.retired = false,
  });

  /// Ключ вещи: он же лежит у человека в `users.owned_wear`.
  final String key;

  /// Раздел гардероба — место на Ту (`glasses`, `neck`, `face`, `top`,
  /// `over`, `pet`). В разделе надета одна вещь, разделы носятся вместе.
  final String cat;

  /// Откуда вещь: `chest` — выпадает из сундука, `coins`, `ad`.
  final String src;
  final String nameRu;
  final String nameEn;

  /// Ключ картинки-значка вещи в каталоге.
  final String iconKey;

  /// Сцена (`idle_base`, `emo_love`) → [слой сзади, слой спереди], ключи
  /// картинок каталога. Пустой слой — null: вещи в этой сцене там не видно.
  final Map<String, List<String?>> layers;
  final String set;
  final String rarity;
  final int price;
  final int sort;

  /// Вещь снята с сервера (`enabled = false`): из сундука больше не выпадает,
  /// но у тех, кому досталась, остаётся и надевается.
  final bool retired;

  bool get fromChest => src == 'chest';

  ({String? back, String? front}) layersFor(String scene) {
    final pair = layers[scene];
    if (pair == null) return (back: null, front: null);
    return (back: pair.isNotEmpty ? pair[0] : null, front: pair.length > 1 ? pair[1] : null);
  }

  static TuWear? fromCatalog(Map<String, dynamic> row) {
    final data = (row['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final key = (data['key'] as String? ?? '').trim();
    final cat = (data['cat'] as String? ?? '').trim();
    if (key.isEmpty || cat.isEmpty) return null;
    final layers = <String, List<String?>>{};
    final raw = data['layers'];
    if (raw is Map) {
      raw.forEach((scene, pair) {
        if (pair is List) layers['$scene'] = [for (final p in pair) p is String && p.isNotEmpty ? p : null];
      });
    }
    return TuWear(
      key: key,
      cat: cat,
      src: data['src'] as String? ?? 'chest',
      nameRu: row['name_ru'] as String? ?? key,
      nameEn: row['name_en'] as String? ?? key,
      iconKey: data['icon'] as String? ?? '',
      layers: layers,
      set: data['set'] as String? ?? '',
      rarity: data['rarity'] as String? ?? '',
      price: (row['price'] as num?)?.toInt() ?? 0,
      sort: (row['sort'] as num?)?.toInt() ?? 500,
      retired: row['enabled'] == false,
    );
  }
}

/// Что показывать в гардеробе: все живые вещи и снятые, если они у человека
/// есть.
List<TuWear> wardrobeItems(List<TuWear> items, {required Set<String> owned}) =>
    [for (final w in items) if (!w.retired || owned.contains(w.key)) w];

/// Разделы гардероба по порядку вкладок. Тот же порядок задаёт, какой слой
/// «спереди» лежит выше: очки ниже шарфа, шарф ниже того, что над головой.
const List<String> kTuWearCats = ['glasses', 'face', 'neck', 'top', 'over', 'pet'];

String tuWearCatName(String cat, {required bool ru}) => switch (cat) {
      'glasses' => ru ? 'Очки' : 'Glasses',
      'face' => ru ? 'Лицо' : 'Face',
      'neck' => ru ? 'Шарфы и пледы' : 'Scarves',
      'top' => ru ? 'Макушка' : 'Head',
      'over' => ru ? 'Над головой' : 'Above',
      'pet' => ru ? 'Друг рядом' : 'Buddy',
      _ => cat,
    };

/// Надеть или снять [key] в разделе [cat]: в разделе одна вещь, повторное
/// нажатие снимает.
Map<String, String> wearToggle(Map<String, String> outfit, String cat, String key) {
  final next = Map<String, String>.of(outfit);
  if (next[cat] == key) {
    next.remove(cat);
  } else {
    next[cat] = key;
  }
  return next;
}

/// Ключ сцены для слоёв одежды: эмоция пака важнее сцены облачка (её играет
/// покой), сцена облачка — ключ каталога без приставки `cloud_`.
String? wearSceneOf({required String art, required String? emotion}) {
  if (emotion != null && emotion.isNotEmpty) return 'emo_$emotion';
  // Тряска в цвете эмоции движется так же, как обычная: одежда та же.
  if (art.startsWith('cloud_shake_emo_')) return 'shake_base';
  if (art.startsWith('cloud_')) return art.substring(6);
  return null;
}

/// Слои сцены [scene] для наряда [outfit]: только вещи во владении, по
/// порядку разделов. Сзади — снизу вверх, спереди — снизу вверх.
({List<String> back, List<String> front}) wearSceneLayers(
  Map<String, String> outfit,
  List<TuWear> items, {
  required Set<String> owned,
  required String scene,
}) {
  final back = <String>[], front = <String>[];
  for (final cat in kTuWearCats) {
    final key = outfit[cat];
    if (key == null || !owned.contains(key)) continue;
    TuWear? item;
    for (final w in items) {
      if (w.key == key) item = w;
    }
    if (item == null) continue;
    final l = item.layersFor(scene);
    if (l.back != null) back.add(l.back!);
    if (l.front != null) front.add(l.front!);
  }
  return (back: back, front: front);
}

String wearOutfitEncode(Map<String, String> outfit) => jsonEncode(outfit);

Map<String, String> wearOutfitDecode(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final m = jsonDecode(raw);
    if (m is! Map) return {};
    return {for (final e in m.entries) if (e.value is String) '${e.key}': e.value as String};
  } catch (_) {
    return {};
  }
}
