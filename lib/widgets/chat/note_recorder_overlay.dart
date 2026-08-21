import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../services/note_recorder_service.dart';
import '../../theme/motion.dart';
import 'note_shape_view.dart';
import 'note_shapes.dart';

/// Экран съёмки фигурки поверх чата.
///
/// Чат остаётся видимым за размытием — это не декорация: человек снимает ответ
/// на конкретное сообщение и должен видеть, на какое. Управление разнесено по
/// краям, центр отдан кадру.
///
/// Сам виджет ничем не владеет: камеру держит [NoteRecorderService], состояние
/// — экран чата. Здесь только отрисовка и жесты.
class NoteRecorderOverlay extends StatelessWidget {
  final CameraController? controller;

  /// Выбранная форма и вся лента для выбора.
  final NoteShape shape;
  final ValueChanged<NoteShape> onShape;

  /// Сколько уже снято — тикает каждые 60 мс.
  final ValueListenable<Duration> elapsed;

  final bool recording;
  final bool paused;

  /// Запись закреплена: палец убран, съёмка идёт дальше.
  final bool locked;

  /// Палец уведён влево — отпустит, и снятое пропадёт.
  final bool cancelling;

  final bool mirrored;
  final bool torchOn;
  final bool canFlip;
  final bool canTorch;

  /// Причина, по которой снимать нельзя (нет разрешения, камера занята).
  final String? error;

  /// Ещё одна попытка поднять камеру: разрешение выдали не с первого раза.
  final VoidCallback onRetry;

  final VoidCallback onFlip;
  final VoidCallback onTorch;
  final VoidCallback onMirror;
  final VoidCallback onPauseToggle;
  final VoidCallback onCancel;
  final VoidCallback onSend;
  final VoidCallback onClose;

  const NoteRecorderOverlay({
    super.key,
    required this.controller,
    required this.shape,
    required this.onShape,
    required this.elapsed,
    required this.recording,
    required this.paused,
    required this.locked,
    required this.cancelling,
    required this.mirrored,
    required this.torchOn,
    required this.canFlip,
    required this.canTorch,
    required this.error,
    required this.onRetry,
    required this.onFlip,
    required this.onTorch,
    required this.onMirror,
    required this.onPauseToggle,
    required this.onCancel,
    required this.onSend,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = LocaleService.current;
    final media = MediaQuery.of(context);
    // Фигура крупная, но не в край: у звёздочки лучи должны дышать.
    final side = (media.size.width * 0.76)
        .clamp(180.0, media.size.height * 0.44)
        .toDouble();

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Плотная поверхность вместо размытия. Размытие всего чата стоит
          // полного прохода по кадру каждые шестнадцать миллисекунд — на нём
          // и проседала съёмка; к тому же снимать удобнее, когда за кадром
          // ничего не мелькает.
          Positioned.fill(
            child: ColoredBox(color: cs.surface.withValues(alpha: 0.97)),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  _topBar(context, cs, s),
                  Expanded(
                    child: Center(
                      child: error != null
                          ? _errorBlock(cs, s)
                          : _stage(context, cs, side),
                    ),
                  ),
                  _shapeStrip(cs),
                  const SizedBox(height: 12),
                  _bottomBar(context, cs, s),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context, ColorScheme cs, AppStrings s) {
    // Держать палец не нужно: удержание только запускает съёмку. Поэтому и
    // подсказки другие, чем у голосовых, — про отмену и отправку, а не про
    // «вверх, чтобы закрепить».
    final hint = cancelling
        ? s.noteReleaseToCancel
        : recording
            ? (locked ? s.noteTapToSend : s.noteHandsFreeHint)
            : s.noteHoldToRecord;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.short4,
              child: Text(
                hint,
                key: ValueKey(hint),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: cancelling ? FontWeight.w700 : FontWeight.w500,
                  color: cancelling ? cs.error : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _stage(BuildContext context, ColorScheme cs, double side) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _sideTools(cs),
        // Обод слушает таймер сам: перерисовывается ТОЛЬКО он, а превью
        // камеры и маска формы остаются нетронутыми. Раньше здесь стоял
        // ValueListenableBuilder вокруг всего вида, и шестнадцать раз в
        // секунду пересобиралось дерево вместе с CameraPreview.
        NoteShapeView(
          shape: shape,
          size: side,
          ringColor: cancelling ? cs.error : cs.primary,
          trackColor: cs.outlineVariant.withValues(alpha: 0.5),
          ringWidth: 5,
          ringListenable: elapsed,
          ringValue: () => recording
              ? (elapsed.value.inMilliseconds /
                      NoteRecorderService.maxDuration.inMilliseconds)
                  .clamp(0.0, 1.0)
              : 0.0,
          child: _preview(cs),
        ),
        _pauseButton(cs),
      ],
    );
  }

  Widget _preview(ColorScheme cs) {
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      return ColoredBox(
        color: cs.surfaceContainerHigh,
        child: Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    // Превью зеркалим, файл — нет: иначе надпись на футболке уедет задом
    // наперёд у того, кто будет смотреть.
    final preview = FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: c.value.previewSize?.height ?? 1,
        height: c.value.previewSize?.width ?? 1,
        child: CameraPreview(c),
      ),
    );
    if (!mirrored) return preview;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
      child: preview,
    );
  }

  Widget _sideTools(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canFlip)
            _RoundTool(
              icon: Icons.cameraswitch_rounded,
              onTap: recording && !paused ? null : onFlip,
              cs: cs,
            ),
          if (canTorch) ...[
            const SizedBox(height: 10),
            _RoundTool(
              icon: torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              active: torchOn,
              onTap: onTorch,
              cs: cs,
            ),
          ],
          const SizedBox(height: 10),
          _RoundTool(
            icon: Icons.flip_rounded,
            active: mirrored,
            onTap: onMirror,
            cs: cs,
          ),
        ],
      ),
    );
  }

  Widget _pauseButton(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: _RoundTool(
        icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        onTap: recording ? onPauseToggle : null,
        cs: cs,
      ),
    );
  }

  /// Лента форм: тап меняет маску морфом, съёмка при этом не прерывается.
  Widget _shapeStrip(ColorScheme cs) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: kNoteShapes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final item = kNoteShapes[i];
          final active = item.id == shape.id;
          return GestureDetector(
            onTap: () => onShape(item),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: Motion.short4,
              curve: Motion.standard,
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? cs.secondaryContainer : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: AnimatedScale(
                duration: Motion.short4,
                curve: Motion.emphasized,
                scale: active ? 1.08 : 0.92,
                child: NoteShapeGlyph(
                  shape: item,
                  size: 28,
                  color: active ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bottomBar(BuildContext context, ColorScheme cs, AppStrings s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: Motion.short4,
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cancelling ? cs.errorContainer : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                children: [
                  _RecDot(
                    color: cancelling ? cs.onErrorContainer : cs.error,
                    active: recording && !paused,
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 58,
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: elapsed,
                      builder: (_, value, _) => Text(
                        _fmt(value),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: cancelling
                              ? cs.onErrorContainer
                              : cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (recording)
                    TextButton(
                      onPressed: onCancel,
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                      child: Text(s.cancel),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Отправка доступна, когда снятое уже есть: до этого кнопка
          // приглушена, чтобы по ней не били впустую.
          AnimatedScale(
            duration: Motion.short4,
            curve: Motion.emphasized,
            scale: recording ? 1 : 0.92,
            child: IconButton.filled(
              onPressed: recording ? onSend : null,
              icon: const Icon(Icons.send_rounded, size: 22),
              style: IconButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                disabledBackgroundColor: cs.surfaceContainerHighest,
                disabledForegroundColor: cs.onSurfaceVariant,
                minimumSize: const Size(56, 56),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBlock(ColorScheme cs, AppStrings s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_rounded, size: 40, color: cs.error),
          const SizedBox(height: 12),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: cs.onSurface),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(onPressed: onClose, child: Text(s.close)),
              const SizedBox(width: 8),
              FilledButton(onPressed: onRetry, child: Text(s.retry)),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final sec = d.inSeconds % 60;
    final tenth = (d.inMilliseconds % 1000) ~/ 100;
    return '$m:${sec.toString().padLeft(2, '0')},$tenth';
  }
}

class _RoundTool extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final ColorScheme cs;

  const _RoundTool({
    required this.icon,
    required this.onTap,
    required this.cs,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor:
            active ? cs.secondaryContainer : cs.surfaceContainerHigh,
        foregroundColor: active
            ? cs.onSecondaryContainer
            : (enabled ? cs.onSurfaceVariant : cs.outlineVariant),
        minimumSize: const Size(42, 42),
      ),
    );
  }
}

/// Точка записи. Пульсирует, только пока идёт съёмка: на паузе она горит ровно.
class _RecDot extends StatefulWidget {
  final Color color;
  final bool active;
  const _RecDot({required this.color, required this.active});

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _RecDot old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.25).animate(_c),
        child: Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      );
}
