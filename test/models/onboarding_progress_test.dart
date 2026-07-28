import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/onboarding_progress.dart';

/// Первые действия новичка. Правила собраны в чистых функциях, потому что от
/// них зависит, увидит ли человек карточку вообще: по базе 43% новичков не
/// доходят до пары, и почти все они уходят в день установки.
void main() {
  const all = {
    OnboardingStep.photo,
    OnboardingStep.partner,
    OnboardingStep.mood,
    OnboardingStep.widget,
  };

  group('Что считается пройденным', () {
    test('Пусто у того, кто ничего не делал', () {
      expect(
        OnboardingProgress.doneSteps(
          hasPhoto: false,
          hasPartner: false,
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
          hasPartner: true,
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
          hasPartner: false,
          moodToday: false,
          widgetPinned: false,
        ),
        {OnboardingStep.photo},
        reason: 'заставлять проходить пройденное — верный способ раздражать',
      );
    });
  });

  group('Показывать ли карточку', () {
    test('Новичку с незакрытыми шагами — да', () {
      expect(
        OnboardingProgress.visible(
          done: const {OnboardingStep.photo},
          daysSinceSignup: 0,
          dismissed: false,
        ),
        isTrue,
      );
    });

    test('Все шаги пройдены — карточки нет', () {
      expect(
        OnboardingProgress.visible(done: all, daysSinceSignup: 1, dismissed: false),
        isFalse,
      );
    });

    test('Через две недели уходит даже с незакрытыми шагами', () {
      expect(
        OnboardingProgress.visible(
          done: const {OnboardingStep.photo},
          daysSinceSignup: OnboardingProgress.lifetimeDays,
          dismissed: false,
        ),
        isFalse,
        reason: 'незакрытый список на видном месте раздражает сильнее, чем помогает',
      );
    });

    test('Закрыл руками — больше не поднимается', () {
      expect(
        OnboardingProgress.visible(
          done: const {},
          daysSinceSignup: 0,
          dismissed: true,
        ),
        isFalse,
      );
    });
  });

  group('Порядок шагов', () {
    test('Следующий — первый невыполненный по порядку', () {
      expect(
        OnboardingProgress.nextStep(const {OnboardingStep.photo}),
        OnboardingStep.partner,
      );
      expect(
        OnboardingProgress.nextStep(
          const {OnboardingStep.photo, OnboardingStep.partner},
        ),
        OnboardingStep.mood,
      );
    });

    test('Всё пройдено — следующего нет', () {
      expect(OnboardingProgress.nextStep(all), isNull);
    });

    test('Партнёр идёт раньше настроения и виджета', () {
      final order = OnboardingProgress.order;
      expect(order.indexOf(OnboardingStep.partner),
          lessThan(order.indexOf(OnboardingStep.mood)));
      expect(order.indexOf(OnboardingStep.partner),
          lessThan(order.indexOf(OnboardingStep.widget)),
          reason: 'без пары настроение и виджет наполовину бессмысленны');
    });
  });

  group('Развёрнутый вид или строка', () {
    test('Без пары карточка развёрнута — там главный шаг', () {
      expect(
        OnboardingProgress.collapsed(
          hasPartner: false,
          done: const {OnboardingStep.photo},
        ),
        isFalse,
      );
    });

    test('С парой сворачивается в строку и пропускает вперёд остальное', () {
      expect(
        OnboardingProgress.collapsed(
          hasPartner: true,
          done: const {OnboardingStep.photo, OnboardingStep.partner},
        ),
        isTrue,
      );
    });
  });

  group('Шаги, которые без пары не сделать', () {
    test('Настроение и виджет приглушены, пока партнёра нет', () {
      expect(OnboardingProgress.dimmed(OnboardingStep.mood, hasPartner: false), isTrue);
      expect(OnboardingProgress.dimmed(OnboardingStep.widget, hasPartner: false), isTrue);
    });

    test('Фото и партнёр доступны всегда', () {
      expect(OnboardingProgress.dimmed(OnboardingStep.photo, hasPartner: false), isFalse);
      expect(OnboardingProgress.dimmed(OnboardingStep.partner, hasPartner: false), isFalse);
    });

    test('С парой приглушать нечего', () {
      for (final step in all) {
        expect(OnboardingProgress.dimmed(step, hasPartner: true), isFalse);
      }
    });
  });
}
