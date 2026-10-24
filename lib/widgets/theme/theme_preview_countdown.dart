import 'dart:async';

import 'package:flutter/material.dart';

/// Остаток просмотра темы: «0:42». Секунды округляются вверх, поэтому в
/// первую секунду видно «1:00», а «0:00» не показывается, пока тема ещё стоит.
String themePreviewLeft(Duration left) {
  final seconds = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '${seconds ~/ 60}:$rest';
}

/// Подпись «Предпросмотр · 0:42» на плашке просмотра темы. Без остатка тема
/// гасла бы внезапно, и это читалось бы поломкой.
class ThemePreviewCountdown extends StatefulWidget {
  const ThemePreviewCountdown({
    super.key,
    required this.label,
    required this.endsAt,
    this.style,
    this.now = DateTime.now,
  });

  final String label;
  final DateTime? endsAt;
  final TextStyle? style;
  final DateTime Function() now;

  @override
  State<ThemePreviewCountdown> createState() => _ThemePreviewCountdownState();
}

class _ThemePreviewCountdownState extends State<ThemePreviewCountdown> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ends = widget.endsAt;
    final text = ends == null
        ? widget.label
        : '${widget.label} · ${themePreviewLeft(ends.difference(widget.now()))}';
    return Text(text, style: widget.style);
  }
}
