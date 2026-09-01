import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/coloring_picture.dart';

/// Своя раскраска открывалась пустым листом (жалоба 01.09.2026: «выбираю
/// картинку, а мне просто даётся пустой холст»). Между экранами и по холсту
/// ходит один id, а `byId` знал только десять встроенных картинок — свой
/// `own_…` не находился нигде, раскраска считалась невыбранной, и контур не
/// грузился вовсе.
void main() {
  group('ColoringPicture.byId', () {
    test('встроенная картинка находится и без своих', () {
      final p = ColoringPicture.byId('cafe');
      expect(p, isNotNull);
      expect(p!.isOwn, isFalse);
    });

    test('своя картинка без списка не находится — это и был баг', () {
      expect(ColoringPicture.byId('own_1756700000000'), isNull);
    });

    test('своя картинка находится в переданном списке', () {
      final own = [
        ColoringPicture.own(id: 'own_1', title: 'Моя раскраска', ratio: 0.75),
        ColoringPicture.own(id: 'own_2', title: 'Кот', ratio: 1.0),
      ];
      final p = ColoringPicture.byId('own_2', own: own);
      expect(p, isNotNull);
      expect(p!.title, 'Кот');
      expect(p.isOwn, isTrue);
      expect(p.ownRatio, 1.0);
    });

    test('чужой own-id не подменяется первой попавшейся своей', () {
      final own = [
        ColoringPicture.own(id: 'own_1', title: 'Моя раскраска', ratio: 1.0),
      ];
      expect(ColoringPicture.byId('own_9', own: own), isNull);
    });

    test('пустой id и null — обычный холст', () {
      expect(ColoringPicture.byId(null), isNull);
      expect(ColoringPicture.byId(''), isNull);
    });
  });

  group('ColoringPicture.isOwnId', () {
    test('по id видно, где искать контур', () {
      expect(ColoringPicture.isOwnId('own_1756700000000'), isTrue);
      expect(ColoringPicture.isOwnId('cafe'), isFalse);
    });
  });
}
