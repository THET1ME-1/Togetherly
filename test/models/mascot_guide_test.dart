import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mascot_guide.dart';

/// Облачко-гид сначала включается одному человеку — владельцу, чтобы он
/// проверил его на себе, а остальные не увидели ничего, даже обновившись.
/// После проверки сервер ставит дату, и гид получают все, кто
/// зарегистрировался с этого дня. Всё задаётся полем `app_config.mascot_guide`.
void main() {
  const owner = 'ufge0IwvR4RehZ9TgKijm5xc9C32';

  group('разбор поля с сервера', () {
    test('поля нет или оно кривое — гид выключен у всех', () {
      for (final raw in [null, '', 'да', 42, true, const <String, dynamic>{}]) {
        final c = MascotGuideConfig.parse(raw);
        expect(c.uids, isEmpty);
        expect(c.newSince, isNull);
      }
    });

    test('список людей и дата для новых читаются', () {
      final c = MascotGuideConfig.parse({
        'uids': [owner, 'abc'],
        'new_since': '2026-11-05T00:00:00Z',
      });
      expect(c.uids, {owner, 'abc'});
      expect(c.newSince, DateTime.utc(2026, 11, 5));
    });

    test('мусор в списке пропускается, кривая дата — как её нет', () {
      final c = MascotGuideConfig.parse({
        'uids': [owner, 7, null, ''],
        'new_since': 'завтра',
      });
      expect(c.uids, {owner});
      expect(c.newSince, isNull);
    });
  });

  group('кому показывать', () {
    final onlyOwner = MascotGuideConfig.parse({'uids': [owner]});

    test('владелец из списка видит гида', () {
      expect(mascotGuideOn(onlyOwner, uid: owner, createdAt: DateTime.utc(2026, 6, 23)), isTrue);
    });

    test('остальные не видят, пока дата для новых не поставлена', () {
      expect(mascotGuideOn(onlyOwner, uid: 'someone', createdAt: DateTime.utc(2026, 12, 1)), isFalse);
    });

    test('с датой — видят те, кто зарегистрировался в этот день и позже', () {
      final c = MascotGuideConfig.parse({'uids': [owner], 'new_since': '2026-11-05T00:00:00Z'});
      expect(mascotGuideOn(c, uid: 'new', createdAt: DateTime.utc(2026, 11, 5, 10)), isTrue);
      expect(mascotGuideOn(c, uid: 'old', createdAt: DateTime.utc(2026, 11, 4, 23)), isFalse);
    });

    test('до входа в аккаунт (экраны приветствия) решает только дата для новых', () {
      final withDate = MascotGuideConfig.parse({'uids': [owner], 'new_since': '2026-11-05T00:00:00Z'});
      expect(mascotGuideOn(withDate, uid: null, createdAt: null), isTrue);
      expect(mascotGuideOn(onlyOwner, uid: null, createdAt: null), isFalse);
    });

    test('телефон, на котором гид уже был включён, показывает его и после выхода из аккаунта', () {
      expect(mascotGuideOn(onlyOwner, uid: null, createdAt: null, rememberedOnDevice: true), isTrue);
    });
  });
}
