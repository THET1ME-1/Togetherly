/// Код пополнения и Togetherly+ из телеграм-бота: `TG-XXXX-XXXX`.
///
/// Алфавит без `0`, `O`, `1` и `I` — бот их не выдаёт намеренно (код диктуют
/// голосом и вводят руками с телефона, а эти четыре символа путают чаще всего,
/// см. `ALPHABET` в snt-bot/plus.py). Раз бот их не выдаёт, поле не должно их
/// принимать: иначе человек набирает «TG-O1..», получает отказ сервера и не
/// понимает, где ошибся.
class RedeemCode {
  const RedeemCode._();

  /// Символы, из которых код может состоять.
  static const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Длина кода без дефисов: две буквы префикса и восемь символов тела.
  static const int length = 10;

  /// Оставляет от введённого только то, что может быть кодом: прописные буквы
  /// алфавита, без дефисов и пробелов, не длиннее [length].
  static String digits(String input) {
    final buf = StringBuffer();
    for (final ch in input.toUpperCase().split('')) {
      if (!alphabet.contains(ch)) continue;
      buf.write(ch);
      if (buf.length == length) break;
    }
    return buf.toString();
  }

  /// Как код показывается человеку: `TG-4F2A-B19C`. Незаконченный показывается
  /// ровно настолько, насколько набран, — дефисы не забегают вперёд.
  static String formatted(String raw) {
    final s = digits(raw);
    if (s.length <= 2) return s;
    if (s.length <= 6) return '${s.substring(0, 2)}-${s.substring(2)}';
    return '${s.substring(0, 2)}-${s.substring(2, 6)}-${s.substring(6)}';
  }

  static bool isComplete(String raw) => digits(raw).length == length;
}
