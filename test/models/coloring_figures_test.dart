import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/coloring_figures.dart';
import 'package:love_app/models/coloring_picture.dart';
import 'package:love_app/models/draw_stroke.dart';
import 'package:love_app/utils/coloring_halves.dart';

/// Раскраска с выбором, кто нарисован на каждой половине: девушка или парень.
///
/// Владелец: «кастомизацию, кого выбирать для рисунка, парня или девушку, с
/// каждой стороны по отдельности». Половины картинки лежат вариантами, лист
/// собирается из двух. Ошибка здесь видна сразу: у одного телефона слева
/// девушка, у другого парень, или заливки ложатся мимо новых линий.
void main() {
  DrawStroke line(double x, {bool eraser = false}) => DrawStroke(
        id: 's$x',
        userId: 'u',
        colorValue: 0xFF000000,
        strokeWidth: 4,
        points: [DrawPoint(x, 0.3), DrawPoint(x, 0.6)],
        isEraser: eraser,
        orderIndex: 0,
      );

  DrawStroke fill(double centerX, double width) => DrawStroke(
        id: 'f$centerX',
        userId: 'u',
        colorValue: 0xFFFF0000,
        strokeWidth: 0,
        points: const [],
        orderIndex: 0,
        imageUrl: 'file:///fill.png',
        imageX: centerX,
        imageY: 0.5,
        imageWidth: width,
        imageHeight: 0.2,
      );

  group('выбор не задан', () {
    test('лист как нарисован: слева девушка, справа парень — у обоих телефонов', () {
      final figures = ColoringFigures.fromStorage(null, null);
      expect(figures.left, ColoringFigure.girl);
      expect(figures.right, ColoringFigure.boy);
      expect(ColoringFigures.fromStorage('', '  '), figures);
    });

    test('мусор в поле читается как «не задано», а не роняет экран', () {
      expect(ColoringFigures.fromStorage('кот', 'BOY'), const ColoringFigures(left: ColoringFigure.girl, right: ColoringFigure.boy));
      expect(ColoringFigures.fromStorage('boy', 'girl'), const ColoringFigures(left: ColoringFigure.boy, right: ColoringFigure.girl));
    });

    test('смена одной половины не трогает другую', () {
      const start = ColoringFigures(left: ColoringFigure.girl, right: ColoringFigure.boy);
      final next = start.withSide(ColoringSide.right, ColoringFigure.girl);
      expect(next.left, ColoringFigure.girl);
      expect(next.right, ColoringFigure.girl);
      expect(next.on(ColoringSide.right), ColoringFigure.girl);
    });
  });

  group('выбор при заведении листа', () {
    test('моя половина по моему полу, половина партнёра — противоположная', () {
      final f = coloringFiguresForStart(mySide: ColoringSide.right, myGender: 'female');
      expect(f.right, ColoringFigure.girl);
      expect(f.left, ColoringFigure.boy);
      final m = coloringFiguresForStart(mySide: ColoringSide.left, myGender: 'male');
      expect(m.left, ColoringFigure.boy);
      expect(m.right, ColoringFigure.girl);
    });

    test('пол не указан или свой — как нарисовано', () {
      expect(coloringFiguresForStart(mySide: ColoringSide.right, myGender: ''), ColoringFigures.drawn);
      expect(coloringFiguresForStart(mySide: ColoringSide.left, myGender: 'небинарный'), ColoringFigures.drawn);
    });
  });

  group('когда половину уже не поменять', () {
    test('краска на половине — по мазку и по заливке, стёрка не в счёт', () {
      expect(coloringSideHasPaint([line(0.2)], ColoringSide.left), isTrue);
      expect(coloringSideHasPaint([line(0.2)], ColoringSide.right), isFalse);
      expect(coloringSideHasPaint([line(0.8, eraser: true)], ColoringSide.right), isFalse);
      expect(coloringSideHasPaint([fill(0.75, 0.3)], ColoringSide.right), isTrue);
      expect(coloringSideHasPaint([fill(0.75, 0.3)], ColoringSide.left), isFalse);
      expect(coloringSideHasPaint(const [], ColoringSide.left), isFalse);
    });

    test('краска в разделителе посередине не запирает ни одну половину', () {
      // Верёвка «Снеговика» шириной 44 точки из 1600 стоит на середине, её
      // перекрученные звенья — ячейки под заливку.
      expect(coloringSideHasPaint([fill(0.5, 0.02)], ColoringSide.left), isFalse);
      expect(coloringSideHasPaint([fill(0.5, 0.02)], ColoringSide.right), isFalse);
      expect(coloringSideHasPaint([fill(0.505, 0.012)], ColoringSide.right), isFalse);
      expect(coloringSideHasPaint([line(0.497)], ColoringSide.left), isFalse);
      // А заливка, ушедшая за верёвку, — уже краска на половине.
      expect(coloringSideHasPaint([fill(0.45, 0.06)], ColoringSide.left), isTrue);
    });

    test('замок: владелец половины нажал «Готово» или на ней есть краска', () {
      expect(coloringFigureLocked(ownerDone: false, hasPaint: false), isFalse);
      expect(coloringFigureLocked(ownerDone: true, hasPaint: false), isTrue);
      expect(coloringFigureLocked(ownerDone: false, hasPaint: true), isTrue);
    });
  });

  group('картинки', () {
    test('у «Снеговика» есть обе фигуры на обеих половинах, 800×1600', () {
      final picture = ColoringPicture.byId('snowman')!;
      expect(picture.figures, isTrue);
      for (final side in ColoringSide.values) {
        for (final figure in ColoringFigure.values) {
          final path = picture.halfAsset(side, figure);
          final file = File(path);
          expect(file.existsSync(), isTrue, reason: path);
          final header = ByteData.sublistView(file.readAsBytesSync().sublist(16, 24));
          expect(header.getUint32(0), 800, reason: '$path по ширине');
          expect(header.getUint32(4), 1600, reason: '$path по высоте');
        }
      }
      expect(File(picture.thumbAsset).existsSync(), isTrue);
    });

    testWidgets('половины склеиваются в квадрат 1600 с верёвкой посередине', (tester) async {
      await tester.runAsync(() async {
        final picture = ColoringPicture.byId('snowman')!;
        Future<ui.Image> load(ColoringSide side, ColoringFigure figure) async {
          final bytes = File(picture.halfAsset(side, figure)).readAsBytesSync();
          final codec = await ui.instantiateImageCodec(bytes);
          return (await codec.getNextFrame()).image;
        }

        final left = await load(ColoringSide.left, ColoringFigure.boy);
        final right = await load(ColoringSide.right, ColoringFigure.boy);
        final sheet = await composeColoringHalves(left, right);
        expect(sheet.width, 1600);
        expect(sheet.height, 1600);
        final data = (await sheet.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        int alphaAt(int x, int y) => data.getUint8((y * 1600 + x) * 4 + 3);
        // Края верёвки — сплошные линии по всей высоте: через них заливка не
        // перетечёт на половину партнёра.
        for (var y = 0; y < 1600; y++) {
          expect(alphaAt(779, y), greaterThan(200), reason: 'дыра в левом крае верёвки, y=$y');
          expect(alphaAt(820, y), greaterThan(200), reason: 'дыра в правом крае верёвки, y=$y');
        }
        // Белая бумага вокруг прозрачна: контур лежит поверх мазков. Точка
        // выбрана в просвете между снежинками, пустом у обеих левых половин.
        expect(alphaAt(160, 200), 0);
        for (final image in [left, right, sheet]) {
          image.dispose();
        }
      });
    });

    test('у прежних раскрасок вариантов нет, их контур — один файл', () {
      for (final p in ColoringPicture.all.where((p) => p.id != 'snowman')) {
        expect(p.figures, isFalse, reason: p.id);
        expect(File(p.outlineAsset).existsSync(), isTrue, reason: p.id);
      }
    });
  });

  group('проводка', () {
    String read(String path) => File(path).readAsStringSync();

    test('смена фигуры пишет только свою половину и не сбрасывает «Готово»', () {
      final repo = read('lib/services/canvas_repository.dart');
      final body = RegExp(r'Future<void> setColoringFigure\([\s\S]*?\);').firstMatch(repo)!.group(0)!;
      expect(body.contains('coloringDone'), isFalse, reason: 'смена фигуры стёрла бы партнёру «Готово»');
      expect(body.contains('coloringFigureLeft') && body.contains('coloringFigureRight'), isTrue);
      expect(read('lib/services/pb_data_service.dart').contains("body['coloring_figure_left']"), isTrue);
      expect(read('lib/services/pb_data_service.dart').contains("body['coloring_figure_right']"), isTrue);
    });

    test('сервер знает оба поля', () {
      final hotpath = read('pocketbase/hotpath/hotpath.py');
      final migrate = read('pocketbase/hotpath/migrate_table.py');
      final schema = read('pocketbase/collections_schema.json');
      for (final field in ['coloring_figure_left', 'coloring_figure_right']) {
        expect(hotpath.contains('"$field": "text"'), isTrue, reason: 'hotpath без $field');
        expect(migrate.contains('"$field": "text"'), isTrue, reason: 'migrate_table без $field');
        expect(schema.contains('"$field"'), isTrue, reason: 'схема без $field');
      }
    });

    test('экран собирает контур из половин и перечитывает его, когда фигура сменилась', () {
      final screen = read('lib/screens/draw_screen.dart');
      expect(screen.contains('halfAsset('), isTrue, reason: 'контур с вариантами не собирается из половин');
      expect(screen.contains('meta.coloringFigureLeft'), isTrue);
      expect(screen.contains('meta.coloringFigureRight'), isTrue);
    });
  });
}
