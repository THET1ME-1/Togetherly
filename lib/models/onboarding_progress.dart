/// Первые действия новичка.
///
/// По базе на 28 июля: до пары доходят 57% зарегистрировавшихся, и у дошедших
/// дожитие до седьмого дня 47,7% против 10,4% у одиночек. Ещё резче работает
/// количество тронутых возможностей: ни одной — 9,8%, четыре и больше — 58,5%.
/// Отсюда карточка на главной: довести до четырёх действий в первые дни.
///
/// Правила вынесены в чистые функции: от них зависит, увидит ли человек
/// карточку вообще, и их проще держать под тестами, чем внутри экрана.
library;

/// Шаг, который новичок должен пройти.
enum OnboardingStep {
  /// Фото профиля — его видит партнёр в чате, виджете и ленте.
  photo,

  /// Подключить партнёра. Главный шаг: без него половина приложения мертва.
  partner,

  /// Отметить сегодняшнее настроение.
  mood,

  /// Поставить виджет на рабочий стол.
  widget,
}

abstract final class OnboardingProgress {
  /// Порядок в карточке. Партнёр идёт вторым: настроение и виджет без пары
  /// наполовину бессмысленны, вести к ним раньше — сбивать с главного.
  static const List<OnboardingStep> order = [
    OnboardingStep.photo,
    OnboardingStep.partner,
    OnboardingStep.mood,
    OnboardingStep.widget,
  ];

  /// Сколько дней карточка живёт на главной. Дальше уходит даже с незакрытыми
  /// шагами: список, который висит месяц, читается как упрёк.
  static const int lifetimeDays = 14;

  /// Что уже сделано. Считается по фактам в данных, а не по нажатиям: кто
  /// поставил аватар ещё при регистрации, увидит шаг закрытым.
  static Set<OnboardingStep> doneSteps({
    required bool hasPhoto,
    required bool hasPartner,
    required bool moodToday,
    required bool widgetPinned,
  }) =>
      {
        if (hasPhoto) OnboardingStep.photo,
        if (hasPartner) OnboardingStep.partner,
        if (moodToday) OnboardingStep.mood,
        if (widgetPinned) OnboardingStep.widget,
      };

  /// Показывать ли карточку.
  static bool visible({
    required Set<OnboardingStep> done,
    required int daysSinceSignup,
    required bool dismissed,
  }) {
    if (dismissed) return false;
    if (daysSinceSignup >= lifetimeDays) return false;
    return done.length < order.length;
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
  /// Пока пары нет, главная короткая — маскот, карта, достижения и лента
  /// показываются только в паре, — и карточка занимает пустующее место. Как
  /// только партнёр появился, все эти блоки приходят, и список уступает им
  /// место, оставаясь строкой с прогрессом.
  static bool collapsed({
    required bool hasPartner,
    required Set<OnboardingStep> done,
  }) =>
      hasPartner;

  /// Приглушить ли шаг: сделать его сейчас нельзя, но видно, что будет дальше.
  static bool dimmed(OnboardingStep step, {required bool hasPartner}) {
    if (hasPartner) return false;
    return step == OnboardingStep.mood || step == OnboardingStep.widget;
  }
}
