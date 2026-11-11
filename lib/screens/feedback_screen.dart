import 'package:flutter/material.dart';

import '../dict_strings.dart';
import '../models/feedback.dart';
import '../services/feedback_service.dart';
import '../theme/profile_theme.dart';

/// «Сообщить о проблеме»: обращение уходит на наш сервер прямо из приложения.
///
/// Google Play требует, чтобы о проблеме (и отдельно — о безопасности детей)
/// можно было сообщить, не выходя из приложения: 1.42 отклонили 11.11.2026,
/// потому что поддержка открывала почту, а «Написать нам» — Telegram. Отсюда
/// правило экрана: никаких внешних переходов.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({
    super.key,
    required this.scheme,
    required this.accountEmail,
    this.initialKind = FeedbackKind.bug,
    this.send,
  });

  final ColorScheme scheme;

  /// Почта аккаунта: на неё придёт ответ. Пустая — у входа без почты.
  final String accountEmail;

  final FeedbackKind initialKind;

  /// Отправка; в тесте подменяется, в приложении — [FeedbackService].
  final Future<FeedbackSent> Function(FeedbackKind kind, String text)? send;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _text = TextEditingController();
  late FeedbackKind _kind = widget.initialKind;
  bool _sending = false;
  bool _sent = false;

  /// Что показать под полем после отказа.
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  static String _labelOf(FeedbackKind kind) => switch (kind) {
    FeedbackKind.bug => trKey('fb.kindBug'),
    FeedbackKind.idea => trKey('fb.kindIdea'),
    FeedbackKind.payment => trKey('fb.kindPayment'),
    FeedbackKind.abuse => trKey('fb.kindAbuse'),
    FeedbackKind.childSafety => trKey('fb.kindChild'),
    FeedbackKind.other => trKey('fb.kindOther'),
  };

  static IconData _iconOf(FeedbackKind kind) => switch (kind) {
    FeedbackKind.bug => Icons.bug_report_rounded,
    FeedbackKind.idea => Icons.lightbulb_rounded,
    FeedbackKind.payment => Icons.payments_rounded,
    FeedbackKind.abuse => Icons.flag_rounded,
    FeedbackKind.childSafety => Icons.shield_rounded,
    FeedbackKind.other => Icons.chat_bubble_rounded,
  };

  Future<void> _submit() async {
    if (_sending) return;
    if (!feedbackReady(_text.text)) {
      setState(() => _error = trKey('fb.tooShort'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final send = widget.send ?? const FeedbackService().send;
    final result = await send(_kind, _text.text.trim());
    if (!mounted) return;
    setState(() {
      _sending = false;
      switch (result) {
        case FeedbackSent.ok:
          _sent = true;
        case FeedbackSent.tooMany:
          _error = trKey('fb.errTooMany');
        case FeedbackSent.failed:
          _error = trKey('fb.errFailed');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(
            trKey('fb.title'),
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        body: SafeArea(child: _sent ? _done(cs) : _form(cs)),
      ),
    );
  }

  TextStyle _body(ColorScheme cs, {double size = 15, Color? color}) =>
      TextStyle(
        fontFamily: ProfileTheme.bodyFont,
        fontSize: size,
        height: 1.35,
        color: color ?? cs.onSurfaceVariant,
      );

  Widget _form(ColorScheme cs) {
    final reply = widget.accountEmail.isEmpty
        ? trKey('fb.replyNoMail')
        : trKey('fb.replyTo').replaceAll('{0}', widget.accountEmail);
    // Кнопка закреплена под списком: на невысоком экране с открытой
    // клавиатурой она иначе уезжала за край, и отправить было нечем.
    return Column(
      children: [
        Expanded(child: _fields(cs, reply)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              key: const Key('feedback_send'),
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  : Text(
                      trKey('fb.send'),
                      style: const TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fields(ColorScheme cs, String reply) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        Text(trKey('fb.intro'), style: _body(cs)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in FeedbackKind.values)
              ChoiceChip(
                key: Key('feedback_kind_${kind.wire}'),
                avatar: Icon(
                  _iconOf(kind),
                  size: 18,
                  color: _kind == kind
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
                ),
                label: Text(_labelOf(kind)),
                selected: _kind == kind,
                showCheckmark: false,
                onSelected: _sending
                    ? null
                    : (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        if (_kind == FeedbackKind.childSafety) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_rounded,
                    size: 20, color: cs.onTertiaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    trKey('fb.childNote'),
                    style: _body(cs, size: 14, color: cs.onTertiaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          key: const Key('feedback_text'),
          controller: _text,
          enabled: !_sending,
          minLines: 6,
          maxLines: 12,
          maxLength: kFeedbackMax,
          textCapitalization: TextCapitalization.sentences,
          style: _body(cs, size: 16, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: trKey('fb.hint'),
            hintStyle: _body(cs, size: 16),
            errorText: _error,
            errorMaxLines: 3,
            filled: true,
            fillColor: cs.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
        const SizedBox(height: 4),
        Text(reply, style: _body(cs, size: 13)),
      ],
    );
  }

  Widget _done(ColorScheme cs) {
    final reply = widget.accountEmail.isEmpty
        ? trKey('fb.sentNoMail')
        : trKey('fb.sentBody').replaceAll('{0}', widget.accountEmail);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded,
                  size: 44, color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            trKey('fb.sentTitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(reply, textAlign: TextAlign.center, style: _body(cs)),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: FilledButton.tonal(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(
                trKey('fb.done'),
                style: const TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
