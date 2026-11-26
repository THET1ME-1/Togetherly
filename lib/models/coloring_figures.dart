import 'coloring_picture.dart';
import 'draw_stroke.dart';

/// Кто нарисован на половине раскраски.
enum ColoringFigure {
  girl,
  boy;

  /// Значение из меты холста. Пустое и незнакомое — null: половина тогда
  /// рисуется так, как нарисована картинка.
  static ColoringFigure? fromStorage(String? raw) => switch (raw?.trim()) {
        'girl' => ColoringFigure.girl,
        'boy' => ColoringFigure.boy,
        _ => null,
      };

  String get storage => name;
}

/// Кто на какой половине листа.
///
/// Выбор живёт в мете холста двумя полями (`coloring_figure_left`,
/// `coloring_figure_right`): каждая половина пишется отдельно, и правки двух
/// людей в одну секунду друг друга не затирают. Выбор привязан к половине, а
/// не к человеку: обмен половин меняет, кто какую красит, но не картинку.
class ColoringFigures {
  const ColoringFigures({required this.left, required this.right});

  final ColoringFigure left;
  final ColoringFigure right;

  /// Как нарисовано: девушка слева, парень справа. Им же показывается лист,
  /// где выбор не записан (лист старой сборки, запись не дошла) — одинаково
  /// на обоих телефонах.
  static const drawn =
      ColoringFigures(left: ColoringFigure.girl, right: ColoringFigure.boy);

  factory ColoringFigures.fromStorage(String? left, String? right) =>
      ColoringFigures(
        left: ColoringFigure.fromStorage(left) ?? drawn.left,
        right: ColoringFigure.fromStorage(right) ?? drawn.right,
      );

  ColoringFigure on(ColoringSide side) =>
      side == ColoringSide.left ? left : right;

  ColoringFigures withSide(ColoringSide side, ColoringFigure figure) =>
      side == ColoringSide.left
          ? ColoringFigures(left: figure, right: right)
          : ColoringFigures(left: left, right: figure);

  @override
  bool operator ==(Object other) =>
      other is ColoringFigures && other.left == left && other.right == right;

  @override
  int get hashCode => Object.hash(left, right);

  @override
  String toString() => 'ColoringFigures(${left.name}, ${right.name})';
}

/// С чего начинается выбор, когда человек заводит лист.
///
/// Своя половина — по своему полу, половина партнёра — противоположная. Пол
/// партнёра на экране рисования неизвестен, поэтому это только начальная
/// отметка: лист выбора открывается сразу, и пара из двух девушек или двух
/// парней ставит своё одним касанием. Пол не указан — как нарисовано.
ColoringFigures coloringFiguresForStart({
  required ColoringSide mySide,
  required String myGender,
}) {
  final ColoringFigure mine;
  switch (myGender) {
    case 'female':
      mine = ColoringFigure.girl;
    case 'male':
      mine = ColoringFigure.boy;
    default:
      return ColoringFigures.drawn;
  }
  final partner =
      mine == ColoringFigure.girl ? ColoringFigure.boy : ColoringFigure.girl;
  return mySide == ColoringSide.left
      ? ColoringFigures(left: mine, right: partner)
      : ColoringFigures(left: partner, right: mine);
}

/// Есть ли на половине краска: мазок или заливка. Точки в долях листа, у
/// заливки и картинки `imageX` — середина. Стёрка краской не считается.
bool coloringSideHasPaint(Iterable<DrawStroke> strokes, ColoringSide side) {
  bool onSide(double x) => side == ColoringSide.left ? x < 0.5 : x > 0.5;
  for (final stroke in strokes) {
    if (stroke.isEraser) continue;
    final x = stroke.imageX;
    final w = stroke.imageWidth;
    if (stroke.isImageStroke && x != null && w != null) {
      if (onSide(side == ColoringSide.left ? x - w / 2 : x + w / 2)) {
        return true;
      }
      continue;
    }
    for (final p in stroke.points) {
      if (onSide(p.x)) return true;
    }
  }
  return false;
}

/// Можно ли ещё сменить фигуру на половине. Нельзя, когда её хозяин нажал
/// «Готово» или на ней уже есть краска: заливки, сделанные по одному рисунку,
/// легли бы мимо линий другого.
bool coloringFigureLocked({required bool ownerDone, required bool hasPaint}) =>
    ownerDone || hasPaint;
