import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import '../dict_strings.dart';
import '../services/locale_service.dart';
import '../utils/pair_time.dart';

/// Предустановленные настроения с цветами.
class MoodOption {
  final String id;
  final String imagePath;
  final String label;
  final Color color;

  /// Для НОВЫХ эмоций из удалённого каталога, чьего id нет в сборке:
  /// английская метка и «тир» (score) приходят из манифеста. Для встроенных
  /// настроений — null (метка/score берутся из switch'ей по id ниже).
  final String? labelEn;
  final int? scoreOverride;

  const MoodOption({
    required this.id,
    required this.imagePath,
    required this.label,
    required this.color,
    this.labelEn,
    this.scoreOverride,
  });

  /// Метка настроения на текущем языке.
  ///
  /// Встроенные настроения лежат в словаре (`lib/l10n/dict/moods.dart`), где
  /// язык — колонка. Настроение из серверного пака в сборке неизвестно: его
  /// метка приходит манифестом, поэтому остаётся выбор из того, что дали.
  String get localizedLabel {
    final key = 'mood_$id';
    if (kStrings.containsKey(key)) return trKey(key);
    return LocaleService.instance.isRussian ? label : (labelEn ?? label);
  }

  int get score {
    if (scoreOverride != null) return scoreOverride!;
    switch (id) {
      case 'happy':
      case 'love':
      case 'laugh':
      case 'kiss':
        return 5;
      case 'winking':
      case 'pride':
      case 'cool':
      case 'drooling':
      case 'bliss':
        return 4;
      case 'no_emotion':
      case 'embarrassed':
      case 'surprise':
      case 'liar':
      case 'sleepy':
      case 'tired':
        return 3;
      case 'sad':
      case 'sick':
      case 'hurt':
      case 'missing':
      case 'anxiety':
      case 'disappointed':
      case 'upset':
        return 2;
      case 'very_sad':
      case 'anger':
      case 'devil':
      case 'fear':
        return 1;
      default:
        return 3;
    }
  }

  // Цвета соответствуют фонам картинок из папки «new emodji».
  static const _yellow = Color(
    0xFFFFC800,
  ); // Счастье, Смех, Гордость, Подмигиваю, Крутой
  static const _pink = Color(0xFFF06EAF); // Люблю, Целую, Смущен
  static const _slate = Color(0xFF7A7FA8); // Нет эмоций, Скучаю, Болен
  static const _blue = Color(0xFF6E8FBF); // Грустно, Очень грустно
  static const _purple = Color(0xFFA066D8); // Тревожность, Страх, Удивление
  static const _red = Color(0xFFFA282F); // Злость, Дьявол, Врунишка
  static const _skyBlue = Color(0xFF62B8E8); // Слюни текут

  static const List<MoodOption> all = [
    MoodOption(
      id: 'happy',
      imagePath: 'assets/images/new emodji/Счастье.webp',
      label: 'Счастье',
      color: _yellow,
    ),
    MoodOption(
      id: 'love',
      imagePath: 'assets/images/new emodji/Люблю.webp',
      label: 'Люблю',
      color: _pink,
    ),
    MoodOption(
      id: 'kiss',
      imagePath: 'assets/images/new emodji/Целую.webp',
      label: 'Целую',
      color: _pink,
    ),
    MoodOption(
      id: 'laugh',
      imagePath: 'assets/images/new emodji/Смех.webp',
      label: 'Смех',
      color: _yellow,
    ),
    MoodOption(
      id: 'pride',
      imagePath: 'assets/images/new emodji/Гордость.webp',
      label: 'Гордость',
      color: _yellow,
    ),
    MoodOption(
      id: 'cool',
      imagePath: 'assets/images/new emodji/Крутой.webp',
      label: 'Крутой',
      color: _yellow,
    ),
    MoodOption(
      id: 'winking',
      imagePath: 'assets/images/new emodji/Подмигиваю.webp',
      label: 'Подмигиваю',
      color: _yellow,
    ),
    MoodOption(
      id: 'drooling',
      imagePath: 'assets/images/new emodji/Слюни текут.webp',
      label: 'Слюни текут',
      color: _skyBlue,
    ),
    MoodOption(
      id: 'embarrassed',
      imagePath: 'assets/images/new emodji/Смущен.webp',
      label: 'Смущен',
      color: _pink,
    ),
    MoodOption(
      id: 'no_emotion',
      imagePath: 'assets/images/new emodji/Нет эмоций.webp',
      label: 'Нет эмоций',
      color: _slate,
    ),
    MoodOption(
      id: 'missing',
      imagePath: 'assets/images/new emodji/Скучаю.webp',
      label: 'Скучаю',
      color: _slate,
    ),
    MoodOption(
      id: 'sad',
      imagePath: 'assets/images/new emodji/Грустно.webp',
      label: 'Грустно',
      color: _blue,
    ),
    MoodOption(
      id: 'very_sad',
      imagePath: 'assets/images/new emodji/Очень грустно.webp',
      label: 'Очень грустно',
      color: _blue,
    ),
    MoodOption(
      id: 'hurt',
      imagePath: 'assets/images/new emodji/Обида.webp',
      label: 'Обида',
      color: _red,
    ),
    MoodOption(
      id: 'liar',
      imagePath: 'assets/images/new emodji/Врунишка.webp',
      label: 'Врунишка',
      color: _red,
    ),
    MoodOption(
      id: 'anxiety',
      imagePath: 'assets/images/new emodji/Тревожность.webp',
      label: 'Тревожность',
      color: _purple,
    ),
    MoodOption(
      id: 'sick',
      imagePath: 'assets/images/new emodji/Болен.webp',
      label: 'Болен',
      color: _slate,
    ),
    MoodOption(
      id: 'surprise',
      imagePath: 'assets/images/new emodji/Удивление.webp',
      label: 'Удивление',
      color: _purple,
    ),
    MoodOption(
      id: 'fear',
      imagePath: 'assets/images/new emodji/Страх.webp',
      label: 'Страх',
      color: _purple,
    ),
    MoodOption(
      id: 'anger',
      imagePath: 'assets/images/new emodji/Злость.webp',
      label: 'Злость',
      color: _red,
    ),
    MoodOption(
      id: 'devil',
      imagePath: 'assets/images/new emodji/Дьявол.webp',
      label: 'Дьявол',
      color: _red,
    ),
  ];

  // ── Pink pack (бесплатный) — каваи-стикеры с прозрачным фоном ──────────────
  // id переиспользуют классические, где эмоция совпадает (тогда score, цвет
  // в календаре и слияние в статистике работают «из коробки»). Уникальные для
  // пака настроения (bliss/sleepy/disappointed/upset) добавлены в switch'и
  // score/localizedLabel выше. color = цвет «тира» эмоции — для подсветки в
  // пикере и точек календаря, чтобы шкала настроения оставалась единой.
  static const String _pinkDir = 'assets/images/mood_packs/pink';
  static const List<MoodOption> pinkPack = [
    MoodOption(
      id: 'happy',
      imagePath: '$_pinkDir/happy.webp',
      label: 'Радость',
      color: _yellow,
    ),
    MoodOption(
      id: 'love',
      imagePath: '$_pinkDir/love.webp',
      label: 'Влюблён',
      color: _pink,
    ),
    MoodOption(
      id: 'kiss',
      imagePath: '$_pinkDir/kiss.webp',
      label: 'Целую',
      color: _pink,
    ),
    MoodOption(
      id: 'laugh',
      imagePath: '$_pinkDir/laugh.webp',
      label: 'Смешно',
      color: _yellow,
    ),
    MoodOption(
      id: 'bliss',
      imagePath: '$_pinkDir/bliss.webp',
      label: 'Наслаждение',
      color: _yellow,
    ),
    MoodOption(
      id: 'cool',
      imagePath: '$_pinkDir/cool.webp',
      label: 'Крутая',
      color: _yellow,
    ),
    MoodOption(
      id: 'winking',
      imagePath: '$_pinkDir/winking.webp',
      label: 'Подмигиваю',
      color: _yellow,
    ),
    MoodOption(
      id: 'drooling',
      imagePath: '$_pinkDir/drooling.webp',
      label: 'Слюни текут',
      color: _skyBlue,
    ),
    MoodOption(
      id: 'embarrassed',
      imagePath: '$_pinkDir/embarrassed.webp',
      label: 'Смущение',
      color: _pink,
    ),
    MoodOption(
      id: 'no_emotion',
      imagePath: '$_pinkDir/no_emotion.webp',
      label: 'Нет эмоций',
      color: _slate,
    ),
    MoodOption(
      id: 'surprise',
      imagePath: '$_pinkDir/surprise.webp',
      label: 'Удивление',
      color: _purple,
    ),
    MoodOption(
      id: 'sleepy',
      imagePath: '$_pinkDir/sleepy.webp',
      label: 'Сплю',
      color: _slate,
    ),
    MoodOption(
      id: 'tired',
      imagePath: '$_pinkDir/tired.webp',
      label: 'Устала',
      color: _slate,
    ),
    MoodOption(
      id: 'missing',
      imagePath: '$_pinkDir/missing.webp',
      label: 'Скучаю',
      color: _slate,
    ),
    MoodOption(
      id: 'sad',
      imagePath: '$_pinkDir/sad.webp',
      label: 'Грусть',
      color: _blue,
    ),
    MoodOption(
      id: 'sick',
      imagePath: '$_pinkDir/sick.webp',
      label: 'Болен',
      color: _slate,
    ),
    MoodOption(
      id: 'anxiety',
      imagePath: '$_pinkDir/anxiety.webp',
      label: 'Тревожность',
      color: _purple,
    ),
    MoodOption(
      id: 'disappointed',
      imagePath: '$_pinkDir/disappointed.webp',
      label: 'Разочарование',
      color: _blue,
    ),
    MoodOption(
      id: 'upset',
      imagePath: '$_pinkDir/upset.webp',
      label: 'Расстроена',
      color: _blue,
    ),
    MoodOption(
      id: 'very_sad',
      imagePath: '$_pinkDir/very_sad.webp',
      label: 'Плачу',
      color: _blue,
    ),
    MoodOption(
      id: 'fear',
      imagePath: '$_pinkDir/fear.webp',
      label: 'Страх',
      color: _purple,
    ),
    MoodOption(
      id: 'anger',
      imagePath: '$_pinkDir/anger.webp',
      label: 'Злость',
      color: _red,
    ),
  ];

  // ── Bunny pack — каваи-зайка, единый стиль ───────────────────────────────
  // Двадцать одна эмоция, порядок тот же, что у остальных паков: сперва
  // светлые, потом ровные, дальше грустные и злые. Так шкала настроения
  // читается одинаково, каким бы паком человек ни пользовался.
  static const String _bunnyDir = 'assets/images/mood_packs/bunny';
  static const List<MoodOption> bunnyPack = [
    MoodOption(
      id: 'love',
      imagePath: '$_bunnyDir/love.webp',
      label: 'Люблю',
      color: _pink,
    ),
    MoodOption(
      id: 'kiss',
      imagePath: '$_bunnyDir/kiss.webp',
      label: 'Целую',
      color: _pink,
    ),
    MoodOption(
      id: 'laugh',
      imagePath: '$_bunnyDir/laugh.webp',
      label: 'Смех',
      color: _yellow,
    ),
    MoodOption(
      id: 'bliss',
      imagePath: '$_bunnyDir/bliss.webp',
      label: 'Наслаждение',
      color: _yellow,
    ),
    MoodOption(
      id: 'pride',
      imagePath: '$_bunnyDir/pride.webp',
      label: 'Гордость',
      color: _yellow,
    ),
    MoodOption(
      id: 'cool',
      imagePath: '$_bunnyDir/cool.webp',
      label: 'Крутой',
      color: _yellow,
    ),
    MoodOption(
      id: 'winking',
      imagePath: '$_bunnyDir/winking.webp',
      label: 'Подмигиваю',
      color: _yellow,
    ),
    MoodOption(
      id: 'drooling',
      imagePath: '$_bunnyDir/drooling.webp',
      label: 'Слюни текут',
      color: _skyBlue,
    ),
    MoodOption(
      id: 'embarrassed',
      imagePath: '$_bunnyDir/embarrassed.webp',
      label: 'Смущение',
      color: _pink,
    ),
    MoodOption(
      id: 'surprise',
      imagePath: '$_bunnyDir/surprise.webp',
      label: 'Удивление',
      color: _purple,
    ),
    MoodOption(
      id: 'no_emotion',
      imagePath: '$_bunnyDir/no_emotion.webp',
      label: 'Нет эмоций',
      color: _slate,
    ),
    MoodOption(
      id: 'sleepy',
      imagePath: '$_bunnyDir/sleepy.webp',
      label: 'Сплю',
      color: _slate,
    ),
    MoodOption(
      id: 'tired',
      imagePath: '$_bunnyDir/tired.webp',
      label: 'Устала',
      color: _slate,
    ),
    MoodOption(
      id: 'missing',
      imagePath: '$_bunnyDir/missing.webp',
      label: 'Скучаю',
      color: _slate,
    ),
    MoodOption(
      id: 'sick',
      imagePath: '$_bunnyDir/sick.webp',
      label: 'Болен',
      color: _slate,
    ),
    MoodOption(
      id: 'sad',
      imagePath: '$_bunnyDir/sad.webp',
      label: 'Грусть',
      color: _blue,
    ),
    MoodOption(
      id: 'disappointed',
      imagePath: '$_bunnyDir/disappointed.webp',
      label: 'Разочарование',
      color: _blue,
    ),
    MoodOption(
      id: 'hurt',
      imagePath: '$_bunnyDir/hurt.webp',
      label: 'Обида',
      color: _red,
    ),
    MoodOption(
      id: 'anxiety',
      imagePath: '$_bunnyDir/anxiety.webp',
      label: 'Тревожность',
      color: _purple,
    ),
    MoodOption(
      id: 'liar',
      imagePath: '$_bunnyDir/liar.webp',
      label: 'Врунишка',
      color: _red,
    ),
    MoodOption(
      id: 'anger',
      imagePath: '$_bunnyDir/anger.webp',
      label: 'Злость',
      color: _red,
    ),
  ];

  /// Все ВСТРОЕННЫЕ настроения — для поиска по id/пути. Классические идут
  /// первыми, поэтому для общих id [byId] возвращает каноничный (классический)
  /// вариант (его метку/цвет видно в статистике и календаре).
  static const List<MoodOption> registry = [...all, ...pinkPack, ...bunnyPack];

  /// Настроения из УДАЛЁННОГО каталога (паки, скачанные манифестом). Нужны,
  /// чтобы у НОВЫХ эмоций (id которых нет в сборке) корректно резолвились
  /// цвет/score/метка в календаре и статистике. Наполняется CatalogService при
  /// старте. Встроенные ищем первыми (канон), удалённые — фолбэком.
  static List<MoodOption> _remote = const [];

  /// Зарегистрировать настроения удалённых паков (вызывает CatalogService).
  static void registerRemoteMoods(List<MoodOption> moods) {
    _remote = List.unmodifiable(moods);
  }

  static MoodOption? byId(String id) {
    for (final m in registry) {
      if (m.id == id) return m;
    }
    for (final m in _remote) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Найти настроение по пути к картинке (нужно, когда сохранён только
  /// imagePath — напр. при авто-отправке настроения из виджета в календарь).
  static MoodOption? byImagePath(String path) {
    if (path.isEmpty) return null;
    for (final m in _remote) {
      if (m.imagePath == path) return m;
    }
    for (final m in registry) {
      if (m.imagePath == path) return m;
    }
    return null;
  }

  /// Свежий адрес той же картинки, если пак каталога перезаливали.
  ///
  /// В отметке настроения лежит АБСОЛЮТНЫЙ адрес картинки — так партнёр видит
  /// именно тот набор, которым отметились, даже если у него выбран другой. Но
  /// PocketBase при каждой заливке даёт файлам новые имена, и после обновления
  /// пака все прежние отметки начинали ссылаться на удалённые файлы: 404,
  /// вместо картинки классический фолбэк. Ровно так «пропала» анимация пёсика
  /// на главном и в календаре — старые отметки показывали не его.
  ///
  /// Поэтому адрес разбирается на пак и настроение и ищется в текущем
  /// каталоге. Имя файла PocketBase выглядит как `<id>_<10 символов>.webp`,
  /// а id настроения сам может содержать `_` (`no_emotion`, `very_sad`) —
  /// отсюда отсечка по длине суффикса, а не по первому подчёркиванию.
  /// Возвращает null, если адрес и так актуален или пака в каталоге нет.
  static String? freshRemotePath(String path) {
    const marker = '/catalog_items/';
    final at = path.indexOf(marker);
    if (at < 0) return null;
    final tail = path.substring(at + marker.length);
    final slash = tail.indexOf('/');
    if (slash <= 0) return null;
    final packId = tail.substring(0, slash);
    var file = tail.substring(slash + 1);
    final q = file.indexOf('?');
    if (q > 0) file = file.substring(0, q);
    final dot = file.lastIndexOf('.');
    final base = dot > 0 ? file.substring(0, dot) : file;
    if (base.length <= 11) return null;
    final id = base.substring(0, base.length - 11);

    for (final m in _remote) {
      if (m.id != id) continue;
      if (!m.imagePath.contains('$marker$packId/')) continue;
      return m.imagePath == path ? null : m.imagePath;
    }
    return null;
  }

  /// Эквивалентная картинка из КЛАССИЧЕСКОГО пака для [path] по id настроения.
  /// Классический пак входит в любую сборку (самые старые ассеты), поэтому это
  /// безопасный фолбэк, когда картинка из нового пака отсутствует в текущей
  /// сборке — например, партнёр прислал настроение из пака, которого нет в
  /// нашей версии приложения (постепенный раскат). id переиспользуются между
  /// паками, а имена файлов новых паков совпадают с id (happy.webp → happy).
  /// Возвращает null, если [path] уже из классического пака или соответствие
  /// не найдено.
  static String? classicFallbackFor(String path) {
    if (path.isEmpty) return null;
    for (final m in all) {
      if (m.imagePath == path)
        return null; // уже классический — фолбэк не нужен
    }
    var id = byImagePath(path)?.id;
    id ??= path.split('/').last.split('.').first; // имя файла без расширения
    for (final m in all) {
      if (m.id == id) return m.imagePath;
    }
    return null;
  }
}

/// Одна запись настроения за определённое время.
class MoodEntry {
  final String id;
  final String moodId; // id из MoodOption
  final String imagePath;
  final String label;

  /// Время отметки в часах читателя. У записей до 13 августа 2026 тут часы
  /// автора: пояс тогда не сохранялся, см. [PairTime].
  final DateTime timestamp;

  /// Пояс автора (`+03:00`). Пусто — запись старая.
  final String zone;

  /// Сутки, в которые отметился автор. Он ставил настроение «за сегодня»,
  /// поэтому в календаре партнёра отметка лежит в дне автора, даже если у
  /// читателя уже завтра.
  final DateTime authorDate;

  MoodEntry({
    required this.id,
    required this.moodId,
    required this.imagePath,
    required this.label,
    required this.timestamp,
    this.zone = '',
    DateTime? authorDate,
  }) : authorDate = authorDate ??
            DateTime(timestamp.year, timestamp.month, timestamp.day);

  Color get color => MoodOption.byId(moodId)?.color ?? const Color(0xFF9CA3AF);
  int get score => MoodOption.byId(moodId)?.score ?? 3;

  /// Метка на текущем языке приложения (перевод по id, не хранимая строка).
  String get localizedLabel => MoodOption.byId(moodId)?.localizedLabel ?? label;

  Map<String, dynamic> toJson() => {
    'id': id,
    'moodId': moodId,
    'imagePath': imagePath,
    'label': label,
    'timestamp': PairTime.write(timestamp),
    'tz': zone.isEmpty ? PairTime.zoneNow() : zone,
  };

  factory MoodEntry.fromJson(Map<String, dynamic> json) {
    final zone = (json['tz'] ?? '').toString();
    return MoodEntry(
      id: json['id'] as String,
      moodId: json['moodId'] as String,
      imagePath: json['imagePath'] as String,
      label: json['label'] as String,
      timestamp: PairTime.read(json['timestamp'], zone) ?? DateTime.now(),
      zone: zone,
      authorDate: PairTime.authorDay(json['timestamp'], zone),
    );
  }

  /// PocketBase-запись (коллекция `mood_entries`) → модель. Плоские snake_case
  /// колонки; id = id записи; timestamp — ISO-строка в UTC, `tz` — пояс автора.
  factory MoodEntry.fromPb(RecordModel rec) {
    final d = rec.data;
    final raw = (d['timestamp'] ?? '').toString();
    final zone = (d['tz'] ?? '').toString();
    return MoodEntry(
      id: rec.id,
      moodId: (d['mood_id'] ?? '').toString(),
      imagePath: (d['image_path'] ?? '').toString(),
      label: (d['label'] ?? '').toString(),
      timestamp: PairTime.read(raw, zone) ?? DateTime.now(),
      zone: zone,
      authorDate: PairTime.authorDay(raw, zone),
    );
  }

  /// Дневной ключ для группировки (yyyy-MM-dd) — по суткам автора.
  String get dayKey {
    final y = authorDate.year.toString().padLeft(4, '0');
    final m = authorDate.month.toString().padLeft(2, '0');
    final d = authorDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
