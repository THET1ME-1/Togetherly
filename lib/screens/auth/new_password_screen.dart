import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/partner_reset.dart';
import '../../services/pb_auth_service.dart';
import '../../theme/profile_theme.dart';
import '../../theme/theme_scope.dart';
import '../../widgets/auth/ink.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/connect_expressive.dart';

/// Новый пароль после верного кода партнёра (макет «Вход без писем», 1-А,
/// третий экран). Отвечает `true`, когда пароль сохранён и сессия есть.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key, required this.ticket});

  final PartnerResetTicket ticket;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final pw = _password.text;
    final problem = pw.length < 8
        ? trKey('prShort')
        : pw.length > 71
        ? trKey('prLong')
        : pw != _repeat.text
        ? trKey('prMismatch')
        : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PbAuthService().completePartnerReset(widget.ticket.ticket, pw);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final failure = partnerResetFailureOf(e);
      setState(() {
        _busy = false;
        _error = switch (failure) {
          PartnerResetFailure.short => trKey('prShort'),
          PartnerResetFailure.long => trKey('prLong'),
          PartnerResetFailure.expired => trKey('prTimeout'),
          _ => trKey('serverSlowRetry'),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(context.appTheme);
    final t = widget.ticket;
    final name = t.name.trim();
    final partner = t.partnerName.trim();

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
              Center(
                child: CookieAvatar(
                  size: 88,
                  color: cs.tertiaryContainer,
                  onColor: inkOn(
                    cs.tertiaryContainer,
                    cs.onTertiaryContainer,
                    cs.onSurface,
                  ),
                  initial: name.isEmpty
                      ? '?'
                      : name.characters.first.toUpperCase(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                trKey('prNewTitle'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: ProfileTheme.displayFont,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              if (partner.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  trKey(t.partnerFemale ? 'prConfirmedF' : 'prConfirmedM')
                      .replaceAll('{0}', partner),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 15,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              AuthField(
                controller: _password,
                label: trKey('prNewTitle'),
                hint: trKey('prShort'),
                accent: cs.primary,
                isPassword: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              AuthField(
                controller: _repeat,
                label: trKey('prRepeat'),
                hint: trKey('prRepeat'),
                accent: cs.primary,
                isPassword: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 14,
                    color: cs.error,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  child: Text(trKey('prSave')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
