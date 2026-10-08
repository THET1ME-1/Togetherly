import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../dict_strings.dart' show trKey;
import '../models/chest.dart';
import '../services/locale_service.dart';
import '../theme/profile_theme.dart';
import '../utils/share_origin.dart';
import '../widgets/chest/chest_share_card.dart';
import '../widgets/common/app_dialog.dart';

/// «Поделиться» выпавшим призом: карточка 1080×1920 с подписью Togetherly.
/// До неё люди делали скриншот экрана сундука, и картинка уходила без имени
/// приложения. Устроено как экран сосуда: предпросмотр, «Сохранить»,
/// «Поделиться»; снимается сама карточка, а не экран.
class ChestShareScreen extends StatefulWidget {
  const ChestShareScreen({
    super.key,
    required this.prize,
    required this.title,
    required this.chance,
    required this.scheme,
    required this.fill,
    required this.openUrl,
    this.track,
  });

  final ChestPrize prize;
  final String title;
  final String chance;
  final ColorScheme scheme;
  final Color fill;
  final String? openUrl;

  /// Дорожка приза сезонного сундука; null — обычного.
  final List<List<double>?>? track;

  @override
  State<ChestShareScreen> createState() => _ChestShareScreenState();
}

class _ChestShareScreenState extends State<ChestShareScreen> {
  final GlobalKey _shot = GlobalKey();
  bool _busy = false;

  AppStrings get _s => LocaleService.current;

  /// Снимок карточки в её натуральном размере: масштаб предпросмотра на это
  /// не влияет, `toImage` снимает по локальным координатам границы.
  Future<File> _render() async {
    final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/togetherly_chest_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(data!.buffer.asUint8List());
    return file;
  }

  Future<void> _share() async {
    // Якорь для поповера iPad снимаем ДО первого await: дальше контекст уедет.
    final origin = shareOriginFromContext(context);
    setState(() => _busy = true);
    try {
      final file = await _render();
      await Share.shareXFiles([XFile(file.path)], sharePositionOrigin: origin);
    } catch (e) {
      debugPrint('сундук: поделиться не вышло: $e');
      if (mounted) AppSnack.error(context, _s.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final file = await _render();
      await Gal.putImage(file.path, album: 'Togetherly');
      if (mounted) AppSnack.success(context, _s.savedToGallery);
    } catch (e) {
      debugPrint('сундук: сохранить не вышло: $e');
      if (mounted) AppSnack.error(context, _s.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    final (tierKey, strong) = chestShareTier(widget.prize);
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLow,
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerLow,
          title: Text(trKey('chestShareScreen')),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: FittedBox(
                      child: RepaintBoundary(
                        key: _shot,
                        child: ChestShareCard(
                          prize: widget.prize,
                          title: widget.title,
                          tierLabel: trKey(tierKey),
                          strongTier: strong,
                          chance: widget.chance,
                          scheme: cs,
                          fill: widget.fill,
                          openUrl: widget.openUrl,
                          track: widget.track,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: Text(_s.save),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _share,
                        icon: const Icon(Icons.ios_share_rounded, size: 20),
                        label: Text(_s.share),
                      ),
                    ),
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
