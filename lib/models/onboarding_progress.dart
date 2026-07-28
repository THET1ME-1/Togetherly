/// Первые действия пары.
///
/// По базе на 28 июля: у тех, кто трогал четыре возможности и больше, дожитие
/// до седьмого дня 58,5% против 9,8% у тех, кто не трогал ничего. Отсюда
/// короткий список на главной — довести до первых действий, пока интерес свежий.
///
/// Список показывается только паре. В одиночку обучать нечему: настроение без
/// группы не сохраняется (`MoodService` выходит на пустом `groupId`), из
/// каталога виджетов доступны три штуки из десяти, а чат, лента и карта
/// появляются вместе с партнёром. Одиночка вместо списка видит приглашение —
/// это его единственный осмысленный следующий шаг.
///
/// Правила вынесены в чистые функции: от них зависит, увидит ли человек
/// карточку вообще, и их проще держать под тестами, чем внутри экрана.
library;

/// Шаг, который проходит новая пара.
enum OnboardingStep {
  /// Фото профиля — его видит партнёр в чате, виджете и ленте.
  photo,

  /// Отметить сегодняшнее настроение.
  mood,

  /// Поставить виджет на рабочий стол.
  widget,
}

abstract final class OnboardingProgress {
  /// Порядок в карточке. Фото первым: его видно партнёру во всех разделах,
  /// а поставить его — секунда.
  static const List<OnboardingStep> order = [
    OnboardingStep.photo,
    OnboardingStep.mood,
    OnboardingStep.widget,
  ];

  /// Сколько дней карточка живёт на главной. Дальше уходит даже с незакрытыми
  /// шагами: список, который висит месяц, читается как упрёк.
  static const int lifetimeDays = 14;

  /// Шаги, которые видит человек прямо сейчас. Без пары — ни одного.
  static List<OnboardingStep> stepsFor({required bool hasPartner}) =>
      hasPartner ? order : const [];

  /// Сколько шагов в списке — знаменатель кольца прогресса.
  static int totalFor({required bool hasPartner}) =>
      stepsFor(hasPartner: hasPartner).length;

  /// Что уже сделано. Считается по фактам в данных, а не по нажатиям: кто
  /// поставил аватар ещё при регистрации, увидит шаг закрытым.
  static Set<OnboardingStep> doneSteps({
    required bool hasPhoto,
    required bool moodToday,
    required bool widgetPinned,
  }) =>
      {
        if (hasPhoto) OnboardingStep.photo,
        if (moodToday) OnboardingStep.mood,
        if (widgetPinned) OnboardingStep.widget,
      };

  /// Показывать ли карточку.
  static bool visible({
    required Set<OnboardingStep> done,
    required int daysSinceSignup,
    required bool dismissed,
    required bool hasPartner,
  }) {
    if (!hasPartner) return false;
    if (dismissed) return false;
    if (daysSinceSignup >= lifetimeDays) return false;
    return order.any((s) => !done.contains(s));
  }

  /// Первый невыполненный шаг — на него смотрит человек.
  static OnboardingStep? nextStep(Set<OnboardingStep> done) {
    for (final step in order) {
      if (!done.contains(step)) return step;
    }
    return null;
  }

  /// Свернуть ли карточку в строку.
  ///
  /// Сразу после подключения список развёрнут — это и есть обучение. Как
  /// только сделан первый шаг, человек понял, что от него хотят, и дальше
  /// хватает строки: главная у пары плотная, там маскот, карта, достижения и
  /// лента.
  static bool collapsed({required Set<OnboardingStep> done}) => done.isNotEmpty;
}
