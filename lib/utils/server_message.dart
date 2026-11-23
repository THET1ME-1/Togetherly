import '../dict_strings.dart';
import '../services/locale_service.dart';

/// Отказы сервера на языке приложения.
///
/// Маршруты пары (`invite.pb.js`, `waiting.pb.js`, `/internal/pair-accept` в
/// hotpath) отвечают текстом по-русски, и экраны показывали его как есть:
/// человек с английским приложением, введя неверный код, читал «Код не найден»
/// по-русски. Здесь известные отказы сверяются с английским образцом, а
/// незнакомый русский текст заменяется общей фразой [fallback].
const Map<String, String> kServerMessagesEn = {
  'Код не указан': 'No code entered',
  'Код повреждён': 'This code is damaged',
  'Это ваш собственный код!': 'This is your own code!',
  'Не удалось принять код': 'Couldn’t accept the code',
  'Код не найден. Пусть партнёр нажмёт «Новый код» и продиктует заново':
      'Code not found. Ask your partner to tap “New code” and read it out again',
  'Код не найден': 'Code not found',
  'Группа заполнена': 'This pair is already full',
  'Впишите имя': 'Enter a name',
  'Заявки нет': 'There is no request',
  'Место уже занято': 'This place is already taken',
  'Не сохранилось': 'Couldn’t save',
  'Не получилось': 'Something went wrong',
  'Не удалось создать пару': 'Couldn’t create the pair',
  'Не удалось выдать код': 'Couldn’t issue a code',
  'Не указана пара': 'No pair specified',
  'Пара не найдена': 'Pair not found',
  'Это не ваша пара': 'This is not your pair',
  'Не удалось отправить заявку': 'Couldn’t send the request',
  'У вас уже есть пара': 'You already have a pair',
  'У вас уже есть пара — выйдите из неё': 'You already have a pair — leave it first',
  // Отказы, которые собирает само приложение (`PbDataService.acceptInviteCode`).
  'Введите код': 'Enter the code',
  'Сессия истекла — войдите заново': 'Your session has expired — please sign in again',
  'Сервер не вернул пару': 'The server didn’t return the pair',
  'Ошибка приёма кода': 'Couldn’t accept the code',
};

final RegExp _cyrillic = RegExp('[А-Яа-яЁёІіЇїЄєҐґ]');

/// Текст отказа [message] на языке приложения; незнакомый русский — [fallback].
String serverMessageText(String message, {required String fallback}) {
  final text = message.trim();
  if (text.isEmpty) return fallback;
  if (LocaleService.instance.language == AppLanguage.ru) return text;
  final english = kServerMessagesEn[text];
  if (english != null) return trEnglish(english);
  return _cyrillic.hasMatch(text) ? fallback : text;
}
