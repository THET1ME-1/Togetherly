import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../locale_service.dart';
import 'map_palette.dart';
import 'map_style.dart';

/// Векторные тайлы OpenFreeMap: бесплатно, без ключа, без лимитов.
///
/// Адрес тайлов версионный (`planet/20260913_164504_pt/{z}/{x}/{y}.pbf`) и
/// меняется с каждой пересборкой планеты, поэтому берётся из TileJSON и
/// кэшируется на сутки. Пока TileJSON не ответил — прошлый адрес из prefs, а
/// на самом первом запуске `latest`: он отдаёт те же тайлы.
class MapTiles {
  MapTiles._();

  static const _tileJson = 'https://tiles.openfreemap.org/planet';
  static const _fallback = 'https://tiles.openfreemap.org/planet/latest/{z}/{x}/{y}.pbf';
  static const _prefKey = 'ofm_tiles_template';
  static const _prefAt = 'ofm_tiles_template_at';
  static const maxZoom = 14;

  static String? _template;
  static Future<void>? _refreshing;
  static Map<String, dynamic>? _base;
  static final Map<String, vtr.Theme> _themes = {};

  static const Map<String, String> headers = {
    'User-Agent': 'Togetherly (com.togetherly.love; https://togetherly.day)',
  };

  /// Адрес тайлов, который можно отдать слою прямо сейчас.
  static Future<String> template() async {
    if (_template != null) return _template!;
    try {
      final prefs = await SharedPreferences.getInstance();
      _template = prefs.getString(_prefKey);
      final at = prefs.getInt(_prefAt) ?? 0;
      final stale = DateTime.now().millisecondsSinceEpoch - at > const Duration(days: 1).inMilliseconds;
      if (_template == null) {
        await _refresh();
      } else if (stale) {
        unawaited(_refresh());
      }
    } catch (_) {}
    return _template ?? _fallback;
  }

  static Future<void> _refresh() => _refreshing ??= () async {
        try {
          final res = await http
              .get(Uri.parse(_tileJson), headers: headers)
              .timeout(const Duration(seconds: 8));
          if (res.statusCode != 200) return;
          final tiles = (jsonDecode(res.body) as Map<String, dynamic>)['tiles'];
          if (tiles is List && tiles.isNotEmpty && tiles.first is String) {
            _template = tiles.first as String;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_prefKey, _template!);
            await prefs.setInt(_prefAt, DateTime.now().millisecondsSinceEpoch);
          }
        } catch (_) {
          // Нет сети — остаёмся на прошлом адресе.
        } finally {
          _refreshing = null;
        }
      }();

  static Future<Map<String, dynamic>> _baseStyle() async => _base ??=
      jsonDecode(await rootBundle.loadString('assets/map/base_style.json')) as Map<String, dynamic>;

  /// Цвета карты для темы приложения.
  static MapPalette paletteOf(AppTheme t) =>
      MapPalette.of(ProfileTheme.schemeFor(t), fill: t.fillColor);

  /// Тема отрисовщика под палитру и язык; собирается один раз на пару.
  static Future<vtr.Theme> themeFor(MapPalette p) async {
    final lang = LocaleService.instance.language.code;
    final key = '${p.key}-$lang';
    final ready = _themes[key];
    if (ready != null) return ready;
    final theme = vtr.ThemeReader().read(buildMapStyle(await _baseStyle(), p, lang: lang));
    if (_themes.length > 8) _themes.remove(_themes.keys.first);
    return _themes[key] = theme;
  }
}

/// Подложка карты в цветах темы: ставится в `FlutterMap.children` вместо
/// прежнего `TileLayer` с OpenStreetMap.
///
/// Пока тема и адрес тайлов собираются (доли секунды на первом открытии),
/// видна заливка суши — у карты тот же цвет фона.
class ThemedMapLayer extends StatefulWidget {
  final AppTheme theme;

  const ThemedMapLayer({super.key, required this.theme});

  @override
  State<ThemedMapLayer> createState() => _ThemedMapLayerState();
}

class _ThemedMapLayerState extends State<ThemedMapLayer> {
  vtr.Theme? _theme;
  String? _template;
  String _key = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ThemedMapLayer old) {
    super.didUpdateWidget(old);
    if (MapTiles.paletteOf(widget.theme).key != _key) _load();
  }

  Future<void> _load() async {
    final palette = MapTiles.paletteOf(widget.theme);
    _key = palette.key;
    final results = await Future.wait([MapTiles.themeFor(palette), MapTiles.template()]);
    if (!mounted || palette.key != _key) return;
    setState(() {
      _theme = results[0] as vtr.Theme;
      _template = results[1] as String;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme, template = _template;
    if (theme == null || template == null) {
      return ColoredBox(color: MapTiles.paletteOf(widget.theme).land);
    }
    return VectorTileLayer(
      key: ValueKey('${theme.id}|$template'),
      theme: theme,
      tileProviders: TileProviders({
        'openmaptiles': NetworkVectorTileProvider(
          urlTemplate: template,
          maximumZoom: MapTiles.maxZoom,
          httpHeaders: MapTiles.headers,
        ),
      }),
      // Карта общая с фоновым обновлением и превью на главной — держим
      // память скромной: сырые тайлы и разобранные раздельно.
      memoryTileCacheMaxSize: 12 * 1024 * 1024,
      memoryTileDataCacheMaxSize: 24,
      maximumZoom: 18,
    );
  }
}

/// Цвет фона `MapOptions` под подложку: тот же, что у суши.
Color mapBackground(AppTheme t) => MapTiles.paletteOf(t).land;

