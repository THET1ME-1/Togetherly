import '../dict_strings.dart';

/// Человеческое название типа воспоминания.
///
/// Типы приходят с сервера как есть (`memories.type`) и в интерфейсе видны
/// пользователю — в легенде статистики, фильтрах, подписях. Список неполный
/// давал сырые `videoLink` и `location` прямо на экране, поэтому он собран в
/// одном месте и покрыт тестом: при добавлении нового типа тест падает раньше,
/// чем это увидит пара.
String memoryTypeLabel(String type) {
  switch (type) {
    case 'photo':
      return ruEn('Фото', 'Photo');
    case 'video':
      return ruEn('Видео', 'Video');
    case 'videoLink':
      return ruEn('Ссылка на видео', 'Video link');
    case 'text':
      return ruEn('Текст', 'Text');
    case 'music':
      return ruEn('Музыка', 'Music');
    case 'movie':
      return ruEn('Фильм', 'Movie');
    case 'book':
      return ruEn('Книга', 'Book');
    case 'location':
      return ruEn('Место', 'Place');
    case 'audio':
      return ruEn('Аудио', 'Audio');
    case '':
      return ruEn('Без типа', 'Untyped');
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
