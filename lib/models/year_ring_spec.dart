import 'dart:math' as math;
import 'dart:ui';

/// Раскладка виджета «Кольцо года» — одна на iPhone, Android и превью в
/// каталоге.
///
/// До 14.09.2026 каждое из трёх мест рисовало виджет по-своему: на iPhone
/// «1288» вылезало за кольцо, на Android обрезались «ВОСПОМИНАН», в превью
/// плитки выходили за низ карточки, а подписи везде красились светлым
/// акцентом, почти равным заливке. Теперь числа и правила живут здесь, а
/// `YearRingWidgetProvider.kt` и `YearWidgets.swift` повторяют их — сверяет
/// `test/models/year_ring_spec_test.dart`.
///
/// Все размеры — в точках среднего виджета iPhone (338×158). Другие ячейки
/// масштабируют их коэффициентом от стороны кольца.
abstract final class YearRingSpec {
  /// Средний виджет, 4×2.
  static const double mediumWidth = 338;
  static const double mediumHeight = 158;

  /// Малый виджет, 2×2.
  static const double smallSide = 158;

  // 4×2
  static const double ring = 128;
  static const double stroke = 10;
  static const double padLeft = 14;
  static const double padRight = 16;
  static const double gap = 16;

  // 2×2
  static const double smallRing = 112;
  static const double smallStroke = 10;

  /// Прозрачность вторичного текста и дорожки кольца поверх заливки.
  static const double softAlpha = 0.90;
  static const double trackAlpha = 0.22;
  static const double hairlineAlpha = 0.28;

  /// Ширина цифры Onest ExtraBold в долях кегля и доля внутреннего диаметра,
  /// которую число может занять.
  static const double digitEm = 0.58;
  static const double numberShare = 0.74;

  /// Средняя ширина буквы подписи в долях кегля.
  static const double letterEm = 0.56;

  /// Кегль числа внутри кольца: помещается во внутренний диаметр при любом
  /// числе цифр, но не крупнее [max].
  static double numberSize({
    required double inner,
    required int digits,
    required double max,
  }) =>
      math.min(max, inner * numberShare / (math.max(digits, 1) * digitEm));

  /// Кегль строки, которой отведено [width] точек: базовый, пока строка
  /// помещается, дальше уменьшается, а не режется многоточием.
  static double fitText({
    required double base,
    required int chars,
    required double width,
    double em = letterEm,
  }) =>
      chars <= 0 ? base : math.min(base, width / (chars * em));

  /// Конец дуги: сегодняшний день на кольце. Старт на двенадцати часах, по
  /// часовой. Возле этой точки на фоне стоит свечение.
  static Offset arcEnd(Offset center, double radius, double progress) {
    final a = -math.pi / 2 + progress.clamp(0.0, 1.0) * 2 * math.pi;
    return Offset(
      center.dx + radius * math.cos(a),
      center.dy + radius * math.sin(a),
    );
  }

  /// Глубокий тон заливки для нижнего правого угла градиента.
  static Color deepOf(Color primary) =>
      Color.lerp(primary, const Color(0xFF000000), 0.18)!;

  /// Светлый тон для верхнего левого угла.
  static Color lightOf(Color primary) =>
      Color.lerp(primary, const Color(0xFFFFFFFF), 0.08)!;
}
