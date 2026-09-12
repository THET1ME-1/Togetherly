import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_panels.dart';

/// Раскрытые разделы и карточки каталога виджетов.
///
/// Жалоба 12.09.2026: «на экране виджетов всегда закрыты старые виджеты и
/// открыты новые, изменения между экранами и входами не сохраняются». Состояние
/// жило только в памяти экрана, поэтому любой уход с него возвращал умолчания.
void main() {
  test('первый заход открывает новый каталог и фото дня', () {
    expect(WidgetPanels.restore(null), WidgetPanels.byDefault);
  });

  test('пустой список — это решение человека, а не отсутствие настройки', () {
    expect(WidgetPanels.restore(const []), isEmpty);
  });

  test('незнакомые ключи выбрасываются', () {
    final restored =
        WidgetPanels.restore(const [WidgetPanels.legacySection, 'ерунда']);
    expect(restored, {WidgetPanels.legacySection});
  });

  test('порядок записи постоянный, независимо от порядка нажатий', () {
    final a = WidgetPanels.store({WidgetPanels.photoGrid, WidgetPanels.pairWidget});
    final b = WidgetPanels.store({WidgetPanels.pairWidget, WidgetPanels.photoGrid});
    expect(a, b);
  });

  test('круг «сохранили — прочитали» ничего не теряет', () {
    final chosen = {
      WidgetPanels.legacySection,
      WidgetPanels.daysCounter,
      WidgetPanels.partnerPhoto,
    };
    expect(WidgetPanels.restore(WidgetPanels.store(chosen)), chosen);
  });

  test('каждый известный ключ переживает круг', () {
    for (final key in WidgetPanels.known) {
      expect(WidgetPanels.restore(WidgetPanels.store({key})), {key},
          reason: '$key обязан сохраняться');
    }
  });

  group('экран виджетов', () {
    final src = File('lib/screens/widget_screen.dart').readAsStringSync();

    test('состояние раскрытия не живёт отдельными полями в памяти', () {
      for (final dead in [
        'bool _legacySectionExpanded =',
        'bool _newSectionExpanded =',
        'bool _pairWidgetExpanded =',
        'bool _daysCounterExpanded =',
        'bool _photoDayExpanded =',
        'bool _photoGridExpanded =',
      ]) {
        expect(src.contains(dead), isFalse,
            reason: '«$dead» вернёт сброс к умолчаниям при каждом заходе');
      }
    });

    test('набор читается из prefs при открытии и пишется при нажатии', () {
      expect(src.contains('_loadPanels();'), isTrue);
      expect(src.contains('WidgetPanels.prefsKey'), isTrue);
      expect(src.contains('_togglePanel(WidgetPanels.legacySection)'), isTrue);
      expect(src.contains('_togglePanel(WidgetPanels.newSection)'), isTrue);
    });
  });

  group('выбранный размер виджета', () {
    test('круг «сохранили — прочитали»', () {
      const choice = {'pair': 1, 'miss_you': 2, 'mood_tiles': 0};
      expect(WidgetSizeChoice.restore(WidgetSizeChoice.store(choice)), choice);
    });

    test('ничего не выбрано — пустая карта, а не падение', () {
      expect(WidgetSizeChoice.restore(null), isEmpty);
      expect(WidgetSizeChoice.restore(const ['мусор', ':2', 'x:-1']), isEmpty);
    });

    test('двоеточие в имени типа не ломает разбор', () {
      final restored = WidgetSizeChoice.restore(const ['mood:pack:3']);
      expect(restored, {'mood:pack': 3});
    });
  });
}
