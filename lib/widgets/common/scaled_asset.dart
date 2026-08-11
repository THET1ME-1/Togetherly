import 'package:flutter/material.dart';

/// Картинка из ассетов, которая разворачивается ровно в свой размер на экране.
///
/// Все наши ассеты нарисованы с запасом: подарки и значки профиля — квадраты
/// 1024, стикеры настроений — 1254. Показываются они в 22–170 точках, а
/// Flutter без подсказки держит в памяти полный кадр: 1024×1024×4 — это четыре
/// мегабайта на значок величиной с ноготь, и полка подарков разворачивала
/// десятки мегабайт разом.
///
/// Предел ставится по одной стороне: с двумя разом декодер вписывает кадр в
/// прямоугольник и картинка сплющивается.
class ScaledAsset extends StatelessWidget {
  const ScaledAsset(
    this.asset, {
    super.key,
    required this.side,
    this.fit,
    this.color,
  });

  final String asset;

  /// Сторона на экране, в логических точках.
  final double side;
  final BoxFit? fit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return Image.asset(
      asset,
      width: side,
      height: side,
      fit: fit,
      color: color,
      cacheWidth: (side * dpr).ceil(),
    );
  }
}
