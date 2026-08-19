import 'dart:ui';

/// Куда лечь картинке [source] внутри поля [target], сохранив пропорции.
///
/// То же, что `BoxFit.contain` у виджета, только числом: снимок холста
/// собирается не виджетами, а `Canvas.drawImageRect`, и вписывать прежний
/// рисунок туда приходится руками. Пока этого не делали, редактор показывал
/// набросок вписанным, а сохранение растягивало его на весь квадрат — и в
/// готовом маскоте поверх нового рисунка оставалась раздутая копия старого.
Rect containRect({required Size source, required Size target}) {
  if (source.width <= 0 || source.height <= 0) {
    return Rect.fromLTWH(0, 0, target.width, target.height);
  }
  final scale = (target.width / source.width) < (target.height / source.height)
      ? target.width / source.width
      : target.height / source.height;
  final w = source.width * scale;
  final h = source.height * scale;
  return Rect.fromLTWH(
    (target.width - w) / 2,
    (target.height - h) / 2,
    w,
    h,
  );
}
