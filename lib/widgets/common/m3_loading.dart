import 'package:flutter/material.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

/// Общий индикатор ожидания в облике M3 Expressive.
///
/// Фигура непрерывно перетекает по кругу форм (семилистник → пятиугольник →
/// блоб → овал → звезда), как в ролике Material про loading indicator.
/// Ставится там, где ждать неизвестно сколько и проценты неоткуда взять:
/// первый вход, загрузка ленты и чата, подключение к комнате просмотра.
/// Где доля известна — нужен не этот виджет, а полоса ([M3WaveProgress]).
///
/// https://m3.material.io/components/loading-indicator/overview
class M3Loading extends StatelessWidget {
  /// Ниже этого размера морфинг читается как дрожащее пятно, поэтому мелкие
  /// места (спиннер в строке, в маленькой кнопке) остаются кольцом.
  static const double minMorphSize = 24;

  /// Размер поля индикатора. По спецификации это 48, сама фигура рисуется на
  /// 38 внутри него.
  final double size;

  final Color color;

  /// Обвести фигуру тональным кругом — вариант «2» из ролика. Нужен на цветных
  /// подложках (кнопка, карточка с картинкой), где голая фигура теряется.
  final bool contained;

  /// Цвет круга. По умолчанию — secondaryContainer активной схемы.
  final Color? containerColor;

  const M3Loading({
    super.key,
    required this.color,
    this.size = 48,
    this.contained = false,
    this.containerColor,
  });

  @override
  Widget build(BuildContext context) {
    final Widget indicator = size < minMorphSize
        ? CircularProgressIndicator(
            strokeWidth: (size * 0.16).clamp(1.6, 3.0),
            color: color,
            strokeCap: StrokeCap.round,
          )
        : ExpressiveLoadingIndicator(
            color: color,
            constraints: BoxConstraints.tight(Size.square(size)),
          );

    if (!contained) {
      return SizedBox(width: size, height: size, child: indicator);
    }

    // Круг крупнее фигуры в той же пропорции, что в спецификации (48 против 38).
    final double diameter = size * 48 / 38;
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: containerColor ?? Theme.of(context).colorScheme.secondaryContainer,
      ),
      child: SizedBox(width: size, height: size, child: indicator),
    );
  }
}

/// Индикатор во весь экран (первый вход, пустая лента, блокирующий диалог).
class M3PageLoading extends StatelessWidget {
  final Color color;
  final bool contained;
  final Color? containerColor;

  const M3PageLoading({
    super.key,
    required this.color,
    this.contained = false,
    this.containerColor,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: M3Loading(
          color: color,
          contained: contained,
          containerColor: containerColor,
        ),
      );
}
