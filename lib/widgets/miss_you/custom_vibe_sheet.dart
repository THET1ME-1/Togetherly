import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';

/// Ввод своего пожелания. Возвращает текст или `null`, если человек передумал.
Future<String?> showCustomVibeSheet(
  BuildContext context, {
  required AppTheme theme,
}) {
  final s = LocaleService.current;
  return showAppSheet<String>(
    context,
    builder: (_) => _CustomVibeSheet(
      scheme: ProfileTheme.schemeFor(theme),
      title: s.customVibeTitle,
      hint: s.customVibeHint,
      sendLabel: s.post,
      cancelLabel: s.cancel,
    ),
  );
}

class _CustomVibeSheet extends StatefulWidget {
  final ColorScheme scheme;
  final String title;
  final String hint;
  final String sendLabel;
  final String cancelLabel;

  const _CustomVibeSheet({
    required this.scheme,
    required this.title,
    required this.hint,
    required this.sendLabel,
    required this.cancelLabel,
  });

  @override
  State<_CustomVibeSheet> createState() => _CustomVibeSheetState();
}

class _CustomVibeSheetState extends State<_CustomVibeSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;

    return SheetScaffold(
      title: widget.title,
      bottom: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                widget.cancelLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                widget.sendLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(fontSize: 15, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: cs.onSurfaceVariant),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            counterStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
    );
  }
}
