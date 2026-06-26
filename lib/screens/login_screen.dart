import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_data.dart';
import '../services/pb_auth_service.dart';
import '../services/locale_service.dart';
import '../widgets/auth_widgets.dart';

import 'home_screen.dart';
import 'setup_screen.dart';
import 'welcome_screen.dart';

class LoginScreen extends StatefulWidget {
  final UserData userData;
  const LoginScreen({super.key, required this.userData});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color _accent = Color(0xFFFF6B9D);
  static const List<Color> _btnGradient = [
    Color(0xFFFF8FA3),
    Color(0xFFFF6B9D),
  ];

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = true;

  // OAuth: PB authWithOAuth2 зависает навсегда, если юзер закрыл окно провайдера
  // крестиком (нет сигнала отмены). Ловим возврат в приложение и снимаем спиннер.
  AppLifecycleListener? _lifecycle;
  bool _oauthInFlight = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onOAuthResume);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Вернулись из in-app браузера. Если OAuth-вход не завершился за пару секунд
  /// (юзер отменил) — снимаем бесконечную загрузку. На успехе `_oauthInFlight`
  /// уже сброшен (см. `_oauthSignIn`), поэтому ложно не срабатывает.
  void _onOAuthResume() {
    if (!_oauthInFlight) return;
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _oauthInFlight) {
        setState(() {
          _isLoading = false;
          _oauthInFlight = false;
        });
      }
    });
  }

  Future<void> _signInWithEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      _showError(LocaleService.current.invalidEmail);
      return;
    }
    if (password.isEmpty) {
      _showError(LocaleService.current.enterPassword);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = PbAuthService();
      final user = await auth.signInWithEmail(
        email: email,
        password: password,
      );

      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        _showError(LocaleService.current.loginFailed);
        return;
      }

      // Профиль из записи users PocketBase (camelCase — как раньше Firestore).
      final profile = auth.currentProfile();

      if (profile != null &&
          profile['displayName'] != null &&
          profile['gender'] != null) {
        final displayName = profile['displayName'] as String;
        final userEmail = profile['email'] as String? ?? '';
        final avatarUrl = profile['avatarUrl'] as String? ?? '';
        final genderStr = profile['gender'] as String;
        final gender = genderStr == 'male' ? Gender.male : Gender.female;

        await widget.userData.register(
          displayName: displayName,
          email: userEmail,
          gender: gender,
          avatarUrl: avatarUrl,
          isReturningUser: true, // Login - don't clear existing data
        );

        // TODO(pb-cutover): статус «онлайн» (presence) переедет на PB-слой
        // (heartbeat+TTL) вместе с data/realtime-срезом — см. CUTOVER §3.

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => HomeScreen(userData: widget.userData),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else {
        // No complete profile yet — send to setup to finish registration
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => SetupScreen(userData: widget.userData),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      final errorMsg = e.toString();
      if (errorMsg.contains('user-not-found')) {
        _showError(LocaleService.current.userNotFound);
      } else if (errorMsg.contains('wrong-password') ||
          errorMsg.contains('invalid-credential')) {
        _showError(LocaleService.current.wrongPassword);
      } else if (errorMsg.contains('invalid-email')) {
        _showError(LocaleService.current.invalidEmailFormat);
      } else if (errorMsg.contains('too-many-requests')) {
        _showError(LocaleService.current.tooManyAttempts);
      } else if (errorMsg.contains('TimeoutException')) {
        _showError(LocaleService.current.serverNotResponding);
      } else {
        _showError(LocaleService.current.loginError(errorMsg));
      }
    }
  }

  /// Универсальный OAuth-вход: google / apple / yandex / vk / facebook.
  /// Логика одинаковая: есть профиль с полом → домой, иначе → setup.
  Future<void> _oauthSignIn(String provider) async {
    setState(() => _isLoading = true);
    _oauthInFlight = true;
    try {
      final auth = PbAuthService();
      final user = await auth.signInWithOAuth2(provider);
      _oauthInFlight = false;

      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final profile = auth.currentProfile();
      if (profile != null &&
          profile['displayName'] != null &&
          profile['gender'] != null) {
        final displayName = profile['displayName'] as String;
        final email = profile['email'] as String? ?? '';
        final avatarUrl = profile['avatarUrl'] as String? ?? '';
        final genderStr = profile['gender'] as String;
        final gender = genderStr == 'male' ? Gender.male : Gender.female;

        await widget.userData.register(
          displayName: displayName,
          email: email,
          gender: gender,
          avatarUrl: avatarUrl,
          isReturningUser: true, // Login - don't clear existing data
        );

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => HomeScreen(userData: widget.userData),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else {
        // No profile yet - redirect to setup for first time setup
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => SetupScreen(userData: widget.userData),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    } catch (e) {
      _oauthInFlight = false;
      if (mounted) setState(() => _isLoading = false);
      final errorMsg = e.toString();
      if (errorMsg.contains('TimeoutException')) {
        _showError(LocaleService.current.serverNotResponding);
      } else {
        _showError(LocaleService.current.loginError(errorMsg));
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError(LocaleService.current.invalidEmail);
      return;
    }
    try {
      await PbAuthService().sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocaleService.current.passwordResetSent(email)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF4CAF50),
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString();
      if (errorMsg.contains('invalid-email')) {
        _showError(LocaleService.current.invalidEmailFormat);
      } else if (errorMsg.contains('too-many-requests')) {
        _showError(LocaleService.current.tooManyAttempts);
      } else {
        _showError(LocaleService.current.passwordResetError);
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade400,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      ),
    );
  }

  void _goToWelcome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => WelcomeScreen(userData: widget.userData),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _goToSetup() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => SetupScreen(userData: widget.userData),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        // Фон НЕ трогаем — это наш фирменный градиент.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFE4EC), Color(0xFFFFF1F4), Color(0xFFFCE9FF)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Шапка поверх фона: кнопка «назад» ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _backButton(),
                ),
              ),
              const SizedBox(height: 20),
              // ── Белая карточка с формой (как в референсе) ──
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(34)),
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(28, 34, 28, 28 + bottomInset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Text(
                            s.welcomeBack,
                            style: GoogleFonts.rubik(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF2B2230),
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        AuthField(
                          controller: _emailController,
                          label: s.email,
                          hint: s.yourEmail,
                          accent: _accent,
                          keyboardType: TextInputType.emailAddress,
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(
                                RegExp(r'[а-яёА-ЯЁ]')),
                          ],
                        ),
                        const SizedBox(height: 18),
                        AuthField(
                          controller: _passwordController,
                          label: s.password,
                          hint: s.yourPassword,
                          accent: _accent,
                          isPassword: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_isLoading) _signInWithEmail();
                          },
                        ),
                        const SizedBox(height: 16),
                        // Remember me + Forgot password
                        Row(
                          children: [
                            _rememberMeToggle(s),
                            const Spacer(),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _isLoading ? null : _sendPasswordReset,
                              child: Text(
                                s.forgotPassword,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _primaryButton(
                          label: s.login,
                          onTap: _isLoading ? null : _signInWithEmail,
                        ),
                        const SizedBox(height: 26),
                        AuthSocialRow(
                          label: s.signInWith,
                          onGoogle:
                              _isLoading ? null : () => _oauthSignIn('google'),
                          onYandex:
                              _isLoading ? null : () => _oauthSignIn('yandex'),
                          onApple: Platform.isIOS
                              ? (_isLoading ? null : () => _oauthSignIn('apple'))
                              : null,
                        ),
                        const SizedBox(height: 28),
                        // Don't have an account? Sign up
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${s.noAccount} ',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey.shade600),
                            ),
                            GestureDetector(
                              onTap: _isLoading ? null : _goToSetup,
                              child: Text(
                                s.create,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: _accent,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _backButton() {
    return GestureDetector(
      onTap: _goToWelcome,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.75),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        ),
        child: Icon(Icons.arrow_back_rounded,
            color: Colors.grey.shade800, size: 20),
      ),
    );
  }

  Widget _rememberMeToggle(AppStrings s) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _rememberMe = !_rememberMe),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _rememberMe ? _accent : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _rememberMe ? _accent : Colors.grey.shade400,
                width: 2,
              ),
            ),
            child: _rememberMe
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            s.rememberMe,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({required String label, required VoidCallback? onTap}) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: onTap == null
              ? _btnGradient.map((c) => c.withValues(alpha: 0.6)).toList()
              : _btnGradient,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(
                    label,
                    style: GoogleFonts.rubik(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
