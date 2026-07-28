import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/onboarding_progress.dart';

/// Первые действия пары.
///
/// В одиночку обучать нечему: настроение без группы не сохраняется, половина
/// каталога виджетов закрыта, а лента, чат и карта появляются только с
/// партнёром. Поэтому одиночке показывается приглашение, а список шагов ждёт
/// готовой пары.
void main() {
  const all = {
    OnboardingStep.photo,
    OnboardingStep.mood,
    OnboardingStep.widget,
  };

  group('Что считается пройденным', () {
    test('Пусто у того, кто ничего не делал', () {
      expect(
        OnboardingProgress.doneSteps(
          hasPhoto: false,
          moodToday: false,
          widgetPinned: false,
        ),
        isEmpty,
      );
    });

    test('Каждое действие закрывает свой шаг', () {
      expect(
        OnboardingProgress.doneSteps(
          hasPhoto: true,
          moodToday: true,
          widgetPinned: true,
        ),
        all,
      );
    });

    test('Аватар из регистрации закрывает шаг сразу', () {
      expect(
        OnboardingProgress.doneSteps(
          hasPhoto: true,
          moodToday: false,
          widgetPinned: false,
        ),
        {OnboardingStep.photo},
        reason: 'заставлять проходить пройденное — верный способ раздражать',
      );
    });
  });

  group('Одиночке список не показываем', () {
    test('Без пары шагов нет вовсе', () {
      expect(OnboardingProgress.stepsFor(hasPartner: false), isEmpty);
    });

    test('Без пары карточки нет, что бы ни было сделано', () {
      expect(
        OnboardingProgress.visible(
          done: const {},
          daysSinceSignup: 0,
          dismissed: false,
          hasPartner: false,
        ),
        isFalse,
        reason: 'в одиночку эти шаги физически не закрыть — вместо списка '
            'человек видит приглашение',
      );
    });

    test('С парой список из трёх шагов', () {
      expect(
        OnboardingProgress.stepsFor(hasPartner: true),
        [OnboardingStep.photo, OnboardingStep.mood, OnboardingStep.widget],
      );
      expect(OnboardingProgress.totalFor(hasPartner: true), 3);
    });
  });

  group('Показывать ли карточку паре', () {
    test('С незакрытыми шагами — да', () {
      expect(
        OnboardingProgress.visible(
          done: const {OnboardingStep.photo},
          daysSinceSignup: 0,
          dismissed: false,
          hasPartner: true,
        ),
        isTrue,
      );
    });

    test('Всё пройдено — карточки нет', () {
      expect(
        OnboardingProgress.visible(
          done: all,
          daysSinceSignup: 1,
          dismissed: false,
          hasPartner: true,
        ),
        isFalse,
      );
    });

    test('Через две недели уходит даже с незакрытыми шагами', () {
      expect(
        OnboardingProgress.visible(
          done: const {OnboardingStep.photo},
          daysSinceSignup: OnboardingProgress.lifetimeDays,
          dismissed: false,
          hasPartner: true,
        ),
        isFalse,
        reason: 'список, который висит месяц, читается как упрёк',
      );
    });

    test('Пропустил — больше не поднимается', () {
      expect(
        OnboardingProgress.visible(
          done: const {},
          daysSinceSignup: 0,
          dismissed: true,
          hasPartner: true,
        ),
        isFalse,
      );
    });
  });

  group('Порядок шагов', () {
    test('Следующий — первый невыполненный', () {
      expect(
        OnboardingProgress.nextStep(const {OnboardingStep.photo}),
        OnboardingStep.mood,
      );
      expect(
        OnboardingProgress.nextStep(
          const {OnboardingStep.photo, OnboardingStep.mood},
        ),
        OnboardingStep.widget,
      );
    });

    test('Всё пройдено — следующего нет', () {
      expect(OnboardingProgress.nextStep(all), isNull);
    });

    test('Фото первым: его видно партнёру везде', () {
      expect(OnboardingProgress.order.first, OnboardingStep.photo);
    });
  });

  group('Развёрнутый список или строка', () {
    test('Сразу после подключения — развёрнутый: это и есть обучение', () {
      expect(OnboardingProgress.collapsed(done: const {}), isFalse);
    });

    test('Первый шаг сделан — сворачивается в строку', () {
      expect(
        OnboardingProgress.collapsed(done: const {OnboardingStep.photo}),
        isTrue,
        reason: 'человек уже понял, что это, и дальше хватает строки — '
            'главная у пары плотная',
      );
    });
  });
}
