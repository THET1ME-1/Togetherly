import 'dart:ui' as ui;

/// Склеивает контур раскраски из двух половин, левой и правой.
///
/// У картинки с выбором фигур (`ColoringPicture.figures`) контур не лежит
/// одним файлом: каждая половина нарисована дважды, с девушкой и с парнем, и
/// лист собирается из выбранных. Половины одной высоты, левая встаёт в
/// начало, правая — сразу за ней. Исходники не освобождаются: они
/// принадлежат вызывающему.
Future<ui.Image> composeColoringHalves(ui.Image left, ui.Image right) {
  final width = left.width + right.width;
  final height = left.height > right.height ? left.height : right.height;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  canvas.drawImage(left, ui.Offset.zero, paint);
  canvas.drawImage(right, ui.Offset(left.width.toDouble(), 0), paint);
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}
