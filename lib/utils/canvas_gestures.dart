/// Правила жестов холста: где касание — работа, а где просто попытка
/// разглядеть рисунок поближе.
///
/// Раньше инструмент срабатывал в момент касания первым пальцем. Для кисти это
/// терпимо (штрих рисуется по движению), а заливка красит область целиком и
/// сразу: человек сводил два пальца, чтобы приблизить картинку, а первый палец
/// уже залил то, на чём стоял. Второй палец приходит на 20–80 мс позже — когда
/// красить поздно.
library;

/// Считать ли касание тапом заливки.
///
/// [travel] — сколько пикселей прошёл палец, [held] — сколько держали,
/// [extraPointers] — сколько пальцев коснулось холста за это время помимо
/// первого, [zoomed] — менялся ли масштаб или поворот.
///
/// Порог смещения прощает дрожание руки, потолок удержания отсекает
/// «положил палец и думает»: там человек чаще присматривается, чем красит.
bool fillTapAccepted({
  required double travel,
  required Duration held,
  required int extraPointers,
  required bool zoomed,
  double slop = 12,
  Duration limit = const Duration(milliseconds: 600),
}) {
  if (extraPointers > 0 || zoomed) return false;
  return travel <= slop && held < limit;
}

/// Оставлять ли начатый штрих, когда холста коснулся второй палец.
///
/// Ладонь на экране посреди мазка не должна стирать работу — но и огрызок в
/// две точки, поставленный первым пальцем щипка, оставаться на холсте не
/// должен. Различаем их по тому, успел ли штрих стать штрихом: прошёл заметный
/// путь или его вели достаточно долго, чтобы это было намерением.
bool strokeSurvivesSecondFinger({
  required double travel,
  required Duration held,
  double minTravel = 16,
  Duration minHeld = const Duration(milliseconds: 250),
}) =>
    travel >= minTravel || held >= minHeld;

/// Что делает короткий тап несколькими пальцами.
enum MultiTapAction { none, undo, redo }

/// Отмена двумя пальцами и возврат тремя — привычка, принесённая из Procreate.
///
/// Тап отличается от щипка тем же, чем в остальных правилах этого файла:
/// пальцы стояли на месте и недолго. Изменившийся масштаб выдаёт щипок
/// наверняка — отменять чужую работу по случайному сведению пальцев нельзя.
///
/// [fingers] — сколько пальцев было на экране одновременно, [travel] —
/// сколько прошёл самый резвый из них.
MultiTapAction multiTapAction({
  required int fingers,
  required Duration held,
  required double travel,
  required bool zoomed,
  double slop = 14,
  Duration limit = const Duration(milliseconds: 400),
}) {
  if (zoomed || travel > slop || held >= limit) return MultiTapAction.none;
  return switch (fingers) {
    2 => MultiTapAction.undo,
    3 => MultiTapAction.redo,
    _ => MultiTapAction.none,
  };
}

/// Долгое нажатие одним пальцем берёт цвет с холста — приём Procreate.
///
/// От намеренного мазка отличается тем, что палец никуда не поехал: рисующая
/// рука сдвигается сразу, а за цветом человек прижимает палец и ждёт.
/// Порог пути мельче, чем у остальных правил файла: тут нельзя перепутать
/// с началом линии, иначе первый штрих будет пропадать.
bool holdIsEyedropper({
  required Duration held,
  required double travel,
  double slop = 8,
  Duration minHeld = const Duration(milliseconds: 550),
}) =>
    travel <= slop && held >= minHeld;
