// «Сохранить в галерею» в полноэкранном просмотре (обращение 21): фото,
// которое партнёр поставил в парный виджет, можно забрать в галерею, не
// заводя ради него воспоминание.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/dict_strings.dart';
import 'package:love_app/models/memory_media.dart';
import 'package:love_app/services/saved_media_ledger.dart';
import 'package:love_app/widgets/common/gallery_save_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(String url) => MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: GallerySaveBar(
              imageUrl: url,
              title: 'Аня',
              takenAt: DateTime(2026, 10, 17, 18, 20),
            ),
          ),
        ),
      );

  testWidgets('у своего файла кнопка есть', (tester) async {
    await tester.pumpWidget(host('pb://media/abcdefghij12345/photo.jpg'));
    await tester.pumpAndSettle();
    expect(find.text(trKey('photoSaveButton')), findsOneWidget);
    expect(find.text(trKey('photoSaveHint')), findsOneWidget);
  });

  testWidgets('у чужой ссылки кнопки нет', (tester) async {
    await tester.pumpWidget(host('https://example.com/photo.jpg'));
    await tester.pumpAndSettle();
    expect(find.text(trKey('photoSaveButton')), findsNothing);
  });

  testWidgets('уже сохранённое помечено сразу', (tester) async {
    const url = 'pb://media/zyxwvutsrqponml/photo.jpg';
    await SavedMediaLedger.instance
        .add(const MediaFile(ref: url, kind: SaveKind.photo, index: 0).key);
    await tester.pumpWidget(host(url));
    await tester.pumpAndSettle();
    expect(find.text(trKey('photoSaved')), findsOneWidget);
    expect(find.text(trKey('photoSaveButton')), findsNothing);
  });

  test('полноэкранный просмотр подключает кнопку', () {
    final src = File('lib/widgets/widget_content_view.dart').readAsStringSync();
    expect(src, contains('GallerySaveBar('));
    expect(src, contains('bool saveable = true'));
  });

  test('строки есть на всех языках', () {
    for (final key in [
      'photoSaveButton',
      'photoSaveHint',
      'photoSaving',
      'photoSaved',
      'photoSaveFailed',
    ]) {
      final row = kStrings[key];
      expect(row, isNotNull, reason: key);
      for (final language in ['ru', 'en', 'de', 'fr', 'es', 'it', 'pt', 'zh']) {
        expect(row![language], isNotEmpty, reason: '$key/$language');
      }
    }
  });
}
