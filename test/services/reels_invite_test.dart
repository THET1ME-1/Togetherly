import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/reels_source.dart';
import 'package:love_app/services/reels/reels_invite.dart';

void main() {
  test('ответ сервера о живом зове', () {
    final i = ReelsInvite.parse({'ok': true, 'active': true, 'feed': 'tiktok', 'name': 'Аня'}, groupId: 'g1')!;
    expect(i.groupId, 'g1');
    expect(i.source, ReelsSource.tiktok);
    expect(i.name, 'Аня');
  });

  test('зова нет — null', () {
    expect(ReelsInvite.parse({'ok': true, 'active': false}, groupId: 'g1'), isNull);
    expect(ReelsInvite.parse(null), isNull);
  });

  test('данные пуша: свой вид и площадка из известных', () {
    final i = ReelsInvite.parse({'kind': 'reels', 'feed': 'vk', 'group': 'g2', 'by': 'u', 'name': 'Боря'})!;
    expect(i.groupId, 'g2');
    expect(i.source, ReelsSource.vkClips);
    expect(ReelsInvite.parse({'kind': 'chat', 'feed': 'vk', 'group': 'g2'}), isNull);
    expect(ReelsInvite.parse({'kind': 'reels', 'feed': 'youtube', 'group': 'g2'}), isNull);
    expect(ReelsInvite.parse({'kind': 'reels', 'feed': 'vk'}), isNull, reason: 'без пары открыть нечего');
  });

  test('ключи площадок совпадают с сервером (reels_invite.js)', () {
    expect(ReelsSource.values.map((s) => s.key).toSet(), {'shorts', 'tiktok', 'rutube', 'vk', 'dzen'});
  });
}
