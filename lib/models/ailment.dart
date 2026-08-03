import 'package:flutter/material.dart';

import '../services/locale_service.dart';

/// Насколько человеку плохо.
///
/// У настроений цвет говорит, насколько хорошо, — здесь он говорит обратное.
/// Раньше все шестнадцать чипов были одинаковой обводкой, и «Температура»
/// читалась ровно как «Аллергия».
enum AilmentSeverity {
  /// Мешает, но живётся: усталость, бессонница, аллергия.
  light(Color(0xFFFFC800)),

  /// Болит: горло, спина, живот, голова.
  medium(Color(0xFFFF8A3D)),

  /// Свалило: температура, общее недомогание.
  hard(Color(0xFFFA282F));

  const AilmentSeverity(this.color);

  /// Цвет уровня. Тона взяты из палитры настроений: жёлтый «счастья» и
  /// красный «злости», между ними тёплый оранжевый.
  final Color color;
}

/// Один пункт каталога недомоганий («болячки»).
/// Лейблы хранятся прямо здесь (ru/en) — отдельных строк в LocaleService на
/// каждую болячку не заводим; [localizedLabel] выбирает язык на лету.
class Ailment {
  final String id;
  final String emoji;
  final String ru;
  final String en;

  /// Насколько плохо. Задаёт цвет чипа.
  final AilmentSeverity severity;

  const Ailment(this.id, this.emoji, this.ru, this.en, this.severity);

  String get localizedLabel =>
      LocaleService.instance.isRussian ? ru : en;
}

/// Каталог недомоганий. Порядок = порядок отображения в пикере.
const List<Ailment> kAilments = [
  Ailment('unwell', '🤒', 'Нездоровится', 'Unwell', AilmentSeverity.hard),
  Ailment('headache', '🤕', 'Голова болит', 'Headache', AilmentSeverity.medium),
  Ailment('heartburn', '🔥', 'Изжога', 'Heartburn', AilmentSeverity.light),
  Ailment('nausea', '🤢', 'Тошнит', 'Nausea', AilmentSeverity.medium),
  Ailment('cold', '🤧', 'Простуда', 'Cold', AilmentSeverity.medium),
  Ailment('fever', '🌡️', 'Температура', 'Fever', AilmentSeverity.hard),
  Ailment('stomach', '😣', 'Живот болит', 'Stomachache', AilmentSeverity.medium),
  Ailment('throat', '😷', 'Горло болит', 'Sore throat', AilmentSeverity.medium),
  Ailment('cough', '🫁', 'Кашель', 'Cough', AilmentSeverity.medium),
  Ailment('tooth', '🦷', 'Зуб болит', 'Toothache', AilmentSeverity.medium),
  Ailment('back', '🦴', 'Спина болит', 'Back pain', AilmentSeverity.medium),
  Ailment('cramps', '💢', 'Спазмы', 'Cramps', AilmentSeverity.medium),
  Ailment('dizzy', '😵‍💫', 'Кружится голова', 'Dizzy', AilmentSeverity.light),
  Ailment('fatigue', '😴', 'Усталость', 'Tired', AilmentSeverity.light),
  Ailment('insomnia', '🌙', 'Бессонница', 'Insomnia', AilmentSeverity.light),
  Ailment('allergy', '🌿', 'Аллергия', 'Allergy', AilmentSeverity.light),
];

/// Найти болячку по id (для восстановления выбора из сохранённого статуса).
Ailment? ailmentById(String id) {
  for (final a in kAilments) {
    if (a.id == id) return a;
  }
  return null;
}
