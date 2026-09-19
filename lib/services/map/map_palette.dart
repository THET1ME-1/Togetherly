import 'package:flutter/material.dart';

/// Смесь двух цветов в sRGB с округлением каналов — так же считал макет, и
/// так же считают тесты: `t = 0` даёт [a], `t = 1` даёт [b].
Color mixColor(Color a, Color b, double t) {
  int ch(double x, double y) => (x * 255 + (y * 255 - x * 255) * t).round().clamp(0, 255);
  return Color.fromARGB(255, ch(a.r, b.r), ch(a.g, b.g), ch(a.b, b.b));
}

/// Цвета карты «Где мы», снятые с темы приложения.
///
/// Карта не рисуется под каждую палитру отдельно: слои получают роли схемы.
/// Суша — `surfaceContainerLow`, вода — `secondaryContainer`, подтянутый к
/// заливке темы, трассы и границы стран — сама заливка, разбавленная сушей.
/// Поэтому любая из 25 палитр, своя палитра из пикера и тёмный режим получают
/// свою карту без ручной работы. Те же цвета берёт глобус: суша и вода на нём
/// совпадают с картой, и переход между ними не бросается в глаза.
///
/// В тёмной схеме вода не `secondaryContainer`, а суша с четвертью заливки:
/// иначе на почти чёрной суше она терялась (макет от 19.09.2026).
@immutable
class MapPalette {
  final Color land;
  final Color residential;
  final Color park;
  final Color wood;
  final Color water;
  final Color building;
  final Color buildingLine;
  final Color road;
  final Color roadCase;
  final Color motorway;
  final Color motorwayCase;
  final Color rail;
  final Color country;
  final Color region;
  final Color city;
  final Color town;
  final Color village;
  final Color state;
  final Color waterText;
  final Color roadText;

  /// Дуга между двумя людьми и точки на концах.
  final Color thread;

  /// Подложка под дугой и точками — чтобы они читались на любом месте карты.
  final Color halo;

  final Brightness brightness;

  const MapPalette._({
    required this.land,
    required this.residential,
    required this.park,
    required this.wood,
    required this.water,
    required this.building,
    required this.buildingLine,
    required this.road,
    required this.roadCase,
    required this.motorway,
    required this.motorwayCase,
    required this.rail,
    required this.country,
    required this.region,
    required this.city,
    required this.town,
    required this.village,
    required this.state,
    required this.waterText,
    required this.roadText,
    required this.thread,
    required this.halo,
    required this.brightness,
  });

  factory MapPalette.of(ColorScheme cs, {required Color fill}) {
    final land = cs.surfaceContainerLow;
    if (cs.brightness == Brightness.light) {
      return MapPalette._(
        land: land,
        residential: mixColor(land, cs.surfaceContainer, .6),
        park: mixColor(land, cs.tertiaryContainer, .45),
        wood: mixColor(land, cs.tertiaryContainer, .6),
        water: mixColor(cs.secondaryContainer, fill, .14),
        building: cs.surfaceContainerHigh,
        buildingLine: cs.surfaceContainerHighest,
        road: cs.surfaceContainerLowest,
        roadCase: mixColor(cs.outlineVariant, land, .45),
        motorway: mixColor(fill, const Color(0xFFFFFFFF), .72),
        motorwayCase: mixColor(fill, land, .45),
        rail: cs.outlineVariant,
        country: mixColor(fill, land, .3),
        region: mixColor(cs.outlineVariant, land, .2),
        city: cs.onSurface,
        town: cs.onSurfaceVariant,
        village: mixColor(cs.onSurfaceVariant, land, .2),
        state: mixColor(cs.onSurfaceVariant, land, .45),
        waterText: cs.onSecondaryContainer,
        roadText: cs.onSurfaceVariant,
        thread: fill,
        halo: cs.surface,
        brightness: Brightness.light,
      );
    }
    return MapPalette._(
      land: land,
      residential: cs.surfaceContainer,
      park: mixColor(land, cs.tertiaryContainer, .35),
      wood: mixColor(land, cs.tertiaryContainer, .45),
      water: mixColor(land, fill, .24),
      building: cs.surfaceContainerHigh,
      buildingLine: cs.surfaceContainerHighest,
      road: cs.surfaceContainerHighest,
      roadCase: cs.surfaceContainer,
      motorway: mixColor(fill, land, .45),
      motorwayCase: mixColor(fill, land, .7),
      rail: cs.outlineVariant,
      country: mixColor(fill, land, .35),
      region: mixColor(cs.outlineVariant, land, .15),
      city: cs.onSurface,
      town: cs.onSurfaceVariant,
      village: mixColor(cs.onSurfaceVariant, land, .25),
      state: mixColor(cs.onSurfaceVariant, land, .5),
      waterText: cs.onSecondaryContainer,
      roadText: cs.onSurfaceVariant,
      thread: fill,
      halo: cs.surface,
      brightness: Brightness.dark,
    );
  }

  /// Отпечаток цветов: по нему кэшируется собранная тема карты.
  String get key => [
        land, residential, park, wood, water, building, buildingLine, road,
        roadCase, motorway, motorwayCase, rail, country, region, city, town,
        village, state, waterText, roadText,
      ].map((c) => c.toARGB32().toRadixString(16)).join();
}
