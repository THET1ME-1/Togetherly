import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dict_strings.dart';
import '../../models/partner_reset.dart';
import '../../services/pb_auth_service.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../../widgets/auth/ink.dart';
import 'new_password_screen.dart';

/// Ввод кода от партнёра (макет «Вход без писем», 1-А, второй экран).
///
/// Код уже ушёл партнёру: экран открывается после ответа `via: partner`.
/// Отвечает `true`, когда человек задал новый пароль и вошёл.
class PartnerCodeScreen extends StatefulWidget {
  const PartnerCodeScreen({
    super.key,
    required this.email,
    this.ttl = const Duration(minutes: 10),
  });

  final String email;

  /// Сколько живёт код (сервер — `CODE_TTL_MS`).
  final Duration ttl;

  @override
  State<PartnerCodeScreen> createState() => _PartnerCodeScreenState();
}

class _PartnerCodeScreenState extends State<PartnerCodeScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  late DateTime _deadline;
  Timer? _tick;
  bool _busy = false;
  String? _error;

  /// Код уже не годится: истёк, заперт промахами или погашен партнёром.
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _deadline = DateTime.now().add(widget.ttl);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (!_gone && DateTime.now().isAfter(_deadline)) {
          _gone = true;
          _error = trKey('prCodeExpired');
        }
      });
    });
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text;
    if (_busy || code.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ticket = await PbAuthService().verifyPartnerCode(widget.email, code);
      if (!mounted) return;
      setState(() => _busy = false);
      final done = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => NewPasswordScreen(ticket: ticket)),
      );
      if (done == true && mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final failure = partnerResetFailureOf(e);
      setState(() {
        _busy = false;
        _code.clear();
        switch (failure) {
          case PartnerResetFailure.wrong:
            _error = trKey('prWrong').replaceAll('{0}', '${triesLeftOf(e)}');
          case PartnerResetFailure.locked:
            _gone = true;
            _error = trKey('prLocked');
          case PartnerResetFailure.expired || PartnerResetFailure.none:
            _gone = true;
            _error = trKey('prGone');
          case PartnerResetFailure.network:
            _error = trKey('serverSlowRetry');
          default:
            _error = trKey('serverSlowRetry');
        }
      });
    }
  }

  Future<void> _askAgain() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final via = await PbAuthService().requestPartnerReset(widget.email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (via == 'partner') {
          _gone = false;
          _code.clear();
          _deadline = DateTime.now().add(widget.ttl);
        } else {
          _error = trKey('prGone');
        }
      });
    } catch (e) {
      if (!mounted) return;
      final failure = partnerResetFailureOf(e);
      setState(() {
        _busy = false;
        _error = switch (failure) {
          PartnerResetFailure.gap => trKey('prGone'),
          PartnerResetFailure.day => trKey('prDayLimit'),
          _ => trKey('serverSlowRetry'),
        };
      });
    }
  }

  Future<void> _byEmail() async {
    try {
      await PbAuthService().sendPasswordReset(widget.email);
    } catch (_) {
      // Ошибку письма разберёт экран входа при повторе: здесь только уходим.
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop(false);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(trKey('prViaEmailHint').replaceAll('{0}', widget.email)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    final left = _deadline.difference(DateTime.now());
    final secs = left.isNegative ? 0 : left.inSeconds;
    final leftText = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';

    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(backgroundColor: cs.surface, elevation: 0),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Text(
                trKey('prCodeTitle'),
                style: TextStyle(
                  fontFamily: ProfileTheme.displayFont,
                  fontSize: 26,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                trKey('prCodeText'),
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 15,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              _CodeCells(
                controller: _code,
                focus: _focus,
                enabled: !_gone && !_busy,
                onComplete: _verify,
              ),
              const SizedBox(height: 14),
              Text(
                _error ?? trKey('prCodeLeft').replaceAll('{0}', leftText),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 14,
                  color: _error == null ? cs.onSurfaceVariant : cs.error,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: _gone
                    ? FilledButton(
                        onPressed: _busy ? null : _askAgain,
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                        child: Text(trKey('prAskAgain')),
                      )
                    : FilledButton(
                        onPressed:
                            _busy || _code.text.length != 6 ? null : _verify,
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                        child: Text(trKey('prNext')),
                      ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _byEmail,
                child: Text(
                  trKey('prNoPartner'),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Шесть ячеек кода поверх невидимого поля: клавиатура, вставка и
/// автозаполнение кода работают как у обычного поля.
class _CodeCells extends StatelessWidget {
  const _CodeCells({
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.onComplete,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = controller.text;
    Widget cell(int i) {
      final active = enabled && i == text.length;
      return Expanded(
        child: AspectRatio(
          aspectRatio: 0.78,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? cs.primaryContainer : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: active ? Border.all(color: cs.primary, width: 2) : null,
            ),
            child: Text(
              i < text.length ? text[i] : '',
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: active
                    ? inkOn(
                        cs.primaryContainer,
                        cs.onPrimaryContainer,
                        cs.onSurface,
                      )
                    : cs.onSurface,
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              cell(i),
            ],
            const SizedBox(width: 16),
            for (var i = 3; i < 6; i++) ...[
              if (i > 3) const SizedBox(width: 8),
              cell(i),
            ],
          ],
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focus,
              enabled: enabled,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              showCursor: false,
              enableInteractiveSelection: false,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
              ),
              onChanged: (v) {
                if (v.length == 6) onComplete();
              },
            ),
          ),
        ),
      ],
    );
  }
}
