import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../utils/qr_decoder.dart';
import '../common/m3_loading.dart';

/// Сканер QR без ML Kit: камера плюс чистый Dart-декодер.
///
/// Стоит в сборках вне Google Play и там, где сервисов Google на телефоне нет.
/// Модель распознавания ML Kit туда не поставить — её движок нативный, скачать
/// его неоткуда, а вшивать 5,5 МБ ради одного экрана дорого. `zxing2` весит
/// как кусок кода и качать не требует ничего.
///
/// Читаем не каждый кадр: камера отдаёт тридцать в секунду, декодер живёт в
/// том же изоляте, и разбор каждого кадра положил бы плавность превью. Хватает
/// нескольких попыток в секунду — код держат перед камерой секундами.
class ZxingScanView extends StatefulWidget {
  const ZxingScanView({
    super.key,
    required this.onCode,
    required this.onUnavailable,
  });

  /// Распознанная строка. Экран сам решает, что в ней code, а что ссылка.
  final void Function(String value) onCode;

  /// Камеры нет или в ней отказано — показать понятное окно вместо чёрноты.
  final VoidCallback onUnavailable;

  @override
  State<ZxingScanView> createState() => _ZxingScanViewState();
}

class _ZxingScanViewState extends State<ZxingScanView> {
  CameraController? _controller;
  final QrDecoder _decoder = QrDecoder();

  /// Разбор идёт прямо сейчас — следующие кадры пропускаем целиком.
  bool _busy = false;
  bool _done = false;
  DateTime _lastTry = DateTime.fromMillisecondsSinceEpoch(0);

  /// Четыре попытки в секунду: чаще не нужно, реже — заметная задержка.
  static const Duration _interval = Duration(milliseconds: 250);

  /// Сторона картинки, которую отдаём декодеру. Шесть символов читаются и с
  /// трёхсот точек, а полный кадр — миллион чисел на каждый разбор.
  static const int _maxSide = 320;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    final c = _controller;
    _controller = null;
    c?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        widget.onUnavailable();
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        // Формат задаём явно: по умолчанию на Android приезжает JPEG-поток, а
        // из него плоскость яркости не достать.
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.startImageStream(_onFrame);
      setState(() => _controller = controller);
    } catch (e) {
      debugPrint('ZxingScanView: камера не поднялась — $e');
      if (mounted) widget.onUnavailable();
    }
  }

  void _onFrame(CameraImage image) {
    if (_busy || _done) return;
    final now = DateTime.now();
    if (now.difference(_lastTry) < _interval) return;
    _lastTry = now;
    _busy = true;

    try {
      final code = _decode(image);
      if (code != null && !_done) {
        _done = true;
        widget.onCode(code);
      }
    } catch (_) {
      // Кадр не читается — это норма, а не сбой: их тридцать в секунду.
    } finally {
      _busy = false;
    }
  }

  String? _decode(CameraImage image) {
    final plane = image.planes.first;
    return _decoder.decode(
      bytes: plane.bytes,
      bytesPerRow: plane.bytesPerRow,
      width: image.width,
      height: image.height,
      // На iOS кадр приходит BGRA — четыре байта на точку; берётся первый
      // канал, для чёрно-белого квадрата разницы нет.
      bytesPerPixel: Platform.isIOS ? 4 : 1,
      maxSide: _maxSide,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: M3Loading(color: Colors.white, size: 48));
    }
    // Превью растягиваем по короткой стороне и обрезаем: иначе камера с
    // соотношением 4:3 оставляет чёрные поля на пол-экрана.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 1,
          height: controller.value.previewSize?.width ?? 1,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
