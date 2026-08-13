import 'dart:ui' as ui;

/// Кэш уже закончённых штрихов раскраски.
///
/// `_DrawingPainter` перерисовывал ВСЕ накопленные штрихи на каждое движение
/// пальца: на большом рисунке и при увеличении это тот самый лаг, на который
/// жалуются («совместные раскраски лагают»). Разделить слои нельзя — ластик
/// работает поверх общего, — поэтому закоммиченные штрихи пишутся в
/// [ui.Picture] и на каждом кадре просто выкладываются одной командой, а
/// заново рисуется только текущий мазок.
///
/// Кэш живёт в состоянии экрана, а не в самом painter: painter пересоздаётся
/// на каждой перестройке.
class StrokeLayerCache {
  ui.Picture? _picture;
  int _count = -1;
  ui.Size _size = ui.Size.zero;

  /// Готовый слой, если он всё ещё описывает те же штрихи на том же холсте.
  ui.Picture? pictureFor(int strokeCount, ui.Size size) {
    if (_picture == null) return null;
    if (_count != strokeCount || _size != size) return null;
    return _picture;
  }

  /// Запомнить свежий слой. Прежний освобождаем: каждая запись держит память
  /// растра, а перерисовок за сеанс рисования сотни.
  void save(ui.Picture picture, int strokeCount, ui.Size size) {
    _picture?.dispose();
    _picture = picture;
    _count = strokeCount;
    _size = size;
  }

  /// Сбросить слой: цвет фона, текстура листа или поворот холста меняют то,
  /// чего счётчик штрихов не видит.
  void invalidate() {
    _picture?.dispose();
    _picture = null;
    _count = -1;
    _size = ui.Size.zero;
  }

  void dispose() => invalidate();
}
