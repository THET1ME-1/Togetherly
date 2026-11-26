/// Ёлка пары (26.11.2026): правила без интерфейса.
/// Решения — `docs/superpowers/specs/2026-11-26-xmas-tree-design.md`.
library;

/// Сезон ёлки по дате: ёлка «2026» — Новый 2027 год, её наряжают в декабре
/// 2026-го. В январе последней остаётся прошлогодняя ёлка.
int xtLatestSeason(DateTime d) => d.month == 12 ? d.year : d.year - 1;

/// Ёлка стоит на главной рядом с маскотом весь декабрь по часам телефона.
bool xtHomeTileVisible(DateTime d) => d.month == 12;

/// Сезон ёлки, которую сейчас наряжают, или null вне декабря.
int? xtActiveSeason(DateTime d) => xtHomeTileVisible(d) ? d.year : null;

/// «2026–27».
String xtSeasonLabel(int season) => '$season–${((season + 1) % 100).toString().padLeft(2, '0')}';

/// Стиль, звезда и гирлянда ёлки.
class PairTree {
  const PairTree({this.kind = 'fir', this.star = true, this.garland = true});

  factory PairTree.fromJson(Map<String, dynamic>? j) => j == null
      ? const PairTree()
      : PairTree(
          kind: j['kind'] == 'snowy' ? 'snowy' : 'fir',
          star: j['star'] != false,
          garland: j['garland'] != false,
        );

  final String kind;
  final bool star;
  final bool garland;

  PairTree copyWith({String? kind, bool? star, bool? garland}) =>
      PairTree(kind: kind ?? this.kind, star: star ?? this.star, garland: garland ?? this.garland);

  @override
  bool operator ==(Object other) =>
      other is PairTree && other.kind == kind && other.star == star && other.garland == garland;
  @override
  int get hashCode => Object.hash(kind, star, garland);
}

/// Игрушка на ёлке: точка подвеса в единицах холста ёлки −8…108 и автор.
class TreeToy {
  const TreeToy({required this.id, required this.toy, required this.x, required this.y, required this.author, this.created});

  static TreeToy? fromJson(Map<String, dynamic> j) {
    final id = j['id'], toy = j['toy'];
    if (id is! String || toy is! String || id.isEmpty || toy.isEmpty) return null;
    return TreeToy(
      id: id,
      toy: toy,
      x: (j['x'] as num?)?.toDouble() ?? 50,
      y: (j['y'] as num?)?.toDouble() ?? 50,
      author: j['author'] as String? ?? '',
      created: DateTime.tryParse((j['created'] as String? ?? '').replaceFirst(' ', 'T')),
    );
  }

  final String id;
  final String toy;
  final double x;
  final double y;
  final String author;
  final DateTime? created;

  TreeToy moved(double x, double y) => TreeToy(id: id, toy: toy, x: x, y: y, author: author, created: created);
}

/// Ответ `/api/tree/state`.
class TreeState {
  const TreeState({this.tree = const PairTree(), this.toys = const [], this.owned = const {}, this.seasons = const []});

  factory TreeState.fromJson(Map<String, dynamic> j) => TreeState(
        tree: PairTree.fromJson((j['tree'] as Map?)?.cast<String, dynamic>()),
        toys: [
          for (final t in (j['toys'] as List? ?? const []))
            if (t is Map) ?TreeToy.fromJson(t.cast<String, dynamic>()),
        ],
        owned: xtOwned(j['owned']),
        seasons: [for (final s in (j['seasons'] as List? ?? const [])) if (s is num) s.toInt()],
      );

  final PairTree tree;
  final List<TreeToy> toys;
  final Map<String, int> owned;
  final List<int> seasons;

  TreeState copyWith({PairTree? tree, List<TreeToy>? toys, Map<String, int>? owned, List<int>? seasons}) =>
      TreeState(tree: tree ?? this.tree, toys: toys ?? this.toys, owned: owned ?? this.owned, seasons: seasons ?? this.seasons);
}

/// Коробка из ответа сервера: служебные ключи (с «_») и пустые — мимо.
Map<String, int> xtOwned(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final e in raw.entries)
      if (e.key is String && !(e.key as String).startsWith('_') && e.value is num && (e.value as num) > 0)
        e.key as String: (e.value as num).toInt(),
  };
}

/// Сколько моих игрушек каждого вида ещё в коробке для этой ёлки: каждая ёлка
/// наряжается из всей коробки, повешенная мной убавляет счёт.
Map<String, int> xtFreeToys(Map<String, int> owned, List<TreeToy> toys, String myUid) {
  final used = <String, int>{};
  for (final t in toys) {
    if (t.author == myUid) used[t.toy] = (used[t.toy] ?? 0) + 1;
  }
  return {for (final e in owned.entries) e.key: (e.value - (used[e.key] ?? 0)).clamp(0, 1 << 30)};
}

/// Игрушка из каталога (`kind = toy`, id `toy_<ключ>`).
class XtToy {
  const XtToy({
    required this.key,
    required this.cat,
    required this.src,
    required this.price,
    required this.pickArt,
    required this.treeArt,
    required this.names,
    this.live = false,
    this.rarity = 'common',
    this.sort = 500,
  });

  static XtToy? fromCatalog(Map<String, dynamic> row) {
    final d = (row['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final key = d['key'];
    if (key is! String || key.isEmpty) return null;
    return XtToy(
      key: key,
      cat: d['cat'] as String? ?? 'figs',
      src: d['src'] == 'coins' ? 'coins' : 'chest',
      price: (row['price'] as num?)?.toInt() ?? 0,
      pickArt: d['pick'] as String? ?? '',
      treeArt: d['tree'] as String? ?? '',
      names: {
        for (final e in ((d['name'] as Map?) ?? const {}).entries)
          if (e.value is String) '${e.key}': e.value as String,
      },
      live: d['live'] == true,
      rarity: d['rarity'] as String? ?? 'common',
      sort: (row['sort'] as num?)?.toInt() ?? 500,
    );
  }

  final String key;

  /// Раздел листа: `balls`, `tu`, `figs`, `style`.
  final String cat;

  /// `coins` — продаётся за [price], `chest` — только из сундука.
  final String src;
  final int price;
  final String pickArt;
  final String treeArt;
  final Map<String, String> names;
  final bool live;
  final String rarity;
  final int sort;

  bool get isStyle => cat == 'style';
  bool get forSale => src == 'coins' && price > 0;

  String name(String lang) => names[lang] ?? names['en'] ?? names['ru'] ?? key;
}

/// Ключ стиля в коробке: `style_snowy`.
String xtStyleKey(String kind) => 'style_$kind';

/// Стиль ёлки доступен: ель есть у всех, «Под снегом» — из сундука.
bool xtStyleOwned(String kind, Map<String, int> owned) => kind == 'fir' || (owned[xtStyleKey(kind)] ?? 0) > 0;
