import '../models/canvas_background.dart';
import '../models/profile_icon.dart';

/// Что показывать на месте платной вещи.
enum PlusGate {
  /// Куплено — фича работает.
  open,

  /// Не куплено, но купить можно: замок и переход на экран Togetherly+.
  locked,

  /// Togetherly+ на этой платформе не существует — платного места нет вовсе.
  hidden,
}

/// Правила доступа Togetherly+ в одном месте.
///
/// Чистые функции без обращений к сети и синглтонам: их зовут и экраны, и
/// модели, и тесты. Раньше каждое «что открывает Plus» жило своим кодом в своём
/// файле, из-за чего витрина обещала одно, а приложение делало другое.
class PlusAccess {
  const PlusAccess._();

  /// Что рисовать на месте платной вещи.
  ///
  /// [active] — куплен ли Togetherly+ на аккаунте, [exists] — продаётся ли он
  /// на этой платформе вообще. Купленное открыто всегда: флаг живёт на
  /// аккаунте, и человек, оплативший с Android, заходит с iPhone и видит своё.
  /// А вот предлагать покупку можно только там, где Плюс существует, — на iOS
  /// витрина стоила бы реджекта (2.1(b) на паках монет уже стоила).
  static PlusGate gate({required bool active, required bool exists}) {
    if (active) return PlusGate.open;
    return exists ? PlusGate.locked : PlusGate.hidden;
  }

  /// Потолок файла в PocketBase (`media.file.maxSize`). Выше него не пропустит
  /// сервер, поэтому клиентские лимиты не имеют права его превышать.
  static const int serverFileLimit = 200 * 1024 * 1024;

  /// Файл воспоминания без Plus.
  static const int memoryFileBytes = 100 * 1024 * 1024;

  /// Файл воспоминания с Plus — ровно серверный потолок.
  static const int memoryFileBytesPlus = serverFileLimit;

  /// Сколько весит самый большой файл, который можно положить в воспоминание.
  static int memoryFileLimit({required bool plus}) =>
      plus ? memoryFileBytesPlus : memoryFileBytes;

  /// Влезает ли файл в потолок.
  static bool fitsMemoryLimit({required int bytes, required bool plus}) =>
      bytes <= memoryFileLimit(plus: plus);

  /// Доступен ли фон холста.
  ///
  /// Бесплатные (`price == 0` — чистый, клетка, точки) открыты всем. Остальные
  /// девять из набора стоят монет, и Togetherly+ открывает их разом. Купленные
  /// поштучно остаются доступными и без Plus — за них уже заплачено.
  static bool ownsBackground({
    required CanvasBackground id,
    required bool plus,
    required Set<String> owned,
  }) {
    final spec = kCanvasBackgrounds[id];
    if (spec == null || spec.price == 0) return true;
    return plus || owned.contains(id.name);
  }

  /// Доступен ли значок профиля.
  ///
  /// Plus открывает все значки, которые иначе продаются за монеты. Наградные
  /// (`grantOnly` — Sponsor, Helper) не открывает: их выдают руками за дело, и
  /// продажа обесценила бы их для всех, кто получил.
  static bool ownsIcon({
    required String id,
    required bool plus,
    required Set<String> owned,
    required Set<String> granted,
  }) {
    if (owned.contains(id) || granted.contains(id)) return true;
    if (!plus) return false;
    final icon = ProfileIcon.byId(id);
    return icon != null && !icon.grantOnly;
  }
}
