import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../../dict_strings.dart';
import '../../models/login_methods.dart';
import '../../services/locale_service.dart';
import '../../services/pb_auth_service.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/auth/ink.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/settings_scaffold.dart';

/// Название провайдера на экране.
String loginProviderName(String provider) => switch (provider) {
  'google' => 'Google',
  'yandex' => trKey('lmYandex'),
  'apple' => 'Apple',
  _ => provider,
};

/// Строка «Способы входа · 1 из 4» в разделе «Аккаунт» настроек. Сама
/// открывает экран и перечитывает счёт, когда человек возвращается.
class LoginMethodsRow extends StatefulWidget {
  const LoginMethodsRow({
    super.key,
    required this.scheme,
    required this.onChangePassword,
  });

  final ColorScheme scheme;
  final VoidCallback onChangePassword;

  @override
  State<LoginMethodsRow> createState() => _LoginMethodsRowState();
}

class _LoginMethodsRowState extends State<LoginMethodsRow> {
  LoginMethods? _methods;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final m = await PbAuthService().loadLoginMethods();
      if (mounted) setState(() => _methods = m);
    } catch (_) {
      // Без счёта строка всё равно ведёт на экран.
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _methods;
    final ios = Platform.isIOS;
    return SettingsRow(
      icon: Icons.key_rounded,
      title: trKey('lmTitle'),
      subtitle: m == null
          ? null
          : trKey('lmRowHint')
                .replaceAll('{0}', '${m.count}')
                .replaceAll('{1}', '${m.total(ios: ios)}'),
      iconBg: m != null && m.atRisk ? widget.scheme.tertiaryContainer : null,
      iconFg: m != null && m.atRisk ? widget.scheme.onTertiaryContainer : null,
      trailing: const SettingsChevron(),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LoginMethodsScreen(
              scheme: widget.scheme,
              onChangePassword: widget.onChangePassword,
            ),
          ),
        );
        unawaited(_load());
      },
    );
  }
}

/// Экран «Способы входа» (макет «Вход без писем», 3-Б): счётчик сверху и
/// плитки пароля и провайдеров. Аккаунт один, войти в него можно любым
/// привязанным способом.
class LoginMethodsScreen extends StatefulWidget {
  const LoginMethodsScreen({
    super.key,
    required this.scheme,
    required this.onChangePassword,
    this.initial,
    this.ios,
  });

  final ColorScheme scheme;

  /// Смена известного пароля — прежний лист со старым паролем.
  final VoidCallback onChangePassword;

  /// Готовые данные для теста: тогда экран не ходит в сеть.
  final LoginMethods? initial;

  /// Платформа для теста; в приложении — `Platform.isIOS`.
  final bool? ios;

  @override
  State<LoginMethodsScreen> createState() => _LoginMethodsScreenState();
}

class _LoginMethodsScreenState extends State<LoginMethodsScreen> {
  LoginMethods? _methods;
  bool _failed = false;

  /// Провайдер, который сейчас привязывается.
  String? _linking;

  /// Вход у провайдера не даёт сигнала отмены: человек закрыл страницу —
  /// ответ не придёт никогда. Снимаем ожидание после возврата в приложение.
  AppLifecycleListener? _lifecycle;

  bool get _ios => widget.ios ?? Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _methods = widget.initial;
    if (_methods == null) unawaited(_load());
    _lifecycle = AppLifecycleListener(
      onResume: () {
        final was = _linking;
        if (was == null) return;
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted && _linking == was) setState(() => _linking = null);
        });
      },
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await PbAuthService().loadLoginMethods();
      if (mounted) {
        setState(() {
          _methods = m;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _link(String provider) async {
    if (_linking != null) return;
    setState(() => _linking = provider);
    try {
      await PbAuthService().linkProvider(provider);
      if (!mounted) return;
      _snack(trKey('lmLinkedOk').replaceAll('{0}', loginProviderName(provider)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(
        isLinkedElsewhere(e)
            ? trKey(
                'lmLinkedElsewhere',
              ).replaceAll('{0}', loginProviderName(provider))
            : trKey('lmLinkFailed'),
      );
    } finally {
      if (mounted) setState(() => _linking = null);
    }
  }

  Future<void> _unlink(String provider) async {
    final m = _methods;
    if (m == null) return;
    if (!m.canUnlink(provider)) {
      _snack(trKey('lmLastMethod'));
      return;
    }
    final name = loginProviderName(provider);
    final cs = widget.scheme;
    final ok = await showModalSheet<bool>(
      context: context,
      backgroundColor: cs.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Theme(
        data: ProfileTheme.data(cs),
        child: _ConfirmSheet(
          title: trKey('lmUnlinkTitle').replaceAll('{0}', name),
          text: trKey('lmUnlinkText').replaceAll('{0}', name),
          action: trKey('lmUnlink'),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PbAuthService().unlinkProvider(provider);
      if (!mounted) return;
      _snack(trKey('lmUnlinkedOk').replaceAll('{0}', name));
    } catch (e) {
      if (!mounted) return;
      _snack(isLastMethod(e) ? trKey('lmLastMethod') : trKey('serverSlowRetry'));
    }
    await _load();
  }

  Future<void> _setPassword() async {
    final cs = widget.scheme;
    final saved = await showModalSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Theme(
        data: ProfileTheme.data(cs),
        child: _SetPasswordSheet(email: _methods?.email ?? ''),
      ),
    );
    if (saved != true || !mounted) return;
    _snack(trKey('lmPasswordSaved'));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    final m = _methods;
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(
            trKey('lmTitle'),
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        body: m == null
            ? Center(
                child: _failed
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              trKey('lmLoadError'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: ProfileTheme.bodyFont,
                                fontSize: 15,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: () {
                                setState(() => _failed = false);
                                unawaited(_load());
                              },
                              child: Text(LocaleService.current.retry),
                            ),
                          ],
                        ),
                      )
                    : SizedBox(
                        width: 48,
                        height: 48,
                        child: ExpressiveLoadingIndicator(color: cs.primary),
                      ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).padding.bottom + 32,
                ),
                children: [
                  _Meter(methods: m, ios: _ios),
                  const SizedBox(height: 12),
                  _Tiles(
                    methods: m,
                    ios: _ios,
                    linking: _linking,
                    onPassword: m.password
                        ? widget.onChangePassword
                        : _setPassword,
                    onProvider: (p) =>
                        m.providers.contains(p) ? _unlink(p) : _link(p),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Счётчик «1/4» и подсказка. Один способ — тёплая плашка с призывом.
class _Meter extends StatelessWidget {
  const _Meter({required this.methods, required this.ios});

  final LoginMethods methods;
  final bool ios;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final risk = methods.atRisk;
    final fg = risk
        ? inkOn(cs.tertiaryContainer, cs.onTertiaryContainer, cs.onSurface)
        : cs.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: risk ? cs.tertiaryContainer : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Text(
            '${methods.count}/${methods.total(ios: ios)}',
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 32,
              height: 1,
              fontWeight: FontWeight.w800,
              fontVariations: const [FontVariation('wght', 800)],
              color: fg,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              trKey(risk ? 'lmRiskText' : 'lmSafeText'),
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 13.5,
                height: 1.35,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Плитки два на два. Если плиток нечётно (Android: пароль, Google, Яндекс),
/// пароль занимает всю ширину, а провайдеры встают парой под ним.
class _Tiles extends StatelessWidget {
  const _Tiles({
    required this.methods,
    required this.ios,
    required this.linking,
    required this.onPassword,
    required this.onProvider,
  });

  final LoginMethods methods;
  final bool ios;
  final String? linking;
  final VoidCallback onPassword;
  final ValueChanged<String> onProvider;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final providers = methods.tiles(ios: ios);
    final password = _Tile(
      on: methods.password,
      logo: Icon(Icons.password_rounded, color: cs.primary),
      name: trKey('lmPassword'),
      hint: methods.password && methods.email.isNotEmpty
          ? methods.email
          : (methods.password ? '' : trKey('lmNoPassword')),
      state: trKey(methods.password ? 'lmOn' : 'lmSetPassword'),
      busy: false,
      onTap: onPassword,
    );
    final tiles = [
      for (final p in providers)
        _Tile(
          on: methods.providers.contains(p),
          logo: switch (p) {
            'google' => const GoogleLogo(size: 22),
            'yandex' => const YandexGlyph(),
            _ => Icon(Icons.apple, size: 24, color: cs.onSurface),
          },
          name: loginProviderName(p),
          hint: trKey(p == 'apple' ? 'lmIphone' : 'lmOneTap'),
          state: trKey(methods.providers.contains(p) ? 'lmLinked' : 'lmLink'),
          busy: linking == p,
          onTap: linking == null ? () => onProvider(p) : null,
        ),
    ];
    // Пароль плюс чётное число провайдеров — плиток нечётно, и пароль
    // ложится отдельной строкой во всю ширину.
    final wide = providers.length.isEven;
    final all = wide ? tiles : [password, ...tiles];
    final rows = <Widget>[
      if (wide) password,
      for (var i = 0; i < all.length; i += 2)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: all[i]),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < all.length ? all[i + 1] : const SizedBox(),
              ),
            ],
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          rows[i],
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.on,
    required this.logo,
    required this.name,
    required this.hint,
    required this.state,
    required this.busy,
    required this.onTap,
  });

  final bool on;
  final Widget logo;
  final String name;
  final String hint;
  final String state;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = on
        ? inkOn(cs.primaryContainer, cs.onPrimaryContainer, cs.onSurface)
        : cs.onSurface;
    return Material(
      color: on ? cs.primaryContainer : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 132),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    shape: BoxShape.circle,
                  ),
                  child: logo,
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                if (hint.isNotEmpty)
                  Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontSize: 12.5,
                      color: fg.withValues(alpha: 0.8),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (busy)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: ExpressiveLoadingIndicator(color: cs.primary),
                      )
                    else
                      Icon(
                        on
                            ? Icons.check_circle_rounded
                            : Icons.add_circle_rounded,
                        size: 17,
                        color: on ? fg : cs.primary,
                      ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        state,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: on ? fg : cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.title,
    required this.text,
    required this.action,
  });

  final String title;
  final String text;
  final String action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 15,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: const StadiumBorder(),
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    ),
                    child: Text(action),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Пароль для аккаунта, заведённого через Google или Apple.
class _SetPasswordSheet extends StatefulWidget {
  const _SetPasswordSheet({required this.email});

  final String email;

  @override
  State<_SetPasswordSheet> createState() => _SetPasswordSheetState();
}

class _SetPasswordSheetState extends State<_SetPasswordSheet> {
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
      await PbAuthService().setInitialPassword(pw);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = trKey('serverSlowRetry');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                trKey('lmSetTitle'),
                style: TextStyle(
                  fontFamily: ProfileTheme.displayFont,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                trKey('lmSetText').replaceAll('{0}', widget.email),
                style: TextStyle(
                  fontFamily: ProfileTheme.bodyFont,
                  fontSize: 14.5,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              AuthField(
                controller: _password,
                label: trKey('lmPassword'),
                hint: trKey('prShort'),
                accent: cs.primary,
                isPassword: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
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
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.error, fontSize: 14),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  child: Text(trKey('lmSave')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
