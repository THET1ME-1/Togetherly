import '../dict_strings.dart';
import '../services/locale_service.dart';

/// Строка ёлки из словаря (`l10n/dict/xmas.dart`) с подстановкой `{имя}`.
String xt(String key, [Map<String, Object> args = const {}]) {
  var s = trKey(key);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Форма слова к числу: `.1`, `.2` или `.5` ключа [base] (`xt.toys`, `xt.days`).
/// Русский и украинский — по трём формам, остальные — «один / много».
String xtWord(int n, String base) {
  final code = LocaleService.instance.language.code;
  return trKey('$base.${xtPluralForm(n, code)}');
}

int xtPluralForm(int n, String code) {
  if (code == 'ru' || code == 'uk') {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 1;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 2;
    return 5;
  }
  return n == 1 ? 1 : 5;
}
