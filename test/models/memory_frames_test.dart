// Кадры записи при правке: прежние (уже на сервере) и только что выбранные.
//
// До 10.11.2026 новый кадр, поставленный обложкой, стирал из записи все
// прежние: форма обнуляла их список, и при сохранении в записи оставались
// только новые снимки. Человек добавлял одно фото к десяти и терял десять.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory_frames.dart';

void main() {
  group('место кадра в общем ряду', () {
    test('обычный порядок: сперва прежние, затем новые', () {
      FrameSlot at(int position) =>
          frameSlot(position, keptCount: 2, freshCount: 2, freshCover: false);
      expect(at(0), const FrameSlot.kept(0));
      expect(at(1), const FrameSlot.kept(1));
      expect(at(2), const FrameSlot.fresh(0));
      expect(at(3), const FrameSlot.fresh(1));
    });

    test('новый кадр обложкой: он первый, прежние идут следом', () {
      FrameSlot at(int position) =>
          frameSlot(position, keptCount: 2, freshCount: 2, freshCover: true);
      expect(at(0), const FrameSlot.fresh(0));
      expect(at(1), const FrameSlot.kept(0));
      expect(at(2), const FrameSlot.kept(1));
      expect(at(3), const FrameSlot.fresh(1));
    });

    test('новых кадров нет — отметка обложки ничего не сдвигает', () {
      expect(
          frameSlot(0, keptCount: 2, freshCount: 0, freshCover: true),
          const FrameSlot.kept(0));
    });

    test('прежних кадров нет — ряд состоит из новых', () {
      expect(
          frameSlot(1, keptCount: 0, freshCount: 3, freshCover: true),
          const FrameSlot.fresh(1));
    });
  });

  group('что ляжет в запись после сохранения', () {
    test('новые кадры встают в конец, прежние остаются', () {
      expect(
        framesAfterEdit(
            kept: ['a', 'b'], uploaded: ['x', 'y'], freshCover: false),
        ['a', 'b', 'x', 'y'],
      );
    });

    test('новый кадр обложкой прежних НЕ стирает', () {
      expect(
        framesAfterEdit(
            kept: ['a', 'b'], uploaded: ['x', 'y'], freshCover: true),
        ['x', 'a', 'b', 'y'],
      );
    });

    test('обложка не загрузилась — прежние на месте, обложкой первый прежний',
        () {
      expect(
        framesAfterEdit(
            kept: ['a', 'b'], uploaded: [null, 'y'], freshCover: true),
        ['a', 'b', 'y'],
      );
    });

    test('незагрузившийся кадр пропускается', () {
      expect(
        framesAfterEdit(
            kept: ['a'], uploaded: ['x', null, 'z'], freshCover: false),
        ['a', 'x', 'z'],
      );
    });
  });

  group('форма и лента ходят через эти правила', () {
    test('форма не обнуляет прежние кадры и считает место общим правилом', () {
      final form =
          File('lib/screens/memory_photo_form_screen.dart').readAsStringSync();
      // Само поле объявлено пустым списком; искать надо присваивание в коде.
      expect(RegExp(r'^\s*_kept = \[\]', multiLine: true).hasMatch(form),
          isFalse,
          reason: 'обнуление списка стирало прежние фото записи');
      expect(form, contains('frameSlot('));
      expect(form, contains('freshCover:'));
    });

    test('сохранение правки собирает список общим правилом', () {
      final lane =
          File('lib/screens/memory_lane_screen.dart').readAsStringSync();
      expect(lane, contains('framesAfterEdit('));
    });
  });
}
