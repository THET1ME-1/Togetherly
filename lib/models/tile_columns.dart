/// Раскладка плиток по ширине экрана.
///
/// Чипы «что ещё передать» лежали в `Wrap` и держали свою ширину: два рядом не
/// влезали, один занимал половину строки, справа оставалась пустота — её и
/// заметил автор на снимке (17.08.2026). Ширина у людей разная: 320 dp на старых
/// Android, 393 на iPhone 15, 430 на Pro Max, за 700 на планшете, — поэтому
/// колонки считаем, а не задаём.
library;

/// Сколько плиток шириной хотя бы [minTileWidth] влезает в [width].
///
/// Меньше одной не бывает: на самом узком экране плитка растянется на всю
/// ширину, и это лучше половины строки с пустотой рядом.
int tileColumns({
  required double width,
  required double minTileWidth,
  int maxColumns = 6,
}) {
  if (!width.isFinite || width <= 0 || minTileWidth <= 0) return 1;
  final fits = (width / minTileWidth).floor();
  if (fits < 1) return 1;
  return fits > maxColumns ? maxColumns : fits;
}

/// Ширина одной плитки, когда [columns] штук делят [width] с зазором [spacing].
double tileWidth({
  required double width,
  required int columns,
  required double spacing,
}) {
  if (!width.isFinite || width <= 0 || columns < 1) return 0;
  final gaps = spacing * (columns - 1);
  final free = width - gaps;
  return free <= 0 ? width : free / columns;
}
