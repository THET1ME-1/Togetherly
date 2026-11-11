/// Поиск, фильтры и сортировка каталога виджетов.
///
/// Каталог — пять сворачивающихся разделов, платные виджеты лежат там же под
/// замком. Найти нужный можно было, только раскрывая разделы подряд (просьба
/// владельца 11.11.2026: «Платные бесплатные, людям неудобно»). Здесь правила
/// без интерфейса: что найдётся по запросу, что оставит фильтр и в каком
/// порядке встанет результат.
library;

/// Какие виджеты показывать по цене.
enum CatalogPrice { all, free, plus }

/// Порядок выдачи.
enum CatalogSort { sections, name, newest }

/// Виджет каталога для поиска: всё, что о нём нужно знать без построения
/// превью.
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.section,
    required this.title,
    required this.subtitle,
    required this.added,
    this.plus = false,
    this.providers = const [],
  });

  final String id;

  /// Ключ раздела (`WidgetPanels.section*`).
  final String section;
  final String title;
  final String subtitle;

  /// Нужен Togetherly+.
  final bool plus;

  /// Короткие имена Android-провайдеров всех размеров: по ним узнаём, стоит
  /// ли виджет на рабочем столе.
  final List<String> providers;

  /// Когда виджет появился в приложении: для «Сначала новые».
  final DateTime added;
}

/// Что человек ввёл и выбрал над каталогом.
class CatalogQuery {
  const CatalogQuery({
    this.text = '',
    this.price = CatalogPrice.all,
    this.onlyOnScreen = false,
    this.sort = CatalogSort.sections,
  });

  final String text;
  final CatalogPrice price;
  final bool onlyOnScreen;
  final CatalogSort sort;

  /// Ничего не задано: каталог показывается как раньше, разделами.
  bool get isDefault =>
      text.trim().isEmpty &&
      price == CatalogPrice.all &&
      !onlyOnScreen &&
      sort == CatalogSort.sections;

  CatalogQuery copyWith({
    String? text,
    CatalogPrice? price,
    bool? onlyOnScreen,
    CatalogSort? sort,
  }) =>
      CatalogQuery(
        text: text ?? this.text,
        price: price ?? this.price,
        onlyOnScreen: onlyOnScreen ?? this.onlyOnScreen,
        sort: sort ?? this.sort,
      );

  CatalogQuery reset() => const CatalogQuery();
}

/// Строка для сравнения: нижний регистр, «ё» как «е», латиница без
/// надстрочных знаков («é» как «e»), чтобы «ещё» нашлось по «еще», а
/// «Über» встал рядом с «U».
String foldForSearch(String value) {
  final lower = value.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_folds[char] ?? char);
  }
  return out.toString();
}

const Map<String, String> _folds = {
  'ё': 'е',
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ß': 'ss',
  'ґ': 'г', 'ї': 'і',
};

/// Короткое имя провайдера: `com.togetherly.love.MoodWidgetProvider` →
/// `MoodWidgetProvider`.
String _shortProvider(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? name : name.substring(dot + 1);
}

/// Стоит ли виджет на столе хоть одним из размеров.
bool isOnScreen(CatalogEntry entry, Set<String> onScreen) {
  if (onScreen.isEmpty) return false;
  final short = {for (final name in onScreen) _shortProvider(name)};
  return entry.providers.any(short.contains);
}

/// Сколько разных виджетов каталога стоит на столе.
int countOnScreen(List<CatalogEntry> entries, Set<String> onScreen) =>
    entries.where((e) => isOnScreen(e, onScreen)).length;

/// Выдача каталога по запросу.
///
/// [sectionOrder] — порядок разделов в каталоге, [sectionTitles] — их
/// названия на языке приложения: по ним тоже ищем («таймеры» находит весь
/// раздел «Дни и таймеры»). Внутри равных порядок исходного списка.
List<CatalogEntry> applyCatalogQuery(
  List<CatalogEntry> entries,
  CatalogQuery query, {
  Set<String> onScreen = const {},
  List<String> sectionOrder = const [],
  Map<String, String> sectionTitles = const {},
}) {
  final words = foldForSearch(query.text)
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  bool matches(CatalogEntry entry) {
    if (query.price == CatalogPrice.free && entry.plus) return false;
    if (query.price == CatalogPrice.plus && !entry.plus) return false;
    if (query.onlyOnScreen && !isOnScreen(entry, onScreen)) return false;
    if (words.isEmpty) return true;
    final haystack = foldForSearch(
      '${entry.title} ${entry.subtitle} ${sectionTitles[entry.section] ?? ''}',
    );
    return words.every(haystack.contains);
  }

  final found = [
    for (var i = 0; i < entries.length; i++)
      if (matches(entries[i])) (index: i, entry: entries[i]),
  ];

  int sectionRank(CatalogEntry entry) {
    final rank = sectionOrder.indexOf(entry.section);
    return rank < 0 ? sectionOrder.length : rank;
  }

  int byOrder(({int index, CatalogEntry entry}) a, ({int index, CatalogEntry entry}) b) =>
      a.index.compareTo(b.index);

  switch (query.sort) {
    case CatalogSort.sections:
      found.sort((a, b) {
        final bySection = sectionRank(a.entry).compareTo(sectionRank(b.entry));
        return bySection != 0 ? bySection : byOrder(a, b);
      });
    case CatalogSort.name:
      found.sort((a, b) {
        final byName = foldForSearch(a.entry.title).compareTo(foldForSearch(b.entry.title));
        return byName != 0 ? byName : byOrder(a, b);
      });
    case CatalogSort.newest:
      found.sort((a, b) {
        final byDate = b.entry.added.compareTo(a.entry.added);
        return byDate != 0 ? byDate : byOrder(a, b);
      });
  }
  return [for (final item in found) item.entry];
}
