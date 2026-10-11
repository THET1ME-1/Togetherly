import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/memory/adult_veil.dart';
import 'package:love_app/widgets/memory/media_strip.dart';

/// Завеса 18+ для глаз: `flutter test test/goldens/adult_veil_preview.dart`
/// → build/adult-veil/veil.png. Слева кадр как есть, справа под завесой, в
/// трёх размерах: плёнка ленты (56), плёнка записи (76), плитка главной.
/// Имя без `_test`: обычный прогон его не берёт.
void main() {
  setUpAll(() async {
    final loader = FontLoader('MaterialIcons')
      ..addFont(File('${Platform.environment['HOME']}/snap/flutter/common/flutter'
              '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView));
    await loader.load();
  });

  testWidgets('завеса 18+', (tester) async {
    final image = await tester.runAsync(() async {
      final bytes = File('assets/images/Screenshots/01 profile.jpg').readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 400);
      return (await codec.getNextFrame()).image;
    });
    final provider = _Ready(image!);
    final key = GlobalKey();

    Widget pair(double h) => Row(mainAxisSize: MainAxisSize.min, children: [
          FilmFrame(url: 'a$h', provider: provider, height: h),
          const SizedBox(width: 12),
          FilmFrame(url: 'b$h', provider: provider, height: h, blurred: true),
        ]);
    Widget tile({required bool veiled}) {
      final img = Image(image: provider, fit: BoxFit.cover);
      return SizedBox(
        width: 240,
        height: 135,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: veiled ? AdultVeil(child: img) : img,
        ),
      );
    }

    await tester.binding.setSurfaceSize(const Size(560, 420));
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFFFFF6F4),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                pair(56),
                const SizedBox(height: 16),
                pair(76),
                const SizedBox(height: 16),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  tile(veiled: false),
                  const SizedBox(width: 12),
                  tile(veiled: true),
                ]),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/adult-veil/veil.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}

class _Ready extends ImageProvider<_Ready> {
  _Ready(this.image);
  final ui.Image image;

  @override
  Future<_Ready> obtainKey(ImageConfiguration configuration) async => this;

  @override
  ImageStreamCompleter loadImage(_Ready key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: image.clone())));
}
