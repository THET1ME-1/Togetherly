import 'dart:ui' as ui;

/// Кэш уже закончённых штрихов раскраски.
///
/// `_DrawingPainter` перерисовывал ВСЕ накопленные штрихи на каждое движение
/// пальца: на большом рисунке и при увеличении это тот самый лаг, на который
/// жалуются («совместные раскраски лагают»). Для рисунка в один слой
/// закоммиченные штрихи пишутся в
/// [ui.Picture] и на каждом кадре просто выкладываются одной командой, а
/// заново рисуется только текущий мазок.
///
/// Кэш живёт в состоянии экрана, а не в самом painter: painter пересоздаётся
/// на каждой перестройке.
///
/// **Ключ — ревизия основы плюс длина префикса, а не число штрихов**
/// (18.08.2026). По числу выходило две беды: удалили один штрих и добавили
/// другой — счётчик прежний, и на экране оставалась старая картинка; а любое
/// добавление меняло число и пересобирало слой целиком, из-за чего в пиксельной
/// раскраске (штрих — это клетка, их десятки в секунду) работа росла
/// квадратично.
///
/// Теперь слой знает, какой ПРЕФИКС состава он содержит. Пока штрихи только
/// дописываются в конец, слой не трогают вовсе: свежие рисуются поверх него.
/// Всё, что ломает префикс — отмена, замена, пересортировка, смена фона, — 
/// двигает ревизию основы, и слой пересобирается честно.
class StrokeLayerCache {
  ui.Picture? _picture;
  int _revision = -1;
  int _prefixCount = 0;
  ui.Size _size = ui.Size.zero;

  /// Сколько штрихов уже лежит внутри слоя: остальные рисуются поверх.
  int get prefixCount => _picture == null ? 0 : _prefixCount;

  /// Слой, если он описывает начало текущего состава: та же основа, тот же
  /// размер холста и штрихов стало не меньше, чем в нём записано.
  ui.Picture? prefixFor({
    required int revision,
    required int available,
    required ui.Size size,
  }) {
    if (_picture == null) return null;
    if (_revision != revision || _size != size) return null;
    if (_prefixCount > available) return null;
    return _picture;
  }

  /// Запомнить свежий слой. Прежний освобождаем: каждая запись держит память
  /// растра, а перерисовок за сеанс рисования сотни.
  void save(
    ui.Picture picture, {
    required int revision,
    required ui.Size size,
    int prefixCount = 0,
  }) {
    if (!identical(_picture, picture)) _picture?.dispose();
    _picture = picture;
    _revision = revision;
    _prefixCount = prefixCount;
    _size = size;
  }

  /// Сбросить слой: цвет фона, текстура листа или поворот холста меняют то,
  /// чего ревизия состава не видит.
  void invalidate() {
    _picture?.dispose();
    _picture = null;
    _revision = -1;
    _prefixCount = 0;
    _size = ui.Size.zero;
  }

  void dispose() => invalidate();
}

/// Готовые картинки слоёв рисунка, когда слоёв больше одного.
///
/// Каждый слой рисуется отдельно (`paintLayers`), чтобы ластик стирал только
/// свой слой. Картинка слоя пересобирается, только когда его штрихи
/// изменились: сравниваются ссылки, как в [appendOnly].
class LayerPictures {
  final Map<int, ui.Picture> _pictures = {};
  final Map<int, List<Object?>> _strokes = {};
  final Map<int, ui.Size> _sizes = {};

  /// Картинка слоя для этих штрихов: прежняя, если штрихи те же, иначе новая
  /// из [record]. null — записать нельзя (растр картинки ещё едет).
  ui.Picture? pictureFor(
    int layer,
    List<Object?> strokes,
    ui.Size size,
    ui.Picture? Function() record,
  ) {
    final old = _strokes[layer];
    final ready = _pictures[layer];
    if (ready != null &&
        old != null &&
        _sizes[layer] == size &&
        old.length == strokes.length &&
        appendOnly(old, strokes)) {
      return ready;
    }
    _pictures.remove(layer)?.dispose();
    _strokes.remove(layer);
    final picture = record();
    if (picture == null) return null;
    _pictures[layer] = picture;
    _strokes[layer] = List.of(strokes);
    _sizes[layer] = size;
    return picture;
  }

  /// Оставить только картинки слоёв, что есть в рисунке.
  void keepOnly(Iterable<int> layers) {
    final keep = layers.toSet();
    final gone = _pictures.keys.where((l) => !keep.contains(l)).toList();
    for (final layer in gone) {
      _pictures.remove(layer)?.dispose();
      _strokes.remove(layer);
      _sizes.remove(layer);
    }
  }

  /// Забыть все картинки: фон, размер листа или растр картинки поменялись.
  void invalidate() {
    for (final picture in _pictures.values) {
      picture.dispose();
    }
    _pictures.clear();
    _strokes.clear();
    _sizes.clear();
  }

  void dispose() => invalidate();
}

/// Правда ли, что список только дописали в конец.
///
/// Экран пересобирает видимые штрихи целиком, но объекты в нём остаются те же,
/// поэтому «дописали» узнаётся сравнением ссылок: перебор указателей стоит
/// микросекунды против перерисовки сотен путей. Всё, что не дописывание —
/// отмена, замена, пересортировка, — двигает ревизию основы и честно
/// пересобирает слой.
bool appendOnly(List<Object?> prev, List<Object?> next) {
  if (next.length < prev.length) return false;
  for (var i = 0; i < prev.length; i++) {
    if (!identical(prev[i], next[i])) return false;
  }
  return true;
}
