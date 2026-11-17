import 'memory.dart';

/// С какой вкладки открывать форму-лист для типа, который не живёт в форме
/// «как фото».
///
/// Ссылка на видео своей формы не имеет: поле ссылки стоит в форме видео на
/// вкладке «По ссылке», и запись сохраняется типом `videoLink`, когда ссылка
/// вписана. Задания дня вида «Видео, которое…» приходят сюда типом
/// `videoLink`, и прежде форма открывалась пустой: название, описание и дата,
/// ни ссылки, ни файла.
({MemoryType type, bool byLink}) memoryFormEntry(MemoryType type) {
  if (type == MemoryType.video || type == MemoryType.videoLink) {
    return (type: MemoryType.video, byLink: true);
  }
  return (type: type, byLink: false);
}
