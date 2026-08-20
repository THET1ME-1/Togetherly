import 'dart:ui';

/// Сила сглаживания по умолчанию. Procreate держит свой Streamline примерно
/// на этом же уровне: дрожь уходит, а отставание в две-три доли кадра рука
/// ещё не замечает.
const double kDefaultSmoothing = 0.35;

/// Стабилизатор линии: гасит дрожь руки, пока палец ведёт мазок.
///
/// Работает как у Ibis Paint и Procreate: рисуется не там, где палец, а там,
/// куда точка догоняет его с отставанием. Мелкая дрожь усредняется, длинная
/// дуга остаётся дугой.
///
/// Считает в ЭКРАННЫХ точках, до перевода в координаты холста: дрожит рука, а
/// не рисунок, и при увеличении сглаживать надо ровно так же.
///
/// Главное свойство — уже отданные точки НЕ меняются. Живой мазок уезжает
/// партнёру приростами (`live_stroke_wire`), и правка задним числом
/// рассыпала бы у него линию.
class StrokeStabilizer {
  StrokeStabilizer({this.strength = 0.5, this.minStep = 0.6});

  /// Сила сглаживания, 0…1. Ноль выключает стабилизатор целиком: точки идут
  /// как есть, и пиксельный режим получает свои клетки без отставания.
  final double strength;

  /// Насколько далеко должна уехать сглаженная точка, чтобы её стоило
  /// добавлять. Отсекает частокол точек на месте — заодно меньше данных
  /// уходит в канал.
  final double minStep;

  Offset? _smoothed;
  Offset? _raw;
  Offset? _emitted;

  bool get _off => strength <= 0;

  /// Начало мазка: первая точка всегда стоит там, где палец.
  Offset begin(Offset raw) {
    _smoothed = raw;
    _raw = raw;
    _emitted = raw;
    return raw;
  }

  /// Очередное движение пальца. `null` — точку добавлять не нужно.
  Offset? update(Offset raw) {
    _raw = raw;
    if (_off) {
      _smoothed = raw;
      _emitted = raw;
      return raw;
    }
    final from = _smoothed ?? raw;
    final next = Offset.lerp(from, raw, 1 - strength)!;
    _smoothed = next;
    final last = _emitted;
    if (last != null && (next - last).distance < minStep) return null;
    _emitted = next;
    return next;
  }

  /// Хвост мазка: точка догоняет палец, иначе линия обрывается там, где
  /// сглаживание отстало — на быстром движении это заметный недомах.
  List<Offset> finish() {
    final target = _raw;
    var cur = _smoothed;
    if (target == null || cur == null || _off) return const [];
    final out = <Offset>[];
    final stop = minStep <= 0 ? 0.5 : minStep;
    var guard = 0;
    while ((target - cur!).distance > stop && guard < 12) {
      cur = Offset.lerp(cur, target, 1 - strength)!;
      out.add(cur);
      guard++;
    }
    final last = out.isEmpty ? cur : out.last;
    if ((target - last).distance > 0.01) out.add(target);
    if (out.isNotEmpty) {
      _smoothed = out.last;
      _emitted = out.last;
    }
    return out;
  }
}
