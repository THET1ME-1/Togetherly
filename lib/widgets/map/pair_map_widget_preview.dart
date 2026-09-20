import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../../models/pair_map_widget_view.dart';
import '../../services/live_location_service.dart' show LivePoint;
import '../../services/map/pair_map_widget_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';

/// Превью виджета «Где мы» в каталоге приложения.
///
/// Показывает ту картинку, что уже стоит на рабочем столе (последняя
/// отрисовка), а до первой — демо: Кишинёв и Берлин на глобусе, нарисованные
/// тем же конвейером, что и сам виджет. Глобусу плитки не нужны, поэтому демо
/// рисуется без сети.
class PairMapWidgetPreview extends StatefulWidget {
  const PairMapWidgetPreview({
    super.key,
    required this.size,
    required this.theme,
    required this.groupId,
    required this.myName,
    required this.partnerName,
  });

  final MapWidgetSize size;
  final AppTheme theme;
  final String groupId;
  final String myName;
  final String partnerName;

  @override
  State<PairMapWidgetPreview> createState() => _PairMapWidgetPreviewState();
}

class _PairMapWidgetPreviewState extends State<PairMapWidgetPreview> {
  static final Map<String, Future<Map<MapWidgetSize, Uint8List>>> _demo = {};
  Future<File?>? _rendered;

  @override
  void initState() {
    super.initState();
    _rendered = _lastRendered();
  }

  Future<File?> _lastRendered() async {
    try {
      final key = Platform.isIOS
          ? PairMapWidgetService.iosKeys[widget.size]!
          : 'map_${widget.groupId.isEmpty ? 'solo' : widget.groupId}_img_${widget.size.id}';
      final path = await HomeWidget.getWidgetData<String>(key);
      if (path == null || path.isEmpty) return null;
      final f = File(path);
      return f.existsSync() ? f : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<MapWidgetSize, Uint8List>> _demoImages() {
    final cs = ProfileTheme.themeFor(widget.theme).colorScheme;
    final key = '${widget.theme.fillColor.toARGB32()}|${cs.brightness}|${widget.myName}|${widget.partnerName}';
    final now = DateTime.now().millisecondsSinceEpoch;
    return _demo[key] ??= renderPairMapWidgets(
      PairMapWidgetInput(
        paired: true,
        me: LivePoint(lat: 47.0245, lng: 28.8325, accuracy: 10, updatedAt: now),
        partner: LivePoint(lat: 52.52, lng: 13.405, accuracy: 10, updatedAt: now - 5 * 60000),
        myName: widget.myName,
        partnerName: widget.partnerName.isEmpty ? '♥' : widget.partnerName,
        scheme: cs,
        fill: widget.theme.fillColor,
        sizes: {for (final k in MapWidgetSize.values) k: k.size},
        nowMs: now,
      ),
      tiles: (_, _, _) async => null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AspectRatio(
      aspectRatio: s.width / s.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: FutureBuilder<File?>(
          future: _rendered,
          builder: (context, file) {
            final f = file.data;
            if (f != null) return Image.file(f, fit: BoxFit.cover, gaplessPlayback: true);
            if (file.connectionState != ConnectionState.done) return _placeholder();
            return FutureBuilder<Map<MapWidgetSize, Uint8List>>(
              future: _demoImages(),
              builder: (context, demo) {
                final bytes = demo.data?[s];
                if (bytes == null) return _placeholder();
                return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _placeholder() =>
      ColoredBox(color: ProfileTheme.themeFor(widget.theme).colorScheme.surfaceContainerHigh);
}
