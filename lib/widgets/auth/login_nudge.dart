import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dict_strings.dart';
import '../../models/login_methods.dart';
import '../../services/pb_auth_service.dart';
import '../../services/pocketbase_service.dart';
import '../../theme/profile_theme.dart';
import '../auth_widgets.dart';

const String _offKey = 'login_nudge_off';

/// Ответ сервера один раз за запуск: главная перестраивается часто.
Future<LoginMethods?>? _methodsOnce;

/// Показывать ли подсказку: у аккаунта один пароль, со дня регистрации
/// прошли сутки, крестик не нажимали.
bool loginNudgeWanted({
  required LoginMethods methods,
  required DateTime? created,
  required DateTime now,
  required bool dismissed,
}) {
  if (dismissed || created == null) return false;
  if (now.difference(created) < const Duration(days: 1)) return false;
  return methods.password && methods.providers.isEmpty;
}

/// «Не потеряйте аккаунт» на главной (макет «Вход без писем», 3-Б): тем, кто
/// входит только паролем, предлагаем привязать Google. Нажатие привязывает
/// сразу, крестик убирает подсказку насовсем.
class LoginNudge extends StatefulWidget {
  const LoginNudge({super.key, required this.scheme});

  final ColorScheme scheme;

  @override
  State<LoginNudge> createState() => _LoginNudgeState();
}

class _LoginNudgeState extends State<LoginNudge> {
  bool _show = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_decide());
  }

  Future<void> _decide() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_offKey) == true) return;
    final methods = await (_methodsOnce ??= PbAuthService()
        .loadLoginMethods()
        .then<LoginMethods?>((m) => m, onError: (_) => null));
    if (methods == null || !mounted) return;
    final raw = PocketBaseService().currentUser?.data['created'];
    final created = raw is String ? DateTime.tryParse(raw.replaceFirst(' ', 'T')) : null;
    final want = loginNudgeWanted(
      methods: methods,
      created: created,
      now: DateTime.now().toUtc(),
      dismissed: false,
    );
    if (want && mounted) setState(() => _show = true);
  }

  Future<void> _dismiss() async {
    setState(() => _show = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offKey, true);
  }

  Future<void> _link() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await PbAuthService().linkProvider('google');
      messenger?.showSnackBar(
        SnackBar(
          content: Text(trKey('lmLinkedOk').replaceAll('{0}', 'Google')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _methodsOnce = null;
      await _dismiss();
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            isLinkedElsewhere(e)
                ? trKey('lmLinkedElsewhere').replaceAll('{0}', 'Google')
                : trKey('lmLinkFailed'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final cs = widget.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy ? null : _link,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    shape: BoxShape.circle,
                  ),
                  child: const GoogleLogo(size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trKey('lmNudgeTitle'),
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trKey('lmNudgeText'),
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 12.5,
                          height: 1.3,
                          color: cs.onSecondaryContainer.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _dismiss,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: cs.onSecondaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
