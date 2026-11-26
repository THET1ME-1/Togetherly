import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/xmas_tree_geometry.dart';
import 'package:love_app/widgets/xmas/tree_draw.dart';

/// Ёлка, нарисованная кодом, — на глаз рядом с запечёнными слоями мастерской.
/// В общий прогон не входит: `flutter test test/goldens/xmas_tree_vector_preview.dart`,
/// снимки в `build/xmas-vector/` (`<стиль>_<гирлянда>_<поворот>.png`).
void main() {
  test('ёлка кодом', () async {
    final out = Directory('build/xmas-vector')..createSync(recursive: true);
    const size = 600.0;
    for (final kind in const ['fir', 'snowy']) {
      for (final g in const [false, true]) {
        for (final (name, yaw) in [('mid', kXtYaw), ('left', kXtYaw - 0.07), ('right', kXtYaw + 0.07)]) {
          final pics = xtTreePictures(kind, yaw, garland: g);
          final rec = ui.PictureRecorder();
          final c = ui.Canvas(rec);
          c.scale(size / 116);
          c.translate(8, 8);
          for (final part in const ['base', 't3', 't2', 't1', 't0', 'star']) {
            c.drawPicture(pics.layers[part]!);
          }
          final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('${out.path}/${kind}_g${g ? 1 : 0}_$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
      }
    }
  });
}
