import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/push_cover.dart';
import 'package:love_app/services/notif_renderer.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  test('категории iPhone: у каждого вида кнопки на языке приложения', () {
    final ru = NotifRenderer.iosCategories('ru');
    expect(ru.map((c) => c['kind']), NotifRenderer.coverKinds);
    final chat = ru.firstWhere((c) => c['kind'] == 'chat');
    final ids = [for (final a in chat['actions']! as List) (a as Map)['id']];
    expect(ids, ['reply', 'hug', 'read']);
    final miss = ru.firstWhere((c) => c['kind'] == 'miss');
    expect(((miss['actions']! as List).first as Map)['label'], 'Обнять в ответ');
    final en = NotifRenderer.iosCategories('en');
    final missEn = en.firstWhere((c) => c['kind'] == 'miss');
    expect(((missEn['actions']! as List).first as Map)['label'], 'Hug back');
  });

  test('каждый вид обложки с картинкой каталога знает, какую запись догрузить', () {
    // Каталог на телефоне бывает неполным: без записи вместо Ту или котика
    // встала бы иконка приложения.
    expect(NotifRenderer.artIdsFor('miss', const {}), ['art_act_miss']);
    expect(NotifRenderer.artIdsFor('mood_lock', const {}), ['moti']);
    expect(NotifRenderer.artIdsFor('reels', const {}), ['art_act_phone']);
    expect(NotifRenderer.artIdsFor('mascot_miss', const {}), ['art_cloud_idle_sad', 'art_act_sad']);
    // Слои наряда тоже догружаются: без них Ту был бы раздет.
    expect(
        NotifRenderer.artIdsFor('mascot_miss', const {
          'wear_over': ['art_tuw_acorn_idle_sad_f'],
        }),
        contains('art_tuw_acorn_idle_sad_f'));
    expect(NotifRenderer.artIdsFor('invite', const {}), ['art_guide_wait']);
    expect(NotifRenderer.artIdsFor('gift', const {'gift_key': 'bouquet'}), ['gift_bouquet']);
    expect(NotifRenderer.artIdsFor('gift', const {'gift_key': 'frame_hearts'}), ['frame_hearts']);
    expect(NotifRenderer.artIdsFor('celebration', const {}), isEmpty);
    expect(NotifRenderer.artIdsFor('days', const {}), isEmpty);
  });

  test('время в прошлом — ошибка, как у плагина, а не показ сразу', () async {
    tzdata.initializeTimeZones();
    final past = tz.TZDateTime.now(tz.UTC).subtract(const Duration(minutes: 1));
    await expectLater(
      NotifRenderer.schedule(
        plugin: FlutterLocalNotificationsPlugin(),
        id: 1,
        when: past,
        title: 'т',
        body: 'т',
        details: const NotificationDetails(),
        channel: 'c',
        kind: 'mascot_miss',
      ),
      throwsArgumentError,
    );
  });

  test('кнопки экрана несут ссылку, действия телефона — нет', () {
    for (final c in NotifRenderer.iosCategories('ru')) {
      for (final a in c['actions']! as List) {
        final m = a as Map;
        if (kCoverNativeActions.contains(m['id'])) {
          expect(m.containsKey('link'), isFalse, reason: '${c['kind']}/${m['id']}');
        } else {
          expect('${m['link']}', startsWith('loveapp://open/'), reason: '${c['kind']}/${m['id']}');
        }
      }
    }
  });
}
