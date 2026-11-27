import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/xmas_tree.dart';
import 'package:love_app/screens/xmas/xmas_tree_screen.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/xmas_tree_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/profile_theme.dart';
import 'package:love_app/widgets/xmas/tree_home_tile.dart';
import 'package:love_app/widgets/xmas/tree_stage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ёлка пары — на глаз, на запечённых картинках мастерской
/// (`~/Projects/GitHub/togetherly-badges-hand/out_xmas3d`). В общий прогон не
/// входит: `flutter test test/goldens/xmas_tree_preview.dart`, снимки в `build/xmas/`.
final _out = '${Platform.environment['HOME']}/Projects/GitHub/togetherly-badges-hand/out_xmas3d';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
    any = true;
  }
  if (any) await loader.load();
}

ImageProvider _art(String key) {
  final dir = '$_out/$key';
  final lg = File('$dir/lg.webp');
  // комнаты — крупный webp, остальное — неподвижный кадр
  if (key.startsWith('xt_room') && lg.existsSync()) return FileImage(lg);
  return FileImage(File('$dir/still.png'));
}

void main() {
  testWidgets('ёлка пары', (tester) async {
    if (!Directory(_out).existsSync()) return;
    await _loadFont('Onest', ['assets/fonts/Onest.ttf']);
    await _loadFont('Unbounded', ['assets/fonts/Unbounded.ttf']);
    await _loadFont('MaterialIcons', [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      '${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
    SharedPreferences.setMockInitialValues({});
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    // двадцать слоёв по 1200 точек не влезают в кэш по умолчанию (100 МБ)
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1 << 30;
    xtDebugArt = _art;
    addTearDown(() => xtDebugArt = null);

    final toys = <XtToy>[
      for (final d in Directory(_out).listSync().whereType<Directory>().where((d) => d.path.split('/').last.startsWith('toy_')))
        XtToy.fromCatalog(() {
          final j = jsonDecode(File('${d.path}/toy.json').readAsStringSync()) as Map<String, dynamic>;
          return {'price': j['price'], 'sort': j['sort'], 'data': j};
        }())!,
    ]..sort((a, b) => a.sort.compareTo(b.sort));
    CatalogService.instance.debugSetToys(toys);

    TreeToy t(String id, String toy, double x, double y, String by) => TreeToy(id: id, toy: toy, x: x, y: y, author: by, created: DateTime.utc(2026, 12, 3));
    final state = TreeState(
      tree: const PairTree(),
      toys: [
        t('1', 'tu', 48, 23, 'me'), t('2', 'red', 39, 37, 'me'), t('3', 'mandarin', 60, 35, 'him'),
        t('4', 'matryoshka', 32, 52, 'me'), t('5', 'gold', 66, 53, 'him'), t('6', 'cone', 48, 50, 'him'),
        t('7', 'flake', 26, 68, 'me'), t('8', 'valenok', 44, 66, 'him'), t('9', 'blue', 72, 70, 'me'),
      ],
      owned: const {'red': 2, 'blue': 1, 'gold': 1, 'mint': 1, 'tu': 1, 'cane': 1, 'flake': 2},
      seasons: const [2026],
    );

    // все картинки разжать заранее: в тесте их иначе не дождаться
    await tester.runAsync(() async {
      final keys = <String>{
        for (final k in const ['fir', 'snowy']) ...['xt3_${k}_base', 'xt3_${k}_star', 'xt3_${k}_t0', for (final p in const ['t1', 't2', 't3']) ...['xt3_${k}_${p}_g0', 'xt3_${k}_${p}_g1']],
        'xt_room_night', 'xt_pick_style_fir',
        for (final x in toys) ...[x.pickArt, if (x.treeArt.isNotEmpty) x.treeArt],
      };
      for (final k in keys) {
        final p = _art(k);
        final s = p.resolve(ImageConfiguration.empty);
        final c = Completer<void>();
        late ImageStreamListener l;
        l = ImageStreamListener((_, _) { s.removeListener(l); c.complete(); }, onError: (_, _) { s.removeListener(l); c.complete(); });
        s.addListener(l);
        await c.future;
      }
    });

    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory('build/xmas')..createSync(recursive: true);

    Future<void> save(GlobalKey key, String name) async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    for (final b in Brightness.values) {
      XmasTreeService.instance.debugSet(group: 'g', season: 2026, me: 'me', state: state);
      await tester.binding.setSurfaceSize(const Size(360, 780));
      final key = GlobalKey();
      final theme = buildAppTheme(kPalettes[0], b);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.themeFor(theme),
        // рамка снимка — вокруг навигатора: лист открывается поверх экрана
        builder: (context, child) => RepaintBoundary(key: key, child: child),
        home: XmasTreeScreen(theme: theme, groupId: 'g', season: 2026, partnerName: 'Дима'),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await save(key, 'screen_${b.name}');
      // лист «Игрушки»
      await tester.tap(find.text('Игрушки').last);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      await save(key, 'picker_${b.name}');
      await tester.pumpWidget(const SizedBox());
    }

    // плитка главной
    await tester.binding.setSurfaceSize(const Size(360, 200));
    for (final empty in [false, true]) {
      XmasTreeService.instance.debugSet(group: 'g', season: 2026, me: 'me', state: empty ? state.copyWith(toys: const []) : state);
      final key = GlobalKey();
      final theme = buildAppTheme(kPalettes[0], Brightness.light);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ProfileTheme.themeFor(theme),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(width: 151, child: TreeHomeTile(groupId: 'g', season: 2026, myUid: 'me', partnerName: 'Дима', onOpen: () {})),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await save(key, empty ? 'tile_empty' : 'tile');
    }
  });
}
