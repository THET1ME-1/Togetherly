import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/mascot_anim.dart';
import '../../models/mascot_sleep.dart';

/// Кадры, которые уезжают на рабочий стол.
///
/// Виджет рисуется без Flutter, поэтому выбирать строку атласа ему нечем:
/// приложение заранее режет три картинки, а натив показывает ту, что подходит
/// по часам и по серии.
enum MascotWidgetFrame { day, night, sad }

/// Окно «сна нет»: дневной кадр считается так, будто ночь не наступала.
const SleepWindow _kNeverSleeps = SleepWindow(from: 0, to: 0, enabled: false);

/// Режет кадры активного персонажа из его атласа.
///
/// [level] — ступень роста (1..3), та же, что у `MascotAnim.rectRow`.
/// [now] нужен для сезонного наряда: зимой Сезонник и на столе снеговик.
///
/// Картинка выходит один к одному со стороной кадра (48 или 96 точек).
/// Увеличивает её натив: RemoteViews всё равно перемасштабирует битмап под
/// ячейку, а большой PNG только жрёт Binder — на этом уже горели виджеты с
/// фотографиями.
Future<Map<MascotWidgetFrame, Uint8List>> renderMascotWidgetFrames({
  required ui.Image sheet,
  required MascotAnim anim,
  required int level,
  required DateTime now,
}) async {
  final out = <MascotWidgetFrame, Uint8List>{};

  final dayRow = anim.idleRow(now, _kNeverSleeps);
  final day = await _cut(sheet, anim, dayRow, level);
  if (day != null) out[MascotWidgetFrame.day] = day;

  if (anim.nightIdle.isNotEmpty) {
    final night = await _cut(sheet, anim, anim.nightIdle, level);
    if (night != null) out[MascotWidgetFrame.night] = night;
  }

  if (anim.has(MascotAnimState.sad)) {
    final sad = await _cut(sheet, anim, MascotAnimState.sad.name, level);
    if (sad != null) out[MascotWidgetFrame.sad] = sad;
  }

  return out;
}

/// Один кадр строки [row] в PNG. Нулевой столбец: в покое поза читается на
/// любом кадре, а выбирать «самый выразительный» неоткуда — атлас приходит с
/// сервера и приложение про персонажа ничего не знает.
Future<Uint8List?> _cut(
  ui.Image sheet,
  MascotAnim anim,
  String row,
  int level,
) async {
  final src = anim.rectRow(row, 0, level: level);
  final side = anim.frame.toDouble();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    sheet,
    src,
    ui.Rect.fromLTWH(0, 0, side, side),
    ui.Paint()
      // Пиксель-арт со сглаживанием превращается в мыло — то же правило, что
      // держит `PixelMascotView`.
      ..filterQuality = ui.FilterQuality.none
      ..isAntiAlias = false,
  );

  final image = await recorder.endRecording().toImage(anim.frame, anim.frame);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
