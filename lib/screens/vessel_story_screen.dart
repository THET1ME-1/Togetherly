import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/mood_vessel.dart';
import '../models/vessel_sharing.dart';
import '../services/locale_service.dart';
import '../theme/profile_theme.dart';
import '../utils/share_origin.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/mood/vessel_story_card.dart';

/// Экран «поделиться сосудом»: картинка 1080×1920 для сторис.
///
/// Что уходит в картинку, решает человек — галочки над кнопками. Настроения,
/// разговоры и воспоминания отмечены сразу, цикл и близость он включает сам:
/// сторис уходит людям, которых пара не выбирала.
class VesselStoryScreen extends StatefulWidget {
  const VesselStoryScreen({
    super.key,
    required this.days,
    required this.columns,
    required this.title,
    required this.scheme,
  });

  /// Кладка целиком, до отбора: снятые галочки применяются здесь.
  final List<VesselDay> days;
  final int columns;
  final String title;
  final ColorScheme scheme;

  @override
  State<VesselStoryScreen> createState() => _VesselStoryScreenState();
}

class _VesselStoryScreenState extends State<VesselStoryScreen> {
  final GlobalKey _shot = GlobalKey();
  Set<VesselFloor> _show = kDefaultSharedFloors;
  bool _busy = false;

  AppStrings get _s => LocaleService.current;

  List<VesselDay> get _days => vesselForSharing(widget.days, show: _show);

  void _toggle(Set<VesselFloor> kinds) {
    setState(() {
      final next = Set<VesselFloor>.from(_show);
      if (kinds.every(next.contains)) {
        next.removeAll(kinds);
      } else {
        next.addAll(kinds);
      }
      _show = next;
    });
  }

  /// Снимок карточки в её натуральном размере. Масштаб предпросмотра на это не
  /// влияет: `toImage` снимает по локальным координатам границы.
  Future<File> _render() async {
    final boundary =
        _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/togetherly_vessel_'
      '${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(data!.buffer.asUint8List() as Uint8List);
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
      debugPrint('сосуд: поделиться не вышло: $e');
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
      debugPrint('сосуд: сохранить не вышло: $e');
      if (mounted) AppSnack.error(context, _s.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLow,
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerLow,
          title: Text(_s.vesselShareTitle),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _shot,
                      child: VesselStoryCard(
                        days: _days,
                        columns: widget.columns,
                        title: widget.title,
                        daysCaption: _s.vesselStoryDays,
                        scheme: cs,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _chip(_s.vesselLegendMood, Icons.emoji_emotions_rounded,
                        {VesselFloor.mine, VesselFloor.partner}),
                    _chip(_s.vesselLegendChat, Icons.chat_bubble_rounded,
                        {VesselFloor.chat}),
                    _chip(_s.vesselLegendMemory, Icons.photo_camera_rounded,
                        {VesselFloor.memory}),
                    _chip(_s.vesselLegendCycle, Icons.water_drop_rounded,
                        {VesselFloor.cycle, VesselFloor.partnerCycle}),
                    _chip(_s.cycleLegendIntimacy, Icons.favorite_rounded,
                        {VesselFloor.intimacy}),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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

  Widget _chip(String label, IconData icon, Set<VesselFloor> kinds) {
    final on = kinds.every(_show.contains);
    return FilterChip(
      selected: on,
      showCheckmark: false,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onSelected: (_) => _toggle(kinds),
    );
  }
}
