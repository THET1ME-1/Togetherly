// Справка «Как сделать»: тексты на всех языках, шаги зовут кнопки настоящими
// подписями, а в сборках для Google Play и iPhone нет ни слова о внешней
// оплате — за ссылку мимо биллинга магазин снимает приложение.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/l10n/dict/help.dart';
import 'package:love_app/models/help_items.dart';
import 'package:love_app/services/locale_service.dart';

const _langs = ['ru', 'en', 'pt', 'it', 'es', 'fr', 'de'];

Iterable<String> _keysOf(HelpItem i) => [
      'help.${i.id}.q',
      'help.${i.id}.path',
      for (final n in [1, 2, 3]) 'help.${i.id}.s$n',
    ];

void main() {
  final store = helpItems(plusInStore: true);
  final site = helpItems(plusInStore: false);

  test('у каждого ответа вопрос, путь и три шага на всех семи языках', () {
    for (final item in {...store, ...site}) {
      for (final key in _keysOf(item)) {
        for (final lang in _langs) {
          expect(helpStrings[key]?[lang], isNotNull, reason: '$key/$lang');
        }
      }
    }
    for (final t in HelpTopic.values) {
      for (final lang in _langs) {
        expect(helpStrings['help.topic.${t.name}']?[lang], isNotNull);
      }
    }
  });

  test('каждая метка {ключ} — настоящая подпись на всех языках', () {
    final label = RegExp(r'\{(\w+)\}');
    for (final entry in helpStrings.entries) {
      for (final lang in _langs) {
        for (final m in label.allMatches(entry.value[lang] ?? '')) {
          final key = m.group(1)!;
          expect(kStrings[key]?[lang], isNotNull,
              reason: '${entry.key}/$lang ссылается на $key');
        }
      }
    }
  });

  test('в магазинных сборках ни слова о lava.top', () {
    for (final item in store) {
      for (final key in _keysOf(item)) {
        for (final lang in _langs) {
          expect(helpStrings[key]![lang]!.toLowerCase(), isNot(contains('lava')),
              reason: '$key/$lang');
        }
      }
      expect(item.action, isNot(HelpAction.plusSite));
    }
  });

  test('в сборках с сайта Плюс ведёт на lava.top', () {
    final plus = site.singleWhere((i) => i.topic == HelpTopic.plus);
    expect(plus.action, HelpAction.plusSite);
    expect(store.singleWhere((i) => i.topic == HelpTopic.plus).action,
        HelpAction.plusSheet);
  });

  test('поиск прощает окончания, регистр и «ё»', () async {
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    List<String> find(String q) =>
        store.where((i) => helpMatches(i, q)).map((i) => i.id).toList();
    expect(find('Пароля'), contains('password'));
    expect(find('удалить пару'), ['unpair']);
    expect(find('виджета'), containsAll(['widgetPhoto', 'widgetStale']));
    expect(find('счетчик'), contains('startDate'));
    expect(find('абракадабра'), isEmpty);
    expect(find('  '), hasLength(store.length));
  });

  test('наверху два самых частых вопроса', () {
    expect(helpPopular(store).map((i) => i.id), ['plusStore', 'unpair']);
    expect(helpPopular(site).map((i) => i.id), ['plusSite', 'unpair']);
  });
}
