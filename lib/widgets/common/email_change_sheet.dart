import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dict_strings.dart';
import '../../services/email_change_service.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';

/// Смена почты кодом: новый адрес → код из письма → готово. Возвращает новую
/// почту или null, если человек передумал.
Future<String?> showEmailChangeSheet(
  BuildContext context, {
  required ColorScheme scheme,
  EmailChangeService? service,
}) {
  return showAppSheet<String>(
    context,
    background: scheme.surfaceContainerLow,
    builder: (_) => Theme(
      data: ProfileTheme.data(scheme),
      child: EmailChangeSheet(service: service ?? EmailChangeService.instance),
    ),
  );
}

class EmailChangeSheet extends StatefulWidget {
  const EmailChangeSheet({super.key, required this.service});

  final EmailChangeService service;

  @override
  State<EmailChangeSheet> createState() => _EmailChangeSheetState();
}

class _EmailChangeSheetState extends State<EmailChangeSheet> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  /// Адрес, на который ушёл код. Пусто — первый шаг.
  String _sentTo = '';
  bool _busy = false;
  String _error = '';
  int _resendIn = 0;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _countdown(int seconds) {
    _tick?.cancel();
    setState(() => _resendIn = seconds);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  String _say(EmailChangeError e) => trKey('emailChangeErr.${e.name}');

  Future<void> _send() async {
    final email = _email.text.trim();
    if (email.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    final res = await widget.service.requestCode(email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      setState(() => _sentTo = email);
      _countdown(60);
    } else {
      setState(() => _error = _say(res.error!));
      if (res.error == EmailChangeError.wait && res.retryIn > 0) {
        _countdown(res.retryIn);
      }
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    final res = await widget.service.confirm(_sentTo, code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      Navigator.pop(context, res.email.isEmpty ? _sentTo : res.email);
    } else {
      setState(() => _error = _say(res.error!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final second = _sentTo.isNotEmpty;

    InputDecoration field(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: cs.surfaceContainerHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        );

    final progress = SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimary),
    );

    return SheetScaffold(
      title: trKey('emailChangeTitle'),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            key: const Key('email-change-main'),
            onPressed: _busy ? null : (second ? _confirm : _send),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56)),
            child: _busy
                ? progress
                : Text(trKey(second ? 'emailChangeConfirm' : 'emailChangeSend')),
          ),
          if (second) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _sentTo = '';
                            _code.clear();
                            _error = '';
                          }),
                  child: Text(trKey('emailChangeOther')),
                ),
                const Spacer(),
                TextButton(
                  key: const Key('email-change-resend'),
                  onPressed: _busy || _resendIn > 0
                      ? null
                      : () {
                          _email.text = _sentTo;
                          _send();
                        },
                  child: Text(_resendIn > 0
                      ? trKey('emailChangeResendIn')
                          .replaceAll('{s}', '$_resendIn')
                      : trKey('emailChangeResend')),
                ),
              ],
            ),
          ],
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!second) ...[
              Text(
                trKey('emailChangeHint'),
                style: AppFonts.onest(
                    size: 14.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('email-change-email'),
                controller: _email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: field(trKey('emailChangeNewLabel')),
              ),
            ] else ...[
              Text(
                trKey('emailChangeSentTo').replaceAll('{email}', _sentTo),
                style: AppFonts.onest(
                    size: 14.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('email-change-code'),
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textInputAction: TextInputAction.done,
                onChanged: (v) {
                  if (v.length == 6) _confirm();
                },
                style: AppFonts.unbounded(
                    size: 24, weight: 700, color: cs.onSurface),
                decoration: field(trKey('emailChangeCodeLabel')),
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _error,
                key: const Key('email-change-error'),
                style: AppFonts.onest(size: 14, weight: 600, color: cs.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
