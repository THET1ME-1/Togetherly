import 'mascot_anim.dart';

/// Ступень роста, как её видит виджет рабочего стола.
///
/// Совпадает со ступенями атласа (`MascotAnim.levelForStreak`) намеренно:
/// картинка и подпись под ней обязаны говорить одно и то же. Пороги живут
/// здесь И в `MascotAnim` — правишь один, правь второй, за этим следит
/// `test/models/mascot_widget_data_test.dart`.
enum MascotStage {
  baby(1),
  teen(2),
  adult(3);

  const MascotStage(this.level);

  /// Номер блока строк в атласе: его ждёт `MascotAnim.rectRow`.
  final int level;
}

/// Первый день следующей ступени.
const int _kTeenFrom = 7;
const int _kAdultFrom = 30;

int _clampStreak(int streakDays) => streakDays < 0 ? 0 : streakDays;

MascotStage mascotStageOf(int streakDays) {
  final streak = _clampStreak(streakDays);
  if (streak >= _kAdultFrom) return MascotStage.adult;
  if (streak >= _kTeenFrom) return MascotStage.teen;
  return MascotStage.baby;
}

/// Сколько дней серии осталось до следующей ступени. У взрослого ноль.
int mascotDaysToNextStage(int streakDays) {
  final streak = _clampStreak(streakDays);
  if (streak >= _kAdultFrom) return 0;
  if (streak >= _kTeenFrom) return _kAdultFrom - streak;
  return _kTeenFrom - streak;
}

/// Доля пройденного ВНУТРИ текущей ступени, 0..1.
///
/// Считается от начала ступени, а не от нуля дней: иначе подросток на восьмой
/// день показывал бы почти пустую полосу, хотя малыша он уже перерос.
double mascotStageProgress(int streakDays) {
  final streak = _clampStreak(streakDays);
  if (streak >= _kAdultFrom) return 1;
  final start = streak >= _kTeenFrom ? _kTeenFrom : 0;
  final end = streak >= _kTeenFrom ? _kAdultFrom : _kTeenFrom;
  return (streak - start) / (end - start);
}

/// Та же доля целыми процентами: натив рисует полосу по целому числу.
int mascotStagePercent(int streakDays) =>
    (mascotStageProgress(streakDays) * 100).round();

/// Окно сна персонажа в минутах от полуночи.
///
/// Отдельный тип, а не `SleepWindow` из настроек: виджету нужно различать «спит
/// с 23:00» и «спать не умеет вовсе» — последнее задаёт атлас (`nightIdle`), а
/// не человек. Натив читает минуты числом, и −1 для него значит «ночного кадра
/// нет, показывай дневной всегда».
class MascotSleepWindow {
  final int from;
  final int to;

  const MascotSleepWindow({required this.from, required this.to});

  /// Персонаж без ночной сцены.
  static const MascotSleepWindow none = MascotSleepWindow(from: -1, to: -1);

  bool get enabled => from >= 0 && to >= 0 && from != to;
}

/// Всё, что уезжает на рабочий стол про маскота пары.
class MascotWidgetData {
  final String mascotId;
  final String name;
  final int streakDays;

  /// Серия оборвалась: персонаж грустит, пока её не начнут заново.
  final bool sad;

  final MascotSleepWindow sleep;

  const MascotWidgetData({
    required this.mascotId,
    required this.name,
    required this.streakDays,
    required this.sad,
    required this.sleep,
  });

  MascotStage get stage => mascotStageOf(streakDays);

  int get level => stage.level;

  int get daysToNextStage => mascotDaysToNextStage(streakDays);

  int get percent => mascotStagePercent(streakDays);

  /// Ступень для атласа. Держит связь с `MascotAnim` на виду.
  int get atlasLevel => MascotAnim.levelForStreak(_clampStreak(streakDays));
}
