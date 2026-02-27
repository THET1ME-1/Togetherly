import 'package:flutter/material.dart';
import '../models/user_data.dart';
import '../services/locale_service.dart';
import 'setup_screen.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  final UserData userData;
  const WelcomeScreen({super.key, required this.userData});

  static const Color _primary = Color(0xFFEE2B6C);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF2EDE8), Color(0xFFF5F0EC), Color(0xFFF8F5F2)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              children: [
                const Spacer(flex: 3),
                // Smiley face icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCE4EC).withOpacity(0.8),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _primary.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _primary.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // Title text
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                      height: 1.25,
                    ),
                    children: const [
                      TextSpan(text: 'This space is just\nfor the '),
                      TextSpan(
                        text: 'two of you',
                        style: TextStyle(color: _primary),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Subtitle
                Text(
                  'Moments, feelings, connection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade500,
                  ),
                ),
                const Spacer(flex: 2),
                // Create Account button
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed: () async {
                      await userData.markWelcomeSeen();
                      if (!context.mounted) return;
                      Navigator.of(context).pushReplacement(
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) =>
                              SetupScreen(userData: userData),
                          transitionsBuilder: (_, animation, __, child) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                          transitionDuration: const Duration(milliseconds: 400),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                      elevation: 12,
                      shadowColor: _primary.withOpacity(0.4),
                    ),
                    child: Text(
                      LocaleService.current.createAccount,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Login button
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: OutlinedButton(
                    onPressed: () async {
                      await userData.markWelcomeSeen();
                      if (!context.mounted) return;
                      Navigator.of(context).pushReplacement(
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) =>
                              LoginScreen(userData: userData),
                          transitionsBuilder: (_, animation, __, child) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                          transitionDuration: const Duration(milliseconds: 400),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: BorderSide(color: _primary, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                    ),
                    child: Text(
                      LocaleService.current.alreadyHaveAccount,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                // Privacy text
                Text(
                  'PRIVATE & SECURE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade400,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
