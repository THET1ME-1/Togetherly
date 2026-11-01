import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/tu_wear.dart';

Map<String, dynamic> row(String key, String cat, {Map<String, dynamic>? layers, String set = 'autumn'}) => {
      'id': 'wear_$key',
      'kind': 'wear',
      'name_ru': 'Вещь $key',
      'name_en': 'Item $key',
      'sort': 500,
      'data': {
        'key': key,
        'cat': cat,
        'src': 'chest',
        'set': set,
        'rarity': 'rare',
        'icon': 'tuw_${key}_icon',
        'layers': layers ?? {
          'idle_base': ['tuw_${key}_idle_base_b', 'tuw_${key}_idle_base_f'],
          'tap_base': [null, 'tuw_${key}_tap_base_f'],
          'emo_love': ['tuw_${key}_emo_love_b', null],
        },
      },
    };

void main() {
  group('разбор вещи из каталога', () {
    test('ключ, раздел, слои по сценам', () {
      final w = TuWear.fromCatalog(row('scarf', 'neck'))!;
      expect(w.key, 'scarf');
      expect(w.cat, 'neck');
      expect(w.fromChest, isTrue);
      expect(w.nameRu, 'Вещь scarf');
      expect(w.layersFor('idle_base'), (back: 'tuw_scarf_idle_base_b', front: 'tuw_scarf_idle_base_f'));
      expect(w.layersFor('tap_base'), (back: null, front: 'tuw_scarf_tap_base_f'));
      expect(w.layersFor('nope'), (back: null, front: null));
    });

    test('запись без ключа или раздела не разбирается', () {
      expect(TuWear.fromCatalog({'kind': 'wear', 'data': {'cat': 'neck'}}), isNull);
      expect(TuWear.fromCatalog({'kind': 'wear', 'data': {'key': 'x'}}), isNull);
    });
  });

  group('наряд', () {
    test('в разделе одна вещь: новая заменяет прежнюю, повтор снимает', () {
      var o = wearToggle(const {}, 'neck', 'scarf');
      expect(o, {'neck': 'scarf'});
      o = wearToggle(o, 'neck', 'snood');
      expect(o, {'neck': 'snood'});
      o = wearToggle(o, 'glasses', 'specs');
      expect(o, {'neck': 'snood', 'glasses': 'specs'});
      o = wearToggle(o, 'neck', 'snood');
      expect(o, {'glasses': 'specs'});
    });

    test('слои сцены: только надетое и купленное, спереди по порядку разделов', () {
      final items = [TuWear.fromCatalog(row('specs', 'glasses'))!, TuWear.fromCatalog(row('scarf', 'neck'))!, TuWear.fromCatalog(row('umbrella', 'over'))!];
      final outfit = {'over': 'umbrella', 'neck': 'scarf', 'glasses': 'specs'};
      final l = wearSceneLayers(outfit, items, owned: {'scarf', 'specs', 'umbrella'}, scene: 'idle_base');
      expect(l.front, ['tuw_specs_idle_base_f', 'tuw_scarf_idle_base_f', 'tuw_umbrella_idle_base_f']);
      expect(l.back, ['tuw_specs_idle_base_b', 'tuw_scarf_idle_base_b', 'tuw_umbrella_idle_base_b']);
      // чужую вещь (не во владении) не рисуем, даже если она в наряде
      final mine = wearSceneLayers(outfit, items, owned: {'scarf'}, scene: 'idle_base');
      expect(mine.front, ['tuw_scarf_idle_base_f']);
    });

    test('сцена облачка и эмоция пака дают свои ключи слоёв', () {
      expect(wearSceneOf(art: 'cloud_idle_joy', emotion: null), 'idle_joy');
      expect(wearSceneOf(art: 'cloud_tap_base', emotion: 'love'), 'emo_love');
      expect(wearSceneOf(art: 'mascot_other', emotion: null), isNull);
    });

    test('наряд переживает сохранение строкой', () {
      final o = {'neck': 'scarf', 'top': 'acorn'};
      expect(wearOutfitDecode(wearOutfitEncode(o)), o);
      expect(wearOutfitDecode('мусор'), isEmpty);
      expect(wearOutfitDecode(null), isEmpty);
    });
  });

  group('вещь, снятая с сервера', () {
    final live = TuWear.fromCatalog(row('scarf', 'neck'))!;
    final retired = TuWear.fromCatalog({...row('specs', 'glasses'), 'enabled': false})!;

    test('выключенная запись помечается снятой', () {
      expect(live.retired, isFalse);
      expect(retired.retired, isTrue);
    });

    test('в гардеробе её видит только тот, у кого она есть', () {
      expect(wardrobeItems([live, retired], owned: const {}), [live]);
      expect(wardrobeItems([live, retired], owned: const {'specs'}), [live, retired]);
    });
  });
}
