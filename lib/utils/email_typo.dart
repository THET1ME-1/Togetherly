/// Опечатка в домене почты при регистрации (19.09.2026).
///
/// На проде около 1260 аккаунтов с доменом, которого не существует:
/// `gmail.con`, `gmai.com`, `icloud.con`, `gnail.com`. Письмо для смены пароля
/// туда не уходит, и человек теряет вход, как только выйдет из аккаунта.
/// Правило подсказывает исправление, а решает человек: редкий настоящий адрес
/// на похожем домене он оставит как есть.
library;

/// Домены с опечаткой в имени сервиса — точные ошибки с прода.
const Map<String, String> _misspelled = {
  'gmai.com': 'gmail.com',
  'gnail.com': 'gmail.com',
  'gamil.com': 'gmail.com',
  'gmal.com': 'gmail.com',
  'gmaill.com': 'gmail.com',
  'gmial.com': 'gmail.com',
  'gmali.com': 'gmail.com',
  'gmsil.com': 'gmail.com',
  'iclod.com': 'icloud.com',
  'icoud.com': 'icloud.com',
  'iclould.com': 'icloud.com',
  'icluod.com': 'icloud.com',
  'yandx.ru': 'yandex.ru',
  'yanex.ru': 'yandex.ru',
};

/// Сервисы, у которых домен верхнего уровня известен: у почты Google и Apple
/// он один — `.com`.
const _comOnly = {'gmail', 'icloud', 'hotmail', 'outlook', 'yahoo'};

/// Русские сервисы: `.tu` и `.ry` — соседние клавиши `.ru`. Настоящие
/// `yandex.by`, `yandex.kz`, `yandex.com`, `mail.com` не трогаем.
const _ruServices = {'mail', 'yandex', 'list', 'bk', 'inbox', 'rambler', 'ya'};
const _ruTypos = {'tu', 'ry', 'r', 'rj', 'eu'};

/// Верхний уровень, которого не бывает: промах мимо `.com`.
const _comTypos = {'con', 'cpm', 'vom', 'xom', 'cim', 'comm', 'coom', 'om', 'cm', 'c'};

/// Исправленный адрес, если в домене узнаётся опечатка, иначе `null`.
String? emailTypoFix(String email) {
  final e = email.trim();
  final at = e.lastIndexOf('@');
  if (at <= 0 || at == e.length - 1) return null;
  final local = e.substring(0, at);
  final domain = e.substring(at + 1).toLowerCase();
  final fixed = _fixDomain(domain);
  if (fixed == null || fixed == domain) return null;
  return '$local@$fixed';
}

String? _fixDomain(String domain) {
  final known = _misspelled[domain];
  if (known != null) return known;
  final dot = domain.lastIndexOf('.');
  if (dot <= 0) return null;
  final name = domain.substring(0, dot);
  final tld = domain.substring(dot + 1);
  if (_comOnly.contains(name) && tld != 'com') return '$name.com';
  if (_ruServices.contains(name) && _ruTypos.contains(tld)) return '$name.ru';
  if (_comTypos.contains(tld)) return '$name.com';
  return null;
}
