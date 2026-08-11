import 'package:flutter/material.dart';

/// Движение приложения одним набором.
///
/// До 11 августа 2026 длительности и кривые писались по месту: двенадцать
/// разных `Curves` и два десятка чисел от 150 до 600 миллисекунд. Соседние
/// экраны от этого выглядели собранными из разных приложений — карточка
/// въезжала за 220 мс с `easeOut`, лист рядом за 300 с `easeInOut`, и
/// одинаковые по смыслу движения нигде не совпадали.
///
/// Шкала взята из Material 3 (`md.sys.motion.duration`), поэтому прежние
/// значения ложатся на ступени с точностью до двадцати миллисекунд: перевод
/// кода на токены ничего не переигрывает, он только сводит разнобой.
///
/// Как выбирать. **Длительность** — по размеру движения: чем дальше едет
/// предмет, тем дольше. **Кривая** — по роли: [emphasized] для того, ради чего
/// кадр происходит, [standard] для служебного.
abstract final class Motion {
  // ── Шкала длительностей ───────────────────────────────────────────────────

  static const Duration short1 = Duration(milliseconds: 50);
  static const Duration short2 = Duration(milliseconds: 100);
  static const Duration short3 = Duration(milliseconds: 150);
  static const Duration short4 = Duration(milliseconds: 200);

  static const Duration medium1 = Duration(milliseconds: 250);
  static const Duration medium2 = Duration(milliseconds: 300);
  static const Duration medium3 = Duration(milliseconds: 350);
  static const Duration medium4 = Duration(milliseconds: 400);

  static const Duration long1 = Duration(milliseconds: 450);
  static const Duration long2 = Duration(milliseconds: 500);
  static const Duration long3 = Duration(milliseconds: 550);
  static const Duration long4 = Duration(milliseconds: 600);

  // ── Роли: этими именами и пользуемся в коде ───────────────────────────────

  /// Отклик на палец: нажатие кнопки, галочка, смена цвета.
  static const Duration tap = short3;

  /// Мелкое движение внутри блока: сдвиг на пару десятков точек, подсказка.
  static const Duration nudge = short4;

  /// Блок встаёт на место, лист приходит, вкладка меняется.
  static const Duration block = medium1;

  /// Заметное движение: карусель, разворот, переход внутри экрана.
  static const Duration screen = medium4;

  /// Вход блока с пружиной — самое длинное, что есть на экране.
  static const Duration entrance = long2;

  // ── Кривые ────────────────────────────────────────────────────────────────

  /// Главное движение кадра. Медленный старт, быстрая середина, мягкая
  /// посадка — то, чем M3 отличается от школьного `easeInOut`.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Появление: предмет влетает и замедляется к своему месту.
  static const Curve emphasizedIn = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Уход: предмет разгоняется и покидает кадр.
  static const Curve emphasizedOut = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Служебное движение, которое не должно притягивать взгляд.
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Появление служебного: то же, но без разгона в начале.
  static const Curve standardIn = Cubic(0.0, 0.0, 0.0, 1.0);

  // ── Пружины ───────────────────────────────────────────────────────────────

  /// Короткий подхват: кнопка под пальцем, мелкая плитка.
  static final SpringDescription spatialFast =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: 0.8);

  /// Обычное перемещение предмета: карточка входит, блок встаёт на место.
  /// Слегка недодемпфирована, поэтому даёт перелёт на пару точек и возврат —
  /// жёстче выходит щелчок, мягче кисель.
  static final SpringDescription spatial = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 260,
    ratio: 0.72,
  );

  /// Крупный предмет через весь экран.
  static final SpringDescription spatialSlow =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 170, ratio: 0.78);
}
