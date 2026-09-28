import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/partner_task_photos.dart';

Memory _m(
  String id, {
  String author = 'p',
  String? task = 'photo_sky',
  MemoryType type = MemoryType.photo,
  List<String>? urls,
  String? url,
  bool secret = false,
  int day = 1,
}) =>
    Memory(
      id: id,
      groupId: 'g',
      authorUid: author,
      authorName: author,
      type: type,
      createdAt: DateTime(2026, 9, day),
      imageUrl: url ?? 'pb://media/$id/a.jpg',
      imageUrls: urls,
      isSecret: secret,
      dailyTaskId: task,
    );

void main() {
  test('берём только фото партнёра из заданий дня, новые первыми', () {
    final photos = partnerTaskPhotos(
      [
        _m('old', day: 1),
        _m('new', day: 5),
        _m('mine', author: 'me', day: 6),
        _m('plain', task: null, day: 7),
        _m('video', type: MemoryType.video, day: 8),
        _m('secret', secret: true, day: 9),
      ],
      partnerUid: 'p',
    );
    expect(photos, ['pb://media/new/a.jpg', 'pb://media/old/a.jpg']);
  });

  test('все кадры записи идут в карусель, предел соблюдается', () {
    final photos = partnerTaskPhotos(
      [_m('many', urls: [for (var i = 0; i < 15; i++) 'u$i'])],
      partnerUid: 'p',
    );
    expect(photos.length, kPartnerTaskPhotosLimit);
    expect(photos.first, 'u0');
  });

  test('запечатанная капсула в виджет не попадает', () {
    final sealed = _m('capsule')
      ..sealed = true
      ..openAt = DateTime(2027, 1, 1);
    expect(partnerTaskPhotos([sealed], partnerUid: 'p', now: DateTime(2026, 9, 28)), isEmpty);
  });

  test('отправленное партнёром идёт первым, повторы схлопываются', () {
    expect(mergePartnerCarousel(['a', 'b'], ['b', 'c']), ['a', 'b', 'c']);
    expect(
      mergePartnerCarousel([for (var i = 0; i < 30; i++) 's$i'], ['t']).length,
      kPartnerCarouselLimit,
    );
  });

  test('подмешивание стоит на обоих путях: Android и iPhone', () {
    final src = File('lib/services/home_widget_service.dart').readAsStringSync();
    expect(src, contains('_withPartnerTaskPhotos('));
    // Android: карусель виджета «Фото партнёра» собирается в _getPartnerWidgetData.
    final android = src.substring(src.indexOf('Future<Map<String, String>?> _getPartnerWidgetData('));
    expect(android.substring(0, 4000), contains('_withPartnerTaskPhotos('));
    // iPhone: общий вход фото-виджетов.
    final ios = src.substring(src.indexOf('Future<void> _syncIosPhotoWidgets('));
    expect(ios.substring(0, 2500), contains('_withPartnerTaskPhotos('));
  });
}
