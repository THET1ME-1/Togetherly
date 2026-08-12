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

ColoringSide coloringSideFor(String myUid, String partnerUid) {
  if (partnerUid.isEmpty) return ColoringSide.left;
  return myUid.toLowerCase().compareTo(partnerUid.toLowerCase()) <= 0
      ? ColoringSide.left
      : ColoringSide.right;
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
  bool get isOwn => id.startsWith('own_');

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

  static ColoringPicture? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}
