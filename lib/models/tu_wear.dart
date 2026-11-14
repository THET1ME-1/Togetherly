import 'dart:convert';

import '../dict_strings.dart';

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

  /// Сколько роликов отдать за вещь: за ролик — один, за монеты — по
  /// [wearAdsNeeded], из сундука не берётся вовсе.
  int get adsNeeded => switch (src) {
        'ad' => 1,
        'coins' => wearAdsNeeded(price),
        _ => 0,
      };

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

/// Вещь за монеты можно забрать и роликами (09.11.2026): ролик на каждые 50
/// монет цены, с округлением вверх, — от одного за 50 до пяти за 250. Сервер
/// считает тем же правилом (`wear.pb.js`), сторожит `tu_wear_ads_test.dart`.
int wearAdsNeeded(int price) => price <= 0 ? 0 : (price + 49) ~/ 50;

/// Сколько роликов за вещь [key] человек уже досмотрел: `users.wear_ad_views`
/// вида `{ключ: {n, at}}`, пишет только сервер.
int wearAdProgress(Object? raw, String key) {
  if (raw is! Map) return 0;
  final entry = raw[key];
  if (entry is! Map) return 0;
  final n = entry['n'];
  return n is num ? n.toInt() : 0;
}

/// Что показывать в гардеробе: все живые вещи и снятые, если они у человека
/// есть.
List<TuWear> wardrobeItems(List<TuWear> items, {required Set<String> owned}) =>
    [for (final w in items) if (!w.retired || owned.contains(w.key)) w];

/// Чипы над сеткой гардероба (макет «Б. Примерка», 09.11.2026).
enum WearFilter { all, mine, coins, ads }

/// Вещи под выбранный чип, порядок входа сохраняется. «За ролики» — вещи за
/// ролик и вещи за монеты, которые берутся роликами; с Плюсом роликов нет,
/// и остаются только вещи «за ролик» (они ему бесплатны).
List<TuWear> wardrobeFilter(List<TuWear> items, WearFilter filter, {required Set<String> owned, required bool plus}) => [
      for (final w in items)
        if (switch (filter) {
          WearFilter.all => true,
          WearFilter.mine => owned.contains(w.key),
          WearFilter.coins => w.src == 'coins' && !owned.contains(w.key),
          WearFilter.ads => !owned.contains(w.key) && (w.src == 'ad' || (!plus && w.adsNeeded > 0)),
        })
          w,
    ];

/// Порядок гардероба: сначала то, что можно надеть или взять сейчас. Своё,
/// потом за ролик, потом за монеты, на которые хватает, дешёвое вперёд,
/// потом дорогое, и в конце запертое в сундуке. Раньше первыми стояли
/// закрытые пиджаки, а кофты за монеты уезжали вниз.
List<TuWear> wardrobeOrder(List<TuWear> items, {required Set<String> owned, required int coins}) {
  int rank(TuWear w) {
    if (owned.contains(w.key)) return 0;
    if (w.src == 'ad') return 1;
    if (w.src == 'coins') return w.price <= coins ? 2 : 3;
    return 4;
  }

  final out = [...items];
  out.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final byPrice = a.price.compareTo(b.price);
    return byPrice != 0 ? byPrice : a.sort.compareTo(b.sort);
  });
  return out;
}

/// Наряд для примерки: вещь встаёт в свой раздел, остальное надетое остаётся.
Map<String, String> wearTryOn(Map<String, String> outfit, TuWear item) => {...outfit, item.cat: item.key};

/// Разделы гардероба по порядку вкладок. Тот же порядок задаёт, какой слой
/// «спереди» лежит выше: очки ниже шарфа, шарф ниже того, что над головой.
/// Одежда (пиджаки, 06.11.2026) — первой: она на самом теле, под очками и
/// шарфом, как в мастерской (`mascot.js`, слой `dress`).
const List<String> kTuWearCats = ['outfit', 'glasses', 'face', 'neck', 'top', 'over', 'pet'];

// Английская половина идёт через trEnglish: остальные языки берут перевод по ней.
String tuWearCatName(String cat, {required bool ru}) => switch (cat) {
      'outfit' => ru ? 'Одежда' : trEnglish('Clothes'),
      'glasses' => ru ? 'Очки' : trEnglish('Glasses'),
      'face' => ru ? 'Лицо' : trEnglish('Face'),
      'neck' => ru ? 'Шарфы и пледы' : trEnglish('Scarves'),
      'top' => ru ? 'Макушка' : trEnglish('Head'),
      'over' => ru ? 'Над головой' : trEnglish('Above'),
      'pet' => ru ? 'Друг рядом' : trEnglish('Buddy'),
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
  // Сцена в цвете эмоции движется так же, как обычная: одежда та же.
  final emo = RegExp(r'^cloud_([a-z]+)_emo_').firstMatch(art);
  if (emo != null) return '${emo.group(1)}_base';
  // «Лопнул» одной формы во всех цветах: слои одежды общие.
  if (art.startsWith('cloud_burst_')) return 'burst_base';
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
