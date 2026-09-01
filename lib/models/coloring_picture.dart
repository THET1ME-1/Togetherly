import '../services/locale_service.dart';

/// Кто какую половину раскраски красит.
enum ColoringSide {
  /// Левая половина — та, что открывает список участников (обычно она).
  left,

  /// Правая половина.
  right,
}

/// Видно ли половину партнёра во время работы.
enum ColoringMode {
  /// Сюрприз: чужая половина закрыта до тех пор, пока оба не нажмут «Готово».
  surprise,

  /// Вместе: видно, как партнёр красит, прямо сейчас.
  together;

  static ColoringMode fromStorage(String? raw) =>
      raw == 'together' ? ColoringMode.together : ColoringMode.surprise;

  String get storage => this == ColoringMode.together ? 'together' : 'surprise';
}

/// Чья половина листа: сравниваем uid, у кого меньше — тому левая.
///
/// Считается на каждом телефоне отдельно и должно давать зеркальный ответ,
/// поэтому никаких «кто первый зашёл»: только порядок uid. Регистр приводим —
/// иначе `ABC` и `abc` разошлись бы, и оба взяли бы одну половину.
/// Делится ли лист на половины.
///
/// Половины нужны только вдвоём. Пока партнёра нет — пара ещё не собралась или
/// её данные не доехали, — делить лист не на кого, и весь холст остаётся
/// рисующему. Иначе выходит «кисти не работают»: человек ведёт по правой
/// стороне, а касания туда не проходят, потому что сторона по умолчанию левая.
bool coloringSplitApplies(String partnerUid) => partnerUid.trim().isNotEmpty;

ColoringSide coloringSideFor(String myUid, String partnerUid,
    {bool swapped = false}) {
  if (partnerUid.isEmpty) return ColoringSide.left;
  final base = myUid.toLowerCase().compareTo(partnerUid.toLowerCase()) <= 0
      ? ColoringSide.left
      : ColoringSide.right;
  // Порядок uid ничего не знает о картинке: на одной половине бывает нарисован
  // мальчик, на другой девочка, и пара получает их наугад — «у меня выходит
  // сторона мальчика, а у него наоборот». Обмен половин пара включает сама, и
  // он общий на двоих (хранится в `canvas_meta.coloring_swap`), иначе половины
  // разъедутся.
  if (!swapped) return base;
  return base == ColoringSide.left ? ColoringSide.right : ColoringSide.left;
}

/// Раскраска из каталога.
///
/// Картинка — один PNG на 1600×1600 с прозрачным фоном: чёрный контур лежит
/// ПОВЕРХ мазков, поэтому закрасить сам рисунок нельзя, как ни старайся.
/// Вертикальная линия ровно посередине делит холст на две половины — левую и
/// правую, по одной на человека.
class ColoringPicture {
  const ColoringPicture({
    required this.id,
    required this.titleRu,
    required this.titleEn,
    this.ownRatio,
  });

  /// Своя раскраска: контур человек загрузил сам, лист любой пропорции.
  /// Граница половин при этом остаётся вертикальной по центру — доли равные
  /// при любом соотношении сторон.
  factory ColoringPicture.own({
    required String id,
    required String title,
    required double ratio,
  }) =>
      ColoringPicture(
          id: id, titleRu: title, titleEn: title, ownRatio: ratio);

  /// Пропорция листа для своей раскраски. У встроенных лист квадратный.
  final double? ownRatio;

  final String id;
  final String titleRu;
  final String titleEn;

  /// Контур с прозрачным фоном — кладётся поверх рисунка.
  /// Своя раскраска лежит файлом в папке приложения, встроенная — в ассетах.
  /// Отличаем по префиксу id, чтобы не тащить лишнее поле через canvas_meta:
  /// в паре синхронизируется именно id.
  bool get isOwn => isOwnId(id);

  /// Своя это раскраска, судя по id. Тот же признак, но до того, как картинка
  /// найдена: по холсту ходит один id, и по нему решается, где искать контур.
  static bool isOwnId(String id) => id.startsWith('own_');

  String get outlineAsset => 'assets/coloring/$id.png';

  /// Превью для каталога — уже на белой бумаге.
  String get thumbAsset => 'assets/coloring/${id}_thumb.jpg';

  String get title => LocaleService.instance.isRussian ? titleRu : titleEn;

  static const List<ColoringPicture> all = [
    ColoringPicture(id: 'cafe', titleRu: 'Кафе', titleEn: 'Cafe'),
    ColoringPicture(id: 'castle', titleRu: 'Замок', titleEn: 'Castle'),
    ColoringPicture(id: 'rain', titleRu: 'Дождь', titleEn: 'Rain'),
    ColoringPicture(id: 'ferris',
        titleRu: 'Колесо обозрения', titleEn: 'Ferris wheel'),
    ColoringPicture(id: 'metro', titleRu: 'Метро', titleEn: 'Metro'),
    ColoringPicture(id: 'camping', titleRu: 'Палатка', titleEn: 'Camping'),
    ColoringPicture(id: 'festival', titleRu: 'Фестиваль', titleEn: 'Festival'),
    ColoringPicture(id: 'baking', titleRu: 'Готовим вместе', titleEn: 'Baking'),
    ColoringPicture(id: 'beach', titleRu: 'Пляж', titleEn: 'Beach'),
    ColoringPicture(id: 'gaming', titleRu: 'Приставка', titleEn: 'Gaming'),
  ];

  /// Картинка по id.
  ///
  /// [own] — раскраски, которые человек загрузил сам: их нет в [all], а между
  /// экранами и в паре ходит только id. Пока их сюда не передавали, свой
  /// рисунок открывался пустым листом: id вида `own_…` не находился нигде,
  /// раскраска считалась невыбранной и контур не грузился вовсе.
  static ColoringPicture? byId(String? id,
      {List<ColoringPicture> own = const []}) {
    if (id == null || id.isEmpty) return null;
    for (final p in all) {
      if (p.id == id) return p;
    }
    for (final p in own) {
      if (p.id == id) return p;
    }
    return null;
  }
}
