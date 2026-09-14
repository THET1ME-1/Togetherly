import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/documents_file.dart';

void main() {
  const before =
      '/var/mobile/Containers/Data/Application/AAAA-1111/Documents';
  const after =
      '/var/mobile/Containers/Data/Application/BBBB-2222/Documents';

  test('после обновления iPhone файл находится в новой папке', () {
    // Так записывала прежняя сборка: полный путь со старым UUID.
    final stored = '$before/chat_bg_g1_1757500000000.jpg';
    expect(
      documentsFilePath(stored, after),
      '$after/chat_bg_g1_1757500000000.jpg',
    );
  });

  test('в настройки уходит имя файла, а не путь', () {
    expect(documentsFileKey('$before/chat_bg_g1_1.webp'), 'chat_bg_g1_1.webp');
    expect(documentsFilePath('chat_bg_g1_1.webp', after),
        '$after/chat_bg_g1_1.webp');
  });

  test('пустая настройка — фона нет', () {
    expect(documentsFilePath(null, after), isNull);
    expect(documentsFilePath('', after), isNull);
    expect(documentsFilePath('$before/', after), isNull);
  });

  test('фон чата хранит имя файла и ищет его в текущей папке', () {
    final src = File('lib/services/chat_service.dart').readAsStringSync();
    final set = src.split('Future<void> setBackgroundPath(')[1].split('\n  }\n')[0];
    final get = src.split('Future<String?> backgroundPath(')[1].split('\n  }\n')[0];
    expect(set, contains('documentsFileKey('),
        reason: 'полный путь сломается на первом же обновлении iPhone');
    expect(get, contains('documentsFilePath('));
  });
}
