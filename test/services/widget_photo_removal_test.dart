import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_data.dart';
import 'package:love_app/services/widget_service.dart';

/// Что уходит на сервер, когда фото УБИРАЮТ.
///
/// Жалоба от 2026-08-07: «Почему у партнёра не пропадает фото, которое я
/// удалила?». Полей у фото два, и оба выживали удаление:
///
/// * `updatePhotoForPartnerCarousel([])` слала `photoForPartnerUrl: null`, а
///   `upsertWidget` выбрасывает null-поля ради частичного апдейта — старая
///   ссылка оставалась на сервере, и виджет «Фото партнёра» показывал её
///   дальше;
/// * удаление фото парного виджета чистило только `photoUrl`, после чего
///   половина партнёра поднимала фолбэком `photoForPartnerUrl` — тот же самый
///   снимок, потому что в диалоге отправки оба тумблера включены по умолчанию.
WidgetData _data({String? photo, String? forPartner, List<String>? carousel}) =>
    WidgetData(
      uid: 'u1',
      displayName: 'Я',
      photoUrl: photo,
      photoForPartnerUrl: forPartner,
      photoForPartnerUrls: carousel ?? const [],
    );

void main() {
  group('Фото для партнёра', () {
    test('пустой список стирает и одиночное поле — пустой строкой, не null', () {
      final f = WidgetService.photoForPartnerFields(const []);
      expect(f['photoForPartnerUrl'], '');
      expect(f['photoForPartnerUrls'], isEmpty);
    });

    test('первое фото списка становится одиночным полем', () {
      final f = WidgetService.photoForPartnerFields(
        const ['pb://media/a.webp', 'pb://media/b.webp'],
      );
      expect(f['photoForPartnerUrl'], 'pb://media/a.webp');
      expect(f['photoForPartnerUrls'], ['pb://media/a.webp', 'pb://media/b.webp']);
    });
  });

  group('Удаление фото парного виджета', () {
    test('снимает и фото для партнёра, когда это тот же снимок', () {
      const url = 'pb://media/one/shot.webp';
      final f = WidgetService.clearPairPhotoFields(
        _data(photo: url, forPartner: url, carousel: const [url]),
      );
      expect(f['photoUrl'], '');
      expect(f['photoForPartnerUrl'], '');
      expect(f['photoForPartnerUrls'], isEmpty);
    });

    test('тот же снимок с пустой каруселью — тоже снимает оба поля', () {
      const url = 'pb://media/one/shot.webp';
      final f = WidgetService.clearPairPhotoFields(
        _data(photo: url, forPartner: url),
      );
      expect(f['photoForPartnerUrl'], '');
    });

    test('чужой каруселью не распоряжается', () {
      const url = 'pb://media/one/shot.webp';
      final f = WidgetService.clearPairPhotoFields(
        _data(
          photo: url,
          forPartner: url,
          carousel: const [url, 'pb://media/two/other.webp'],
        ),
      );
      expect(f['photoUrl'], '');
      expect(f.containsKey('photoForPartnerUrl'), isFalse);
      expect(f.containsKey('photoForPartnerUrls'), isFalse);
    });

    test('отдельно выбранное фото для партнёра остаётся на месте', () {
      final f = WidgetService.clearPairPhotoFields(
        _data(
          photo: 'pb://media/pair/mine.webp',
          forPartner: 'pb://media/partner/chosen.webp',
        ),
      );
      expect(f['photoUrl'], '');
      expect(f.containsKey('photoForPartnerUrl'), isFalse);
    });

    test('без фото вовсе чистит только своё поле', () {
      expect(WidgetService.clearPairPhotoFields(_data()), {'photoUrl': ''});
      expect(WidgetService.clearPairPhotoFields(null), {'photoUrl': ''});
    });
  });
}
