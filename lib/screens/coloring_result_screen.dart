import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;

import '../models/coloring_picture.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../utils/share_origin.dart';
import '../widgets/common/app_dialog.dart';

/// Итог раскраски: рисунок целиком, поделиться и сохранить.
///
/// Картинка приходит уже склеенной — снимком холста с обеими половинами и
/// контуром поверх. Отдельным экраном, а не листом: рисунком любуются, а не
/// выбирают в нём что-то.
class ColoringResultScreen extends StatefulWidget {
  const ColoringResultScreen({
    super.key,
    required this.png,
    required this.picture,
    required this.theme,
    this.onToMemories,
  });

  final Uint8List png;
  final ColoringPicture picture;
  final AppTheme theme;

  /// Положить в ленту воспоминаний. null — пары нет, кнопки не будет.
  final Future<void> Function(File file)? onToMemories;

  @override
  State<ColoringResultScreen> createState() => _ColoringResultScreenState();
}

class _ColoringResultScreenState extends State<ColoringResultScreen> {
  bool _busy = false;

  AppStrings get _s => LocaleService.current;

  Future<File> _writeTemp() async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/coloring_${widget.picture.id}_'
      '${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(widget.png);
    return file;
  }

  Future<void> _share() async {
    // Origin для iPad-поповера считаем до await: дальше контекст может уехать.
    final origin = shareOriginFromContext(context);
    setState(() => _busy = true);
    try {
      final file = await _writeTemp();
      await Share.shareXFiles([XFile(file.path)], sharePositionOrigin: origin);
    } catch (e) {
      debugPrint('раскраска: поделиться не вышло: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final file = await _writeTemp();
      await Gal.putImage(file.path, album: 'Togetherly');
      if (!mounted) return;
      AppSnack.success(context, _s.coloringSaved);
    } catch (e) {
      debugPrint('раскраска: сохранить не вышло: $e');
      if (mounted) AppSnack.error(context, _s.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toMemories() async {
    final handler = widget.onToMemories;
    if (handler == null) return;
    setState(() => _busy = true);
    try {
      await handler(await _writeTemp());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('раскраска: в воспоминания не ушло: $e');
      if (mounted) AppSnack.error(context, _s.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(widget.theme);
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            _s.coloringRevealTitle,
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontSize: 19,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              color: cs.onSurface,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(widget.png, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.of(context).padding.bottom + 16,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _busy ? null : _share,
                            icon: const Icon(Icons.ios_share_rounded, size: 20),
                            label: Text(_s.coloringShare),
                            style: FilledButton.styleFrom(
                              shape: const StadiumBorder(),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _busy ? null : _save,
                            icon: const Icon(Icons.download_rounded, size: 20),
                            label: Text(_s.coloringSave),
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.surfaceContainerHigh,
                              foregroundColor: cs.onSurface,
                              shape: const StadiumBorder(),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.onToMemories != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _toMemories,
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(_s.coloringToMemories),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
