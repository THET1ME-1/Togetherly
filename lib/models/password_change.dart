/// Проверка полей смены пароля — до похода на сервер.
///
/// Человек, который уже вошёл, меняет пароль сам: вводит текущий и новый.
/// Письмо ему ни к чему, оно нужно только тому, кто пароль забыл или входил
/// через Google и Apple, — там пароля нет вовсе.
///
/// Сервер проверяет то же самое (`oldPassword` обязателен, минимум восемь
/// символов), но его отказ приходит по-английски и общей формулировкой, а
/// человеку нужно знать, какое из трёх полей поправить.
library;

/// Что не так с введённым. `null` — всё в порядке, можно отправлять.
PasswordChangeProblem? passwordChangeProblem({
  required String current,
  required String fresh,
  required String repeat,
}) {
  if (current.isEmpty) return PasswordChangeProblem.noCurrent;
  if (fresh.length < 8) return PasswordChangeProblem.tooShort;
  if (fresh != repeat) return PasswordChangeProblem.mismatch;
  // Пароль, равный прежнему, сервер примет молча — и человек решит, что смена
  // не сработала. Отвечаем сразу.
  if (fresh == current) return PasswordChangeProblem.same;
  return null;
}

enum PasswordChangeProblem { noCurrent, tooShort, mismatch, same }
