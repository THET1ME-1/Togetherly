import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../../models/geo_arc.dart';
import '../../models/globe_math.dart';
import '../../models/live_point_age.dart';
import '../../models/map_distance.dart';
import '../../models/pair_map_widget_view.dart';
import '../../theme/app_palettes.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/map/land_shapes.dart';
import '../../widgets/map/pair_map_widget_art.dart';
import '../home_widget_service.dart';
import '../live_location_service.dart' show LivePoint;
import '../locale_service.dart';
import '../pocketbase_service.dart';
import 'map_palette.dart';
import 'map_tiles.dart';

/// Откуда брать плитку: сеть с кэшем на диске или файлы в тестах.
typedef MapTileLoader = Future<Uint8List?> Function(int z, int x, int y);

/// Всё, что нужно для картинок виджета «Где мы».
class PairMapWidgetInput {
  final bool paired;
  final LivePoint? me;
  final LivePoint? partner;
  final String myName;
  final String partnerName;
  final Uint8List? myAvatar;
  final Uint8List? partnerAvatar;
  final ColorScheme scheme;
  final Color fill;
  final Map<MapWidgetSize, Size> sizes;
  final int nowMs;
  final String? myPlace;
  final String? partnerPlace;

  /// Точек на точку экрана, куда встанет виджет.
  final double pixelRatio;

  /// Предел точек на картинку (свой у каждой системы).
  final int maxPixels;

  const PairMapWidgetInput({
    required this.paired,
    required this.me,
    required this.partner,
    required this.myName,
    required this.partnerName,
    required this.scheme,
    required this.fill,
    required this.sizes,
    required this.nowMs,
    this.myAvatar,
    this.partnerAvatar,
    this.myPlace,
    this.partnerPlace,
    this.pixelRatio = 3,
    this.maxPixels = kMapWidgetMaxPixelsAndroid,
  });
}

/// Рисует картинки виджета «Где мы» всех трёх размеров. Сеть — только через
/// [tiles], поэтому то же самое рисует и превью в тестах.
Future<Map<MapWidgetSize, Uint8List>> renderPairMapWidgets(
  PairMapWidgetInput input, {
  required MapTileLoader tiles,
  List<LandRing>? land,
}) async {
  final s = LocaleService.current;
  final lang = LocaleService.instance.language.code;
  final cs = input.scheme;
  final palette = MapPalette.of(cs, fill: input.fill);
  final theme = await MapTiles.themeFor(palette);
  // Подробная суша: глобус в виджете часто приближен до страны, и контур
  // 110m там ломался заметными углами.
  final rings = land ?? await LandShapes.detailed();
  final meAvatar = await _decode(input.myAvatar);
  final partnerAvatar = await _decode(input.partnerAvatar);
  final onFill = AppThemes.onColor(input.fill, mode: cs.brightness);

  final decoded = <String, vtr.Tile?>{};
  Future<vtr.Tile?> tileAt(int z, int x, int y) async {
    final key = '$z/$x/$y';
    if (decoded.containsKey(key)) return decoded[key];
    vtr.Tile? tile;
    try {
      final bytes = await tiles(z, x, y);
      if (bytes != null && bytes.isNotEmpty) {
        tile = vtr.TileFactory(theme, const vtr.Logger.noop())
            .createTileData(vtr.VectorTileReader().read(bytes))
            .toTile();
      }
    } catch (e) {
      debugPrint('PairMapWidget: плитка $key не разобралась: $e');
    }
    return decoded[key] = tile;
  }

  final me = input.me == null ? null : LatLng(input.me!.lat, input.me!.lng);
  final her = input.partner == null ? null : LatLng(input.partner!.lat, input.partner!.lng);
  final meters = (me != null && her != null) ? metersBetween(me, her) : 0.0;
  final distance = formatMapDistance(meters,
      lang: lang, nearby: s.liveMapNearby, unitM: s.unitM, unitKm: s.unitKm);

  String ageText(LivePoint p) {
    final age = LivePointAge.of(p.updatedAt, nowMs: input.nowMs);
    return switch (age.unit) {
      LivePointAgeUnit.minutes => s.minutesAgo(age.value),
      LivePointAgeUnit.hours => s.hoursAgo(age.value),
      LivePointAgeUnit.days => s.daysAgo(age.value),
      _ => s.mapWidgetNow,
    };
  }

  final partnerAge = input.partner == null
      ? null
      : LivePointAge.of(input.partner!.updatedAt, nowMs: input.nowMs);
  final partnerStale = partnerAge != null &&
      (partnerAge.unit == LivePointAgeUnit.hours || partnerAge.unit == LivePointAgeUnit.days);
  String initial(String name) => name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

  final out = <MapWidgetSize, Uint8List>{};
  for (final kind in MapWidgetSize.values) {
    final size = input.sizes[kind] ?? kind.size;
    final safe = kind.safeFor(size);
    final mode = pairMapMode(paired: input.paired, me: me, partner: her, size: size, safe: safe);

    Offset? mePt, herPt;
    var placed = <(TilePlacement, vtr.Tile)>[];
    var zoom = 13.0;
    GlobeFrame? frame;
    var arcBase = const <Offset>[];

    Future<void> mapAround(LatLng center, double z) async {
      zoom = z;
      final cam = MercatorCamera(centerLat: center.latitude, centerLon: center.longitude, zoom: z, size: size);
      if (me != null) mePt = cam.screen(me.latitude, me.longitude);
      if (her != null) herPt = cam.screen(her.latitude, her.longitude);
      for (final t in tilesFor(center, z, size)) {
        final tile = await tileAt(t.z, t.x, t.y);
        if (tile != null) placed.add((t, tile));
      }
    }

    switch (mode) {
      case PairMapMode.map:
        final fit = fitTwo(me!, her!, size, safe);
        await mapAround(fit.center, fit.zoom);
      case PairMapMode.near:
        final fit = fitOne(LatLng((me!.latitude + her!.latitude) / 2, (me.longitude + her.longitude) / 2),
            size, safe, zoom: 15);
        await mapAround(fit.center, fit.zoom);
      case PairMapMode.onlyMe:
      case PairMapMode.onlyPartner:
        final fit = fitOne(me ?? her!, size, safe, zoom: 13.5);
        await mapAround(fit.center, fit.zoom);
      case PairMapMode.globe:
        frame = globeFrameFor(me!, her!, size, safe);
        final b = frame.basis;
        Offset project(LatLng p) => b.project(Vec3.fromLatLng(p.latitude, p.longitude), frame!.radius, frame.center);
        mePt = project(me);
        herPt = project(her);
        arcBase = [for (final p in greatCircle(me, her, segments: 48)) project(p)];
      case PairMapMode.noPair:
      case PairMapMode.noPoints:
        break;
    }

    final String? caption = switch (mode) {
      PairMapMode.onlyMe => kind == MapWidgetSize.s
          ? s.mapWidgetWaitingShort.replaceAll('{name}', input.partnerName)
          : s.mapWidgetPartnerHidden.replaceAll('{name}', input.partnerName),
      PairMapMode.onlyPartner => kind == MapWidgetSize.s ? s.mapWidgetShareMineShort : s.mapWidgetShareMine,
      PairMapMode.map || PairMapMode.globe || PairMapMode.near => kind == MapWidgetSize.s
          ? (partnerStale ? ageText(input.partner!) : null)
          : '${input.partnerName} · ${ageText(input.partner!)}',
      _ => null,
    };

    String detail(String? place, LivePoint? p, {required bool mine}) {
      if (p == null) {
        return mine
            ? s.mapWidgetShareMineShort
            : s.mapWidgetPartnerHidden.replaceAll('{name}', '').trim();
      }
      return [if (place != null && place.isNotEmpty) place, ageText(p)].join(' · ');
    }

    final art = PairMapWidgetArt(
      kind: kind,
      size: size,
      mode: mode,
      palette: palette,
      fill: input.fill,
      onFill: onFill,
      surface: cs.surface,
      onSurface: cs.onSurface,
      onSurfaceVariant: cs.onSurfaceVariant,
      meBg: cs.tertiaryContainer,
      meFg: cs.onTertiaryContainer,
      partnerBg: cs.secondaryContainer,
      partnerFg: cs.onSecondaryContainer,
      tiles: placed,
      mapTheme: theme,
      zoom: zoom,
      globe: frame,
      land: rings,
      globeArcBase: arcBase,
      me: mePt,
      partner: herPt,
      meAvatar: meAvatar,
      partnerAvatar: partnerAvatar,
      meInitial: initial(input.myName),
      partnerInitial: initial(input.partnerName),
      partnerStale: partnerStale,
      distance: mode == PairMapMode.near ? s.liveMapNearby : distance,
      caption: caption,
      rows: [
        MapWidgetRow(
            mine: false,
            name: input.partnerName,
            detail: detail(input.partnerPlace, input.partner, mine: false)),
        MapWidgetRow(mine: true, name: input.myName, detail: detail(input.myPlace, input.me, mine: true)),
      ],
      title: switch (mode) {
        PairMapMode.noPair => s.mapWidgetNoPairTitle,
        PairMapMode.noPoints => s.mapWidgetNoPointsTitle,
        _ => null,
      },
      subtitle: switch (mode) {
        PairMapMode.noPair => s.mapWidgetNoPairSub,
        PairMapMode.noPoints => s.mapWidgetNoPointsSub,
        _ => null,
      },
    );

    final k = pixelScaleFor(size, dpr: input.pixelRatio, maxPixels: input.maxPixels);
    final (pw, ph) = mapWidgetPixels(size, k);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(k);
    art.paint(canvas);
    final image = await recorder.endRecording().toImage(pw, ph);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png != null) out[kind] = png.buffer.asUint8List();
  }
  meAvatar?.dispose();
  partnerAvatar?.dispose();
  return out;
}

Future<ui.Image?> _decode(Uint8List? bytes) async {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (e) {
    debugPrint('PairMapWidget: аватарка не разобралась: $e');
    return null;
  }
}

/// Канал пары в `live_location`: общий ключ `pair_<a>_<b>` по отсортированным
/// uid — тот же, что у [LiveLocationService].
String pairMapChannel(String pairId, String myUid, String partnerUid) {
  if (myUid.isEmpty || partnerUid.isEmpty) return pairId;
  final ids = [myUid, partnerUid]..sort();
  return 'pair_${ids[0]}_${ids[1]}';
}

/// Виджет «Где мы» на рабочем столе (19.09.2026): приложение рисует картинку,
/// виджет её показывает.
///
/// Перерисовка — при каждом входе в приложение (синхронизация виджетов с
/// главной) и в фоне: на Android раз в 15 минут WorkManager, на iPhone тихий
/// пуш. Реже нельзя по правилам систем: WorkManager не запускает задачи чаще,
/// а Apple выбрасывает лишние тихие пуши.
///
/// Лишней работы не делаем: виджета на столе нет — не рисуем; ничего не
/// поменялось (точки, тема, имена, размеры, подпись давности) — не рисуем.
class PairMapWidgetService {
  PairMapWidgetService._();
  static final instance = PairMapWidgetService._();

  static const _metaKey = 'mapw_meta_v1';
  static const _schemeKey = 'mapw_scheme_v1';
  static const _sigKey = 'mapw_sig_v1';
  static const _iosSizesKey = 'mapw_ios_sizes_v1';
  static const _placesKey = 'mapw_places_v1';
  static const _dprKey = 'mapw_dpr_v1';

  /// Меняется вместе с тем, как рисуется картинка: уже стоящие виджеты
  /// перерисуются, хотя точки не двигались.
  static const _renderVersion = 2;

  /// Провайдеры Android — по одному на размер, как у остальных виджетов.
  static const androidProviders = {
    MapWidgetSize.s: 'PairMapWidget2x2Provider',
    MapWidgetSize.m: 'PairMapWidget4x2Provider',
    MapWidgetSize.l: 'PairMapWidget4x4Provider',
  };

  /// Вид виджета на iPhone (`kind` в WidgetKit).
  static const iosKind = 'PairMapWidget';

  /// Ключи картинок на iPhone: один виджет трёх семейств.
  static const iosKeys = {
    MapWidgetSize.s: 'ios_map_small_path',
    MapWidgetSize.m: 'ios_map_medium_path',
    MapWidgetSize.l: 'ios_map_large_path',
  };

  Future<void>? _running;

  /// Передний план: пара, имена, аватарки и тема известны.
  Future<void> refreshFromApp({
    required String groupId,
    required String myUid,
    required String partnerUid,
    required String myName,
    required String partnerName,
    required String myAvatarUrl,
    required String partnerAvatarUrl,
    required AppTheme theme,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _metaKey,
        jsonEncode({
          'g': groupId,
          'my': myName,
          'partner': partnerName,
          'myAvatar': myAvatarUrl,
          'partnerAvatar': partnerAvatarUrl,
        }),
      );
      await prefs.setString(_schemeKey, jsonEncode(schemeToJson(ProfileTheme.themeFor(theme).colorScheme, theme.fillColor)));
      if (Platform.isIOS) {
        final views = ui.PlatformDispatcher.instance.views;
        if (views.isNotEmpty) {
          final v = views.first;
          await prefs.setDouble(_iosSizesKey, v.physicalSize.width / v.devicePixelRatio);
        }
      }
      final views = ui.PlatformDispatcher.instance.views;
      if (views.isNotEmpty) await prefs.setDouble(_dprKey, views.first.devicePixelRatio);
    } catch (e) {
      debugPrint('PairMapWidget: не сохранились данные для фона: $e');
    }
    await _refreshOnce(groupId: groupId, myUid: myUid, partnerUid: partnerUid);
  }

  /// Фон: WorkManager на Android, тихий пуш на iPhone. Имена, аватарки и тема
  /// берутся из того, что оставил передний план.
  Future<void> refreshInBackground({
    required String groupId,
    required String myUid,
    required String partnerUid,
  }) =>
      _refreshOnce(groupId: groupId, myUid: myUid, partnerUid: partnerUid);

  Future<void> _refreshOnce({required String groupId, required String myUid, required String partnerUid}) {
    // Два входа подряд (главная и фон) не рисуют одно и то же дважды.
    return _running ??= _refresh(groupId: groupId, myUid: myUid, partnerUid: partnerUid)
        .timeout(const Duration(seconds: 40), onTimeout: () {
      debugPrint('PairMapWidget: не уложились в 40 с');
    }).whenComplete(() => _running = null);
  }

  Future<bool> _anyInstalled() async {
    try {
      final all = await HomeWidget.getInstalledWidgets();
      return all.any((w) =>
          w.iOSKind == iosKind ||
          androidProviders.values.any((p) => (w.androidClassName ?? '').endsWith(p)));
    } catch (e) {
      // Спросить не вышло — рисуем: пустой виджет хуже лишней работы.
      return true;
    }
  }

  Future<void> _refresh({required String groupId, required String myUid, required String partnerUid}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!await _anyInstalled()) return;
    final prefs = await SharedPreferences.getInstance();
    final meta = _json(prefs.getString(_metaKey));
    final sameGroup = meta['g'] == groupId;
    final myName = sameGroup ? (meta['my'] as String? ?? '') : '';
    final partnerName = sameGroup ? (meta['partner'] as String? ?? '') : '';
    final (scheme, fill) = schemeFromJson(_json(prefs.getString(_schemeKey)));

    final paired = groupId.isNotEmpty && partnerUid.isNotEmpty;
    final points = paired ? await _fetchPoints(pairMapChannel(groupId, myUid, partnerUid)) : null;
    final me = points?[myUid];
    final partner = points?[partnerUid];
    final sizes = await _sizes(prefs);
    final dpr = await _pixelRatio(prefs);
    final now = DateTime.now().millisecondsSinceEpoch;

    final myPlace = me == null ? null : await _placeOf(prefs, me);
    final partnerPlace = partner == null ? null : await _placeOf(prefs, partner);

    final sig = jsonEncode([
      _renderVersion, dpr, groupId, paired, _pointSig(me), _pointSig(partner), myName, partnerName,
      meta['myAvatar'], meta['partnerAvatar'], schemeToJson(scheme, fill),
      [for (final e in sizes.entries) '${e.key.id}:${e.value.width.round()}x${e.value.height.round()}'],
      LocaleService.instance.language.code, myPlace, partnerPlace,
      // Подпись давности меняется со временем — её часть подписи.
      partner == null ? '' : LivePointAge.of(partner.updatedAt, nowMs: now).unit.name,
      partner == null ? 0 : LivePointAge.of(partner.updatedAt, nowMs: now).value,
    ]);
    if (prefs.getString(_sigKey) == sig) return;

    final myAvatar = sameGroup ? await _avatar(groupId, 'my', meta['myAvatar'] as String?) : null;
    final partnerAvatar = sameGroup ? await _avatar(groupId, 'partner', meta['partnerAvatar'] as String?) : null;

    final images = await renderPairMapWidgets(
      PairMapWidgetInput(
        paired: paired,
        me: me,
        partner: partner,
        myName: myName,
        partnerName: partnerName.isEmpty ? '♥' : partnerName,
        myAvatar: myAvatar,
        partnerAvatar: partnerAvatar,
        scheme: scheme,
        fill: fill,
        sizes: sizes,
        nowMs: now,
        myPlace: myPlace,
        partnerPlace: partnerPlace,
        pixelRatio: dpr,
        maxPixels: Platform.isIOS ? kMapWidgetMaxPixelsIos : kMapWidgetMaxPixelsAndroid,
      ),
      tiles: _loadTile,
    );
    if (images.isEmpty) return;
    await _publish(groupId.isEmpty ? 'solo' : groupId, images);
    await prefs.setString(_sigKey, sig);
  }

  static String _pointSig(LivePoint? p) =>
      p == null ? '' : '${p.lat.toStringAsFixed(5)},${p.lng.toStringAsFixed(5)}';

  static Map<String, dynamic> _json(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Точки обоих из `live_location` одним запросом: запись идёт не чаще раза
  /// в две минуты, свежее всё равно не бывает.
  Future<Map<String, LivePoint>?> _fetchPoints(String channel) async {
    try {
      final pb = PocketBaseService().pb;
      final res = await pb
          .collection('live_location')
          .getList(perPage: 10, filter: pb.filter('channel = {:c}', {'c': channel}))
          .timeout(const Duration(seconds: 10));
      final out = <String, LivePoint>{};
      for (final r in res.items) {
        final uid = r.data['user_uid']?.toString() ?? '';
        final data = r.data['data'];
        if (uid.isEmpty || data is! Map) continue;
        final p = LivePoint.fromMap(data);
        if (p.lat == 0 && p.lng == 0) continue;
        out[uid] = p;
      }
      return out;
    } catch (e) {
      debugPrint('PairMapWidget: точки не пришли: $e');
      return null;
    }
  }

  Future<Map<MapWidgetSize, Size>> _sizes(SharedPreferences prefs) async {
    if (Platform.isIOS) {
      return iosWidgetSizes(prefs.getDouble(_iosSizesKey) ?? 393);
    }
    final out = <MapWidgetSize, Size>{};
    for (final kind in MapWidgetSize.values) {
      final raw = await HomeWidget.getWidgetData<String>('mapw_dims_${kind.id}');
      out[kind] = kind.sizeFrom(raw);
    }
    return out;
  }

  /// Плотность экрана. На Android её пишет провайдер виджета (`mapw_density`)
  /// — в фоне окна нет и спросить не у кого; запасной путь — то, что приложение
  /// видело на переднем плане.
  Future<double> _pixelRatio(SharedPreferences prefs) async {
    if (Platform.isAndroid) {
      final raw = await HomeWidget.getWidgetData<String>('mapw_density');
      final d = double.tryParse(raw ?? '');
      if (d != null && d >= 1) return d;
    }
    final saved = prefs.getDouble(_dprKey);
    return saved != null && saved >= 1 ? saved : 3;
  }

  Future<Uint8List?> _avatar(String groupId, String who, String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final path = await HomeWidgetService.instance.pairImagePath('mapw_${groupId}_${who}_avatar', url);
      if (path == null || path.isEmpty) return null;
      final f = File(path);
      return f.existsSync() ? await f.readAsBytes() : null;
    } catch (e) {
      debugPrint('PairMapWidget: аватарка $who не скачалась: $e');
      return null;
    }
  }

  /// Район для панели крупного виджета. Геокодер системы бывает недоступен
  /// (нет сети, прошивка без сервисов), поэтому район — украшение, а не
  /// условие: не нашёлся — в строке останется только время.
  Future<String?> _placeOf(SharedPreferences prefs, LivePoint p) async {
    final key = '${p.lat.toStringAsFixed(3)},${p.lng.toStringAsFixed(3)}|${LocaleService.instance.language.code}';
    final cache = _json(prefs.getString(_placesKey));
    if (cache.containsKey(key)) return cache[key] as String?;
    String? place;
    try {
      await geo.setLocaleIdentifier(LocaleService.instance.language.code);
      final marks = await geo.placemarkFromCoordinates(p.lat, p.lng).timeout(const Duration(seconds: 6));
      if (marks.isNotEmpty) {
        final m = marks.first;
        place = [m.subLocality, m.locality, m.subAdministrativeArea]
            .firstWhere((x) => x != null && x.trim().isNotEmpty, orElse: () => null)
            ?.trim();
      }
    } catch (e) {
      debugPrint('PairMapWidget: район не определился: $e');
      return null;
    }
    final next = Map<String, dynamic>.from(cache);
    if (next.length > 40) next.remove(next.keys.first);
    next[key] = place ?? '';
    await prefs.setString(_placesKey, jsonEncode(next));
    return place;
  }

  /// Плитка с диска, если свежая; иначе из сети. Сеть не ответила — старая
  /// плитка лучше пустой карты.
  Future<Uint8List?> _loadTile(int z, int x, int y) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/map_tiles');
    final file = File('${dir.path}/${z}_${x}_$y.pbf');
    if (file.existsSync() &&
        DateTime.now().difference(file.lastModifiedSync()) < const Duration(days: 14)) {
      return file.readAsBytes();
    }
    try {
      final template = await MapTiles.template();
      final url = template.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y');
      final res = await http.get(Uri.parse(url), headers: MapTiles.headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        dir.createSync(recursive: true);
        await file.writeAsBytes(res.bodyBytes, flush: true);
        return res.bodyBytes;
      }
    } catch (e) {
      debugPrint('PairMapWidget: плитка $z/$x/$y не скачалась: $e');
    }
    return file.existsSync() ? file.readAsBytes() : null;
  }

  /// Кладёт картинки туда, где их видит виджет, и будит его.
  Future<void> _publish(String g, Map<MapWidgetSize, Uint8List> images) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/map_widget');
    dir.createSync(recursive: true);
    // Имя с номером: WidgetKit держит картинку по пути, и с прежним именем
    // показывал бы старую.
    final rev = DateTime.now().millisecondsSinceEpoch;
    for (final f in dir.listSync()) {
      if (f is File && f.path.contains('map_${g}_')) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    if (Platform.isIOS) await HomeWidgetService.instance.clearAppGroupMedia('mapw_');
    for (final e in images.entries) {
      final file = File('${dir.path}/map_${g}_${e.key.id}_$rev.png');
      await file.writeAsBytes(e.value, flush: true);
      if (Platform.isIOS) {
        final path = await HomeWidgetService.instance.appGroupReadablePath(file.path, 'mapw_${e.key.id}_$rev.png');
        await HomeWidget.saveWidgetData<String>(iosKeys[e.key]!, path);
      } else {
        await HomeWidget.saveWidgetData<String>('map_${g}_img_${e.key.id}', file.path);
      }
    }
    await HomeWidget.saveWidgetData<String>('map_latest_group', g);
    if (Platform.isIOS) {
      await HomeWidget.updateWidget(iOSName: iosKind);
      return;
    }
    for (final p in androidProviders.values) {
      await HomeWidget.updateWidget(name: p, androidName: p, qualifiedAndroidName: 'com.togetherly.love.$p');
    }
  }
}

/// Роли схемы, которые нужны картинке, — строкой для фона: там темы нет.
Map<String, dynamic> schemeToJson(ColorScheme cs, Color fill) => {
      'dark': cs.brightness == Brightness.dark,
      'fill': fill.toARGB32(),
      for (final e in _roles(cs).entries) e.key: e.value.toARGB32(),
    };

Map<String, Color> _roles(ColorScheme cs) => {
      'primary': cs.primary,
      'onPrimary': cs.onPrimary,
      'primaryContainer': cs.primaryContainer,
      'secondary': cs.secondary,
      'onSecondary': cs.onSecondary,
      'secondaryContainer': cs.secondaryContainer,
      'onSecondaryContainer': cs.onSecondaryContainer,
      'tertiary': cs.tertiary,
      'tertiaryContainer': cs.tertiaryContainer,
      'onTertiaryContainer': cs.onTertiaryContainer,
      'error': cs.error,
      'onError': cs.onError,
      'surface': cs.surface,
      'onSurface': cs.onSurface,
      'onSurfaceVariant': cs.onSurfaceVariant,
      'surfaceContainerLowest': cs.surfaceContainerLowest,
      'surfaceContainerLow': cs.surfaceContainerLow,
      'surfaceContainer': cs.surfaceContainer,
      'surfaceContainerHigh': cs.surfaceContainerHigh,
      'surfaceContainerHighest': cs.surfaceContainerHighest,
      'outlineVariant': cs.outlineVariant,
    };

/// Обратно в схему. Нет сохранённой — розовая тема по умолчанию.
(ColorScheme, Color) schemeFromJson(Map<String, dynamic> j) {
  if (j.isEmpty || j['surface'] is! int) {
    final t = buildAppTheme(kPalettes.first, Brightness.light);
    return (ProfileTheme.themeFor(t).colorScheme, t.fillColor);
  }
  Color c(String k, Color fallback) => j[k] is int ? Color(j[k] as int) : fallback;
  final dark = j['dark'] == true;
  final base = dark ? const ColorScheme.dark() : const ColorScheme.light();
  final cs = base.copyWith(
    primary: c('primary', base.primary),
    onPrimary: c('onPrimary', base.onPrimary),
    primaryContainer: c('primaryContainer', base.primaryContainer),
    secondary: c('secondary', base.secondary),
    onSecondary: c('onSecondary', base.onSecondary),
    secondaryContainer: c('secondaryContainer', base.secondaryContainer),
    onSecondaryContainer: c('onSecondaryContainer', base.onSecondaryContainer),
    tertiary: c('tertiary', base.tertiary),
    tertiaryContainer: c('tertiaryContainer', base.tertiaryContainer),
    onTertiaryContainer: c('onTertiaryContainer', base.onTertiaryContainer),
    error: c('error', base.error),
    onError: c('onError', base.onError),
    surface: c('surface', base.surface),
    onSurface: c('onSurface', base.onSurface),
    onSurfaceVariant: c('onSurfaceVariant', base.onSurfaceVariant),
    surfaceContainerLowest: c('surfaceContainerLowest', base.surfaceContainerLowest),
    surfaceContainerLow: c('surfaceContainerLow', base.surfaceContainerLow),
    surfaceContainer: c('surfaceContainer', base.surfaceContainer),
    surfaceContainerHigh: c('surfaceContainerHigh', base.surfaceContainerHigh),
    surfaceContainerHighest: c('surfaceContainerHighest', base.surfaceContainerHighest),
    outlineVariant: c('outlineVariant', base.outlineVariant),
  );
  return (cs, c('fill', cs.primary));
}
