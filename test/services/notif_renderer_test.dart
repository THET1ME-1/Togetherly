import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/notif_renderer.dart';

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

  test('кнопки экрана несут ссылку, действия телефона — нет', () {
    for (final c in NotifRenderer.iosCategories('ru')) {
      for (final a in c['actions']! as List) {
        final m = a as Map;
        if (['reply', 'hug', 'read', 'throw'].contains(m['id'])) {
          expect(m.containsKey('link'), isFalse, reason: '${c['kind']}/${m['id']}');
        } else {
          expect('${m['link']}', startsWith('loveapp://open/'), reason: '${c['kind']}/${m['id']}');
        }
      }
    }
  });
}
