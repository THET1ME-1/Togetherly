// Карточка «партнёр прошёл тест» на главной: показывается один раз.
//
// Пользователь просил прямо: «не вечная будет висеть, пока не посмотришь».
// Поэтому она появляется, когда партнёр прошёл, а человек ещё нет, и исчезает
// навсегда после первого касания — прошёл или закрыл, всё равно.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/love_prompt.dart';

void main() {
  test('партнёр прошёл, я нет — показываем', () {
    expect(
      showLovePrompt(partnerDone: true, mineDone: false, dismissed: false),
      isTrue,
    );
  });

  test('уже закрыли или прошли — больше не показываем', () {
    expect(
      showLovePrompt(partnerDone: true, mineDone: false, dismissed: true),
      isFalse,
    );
    expect(
      showLovePrompt(partnerDone: true, mineDone: true, dismissed: false),
      isFalse,
    );
  });

  test('партнёр ещё не проходил — звать не с чем', () {
    expect(
      showLovePrompt(partnerDone: false, mineDone: false, dismissed: false),
      isFalse,
    );
  });
}
