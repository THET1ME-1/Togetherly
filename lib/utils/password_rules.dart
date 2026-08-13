/// Требования к паролю: восемь символов, заглавная буква и знак.
///
/// Раньше знаки были перечислены списком `[!@#$%^&*(),.?":{}|<>]`, и всё, что
/// в него не попало, проверку не проходило: человек набирал `Parol_123`,
/// приложение отвечало, что спецсимвола нет («при создании пароля „_“ не
/// считает спец символом», 13 августа 2026). Список пришлось бы дополнять
/// вечно — дефис, плюс, скобки, тильда, кириллический №.
///
/// Поэтому правило перевёрнуто: спецсимвол — это всё, что НЕ буква и не цифра.
/// Пробел исключён намеренно: в поле пароля его не видно, и «Parol 1» выглядел
/// бы прошедшим проверку без всякой причины.
enum PasswordProblem { tooShort, noUppercase, noSpecial }

const int kPasswordMinLength = 8;

final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
final RegExp _uppercase = RegExp(r'[\p{Lu}]', unicode: true);

/// Есть ли в пароле знак — любой символ, кроме букв, цифр и пробелов.
bool hasSpecialChar(String password) {
  for (final rune in password.runes) {
    final ch = String.fromCharCode(rune);
    if (ch.trim().isEmpty) continue; // пробелы и переводы строк не в счёт
    if (!_letterOrDigit.hasMatch(ch)) return true;
  }
  return false;
}

/// Чего паролю не хватает. Пустой список — годится.
Set<PasswordProblem> passwordProblems(String password) {
  return {
    if (password.length < kPasswordMinLength) PasswordProblem.tooShort,
    if (!_uppercase.hasMatch(password)) PasswordProblem.noUppercase,
    if (!hasSpecialChar(password)) PasswordProblem.noSpecial,
  };
}
