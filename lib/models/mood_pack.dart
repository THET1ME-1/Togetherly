import 'package:flutter/material.dart';
import '../services/locale_service.dart';
import 'level.dart';
import 'mood_entry.dart';

/// Набор настроений («пак») — например классические эмодзи или розовые каваи.
///
/// Настроение хранит в записи свой [MoodOption.imagePath], поэтому партнёр
/// видит выбранную картинку независимо от того, какой пак выбран у него. Выбор
/// пака — это только то, из какого набора пользователь выбирает у себя
/// (хранится локально в [MoodPackService]).
class MoodPack {
  /// Идентификатор пака (для сохранения выбора).
  final String id;

  /// Бесплатные паки доступны всем без покупки. Pink и Classic — бесплатные.
  /// Флаг оставлен ради будущих платных паков.
  final bool isFree;

  /// Настроения пака (порядок = порядок в пикере).
  final List<MoodOption> moods;

  /// Мягкая подложка под прозрачными стикерами в пикере (от/до для градиента).
  /// null — картинки пака непрозрачные (классические), фон не нужен.
  final List<Color>? tileGradient;

  final String _nameRu;
  final String _nameEn;

  /// Требование разблокировки (для каталожных паков). Встроенные — free.
  final Unlock unlock;

  /// Кто нарисовал пак. Подписывает его в конце листа выбора настроения;
  /// пустая строка означает «наш», подписи не будет. Ссылок тут нет намеренно:
  /// это подпись под работой, а не переход на чужую площадку.
  final String author;

  /// Место в ленте паков — меньше значит левее. Встроенные и каталожные паки
  /// стоят в одном ряду, поэтому и порядок у них общий: у записи каталога это
  /// поле `sort`, и новый пак можно поставить между классическими и розовыми
  /// без выпуска сборки.
  final int sort;

  const MoodPack({
    required this.id,
    required this.isFree,
    required this.moods,
    required String nameRu,
    required String nameEn,
    this.tileGradient,
    this.unlock = const Unlock.free(),
    this.author = '',
    this.sort = 500,
  })  : _nameRu = nameRu,
        _nameEn = nameEn;

  String get name => LocaleService.instance.isRussian ? _nameRu : _nameEn;

  /// Картинка для превью пака в селекторе (первое настроение).
  String get previewImage => moods.isNotEmpty ? moods.first.imagePath : '';

  // ── Каталог ────────────────────────────────────────────────────────────────

  static const MoodPack classic = MoodPack(
    id: 'classic',
    isFree: true,
    nameRu: 'Классические',
    nameEn: 'Classic',
    moods: MoodOption.all,
    sort: 0,
  );

  static const MoodPack pink = MoodPack(
    id: 'pink',
    isFree: true,
    nameRu: 'Розовые',
    nameEn: 'Pink',
    moods: MoodOption.pinkPack,
    tileGradient: [Color(0xFFFFF2F8), Color(0xFFFFDCEC)],
    sort: 100,
  );

  /// Каваи-зайка: двадцать одна эмоция, весь набор нарисован.
  static const MoodPack bunny = MoodPack(
    id: 'bunny',
    isFree: true,
    nameRu: 'Зайка',
    nameEn: 'Bunny',
    moods: MoodOption.bunnyPack,
    tileGradient: [Color(0xFFFFF4F8), Color(0xFFFFE1EC)],
    sort: 110,
  );

  static const List<MoodPack> all = [classic, pink, bunny];

  /// Пак по id; неизвестный/`null` → классический (безопасный дефолт).
  static MoodPack byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return classic;
  }
}

/// Паки в порядке ленты: сперва [MoodPack.sort], при равенстве — прежнее место.
///
/// Отдельной функцией, потому что `List.sort` в Dart не обещает устойчивости:
/// два пака с одинаковым sort иначе меняются местами от запуска к запуску, и
/// лента настроений «дёргается» без единой правки каталога.
List<MoodPack> orderedPacks(Iterable<MoodPack> packs) {
  final list = packs.toList();
  final indexed = [
    for (var i = 0; i < list.length; i++) (pack: list[i], at: i),
  ];
  indexed.sort((a, b) {
    final bySort = a.pack.sort.compareTo(b.pack.sort);
    return bySort != 0 ? bySort : a.at.compareTo(b.at);
  });
  return [for (final e in indexed) e.pack];
}

/// Показывать ли пак в ленте выбора.
///
/// На iPhone платного за деньги набора нет вовсе: вести на оплату мимо биллинга
/// Apple запрещает 3.1.1, поэтому там не показываем ни витрины, ни цены. Но
/// уже открытый набор виден и на iPhone — купить его могли и на Android, и на
/// сайте, а покупка общая на пару. Отбирать оплаченное из-за платформы нельзя.
bool moodPackVisible({
  required bool isIOS,
  required bool isMoney,
  required bool isOpen,
}) =>
    !(isIOS && isMoney && !isOpen);
