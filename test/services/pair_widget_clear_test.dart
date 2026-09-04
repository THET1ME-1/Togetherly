// Пара распалась — виджет обязан забыть её целиком.
//
// Пока «половину без данных» затирали пустотой, отвязка чистила виджет сама:
// `unbindFromGroup` обнулял модель и звал обычную синхронизацию. С 17.08.2026
// тексты половины без данных не трогаются, с 18.08 — и картинки, так что этот
// путь перестал что-либо стирать: на рабочем столе оставались имя, настроение и
// фото бывшего партнёра. Поэтому очистка теперь явная, и её список ключей
// обязан покрывать всё, что виджет пишет при живой паре.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_data.dart';
import 'package:love_app/services/pair_widget_payload.dart';

void main() {
  final full = WidgetData(
    uid: 'u',
    displayName: 'Имя',
    avatarUrl: 'pb://media/a/1',
    status: 'дома',
    moodEmoji: 'assets/mood/happy.webp',
    moodLabel: 'Радость',
    message: 'привет',
    musicTitle: 'песня',
    musicArtist: 'кто-то',
    photoUrl: 'pb://media/b/2',
  );

  test('стираются все текстовые ключи, которые пишет живая пара', () {
    final written = pairWidgetPayload(my: full, partner: full).keys.toSet();
    final cleared = pairWidgetClearPayload().keys.toSet();
    expect(written.difference(cleared), isEmpty,
        reason: 'иначе на столе остаётся имя или настроение бывшего партнёра');
  });

  test('стираются ссылки и пути к картинкам обеих половин', () {
    final cleared = pairWidgetClearPayload().keys.toSet();
    for (final key in const [
      'my_photo_url',
      'partner_photo_url',
      'my_avatar_url',
      'partner_avatar_url',
      'my_photo_path',
      'partner_photo_path',
      'my_avatar_path',
      'partner_avatar_path',
      'my_mood_emoji_path',
      'partner_mood_emoji_path',
      'ios_self_photo_path',
      'ios_partner_photo_path',
      'ios_photo_catalog_self',
      'ios_photo_catalog_partner',
    ]) {
      expect(cleared, contains(key), reason: '$key остаётся от прошлой пары');
    }
  });

  test('все значения пустые — ключ не удаляем, а обнуляем', () {
    expect(pairWidgetClearPayload().values.every((v) => v.isEmpty), isTrue);
  });

  test('файловые ключи названы отдельно — по ним чистится контейнер', () {
    expect(kPairWidgetFileKeys, contains('my_photo_path'));
    expect(kPairWidgetFileKeys, contains('partner_mood_emoji_path'));
    expect(kPairWidgetFileKeys.every(pairWidgetClearPayload().containsKey),
        isTrue);
  });

  group('связка на месте', () {
    test('отвязка от группы больше не стирает виджет', () {
      final src = File('lib/services/widget_service.dart').readAsStringSync();
      final start = src.indexOf('Future<void> unbindFromGroup');
      expect(start, isNot(-1));
      // Берём только тело метода: следующее объявление уже чужое.
      final body = src
          .substring(start)
          .split('\n')
          .takeWhile((l) => !l.startsWith('  Future<void> clearPairWidgetData'))
          .take(45)
          .join('\n');
      // Упоминание в комментарии допустимо, вызов — нет.
      expect(body.contains('clearPairWidgetData()'), isFalse,
          reason: 'экран зовёт отвязку и при переключении между связями');
    });

    test('распад пары чистит по правилу', () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(home, contains('shouldClearPairWidget'));
      expect(home, contains('clearPairWidgetData'));
    });
  });

  // Распад пары обязан вычистить и ключи самой пары (`love_<пара>_<поле>`), а
  // не только общий набор: они появились 04.09.2026, и без этого на столе у
  // человека с двумя связями остаётся лицо бывшего партнёра.
  test('очистка проходит и по ключам самой пары', () {
    final src = File('lib/services/widget_service.dart').readAsStringSync();
    final start = src.indexOf('Future<void> clearPairWidgetData()');
    expect(start, isNot(-1));
    final end = src.indexOf('\n  void _listenToMyData', start);
    final body = src.substring(start, end > 0 ? end : src.length);
    expect(body.contains('pairWidgetKey'), isTrue,
        reason: 'иначе набор распавшейся пары останется в контейнере');
  });
}
