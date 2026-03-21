import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/user_data.dart';
import '../services/firebase_service.dart';
import '../services/locale_service.dart';
import 'home_screen.dart';
import 'setup_screen.dart';

class LoginScreen extends StatefulWidget {
  final UserData userData;
  const LoginScreen({super.key, required this.userData});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color _accent = Color(0xFFFF7E8B);
  static const Color _accentLight = Color(0xFFFEEAF1);

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
      final fb = FirebaseService();
      final user = await fb.signInWithEmailPassword(
        email: email,
        password: password,
      );

      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        _showError(LocaleService.current.loginFailed);
        return;
      }

      // Load user profile from Firestore
      final profile = await fb.loadUserProfile();

      if (profile != null &&
          profile['displayName'] != null &&
          profile['gender'] != null) {
        final displayName = profile['displayName'] as String;
        final userEmail = profile['email'] as String? ?? user.email ?? '';
        final avatarUrl =
            profile['avatarUrl'] as String? ?? user.photoURL ?? '';
        final genderStr = profile['gender'] as String;
        final gender = genderStr == 'male' ? Gender.male : Gender.female;

        await widget.userData.register(
          displayName: displayName,
          email: userEmail,
          gender: gender,
          avatarUrl: avatarUrl,
          isReturningUser: true, // Login - don't clear existing data
        );

        // Устанавливаем статус "онлайн" после входа
        fb.setOnlineStatus(true);

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
        // User exists in Auth but no profile - redirect to setup
        if (mounted) setState(() => _isLoading = false);
        _showError(LocaleService.current.profileNotFound);
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

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final fb = FirebaseService();
      final user = await fb.signInWithGoogle();

      if (user != null) {
        final profile = await fb.loadUserProfile();

        if (profile != null &&
            profile['displayName'] != null &&
            profile['gender'] != null) {
          final displayName = profile['displayName'] as String;
          final email = profile['email'] as String? ?? user.email ?? '';
          final avatarUrl =
              profile['avatarUrl'] as String? ?? user.photoURL ?? '';
          final genderStr = profile['gender'] as String;
          final gender = genderStr == 'male' ? Gender.male : Gender.female;

          await widget.userData.register(
            displayName: displayName,
            email: email,
            gender: gender,
            avatarUrl: avatarUrl,
            isReturningUser: true, // Login - don't clear existing data
          );

          // Устанавливаем статус "онлайн" после входа
          fb.setOnlineStatus(true);

          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) =>
                  HomeScreen(userData: widget.userData),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        } else {
          // No profile yet - redirect to setup for first time setup
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) =>
                  SetupScreen(userData: widget.userData),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      final errorMsg = e.toString();
      if (errorMsg.contains('TimeoutException')) {
        _showError(LocaleService.current.googleNotResponding);
      } else {
        _showError(LocaleService.current.googleLoginError(errorMsg));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/wallpaper/pink-background.png',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  // Icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: _accentLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.login_rounded, color: _accent, size: 32),
                  ),
                  const SizedBox(height: 28),
                  // Title
                  Text(
                    LocaleService.current.welcomeBack,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    LocaleService.current.loginToAccount,
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 40),
                  // Google button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade800,
                        side: BorderSide(color: Colors.grey.shade200),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: Colors.white,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const _GoogleLogo(size: 24),
                          const SizedBox(width: 12),
                          Text(
                            LocaleService.current.signInWithGoogle,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade200)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          LocaleService.current.or,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade200)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Email field
                  _buildTextField(
                    controller: _emailController,
                    label: LocaleService.current.email,
                    hint: LocaleService.current.yourEmail,
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  // Password field
                  _buildPasswordField(),
                  const SizedBox(height: 36),
                  // Login button
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signInWithEmail,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _accent.withOpacity(0.6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32),
                        ),
                        elevation: 12,
                        shadowColor: _accent.withOpacity(0.4),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              LocaleService.current.login,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Register link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${LocaleService.current.noAccount} ',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).pushReplacement(
                            PageRouteBuilder(
                              pageBuilder: (_, __, ___) =>
                                  SetupScreen(userData: widget.userData),
                              transitionsBuilder: (_, animation, __, child) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                              transitionDuration: const Duration(
                                milliseconds: 300,
                              ),
                            ),
                          );
                        },
                        child: Text(
                          LocaleService.current.create,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade900,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(icon, color: _accent, size: 20),
              filled: true,
              fillColor: Colors.white.withOpacity(0.75),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _accent, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            LocaleService.current.password,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade900,
            ),
            decoration: InputDecoration(
              hintText: LocaleService.current.yourPassword,
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                color: _accent,
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.grey.shade500,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.75),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _accent, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final sw = r * 0.22;
    final arcRect = Rect.fromCircle(center: center, radius: r - sw / 2);

    double rad(double deg) => deg * math.pi / 180;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..isAntiAlias = true;

    // Green: bottom-right
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(arcRect, rad(28), rad(54), false, paint);

    // Yellow: bottom-left
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(arcRect, rad(82), rad(90), false, paint);

    // Red: top-left
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(arcRect, rad(172), rad(92), false, paint);

    // Blue: top-right
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(arcRect, rad(264), rad(66), false, paint);

    // Blue horizontal bar
    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTRB(r - sw * 0.15, r - sw / 2, r * 2 - sw * 0.5, r + sw / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter oldDelegate) => false;
}
