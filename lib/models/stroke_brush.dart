/// Кисти холста и режимы ластика.
///
/// Кисть — поле `brush` в карте штриха. Перо в карту не пишется: старые
/// рисунки и сборки, которые о кистях не знают, видят обычную линию пером.
library;

/// Кисть мазка. Порядок совпадает с рядом плиток в панели.
enum StrokeBrush { pen, marker, pencil, airbrush, calligraphy }

/// Как стирает ластик. «Линия целиком» — не мазок, а действие: убирает
/// задетые линии текущего слоя.
enum EraserMode { hard, soft, whole }

/// Незнакомое имя (кисть из сборки поновее) рисуется пером.
StrokeBrush parseStrokeBrush(String? name) {
  for (final brush in StrokeBrush.values) {
    if (brush.name == name) return brush;
  }
  return StrokeBrush.pen;
}

EraserMode parseEraserMode(String? name) {
  for (final mode in EraserMode.values) {
    if (mode.name == name) return mode;
  }
  return EraserMode.hard;
}

/// Мягкий ластик — это ластик, положенный аэрографом: край стёртого размыт.
StrokeBrush brushForEraser(EraserMode mode) =>
    mode == EraserMode.soft ? StrokeBrush.airbrush : StrokeBrush.pen;

/// Зерно случайностей кисти (крошки карандаша). Считается от идентификатора
/// мазка одинаково на любом телефоне, поэтому у партнёра зерно то же, а при
/// подтверждении записи линия не мигает. `String.hashCode` для этого не годится:
/// он не обещает одинаковых чисел в разных сборках.
int brushSeedFor(String key) {
  var hash = 0x811C9DC5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Простой и одинаковый везде генератор случайных чисел (xorshift32).
class BrushRandom {
  BrushRandom(int seed) : _state = (seed & 0xFFFFFFFF) == 0 ? 0x9E3779B9 : seed & 0xFFFFFFFF;

  int _state;

  /// Число от 0 до 1.
  double next() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x;
    return x / 4294967296.0;
  }
}
