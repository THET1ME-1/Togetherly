import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/widget_data.dart';
import 'package:love_app/services/widget_service.dart';

/// Какое фото показывает ПАРНЫЙ виджет на каждой половине.
///
/// Жалоба от 2026-07-26: у партнёра в парном виджете месяц висело первое фото,
/// хотя он менял его несколько раз. Причина — половина партнёра читала
/// `photoForPartnerUrl` (поле отдельного виджета «Фото партнёра») и та ссылка
/// перекрывала свежий `photoUrl`.
WidgetData _data({String? photo, String? forPartner}) => WidgetData(
      uid: 'u1',
      displayName: 'Партнёр',
      photoUrl: photo,
      photoForPartnerUrl: forPartner,
    );

void main() {
  group('Половина партнёра', () {
    test('показывает свежее фото парного виджета, а не фото «для партнёра»', () {
      final d = _data(photo: 'pb://media/new/fresh.webp',
                      forPartner: 'pb://media/old/june.webp');
      expect(WidgetService.pairPhotoOfPartner(d), 'pb://media/new/fresh.webp');
    });

    test('фото «для партнёра» в парный виджет не протекает', () {
      // Жалоба 2026-08-13: «отправил фото партнёру — оно само встало и в
      // парный виджет, хотя в его настройках фото не прикреплено». Фолбэк на
      // `photoForPartnerUrl` убран, а 1983 старые записи, где своего фото
      // никогда не было, перенесены на сервере разовым UPDATE.
      final d = _data(forPartner: 'pb://media/old/june.webp');
      expect(WidgetService.pairPhotoOfPartner(d), '');
    });

    test('пустая строка означает пусто, а не «возьми у соседа»', () {
      final d = _data(photo: '', forPartner: 'pb://media/old/june.webp');
      expect(WidgetService.pairPhotoOfPartner(d), '');
    });

    test('без фото вовсе отдаёт пусто', () {
      expect(WidgetService.pairPhotoOfPartner(_data()), '');
      expect(WidgetService.pairPhotoOfPartner(null), '');
    });
  });

  group('Моя половина', () {
    test('показывает только фото парного виджета', () {
      final d = _data(photo: 'pb://media/new/mine.webp',
                      forPartner: 'pb://media/old/june.webp');
      expect(WidgetService.pairPhotoOfMine(d), 'pb://media/new/mine.webp');
    });

    test('фото «для партнёра» на мою половину не протекает', () {
      final d = _data(forPartner: 'pb://media/old/june.webp');
      expect(WidgetService.pairPhotoOfMine(d), '');
    });
  });
}
