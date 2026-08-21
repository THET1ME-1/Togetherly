import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/note_recorder_service.dart';

/// Переключение камеры при съёмке фигурки.
///
/// CameraX отдаёт ВСЕ камеры устройства, а не пару: у телефона с широким и
/// макро-модулем список из четырёх штук. Перебор по кругу поэтому и выглядел
/// как «кнопка не работает» — с фронтальной попадаешь на второй тыловой
/// модуль, а обратно к себе возвращаешься через три нажатия.
CameraDescription _cam(String name, CameraLensDirection dir) =>
    CameraDescription(name: name, lensDirection: dir, sensorOrientation: 90);

void main() {
  final front = _cam('1', CameraLensDirection.front);
  final back = _cam('0', CameraLensDirection.back);
  final wide = _cam('2', CameraLensDirection.back);
  final macro = _cam('3', CameraLensDirection.back);

  test('Пара камер переключается туда и обратно', () {
    final cams = [front, back];
    expect(nextCameraIndex(cams, 0), 1);
    expect(nextCameraIndex(cams, 1), 0);
  });

  test('Лишние тыловые модули пропускаются', () {
    final cams = [back, wide, macro, front];
    expect(nextCameraIndex(cams, 3), 0, reason: 'с себя — на основную тыловую');
    expect(nextCameraIndex(cams, 0), 3, reason: 'с тыловой — сразу на себя');
    expect(nextCameraIndex(cams, 1), 3, reason: 'с широкой — тоже на себя');
  });

  test('Без фронтальной идём по кругу', () {
    final cams = [back, wide];
    expect(nextCameraIndex(cams, 0), 1);
    expect(nextCameraIndex(cams, 1), 0);
  });

  test('Одна камера остаётся на месте', () {
    expect(nextCameraIndex([front], 0), 0);
    expect(nextCameraIndex(const [], 0), 0);
  });

  test('Индекс вне списка не роняет выбор', () {
    expect(nextCameraIndex([front, back], 7), 0);
  });
}
