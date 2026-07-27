import '../services/locale_service.dart';

/// Человеческое название типа воспоминания.
///
/// Типы приходят с сервера как есть (`memories.type`) и в интерфейсе видны
/// пользователю — в легенде статистики, фильтрах, подписях. Список неполный
/// давал сырые `videoLink` и `location` прямо на экране, поэтому он собран в
/// одном месте и покрыт тестом: при добавлении нового типа тест падает раньше,
/// чем это увидит пара.
String memoryTypeLabel(String type) {
  final ru = LocaleService.instance.isRussian;
  switch (type) {
    case 'photo':
      return ru ? 'Фото' : 'Photo';
    case 'video':
      return ru ? 'Видео' : 'Video';
    case 'videoLink':
      return ru ? 'Ссылка на видео' : 'Video link';
    case 'text':
      return ru ? 'Текст' : 'Text';
    case 'music':
      return ru ? 'Музыка' : 'Music';
    case 'movie':
      return ru ? 'Фильм' : 'Movie';
    case 'book':
      return ru ? 'Книга' : 'Book';
    case 'location':
      return ru ? 'Место' : 'Place';
    case 'audio':
      return ru ? 'Аудио' : 'Audio';
    case '':
      return ru ? 'Без типа' : 'Untyped';
    default:
      return type;
  }
}

/// Все типы, которые встречаются в базе. Держать в согласии с
/// [memoryTypeLabel]: тест проверяет, что каждый из них переведён.
const List<String> kMemoryTypes = [
  'photo',
  'video',
  'videoLink',
  'text',
  'music',
  'movie',
  'book',
  'location',
  'audio',
  '',
];
