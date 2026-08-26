/// Что не считать багом приложения при отправке в Bugsink.
///
/// Панель крашей полезна ровно настолько, насколько в ней мало шума: обрывы
/// сокета на мобильной сети, запреты Android и мёртвые ссылки выключенного
/// Firebase легко дают больше половины всех событий и топят настоящие падения.
/// Предикаты живут отдельным файлом, потому что их проверяет
/// `test/services/crash_noise_test.dart` — из `main.dart` они были недоступны
/// тестам.
library;

import 'package:pocketbase/pocketbase.dart';

/// Фоновые ошибки, которые не роняют приложение: отказы прав и незагрузившийся
/// шрифт. Помечаем их non-fatal, чтобы не путать с настоящими падениями.
bool isBenignBackgroundError(Object error) {
  final s = error.toString();
  return s.contains('permission-denied') ||
      s.contains('permission_denied') ||
      s.contains('firebase_storage/unauthorized') ||
      s.contains('Failed to load font') ||
      // На случай редкого варианта Rubik, не вошедшего в бандл: текст просто
      // рисуется системным шрифтом, не краш.
      s.contains('allowRuntimeFetching');
}

/// Транспортные сетевые сбои = недоступность сервера или плохая сеть человека
/// (часто из-за блокировок в РФ), НЕ баги приложения.
bool isNetworkNoise(Object error) {
  final s = error.toString();
  if (s.contains('SocketException') ||
      s.contains('HandshakeException') ||
      s.contains('Connection closed') ||
      s.contains('Connection reset') ||
      s.contains('Connection refused') ||
      s.contains('Connection failed') ||
      s.contains('Connection terminated') ||
      s.contains('Connection abort') || // вкл. "Software caused connection abort"
      s.contains('Network is unreachable') ||
      s.contains('Connection timed out') ||
      s.contains('Operation timed out') ||
      s.contains('Bad file descriptor')) {
    return true;
  }
  // PocketBase ClientException транспортного уровня: запрос отменён / сервер не
  // ответил. 4xx/5xx (реальные ответы сервера) НЕ трогаем — они информативны.
  if (s.contains('ClientException') &&
      (s.contains('isAbort: true') || s.contains('statusCode: 0'))) {
    return true;
  }
  // PocketBase realtime (SSE) постоянно переподключается на мобильной сети:
  // /api/realtime отдаёт 400 при обрыве/реконнекте — это churn соединения, а не
  // баг. Глушим все ClientException этого эндпоинта независимо от статуса.
  if (s.contains('ClientException') && s.contains('/api/realtime')) {
    return true;
  }
  return false;
}

/// Что из отказов роутов монет НЕ надо показывать в панели крашей.
///
/// Разбор 26.08.2026 по четырёмстам последним событиям `/api/coins/daily-bonus`:
/// 217 — обрыв связи у человека (`statusCode: 0`, DPI и мобильная сеть), 108 —
/// 502 в окно перезапуска PocketBase после выкладки хука, 13 — протухшая
/// сессия. Настоящих серверных ошибок (500 «tx failed») всего 18. То есть
/// четыре пятых потока — шум, который топит эти восемнадцать.
///
/// Здесь режется именно шум: 4xx с внятным телом и 500 доезжают до панели.
bool isCoinsRouteNoise(Object error) {
  final s = error.toString();
  if (isNetworkNoise(error)) return true;
  // Окно перезапуска сервера и сбои прокси: клиент ни при чём, повтор пройдёт.
  if (s.contains('statusCode: 502') ||
      s.contains('statusCode: 503') ||
      s.contains('statusCode: 504')) {
    return true;
  }
  // Протухшая сессия лечится обновлением токена, а не разбором в панели.
  if (s.contains('statusCode: 401')) return true;
  return false;
}

/// Android 12+ (mAllowStartForeground) запрещает старт foreground-сервиса из
/// фона. Прямой путь старта обёрнут в try/catch, но плагин
/// flutter_foreground_task доставляет отказ ещё и асинхронным событием
/// EventChannel → оно всплывает мимо catch. Это ограничение ОС, а не баг.
bool isForegroundServiceRestriction(Object error) {
  final s = error.toString();
  return s.contains('startForeground() not allowed') ||
      s.contains('ForegroundServiceStartNotAllowed') ||
      s.contains('mAllowStartForeground');
}

/// Ссылки на выключенный Firebase Storage.
///
/// Проект Firebase отключён (уход на PocketBase), и старые записи, где лежит
/// прямой `https://firebasestorage.googleapis.com/...`, отвечают 402. Картинка
/// просто не покажется, чинить в клиенте нечего — но в Bugsink это давало 130
/// событий только на версиях 1.16.3–1.17.0.
bool isDeadFirebaseMedia(Object error) {
  final s = error.toString();
  return s.contains('firebasestorage.googleapis.com') &&
      (s.contains('402') || s.contains('403') || s.contains('404'));
}

/// Штатный отказ нашего роута, а не поломка.
///
/// PocketBase SDK бросает `ClientException` на любой не-2xx ответ, поэтому
/// «не хватает монет» и «уже куплено» приезжают в панель наравне с падениями:
/// одних только 402 на покупке иконки набралось 71 с конца июня у 23 человек.
/// Для человека это обычный ход дела — кнопка ответила, что монет мало.
bool isRoutineRouteRefusal(Object error) {
  if (error is! ClientException) return false;
  final code = error.statusCode;
  // Сервер прилёг или сломался — это ошибка, её показываем.
  if (code >= 500 || code == 0) return false;
  // Отказ по существу приходит с объяснением в теле; без него разбирать нечего.
  final reason = error.response['error'];
  if (reason is! String || reason.isEmpty) return false;
  const routine = {
    'insufficient',
    'alreadyOwned',
    'alreadyGranted',
    'already',
    'not_enough_coins',
    'limit',
  };
  return routine.contains(reason);
}

/// Событие вообще не стоит слать в Bugsink.
bool isCrashNoise(Object error) =>
    isNetworkNoise(error) ||
    isForegroundServiceRestriction(error) ||
    isDeadFirebaseMedia(error) ||
    isRoutineRouteRefusal(error);
