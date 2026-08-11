import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../theme/profile_theme.dart';
import '../widgets/common/m3_loading.dart';

/// Съёмка снапа: удержание кнопки пишет ролик на пару секунд.
///
/// Быстрое фото на главной снимает системная камера через `image_picker` — там
/// снимок и так уходит в один тап. Ролик так не снять: `pickVideo` открывает
/// системную камеру, где запись включается и выключается отдельными нажатиями,
/// а нужно именно удержание. Поэтому здесь своё превью на пакете `camera`.
///
/// Предел в три секунды не выдуман: ролик уезжает живым фото в парный виджет,
/// а сервер режет его на восемнадцать кадров (`tools/widget_anim.py`). Длиннее
/// — и движение распадётся на слайд-шоу.
class SnapCaptureScreen extends StatefulWidget {
  const SnapCaptureScreen({super.key, required this.theme});

  final AppTheme theme;

  @override
  State<SnapCaptureScreen> createState() => _SnapCaptureScreenState();
}

class _SnapCaptureScreenState extends State<SnapCaptureScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cam;
  List<CameraDescription> _cameras = const [];
  int _index = 0;
  bool _recording = false;
  bool _failed = false;

  /// Палец ушёл раньше, чем камера подняла запись.
  bool _stopRequested = false;

  /// Кольцо вокруг кнопки: три секунды на полный круг.
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: maxClip,
  );

  static const Duration maxClip = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _ring.addStatusListener((s) {
      // Дошли до края — останавливаем сами, чтобы ролик не рос дальше предела.
      if (s == AnimationStatus.completed && _recording) _stop();
    });
    _start();
  }

  @override
  void dispose() {
    _ring.dispose();
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _failed = true);
        return;
      }
      // Начинаем с фронтальной: снап у пары почти всегда про лицо.
      _index = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_index < 0) _index = 0;
      await _open(_index);
    } catch (e) {
      debugPrint('SnapCapture: камера не поднялась — $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _open(int index) async {
    await _cam?.dispose();
    final controller = CameraController(
      _cameras[index],
      // Средним качеством: ролик всё равно уедет в раскадровку 300 px, а
      // высокое разрешение только раздувает файл и упирается в предел 25 МБ.
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _cam = controller;
      _index = index;
    });
  }

  Future<void> _flip() async {
    if (_cameras.length < 2 || _recording) return;
    await _open((_index + 1) % _cameras.length);
  }

  Future<void> _hold() async {
    final cam = _cam;
    if (cam == null || _recording || !cam.value.isInitialized) return;
    _stopRequested = false;
    HapticFeedback.mediumImpact();
    try {
      await cam.startVideoRecording();
      if (!mounted) return;
      setState(() => _recording = true);
      _ring.forward(from: 0);
      // Камера поднимается не мгновенно, и палец успевает уйти раньше. Без
      // этой проверки отпускание пропадало впустую, кольцо докручивало свои
      // три секунды и закрывало экран роликом, которого никто не просил.
      if (_stopRequested) await _stop();
    } catch (e) {
      debugPrint('SnapCapture: запись не началась — $e');
    }
  }

  Future<void> _stop() async {
    final cam = _cam;
    if (cam == null) return;
    if (!_recording) {
      // Запись ещё стартует — остановит её сам `_hold`, как только дождётся.
      _stopRequested = true;
      return;
    }
    _stopRequested = false;
    _ring.stop();
    setState(() => _recording = false);
    try {
      final file = await cam.stopVideoRecording();
      if (!mounted) return;
      // Совсем короткое нажатие роликом не считается: пусть человек подержит.
      if (_ring.value < 0.16) {
        _ring.value = 0;
        return;
      }
      Navigator.of(context).pop(file.path);
    } catch (e) {
      debugPrint('SnapCapture: запись не остановилась — $e');
      _ring.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(widget.theme);
    final s = LocaleService.current;
    final cam = _cam;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_failed)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  s.cameraPermissionDenied,
                  textAlign: TextAlign.center,
                  style: AppFonts.onest(size: 14, color: Colors.white70),
                ),
              ),
            )
          else if (cam == null || !cam.value.isInitialized)
            const Center(child: M3Loading(color: Colors.white, size: 48))
          else
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: cam.value.previewSize?.height ?? 1,
                  height: cam.value.previewSize?.width ?? 1,
                  child: CameraPreview(cam),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                    const Spacer(),
                    if (_cameras.length > 1)
                      IconButton(
                        onPressed: _flip,
                        icon: const Icon(Icons.cameraswitch_rounded,
                            color: Colors.white),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  _recording ? s.snapRecording : s.snapHoldToRecord,
                  style: AppFonts.onest(
                      size: 14, weight: 600, color: Colors.white),
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  onLongPressStart: (_) => _hold(),
                  onLongPressEnd: (_) => _stop(),
                  onLongPressCancel: _stop,
                  child: AnimatedBuilder(
                    animation: _ring,
                    builder: (context, _) => CustomPaint(
                      size: const Size(96, 96),
                      painter: _ShutterPainter(
                        color: cs.primary,
                        progress: _ring.value,
                        recording: _recording,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShutterPainter extends CustomPainter {
  _ShutterPainter({
    required this.color,
    required this.progress,
    required this.recording,
  });

  final Color color;
  final double progress;
  final bool recording;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;

    canvas.drawCircle(
      center,
      r - 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white.withValues(alpha: 0.6),
    );
    // Кружок внутри сжимается на записи — знакомый жест из мессенджеров.
    canvas.drawCircle(
      center,
      recording ? r * 0.42 : r * 0.66,
      Paint()..color = recording ? color : Colors.white,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r - 3),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ShutterPainter old) =>
      old.progress != progress || old.recording != recording;
}
