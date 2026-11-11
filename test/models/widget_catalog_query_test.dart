// Поиск, фильтры и сортировка в каталоге виджетов (11.11.2026).
//
// Владелец: «Платные бесплатные, людям неудобно». Каталог — пять
// сворачивающихся разделов, платные лежат вперемешку с бесплатными под
// замком, найти нужный виджет можно только листая и раскрывая разделы.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_catalog_query.dart';

CatalogEntry entry(
  String id, {
  String section = 'pair',
  String title = '',
  String subtitle = '',
  bool plus = false,
  List<String> providers = const [],
  String added = '2026-07-19',
}) =>
    CatalogEntry(
      id: id,
      section: section,
      title: title.isEmpty ? id : title,
      subtitle: subtitle,
      plus: plus,
      providers: providers,
      added: DateTime.parse(added),
    );

const sections = ['pair', 'time', 'photos', 'mood', 'notes'];
const sectionTitles = {
  'pair': 'Вы вдвоём',
  'time': 'Дни и таймеры',
  'photos': 'Фотографии',
  'mood': 'Настроение',
  'notes': 'Заметки',
};

List<String> ids(List<CatalogEntry> list) => [for (final e in list) e.id];

List<CatalogEntry> run(
  List<CatalogEntry> all,
  CatalogQuery query, {
  Set<String> onScreen = const {},
}) =>
    applyCatalogQuery(
      all,
      query,
      onScreen: onScreen,
      sectionOrder: sections,
      sectionTitles: sectionTitles,
    );

void main() {
  final catalog = [
    entry('pair', title: 'Парный виджет', subtitle: 'Статус и настроение обоих',
        providers: ['LoveWidgetProvider']),
    entry('miss', title: 'Скучаю', subtitle: 'Сердце партнёру одним касанием',
        plus: true, providers: ['MissWidget2x2Provider', 'MissWidget4x2Provider'], added: '2026-07-25'),
    entry('doing', title: 'Чем заняты', subtitle: 'Две комнатки', added: '2026-11-11',
        providers: ['DoingWidgetProvider']),
    entry('days', section: 'time', title: 'Дни вместе', subtitle: 'Счётчик дней',
        providers: ['DaysCounterWidgetProvider']),
    entry('countdown', section: 'time', title: 'Обратный отсчёт', subtitle: 'До встречи',
        plus: true, added: '2026-07-25', providers: ['CountdownWidget2x2Provider']),
    entry('self_photo', section: 'photos', title: 'Твоё фото', subtitle: 'Снимок дня',
        providers: ['SelfPhotoWidgetProvider']),
    entry('mood', section: 'mood', title: 'Настроение', subtitle: 'Эмоции за день',
        providers: ['MoodWidgetProvider']),
    entry('note', section: 'notes', title: 'Заметка', subtitle: 'Листок на холодильнике',
        plus: true, added: '2026-07-26', providers: ['NoteWidget4x2Provider']),
  ];

  test('без запроса и фильтров каталог как был: по разделам, в своём порядке', () {
    const query = CatalogQuery();
    expect(query.isDefault, isTrue);
    expect(ids(run(catalog, query)), ids(catalog));
  });

  group('поиск', () {
    test('ищет по названию без учёта регистра', () {
      expect(ids(run(catalog, const CatalogQuery(text: 'СКУЧАЮ'))), ['miss']);
    });

    test('ищет по описанию', () {
      expect(ids(run(catalog, const CatalogQuery(text: 'холодильник'))), ['note']);
    });

    test('ищет по названию раздела', () {
      expect(ids(run(catalog, const CatalogQuery(text: 'таймеры'))), ['days', 'countdown']);
    });

    test('«е» находит «ё» и наоборот', () {
      expect(ids(run(catalog, const CatalogQuery(text: 'твое'))), ['self_photo']);
      expect(ids(run(catalog, const CatalogQuery(text: 'партнёр'))), ['miss']);
      expect(ids(run(catalog, const CatalogQuery(text: 'партнер'))), ['miss']);
    });

    test('несколько слов — каждое должно найтись, порядок не важен', () {
      expect(ids(run(catalog, const CatalogQuery(text: 'дней счётчик'))), ['days']);
      expect(ids(run(catalog, const CatalogQuery(text: 'дней заметка'))), isEmpty);
    });

    test('пробелы по краям и пустая строка ничего не фильтруют', () {
      expect(const CatalogQuery(text: '   ').isDefault, isTrue);
      expect(run(catalog, const CatalogQuery(text: '  ')), hasLength(catalog.length));
    });
  });

  group('платные и бесплатные', () {
    test('«Бесплатные» прячет виджеты Togetherly+', () {
      expect(ids(run(catalog, const CatalogQuery(price: CatalogPrice.free))),
          ['pair', 'doing', 'days', 'self_photo', 'mood']);
    });

    test('«Togetherly+» оставляет только платные', () {
      expect(ids(run(catalog, const CatalogQuery(price: CatalogPrice.plus))),
          ['miss', 'countdown', 'note']);
    });

    test('фильтр складывается с поиском', () {
      expect(
        ids(run(catalog, const CatalogQuery(text: 'настроение', price: CatalogPrice.free))),
        ['pair', 'mood'],
      );
    });
  });

  group('на рабочем столе', () {
    test('оставляет виджеты, хоть один размер которых стоит на столе', () {
      final found = run(
        catalog,
        const CatalogQuery(onlyOnScreen: true),
        onScreen: {'MissWidget4x2Provider', 'MoodWidgetProvider'},
      );
      expect(ids(found), ['miss', 'mood']);
    });

    test('полное имя класса тоже узнаётся', () {
      final found = run(
        catalog,
        const CatalogQuery(onlyOnScreen: true),
        onScreen: {'com.togetherly.love.DoingWidgetProvider'},
      );
      expect(ids(found), ['doing']);
    });

    test('числом на столе считается каждый виджет один раз', () {
      expect(
        countOnScreen(catalog, {'MissWidget2x2Provider', 'MissWidget4x2Provider', 'LoveWidgetProvider'}),
        2,
      );
    });
  });

  group('сортировка', () {
    test('по названию — по алфавиту языка, «Ё» рядом с «Е»', () {
      final sorted = run(catalog, const CatalogQuery(sort: CatalogSort.name));
      expect(ids(sorted), ['days', 'note', 'mood', 'countdown', 'pair', 'miss', 'self_photo', 'doing']);
    });

    test('сначала новые — по дате появления, при равной дате порядок каталога', () {
      final sorted = run(catalog, const CatalogQuery(sort: CatalogSort.newest));
      expect(ids(sorted), ['doing', 'note', 'miss', 'countdown', 'pair', 'days', 'self_photo', 'mood']);
    });

    test('по разделам — порядок разделов, внутри порядок каталога', () {
      final shuffled = [catalog[6], catalog[3], catalog[0], catalog[7], catalog[1]];
      expect(ids(run(shuffled, const CatalogQuery(sort: CatalogSort.sections))),
          ['pair', 'miss', 'days', 'mood', 'note']);
    });

    test('другая сортировка — уже не «как было»', () {
      expect(const CatalogQuery(sort: CatalogSort.name).isDefault, isFalse);
    });
  });

  test('сброс возвращает всё к виду по умолчанию', () {
    const busy = CatalogQuery(
      text: 'фото',
      price: CatalogPrice.plus,
      onlyOnScreen: true,
      sort: CatalogSort.newest,
    );
    expect(busy.reset().isDefault, isTrue);
  });

  test('copyWith меняет одно поле и не трогает остальные', () {
    const query = CatalogQuery(text: 'фото', price: CatalogPrice.free);
    final next = query.copyWith(sort: CatalogSort.name);
    expect(next.text, 'фото');
    expect(next.price, CatalogPrice.free);
    expect(next.sort, CatalogSort.name);
  });
}
