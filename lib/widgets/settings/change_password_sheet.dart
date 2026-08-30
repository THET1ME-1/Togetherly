import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart' show ClientException;

import '../../models/password_change.dart';
import '../../services/locale_service.dart';
import '../../services/pb_auth_service.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';

/// Смена пароля тем, кто уже вошёл.
///
/// Письмо тут ни к чему: человек в аккаунте, помнит текущий пароль и хочет
/// новый. Письмо остаётся запасным путём — для забывших и для тех, кто входил
/// через Google или Apple: пароля у них нет вовсе, и «текущий» вводить нечего.
///
/// Возвращает `true`, если пароль сменён, `'mail'` — если человек попросил
/// письмо, и `null`, если лист просто закрыли.
Future<Object?> showChangePasswordSheet(
  BuildContext context, {
  required ColorScheme scheme,
}) {
  return showAppSheet<Object?>(
    context,
    background: scheme.surfaceContainerHigh,
    builder: (ctx) => Theme(
      // Лист живёт выше экрана и цвета берёт у MaterialApp, а не у того, кто
      // его открыл: без этого он выезжает в чужой теме.
      data: ProfileTheme.data(scheme),
      child: _ChangePasswordSheet(scheme: scheme),
    ),
  );
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet({required this.scheme});

  final ColorScheme scheme;

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _fresh = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String _error = '';

  AppStrings get _s => LocaleService.current;

  @override
  void dispose() {
    _current.dispose();
    _fresh.dispose();
    _repeat.dispose();
    super.dispose();
  }

  String _textFor(PasswordChangeProblem p) => switch (p) {
        PasswordChangeProblem.noCurrent => _s.passwordCurrent,
        PasswordChangeProblem.tooShort => _s.passwordTooShort,
        PasswordChangeProblem.mismatch => _s.passwordsDiffer,
        PasswordChangeProblem.same => _s.passwordSameAsOld,
      };

  Future<void> _save() async {
    final problem = passwordChangeProblem(
      current: _current.text,
      fresh: _fresh.text,
      repeat: _repeat.text,
    );
    if (problem != null) {
      setState(() => _error = _textFor(problem));
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await PbAuthService()
          .changePassword(current: _current.text, fresh: _fresh.text);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      // 400 здесь означает ровно одно: не подошёл текущий пароль. Остальные
      // проверки мы уже сделали сами, до сети.
      final code = e is ClientException ? e.statusCode : null;
      setState(() {
        _busy = false;
        _error = code == 400
            ? _s.passwordCurrentWrong
            : (code == 429 ? _s.tooManyAttempts : _s.passwordResetError);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    return SheetScaffold(
      title: _s.changePasswordTitle,
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            _s.changePasswordTitle,
            style: const TextStyle(
              fontFamily: 'Onest',
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_current, _s.passwordCurrent, autofocus: true),
          const SizedBox(height: 12),
          _field(_fresh, _s.passwordNew),
          const SizedBox(height: 12),
          _field(_repeat, _s.passwordRepeat, onSubmit: _save),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _error,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.error,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, 'mail'),
              child: Text(
                _s.passwordForgotCurrent,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool autofocus = false,
    VoidCallback? onSubmit,
  }) {
    return TextField(
      controller: c,
      obscureText: true,
      autofocus: autofocus,
      enabled: !_busy,
      textInputAction:
          onSubmit == null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
