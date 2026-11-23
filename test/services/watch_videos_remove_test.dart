// «Удалите недавние видео и „Наши видео“, они не удаляются» (23.11.2026,
// iPhone, 1.44). Ролика на сервере уже не было, телефон держал его в кэше:
// список своих роликов не сверялся с сервером, а повторное удаление получало
// 404 и показывало «Ошибка». Строку «Недавних» убрать было нечем вовсе.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/watch_history_service.dart';
import 'package:love_app/services/watch_videos_service.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  test('«не найдено» при удалении значит, что ролика уже нет', () {
    expect(recordAlreadyGone(ClientException(statusCode: 404)), isTrue);
    expect(recordAlreadyGone(ClientException(statusCode: 403)), isFalse);
    expect(recordAlreadyGone(ClientException(statusCode: 0)), isFalse,
        reason: 'обрыв сети — не удаление');
    expect(recordAlreadyGone(Exception('x')), isFalse);
  });

  test('строка «Недавних» узнаёт свой ролик по ссылке на файл', () {
    const url = 'https://togetherly.day/api/files/watch_videos/9bywoe45dslp76o/'
        'image_b33a3425_0ff3.mov?token=abc';
    expect(url.contains(watchVideoFilePath('9bywoe45dslp76o')), isTrue);
    expect(url.contains(watchVideoFilePath('9bywoe45dslp76')), isFalse,
        reason: 'похожий номер — чужой ролик');
  });

  test('список своих роликов сверяется с сервером', () {
    final src = File('lib/services/pb_realtime_service.dart').readAsStringSync();
    final start = src.indexOf('watchWatchVideos(');
    final end = src.indexOf('watchWishCategories(', start);
    expect(start, greaterThan(0));
    expect(src.substring(start, end), contains('reconcile: true'));
  });

  test('«Недавние» открывают лист с удалением, а не сразу ролик', () {
    final src = File('lib/screens/together/watch_home_screen.dart').readAsStringSync();
    expect(src, contains('onTap: () => _tapRecent(_recent[i])'));
    expect(src, contains("ValueKey('recent-remove')"));
  });
}
