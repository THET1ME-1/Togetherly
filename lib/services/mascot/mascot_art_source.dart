import '../../models/mascot.dart';
import '../../models/mascot_anim.dart';

/// Откуда виджет берёт картинку персонажа.
///
/// Маскоты у людей разные: пиксельные из каталога, встроенные в приложение,
/// каталожные рисунки и нарисованные вручную. На рабочем столе обязаны
/// работать все, поэтому источник выбирается здесь, а не в трёх местах.
enum MascotArtKind {
  /// Анимированный атлас: кадр вырезает приложение.
  atlas,

  /// Картинка в ассетах приложения.
  asset,

  /// Публичная ссылка каталога.
  network,

  /// Файл в хранилище пары (`pb://…`), нарисованный человеком.
  storage,

  /// Показывать нечего.
  none,
}

class MascotArtSource {
  final MascotArtKind kind;

  /// Путь ассета или ссылка. Пусто у [MascotArtKind.none].
  final String ref;

  const MascotArtSource(this.kind, this.ref);

  /// Пиксель-арт увеличивают целым числом раз и без сглаживания, обычную
  /// картинку — вписывают. Натив различает их по этому признаку.
  bool get pixel => kind == MascotArtKind.atlas;
}

/// Выбирает источник картинки. Порядок тот же, что на главной
/// (`_MascotImage`): атлас старше всего, иначе ассет под рукой, иначе сеть.
MascotArtSource mascotArtSource(Mascot mascot, MascotAnim? anim) {
  if (anim != null) return MascotArtSource(MascotArtKind.atlas, anim.sheetUrl);

  final asset = mascot.defaultAsset;
  if (asset != null && asset.isNotEmpty) {
    return MascotArtSource(MascotArtKind.asset, asset);
  }

  final catalog = mascot.catalogUrl;
  if (catalog != null && catalog.isNotEmpty) {
    return MascotArtSource(MascotArtKind.network, catalog);
  }

  final drawn = mascot.imageUrl;
  if (drawn != null && drawn.isNotEmpty) {
    return MascotArtSource(MascotArtKind.storage, drawn);
  }

  return const MascotArtSource(MascotArtKind.none, '');
}

/// Показывать ли окно сна. Ночная сцена есть только у восьми персонажей, и у
/// остальных пилюля «не ложится спать» была бы шумом, а у рисованных —
/// выдумкой: картинка одна на все часы.
bool mascotSleepsInWidget(MascotAnim? anim) =>
    anim != null && anim.nightIdle.isNotEmpty;
