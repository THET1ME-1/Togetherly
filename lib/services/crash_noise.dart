/// Что не считать багом приложения при отправке в Bugsink.
///
/// Панель крашей полезна ровно настолько, насколько в ней мало шума: обрывы
/// сокета на мобильной сети, запреты Android и мёртвые ссылки выключенного
/// Firebase легко дают больше половины всех событий и топят настоящие падения.
/// Предикаты живут отдельным файлом, потому что их проверяет
/// `test/services/crash_noise_test.dart` — из `main.dart` они были недоступны
/// тестам.
library;

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

/// Событие вообще не стоит слать в Bugsink.
bool isCrashNoise(Object error) =>
    isNetworkNoise(error) ||
    isForegroundServiceRestriction(error) ||
    isDeadFirebaseMedia(error);
