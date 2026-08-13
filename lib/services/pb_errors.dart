/// Как читать отказы PocketBase.
///
/// Ночь 14 августа 2026: сервер захлёбывался на записи, и в журнале за двадцать
/// минут лежало больше полутора тысяч отказов «Value must be unique». Это не
/// поломка данных — это повторные попытки создать то, что уже создано:
/// предыдущий запрос дошёл до сервера, а ответ до телефона нет. Очередь
/// считала такой отказ провалом и повторяла операцию до пяти раз, занимая
/// единственного писателя базы впустую.
library;

import 'package:pocketbase/pocketbase.dart';

/// Отказ означает «такая запись уже есть».
///
/// PocketBase отвечает 400, а в теле называет поля, нарушившие уникальность:
/// первичный ключ (`id`) или составной индекс (`group_id` + `user_uid` и
/// подобные). Для идемпотентной записи это подтверждение, а не ошибка.
bool alreadyExists(Object? error) {
  if (error is! ClientException) return false;
  if (error.statusCode != 400) return false;
  return error.response.toString().contains('Value must be unique');
}

/// Запись не найдена — или её не отдают правила доступа.
///
/// PocketBase намеренно не различает эти случаи: чужую запись он прячет тем же
/// 404, чтобы по ответам нельзя было перебрать чужие данные. Значит и клиенту
/// нельзя считать 404 доказательством того, что записи нет.
bool notFound(Object? error) =>
    error is ClientException && error.statusCode == 404;

/// Сервер попросил притормозить.
bool tooManyRequests(Object? error) =>
    error is ClientException && error.statusCode == 429;

/// Ответа не было вовсе: обрыв, таймаут, DPI провайдера. Такое повторяют,
/// в отличие от отказа по существу.
bool noAnswer(Object? error) =>
    error is ClientException && error.statusCode == 0;
