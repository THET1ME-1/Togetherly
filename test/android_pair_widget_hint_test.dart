// Подсказка на пустой половине парного виджета (PairWidgetHint.kt).
//
// Жалобы «виджет пустой» — самая большая группа в приёмной: половина без
// фото была просто закрашена цветом, и не понять, фото не дошло, его никто
// не ставил или партнёр ещё ничего не добавил. Kotlin здесь не запускается,
// поэтому тест сверяет исходники: решение, разметку, ресурсы и подписи,
// которые пишет приложение.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/services/pair_widget_payload.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  const res = 'android/app/src/main/res';
  final hint = _read('android/app/src/main/kotlin/com/togetherly/love/PairWidgetHint.kt');
  final provider =
      _read('android/app/src/main/kotlin/com/togetherly/love/LoveWidgetProvider.kt');
  final layout = _read('$res/layout/love_widget.xml');
  final strings = _read('$res/values/strings.xml');
  final service = _read('lib/services/widget_service.dart');

  test('не дошедшее фото важнее настроения, пустота — только без всего', () {
    final decide = hint.substring(hint.indexOf('fun decide('));
    final failed = decide.indexOf('-> PHOTO_FAILED');
    final none = decide.indexOf('-> NONE');
    expect(failed, greaterThan(0));
    expect(none, greaterThan(failed),
        reason: 'сперва «фото не дошло», потом «есть что показать»');
    expect(decide, contains('!photoPath.isNullOrEmpty() && !photoShown'));
    expect(decide, contains('photoShown || hasMood || hasText -> NONE'));
    expect(decide, contains('mine -> OWN_EMPTY'));
  });

  test('обе половины вызывают подсказку и прячут центр', () {
    expect('applyHint('.allMatches(provider).length, greaterThanOrEqualTo(3));
    for (final side in ['my', 'partner']) {
      for (final id in ['hint', 'hint_icon', 'hint_title', 'hint_sub']) {
        expect(layout, contains('@+id/${side}_$id"'), reason: '${side}_$id');
        expect(provider, contains('R.id.${side}_$id'), reason: '${side}_$id');
      }
      expect(provider, contains('R.id.${side}_center, R.id.${side}_hint'));
    }
    expect(provider, contains('setViewVisibility(centerId, View.GONE)'));
  });

  test('значки и подложка лежат в ресурсах, запасные подписи есть', () {
    for (final d in [
      'ic_widget_hint_refresh',
      'ic_widget_hint_add_photo',
      'ic_widget_hint_heart',
      'widget_hint_cookie',
    ]) {
      expect(File('$res/drawable/$d.xml').existsSync(), isTrue, reason: d);
      expect('$hint\n$layout', contains(d), reason: d);
    }
    for (final kind in ['fail', 'own', 'partner']) {
      for (final part in ['title', 'sub']) {
        expect(strings, contains('name="love_hint_${kind}_$part"'));
        expect(kPairWidgetHintLabels.keys, contains('love_hint_${kind}_$part'));
      }
      expect(hint, contains('"$kind",'));
    }
  });

  test('приложение пишет подписи на всех семи языках', () {
    for (final key in kPairWidgetHintLabels.values) {
      for (final lang in ['ru', 'en', 'pt', 'it', 'es', 'fr', 'de']) {
        expect(kStrings[key]?[lang], isNotNull, reason: '$key/$lang');
      }
    }
    expect(service, contains('kPairWidgetHintLabels.entries'));
    expect(hint, contains(r'"love_hint_${key}_title"'));
    expect(hint, contains(r'"love_hint_${key}_sub"'));
  });
}
