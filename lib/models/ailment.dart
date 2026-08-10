import 'package:flutter/material.dart';

import '../dict_strings.dart';

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
class Ailment {
  final String id;
  final String emoji;

  /// Насколько плохо. Задаёт цвет чипа.
  final AilmentSeverity severity;

  const Ailment(this.id, this.emoji, this.severity);

  /// Название живёт в словаре (`lib/l10n/dict/ailments.dart`): язык там колонка,
  /// а не пара полей в модели.
  String get localizedLabel => trKey('ailment_$id');
}

/// Каталог недомоганий. Порядок = порядок отображения в пикере.
const List<Ailment> kAilments = [
  Ailment('unwell', '🤒', AilmentSeverity.hard),
  Ailment('headache', '🤕', AilmentSeverity.medium),
  Ailment('heartburn', '🔥', AilmentSeverity.light),
  Ailment('nausea', '🤢', AilmentSeverity.medium),
  Ailment('cold', '🤧', AilmentSeverity.medium),
  Ailment('fever', '🌡️', AilmentSeverity.hard),
  Ailment('stomach', '😣', AilmentSeverity.medium),
  Ailment('throat', '😷', AilmentSeverity.medium),
  Ailment('cough', '🫁', AilmentSeverity.medium),
  Ailment('tooth', '🦷', AilmentSeverity.medium),
  Ailment('back', '🦴', AilmentSeverity.medium),
  Ailment('cramps', '💢', AilmentSeverity.medium),
  Ailment('dizzy', '😵‍💫', AilmentSeverity.light),
  Ailment('fatigue', '😴', AilmentSeverity.light),
  Ailment('insomnia', '🌙', AilmentSeverity.light),
  Ailment('allergy', '🌿', AilmentSeverity.light),
];

/// Найти болячку по id (для восстановления выбора из сохранённого статуса).
Ailment? ailmentById(String id) {
  for (final a in kAilments) {
    if (a.id == id) return a;
  }
  return null;
}
