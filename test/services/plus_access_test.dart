import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/canvas_background.dart';
import 'package:love_app/models/profile_icon.dart';
import 'package:love_app/services/plus_access.dart';

/// Что именно открывает Togetherly+. Правила собраны в одном месте, чтобы
/// витрина, экраны и проверки доступа не разъезжались между собой.
void main() {
  final paid = ProfileIcon.purchasable.first.id;
  final granted = ProfileIcon.all.firstWhere((i) => i.grantOnly).id;

  group('значки профиля', () {
    test('без Plus доступны только купленные и выданные', () {
      expect(
        PlusAccess.ownsIcon(id: paid, plus: false, owned: {}, granted: {}),
        isFalse,
      );
      expect(
        PlusAccess.ownsIcon(id: paid, plus: false, owned: {paid}, granted: {}),
        isTrue,
      );
      expect(
        PlusAccess.ownsIcon(
            id: granted, plus: false, owned: {}, granted: {granted}),
        isTrue,
      );
    });

    test('Plus открывает платные значки без покупки', () {
      expect(
        PlusAccess.ownsIcon(id: paid, plus: true, owned: {}, granted: {}),
        isTrue,
      );
    });

    test('наградной значок за деньги не достаётся даже с Plus', () {
      expect(
        PlusAccess.ownsIcon(id: granted, plus: true, owned: {}, granted: {}),
        isFalse,
        reason: 'иначе Sponsor и Helper перестанут что-либо значить',
      );
    });

    test('выданный вручную наградной остаётся доступным', () {
      expect(
        PlusAccess.ownsIcon(
            id: granted, plus: true, owned: {}, granted: {granted}),
        isTrue,
      );
    });

    test('неизвестный id не открывается ничем', () {
      expect(
        PlusAccess.ownsIcon(id: 'нет-такого', plus: true, owned: {}, granted: {}),
        isFalse,
      );
    });
  });

  group('фоны холста', () {
    test('бесплатные доступны без всего', () {
      expect(
        PlusAccess.ownsBackground(
            id: CanvasBackground.plain, plus: false, owned: {}),
        isTrue,
      );
      expect(
        PlusAccess.ownsBackground(
            id: CanvasBackground.grid, plus: false, owned: {}),
        isTrue,
      );
    });

    test('платный без Plus и без покупки закрыт', () {
      expect(
        PlusAccess.ownsBackground(
            id: CanvasBackground.stars, plus: false, owned: {}),
        isFalse,
      );
    });

    test('Plus открывает все платные', () {
      for (final bg in CanvasBackground.values) {
        expect(
          PlusAccess.ownsBackground(id: bg, plus: true, owned: {}),
          isTrue,
          reason: 'фон ${bg.name}',
        );
      }
    });

    test('купленный за монеты остаётся доступным без Plus', () {
      expect(
        PlusAccess.ownsBackground(
            id: CanvasBackground.film,
            plus: false,
            owned: {CanvasBackground.film.name}),
        isTrue,
      );
    });

    test('в каталоге есть и бесплатные, и платные', () {
      final prices =
          CanvasBackground.values.map((b) => kCanvasBackgrounds[b]!.price);
      expect(prices.any((p) => p == 0), isTrue);
      expect(prices.any((p) => p > 0), isTrue);
    });
  });

  group('потолок файла воспоминания', () {
    test('без Plus — 100 МБ', () {
      expect(PlusAccess.memoryFileLimit(plus: false), 100 * 1024 * 1024);
    });

    test('с Plus — 200 МБ', () {
      expect(PlusAccess.memoryFileLimit(plus: true), 200 * 1024 * 1024);
    });

    test('потолок не выше того, что примет сервер', () {
      expect(PlusAccess.memoryFileLimit(plus: true),
          lessThanOrEqualTo(PlusAccess.serverFileLimit));
    });

    test('файл ровно по границе проходит, на байт больше — нет', () {
      final limit = PlusAccess.memoryFileLimit(plus: false);
      expect(PlusAccess.fitsMemoryLimit(bytes: limit, plus: false), isTrue);
      expect(PlusAccess.fitsMemoryLimit(bytes: limit + 1, plus: false), isFalse);
      expect(PlusAccess.fitsMemoryLimit(bytes: limit + 1, plus: true), isTrue);
    });
  });
}
