/// Откуда трек музыкального воспоминания.
///
/// Свой файл (`pb://`, `localfile://`) играет в приложении, ссылка на
/// сервис открывается снаружи — у таких записей нет файла, только адрес.
class MusicSource {
  const MusicSource({this.name, this.external = false, this.playable = false});

  /// Название сервиса для подписи «Открыть в …»; null — сервис незнакомый.
  final String? name;

  /// Ссылка снаружи: играть её приложение не умеет.
  final bool external;

  /// Есть ли что играть или открывать вовсе.
  final bool playable;
}

MusicSource musicSourceOf(String? url) {
  if (url == null || url.trim().isEmpty) return const MusicSource();
  final lower = url.toLowerCase();
  String? name;
  if (lower.contains('spotify')) {
    name = 'Spotify';
  } else if (lower.contains('music.youtube.com')) {
    name = 'YouTube Music';
  } else if (lower.contains('youtube') || lower.contains('youtu.be')) {
    name = 'YouTube';
  } else if (lower.contains('music.apple.com')) {
    name = 'Apple Music';
  } else if (lower.contains('deezer')) {
    name = 'Deezer';
  } else if (lower.contains('soundcloud')) {
    name = 'SoundCloud';
  } else if (lower.contains('music.yandex') ||
      lower.contains('yandex.ru/music')) {
    name = 'Яндекс Музыка';
  } else if (lower.contains('tidal.com')) {
    name = 'Tidal';
  } else if (lower.contains('vk.com/music') ||
      lower.contains('vk.com/audio') ||
      lower.contains('vk.ru/music')) {
    name = 'VK Музыка';
  }
  final external = name != null ||
      (lower.startsWith('http') && !lower.contains('firebase'));
  return MusicSource(name: name, external: external, playable: true);
}
