/// Файл из папки документов приложения, сохранённый в настройках.
///
/// Полный путь хранить нельзя: на iPhone папка приложения лежит под
/// `…/Data/Application/<UUID>/Documents`, и UUID меняется при КАЖДОМ
/// обновлении. Файл переезжает вместе с папкой, а записанный путь ведёт в
/// никуда. Так пропадал фон чата, купленный за монеты: чат не находил файл,
/// считал его удалённым и стирал настройку — «покупала четыре раза и ставила..
/// или это покупка на один день только?? или из-за обновления??» (отзыв,
/// 10.09.2026).
///
/// Поэтому в настройки кладётся имя файла, а папка подставляется при чтении.
/// Старые записи с полным путём читаются так же — по имени в конце.
library;

/// Что записать в настройки: только имя файла.
String documentsFileKey(String absolutePath) {
  final i = absolutePath.lastIndexOf('/');
  return i < 0 ? absolutePath : absolutePath.substring(i + 1);
}

/// Где файл лежит сейчас. null — в настройках пусто.
String? documentsFilePath(String? stored, String documentsDir) {
  if (stored == null || stored.isEmpty) return null;
  final name = documentsFileKey(stored);
  if (name.isEmpty) return null;
  return '$documentsDir/$name';
}
