import 'dart:ui' show Color;

import 'map_palette.dart';

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Стиль подложки «Где мы» из базового positron (`assets/map/base_style.json`)
/// и цветов темы.
///
/// Перекрашиваются слои по id — таблица ниже повторяет макет 1-в-1. Подписи
/// переводятся на язык приложения (`name:<lang>`, иначе местное название) и
/// рисуются шрифтом Onest, которым набран весь интерфейс. [base] не меняется:
/// на каждую тему собирается своя копия.
Map<String, dynamic> buildMapStyle(
  Map<String, dynamic> base,
  MapPalette p, {
  required String lang,
}) {
  final water = _hex(p.water);
  final land = _hex(p.land);
  final paints = <String, Map<String, Object>>{
    'background': {'background-color': land},
    'park': {'fill-color': _hex(p.park)},
    'water': {'fill-color': water},
    'landcover_ice_shelf': {'fill-color': land},
    'landcover_glacier': {'fill-color': land},
    'landuse_residential': {'fill-color': _hex(p.residential)},
    'landcover_wood': {'fill-color': _hex(p.wood)},
    'waterway': {'line-color': water},
    'building': {'fill-color': _hex(p.building), 'fill-outline-color': _hex(p.buildingLine)},
    'tunnel_motorway_casing': {'line-color': _hex(p.motorwayCase)},
    'tunnel_motorway_inner': {'line-color': _hex(p.motorway)},
    'aeroway-taxiway': {'line-color': _hex(p.roadCase)},
    'aeroway-runway-casing': {'line-color': _hex(p.roadCase)},
    'aeroway-area': {'fill-color': _hex(p.residential)},
    'aeroway-runway': {'line-color': _hex(p.road)},
    'road_area_pier': {'fill-color': land},
    'road_pier': {'line-color': land},
    'highway_path': {'line-color': _hex(p.roadCase)},
    'highway_minor': {'line-color': _hex(p.road)},
    'highway_major_casing': {'line-color': _hex(p.roadCase)},
    'highway_major_inner': {'line-color': _hex(p.road)},
    'highway_major_subtle': {'line-color': _hex(p.roadCase)},
    'highway_motorway_casing': {'line-color': _hex(p.motorwayCase)},
    'highway_motorway_inner': {'line-color': _hex(p.motorway)},
    'highway_motorway_subtle': {'line-color': _hex(p.motorwayCase)},
    'railway_transit': {'line-color': _hex(p.rail)},
    'railway_transit_dashline': {'line-color': land},
    'railway_service': {'line-color': _hex(p.rail)},
    'railway_service_dashline': {'line-color': land},
    'railway': {'line-color': _hex(p.rail)},
    'railway_dashline': {'line-color': land},
    'highway_motorway_bridge_casing': {'line-color': _hex(p.motorwayCase)},
    'highway_motorway_bridge_inner': {'line-color': _hex(p.motorway)},
    'boundary_3': {'line-color': _hex(p.region)},
    'boundary_2': {'line-color': _hex(p.country)},
    'boundary_disputed': {'line-color': _hex(p.region)},
    'waterway_line_label': {'text-color': _hex(p.waterText), 'text-halo-color': water},
    'water_name_point_label': {'text-color': _hex(p.waterText), 'text-halo-color': water},
    'water_name_line_label': {'text-color': _hex(p.waterText), 'text-halo-color': water},
    'highway-name-path': {'text-color': _hex(p.roadText), 'text-halo-color': land},
    'highway-name-minor': {'text-color': _hex(p.roadText), 'text-halo-color': _hex(p.road)},
    'highway-name-major': {'text-color': _hex(p.roadText), 'text-halo-color': _hex(p.road)},
    'airport': {'text-color': _hex(p.town), 'text-halo-color': land},
    'label_other': {'text-color': _hex(p.village), 'text-halo-color': land},
    'label_village': {'text-color': _hex(p.village), 'text-halo-color': land},
    'label_town': {'text-color': _hex(p.town), 'text-halo-color': land},
    'label_state': {'text-color': _hex(p.state), 'text-halo-color': land},
    for (final id in const [
      'label_city',
      'label_city_capital',
      'label_country_3',
      'label_country_2',
      'label_country_1',
    ])
      id: {'text-color': _hex(p.city), 'text-halo-color': land},
  };
  final name = [
    'coalesce',
    ['get', 'name:$lang'],
    ['get', 'name'],
  ];

  final layers = <Map<String, dynamic>>[];
  for (final raw in (base['layers'] as List).cast<Map<String, dynamic>>()) {
    final layer = Map<String, dynamic>.from(raw);
    final paint = Map<String, dynamic>.from((raw['paint'] as Map?) ?? const {});
    final extra = paints[layer['id']];
    if (extra != null) paint.addAll(extra);
    layer['paint'] = paint;
    final layout = raw['layout'] as Map?;
    if (layer['type'] == 'symbol' && layout != null && layout.containsKey('text-field')) {
      layer['layout'] = Map<String, dynamic>.from(layout)
        ..['text-field'] = name
        ..['text-font'] = const ['Onest'];
    }
    layers.add(layer);
  }
  return {
    ...base,
    'id': 'togetherly-${p.key}-$lang',
    'layers': layers,
  };
}
