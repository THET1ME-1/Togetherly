import 'dart:math' as math;
import 'dart:ui';

/// Где живёт панель инструментов холста.
///
/// Лист панели занимает около четырёхсот точек по высоте. Стоймя это половина
/// экрана и холст остаётся рабочим, а лёжа от него не осталось бы ничего —
/// там панель уходит в колонку сбоку.
enum DrawLayout { bottomSheet, sidePanel }

/// Панель снизу или сбоку — решает высота, а не только поворот. Планшет
/// стоймя шире телефона лёжа, но высоты у него хватает.
DrawLayout drawLayoutFor(Size size) {
  const enoughHeight = 620.0;
  if (size.height >= enoughHeight) return DrawLayout.bottomSheet;
  return size.width > size.height
      ? DrawLayout.sidePanel
      : DrawLayout.bottomSheet;
}

/// Ширина боковой колонки. Меньше трёхсот панель ломается: восемь кружков
/// цвета и шесть кнопок перестают помещаться в строку.
double sidePanelWidth(Size size) => math.min(
      math.max(300.0, size.width * 0.32),
      math.max(300.0, size.width / 3),
    );
