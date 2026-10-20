import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/launch_splash.dart';
import '../../services/launch_splash_service.dart';
import '../../services/locale_service.dart';
import '../../theme/profile_theme.dart';
import '../common/m3_loading.dart';
import 'launch_splash_view.dart';

/// «Заставка при запуске» в «Оформлении» (макет, вариант 1 «Ряд в
/// карточке», выбор владельца 20.10.2026): кадры заставок рядом, как
/// палитры. Нажатие выбирает заставку, скачивает её и проигрывает прямо в
/// кадре; играть при запуске она начнёт со следующего раза.
class LaunchSplashPicker extends StatefulWidget {
  const LaunchSplashPicker({super.key, required this.splashes});

  /// Заставки из каталога, что идут сегодня.
  final List<LaunchSplash> splashes;

  static const double tileWidth = 92;
  static const double tileHeight = 199;

  @override
  State<LaunchSplashPicker> createState() => _LaunchSplashPickerState();
}

class _LaunchSplashPickerState extends State<LaunchSplashPicker> {
  final LaunchSplashService _service = LaunchSplashService.instance;
  String? _downloading;
  String? _failed;
  bool _picked = false;
  LaunchSplash? _playing;
  Map<String, ui.Image>? _images;

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    _service.load().then((_) => _changed());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    _free(_images);
    super.dispose();
  }

  Future<void> _pick(LaunchSplash? splash) async {
    if (_downloading != null) return;
    setState(() {
      _failed = null;
      _picked = splash != null;
      _downloading = splash?.key;
    });
    final ok = await _service.select(splash);
    if (!mounted) return;
    setState(() {
      _downloading = null;
      if (!ok && splash != null) _failed = splash.key;
    });
    if (ok && splash != null) await _play();
  }

  /// Проиграть выбранную в её кадре: с диска, как при запуске.
  Future<void> _play() async {
    final local = await _service.readyForLaunch(DateTime.now());
    if (local == null) return;
    Map<String, ui.Image>? images;
    try {
      images = await LaunchSplashService.decode(local);
    } catch (e) {
      debugPrint('LaunchSplash: не разжать для показа: $e');
      return;
    }
    if (!mounted) {
      _free(images);
      return;
    }
    final old = _images;
    setState(() {
      _playing = local;
      _images = images;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _free(old));
  }

  void _stop() {
    if (!mounted) return;
    final old = _images;
    setState(() {
      _playing = null;
      _images = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _free(old));
  }

  void _free(Map<String, ui.Image>? images) {
    if (images == null) return;
    for (final image in images.values) {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = _service.selected;
    final lang = LocaleService.instance.language.code;
    String? note;
    Color? noteColor;
    if (_failed != null) {
      note = trKey('splashFailed');
      noteColor = cs.error;
    } else if (_downloading != null) {
      note = trKey('splashDownloading');
    } else if (_picked && selected.isNotEmpty) {
      note = trKey('splashNextLaunch');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _tile(
                cs,
                id: 'none',
                selected: selected.isEmpty,
                title: trKey('splashNone'),
                art: CustomPaint(painter: _NonePainter(cs.surface, cs.primary)),
                onTap: () => _pick(null),
              ),
              for (final splash in widget.splashes) ...[
                const SizedBox(width: 12),
                _tile(
                  cs,
                  id: splash.key,
                  selected: selected == splash.key,
                  busy: _downloading == splash.key,
                  title: splash.nameFor(lang),
                  sub: trKey('splashSeconds').replaceAll('{s}', _seconds(splash.ms, lang)),
                  art: _art(cs, splash),
                  onTap: () => _pick(splash),
                ),
              ],
            ],
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 2),
            child: Text(
              note,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 12.5,
                color: noteColor ?? cs.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _art(ColorScheme cs, LaunchSplash splash) {
    final playing = _playing;
    final images = _images;
    if (playing != null && images != null && playing.key == splash.key) {
      // Под заставкой — то же, что в кадре «Без заставки»: приложение.
      return Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _NonePainter(cs.surface, cs.primary)),
          LaunchSplashView(key: ValueKey(playing), splash: playing, images: images, onDone: _stop),
        ],
      );
    }
    final still = splash.stillUrl;
    final night = ColoredBox(color: splash.night);
    if (still == null) return night;
    return Image.network(still, fit: BoxFit.cover, errorBuilder: (_, _, _) => night);
  }

  Widget _tile(
    ColorScheme cs, {
    required String id,
    required bool selected,
    required String title,
    required Widget art,
    required VoidCallback onTap,
    String? sub,
    bool busy = false,
  }) {
    return SizedBox(
      width: LaunchSplashPicker.tileWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            selected: selected,
            label: title,
            child: GestureDetector(
              key: ValueKey('splash-tile-$id'),
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: LaunchSplashPicker.tileWidth,
                  height: LaunchSplashPicker.tileHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      art,
                      if (busy) Center(child: M3Loading(size: 32, color: cs.primary)),
                      // Обводка рисуется поверх кадра: у выбранного толще и цвета темы.
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected ? cs.primary : cs.outlineVariant,
                              width: selected ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                      if (selected)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                            child: Icon(Icons.check_rounded, size: 16, color: cs.onPrimary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: cs.onSurface,
            ),
          ),
          if (sub != null)
            Text(
              sub,
              maxLines: 1,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 13,
                height: 1.25,
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// «1,8» по-русски и по-европейски, «1.8» по-английски и по-китайски.
  static String _seconds(int ms, String lang) {
    final text = (ms / 1000).toStringAsFixed(1);
    return lang == 'en' || lang == 'zh' ? text : text.replaceAll('.', ',');
  }
}

/// Кадр «Без заставки»: так приложение запускается сейчас — фон темы и
/// фигура загрузки посередине.
class _NonePainter extends CustomPainter {
  const _NonePainter(this.background, this.blob);

  final Color background;
  final Color blob;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final center = size.center(Offset.zero);
    final r = size.width * 0.12;
    final path = Path();
    for (var i = 0; i <= 64; i++) {
      final a = i / 64 * math.pi * 2;
      final rr = r * (1 + 0.1 * math.cos(9 * a));
      final p = center + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = blob);
  }

  @override
  bool shouldRepaint(_NonePainter old) => old.background != background || old.blob != blob;
}
