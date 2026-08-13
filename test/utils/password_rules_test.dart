import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/password_rules.dart';

void main() {
  group('hasSpecialChar', () {
    test('нижнее подчёркивание — спецсимвол', () {
      // Жалоба 13 августа 2026: «при создании пароля „_“ не считает
      // спецсимволом». В прежнем списке его просто не было.
      expect(hasSpecialChar('Parol_123'), isTrue);
    });

    test('дефис, плюс и скобки тоже', () {
      for (final p in ['Parol-123', 'Parol+123', 'Parol[123]', 'Parol=123']) {
        expect(hasSpecialChar(p), isTrue, reason: p);
      }
    });

    test('привычные знаки остались', () {
      for (final p in ['Parol!1', 'Parol@1', 'Parol#1', 'Parol.1']) {
        expect(hasSpecialChar(p), isTrue, reason: p);
      }
    });

    test('буквы и цифры спецсимволом не считаются', () {
      expect(hasSpecialChar('Parol123'), isFalse);
      expect(hasSpecialChar('ПарольДва2'), isFalse);
    });

    test('пробел за спецсимвол не считаем', () {
      // Иначе «Parol 1» пройдёт проверку, а человек этого не поймёт: пробел
      // в пароле не виден.
      expect(hasSpecialChar('Parol 1'), isFalse);
    });

    test('кириллический знак препинания считается', () {
      expect(hasSpecialChar('Пароль№1'), isTrue);
    });
  });

  group('passwordProblems', () {
    test('короткий пароль без заглавной и знака собирает все претензии', () {
      final problems = passwordProblems('abc');
      expect(problems, contains(PasswordProblem.tooShort));
      expect(problems, contains(PasswordProblem.noUppercase));
      expect(problems, contains(PasswordProblem.noSpecial));
    });

    test('годный пароль претензий не вызывает', () {
      expect(passwordProblems('Parol_123'), isEmpty);
    });

    test('восемь символов — уже достаточно длинный', () {
      expect(passwordProblems('Parol_12'), isEmpty);
      expect(passwordProblems('Parol_1'), contains(PasswordProblem.tooShort));
    });
  });
}
