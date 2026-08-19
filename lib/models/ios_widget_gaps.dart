/// Правила iPhone-виджетов, которые иначе живут внутри платформенных вызовов.
///
/// Оба вынесены сюда после разбора журнала 19 августа 2026: на телефонах их не
/// поймать, а на стенде — одной проверкой.
library;

/// Есть ли на этой системе интерактивность виджетов (кнопки внутри виджета).
///
/// Появилась в iOS 17. Ниже плагин отвечает
/// `PlatformException(-5, Interactivity is only available on iOS 17.0)`, и
/// отказ приходит асинхронно — синхронный `try` вокруг вызова его не ловит.
/// Так набежало 3649 событий за трое суток на версии 1.29.6.
///
/// [osVersion] — `Platform.operatingSystemVersion`, у iOS это строка вида
/// `Version 16.7.10 (Build 20H350)`. Не разобрали — считаем, что нет:
/// промолчать дешевле, чем получить необработанный отказ платформы.
bool supportsWidgetInteractivity(String osVersion) {
  final match = RegExp(r'(\d+)').firstMatch(osVersion);
  if (match == null) return false;
  final major = int.tryParse(match.group(1) ?? '');
  return major != null && major >= 17;
}

/// Что показать в виджете «Фото дня» на iPhone.
///
/// У этого виджета на айфоне нет настроек экземпляра, как на Android: там
/// человек выбирает «моё» или «партнёра» прямо на рабочем столе, здесь снимок
/// один. Берём снимок партнёра — ради него виджет и ставят, — а если у него
/// пусто, показываем своё.
///
/// `null` означает «запись не приехала» и своим снимком не подменяется: иначе
/// фоновая синхронизация без сети меняла бы фото партнёра на столе на своё.
({String url, String author}) iosDayPhoto({
  required List<String>? mine,
  required List<String>? theirs,
  required String myName,
  required String partnerName,
}) {
  if (theirs != null && theirs.isNotEmpty) {
    return (url: theirs.first, author: partnerName);
  }
  if (theirs == null) return (url: '', author: '');
  if (mine != null && mine.isNotEmpty) {
    return (url: mine.first, author: myName);
  }
  return (url: '', author: '');
}
