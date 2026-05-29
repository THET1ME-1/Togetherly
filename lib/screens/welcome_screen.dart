import '../widgets/storage_image.dart';
import 'package:flutter/material.dart';
import '../models/user_data.dart';
import '../services/locale_service.dart';
import 'setup_screen.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  final UserData userData;
  const WelcomeScreen({super.key, required this.userData});

  static const Color _btnColor = Color(0xFFFF7E8B);

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          StorageImage(
            imageUrl:
                'https://firebasestorage.googleapis.com/v0/b/togetherly-d4856.firebasestorage.app/o/wallpapers%2Fpink-background.webp?alt=media',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (_, __) => const ColoredBox(color: Color(0xFFFFF0EA)),
            errorWidget: (_, __, ___) =>
                const ColoredBox(color: Color(0xFFFFF0EA)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _btnColor.withOpacity(0.25),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.favorite_rounded,
                            color: _btnColor,
                            size: 40,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade900,
                            height: 1.3,
                          ),
                          children: [
                            TextSpan(text: s.welcomeTitle1),
                            TextSpan(
                              text: s.welcomeTitle2,
                              style: const TextStyle(color: _btnColor),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        s.welcomeSubtitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Colors.grey.shade500,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      _buildFeatureRow(s),
                      const SizedBox(height: 24),
                      _buildStepsCard(s),
                      const SizedBox(height: 28),
                      _buildButtons(context, s),
                      const SizedBox(height: 16),
                      Text(
                        s.privateSecure,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade400,
                          letterSpacing: 2.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(AppStrings s) {
    final features = [
      (Icons.photo_library_outlined, s.welcomeFeatureMemories),
      (Icons.mood_rounded, s.welcomeFeatureMood),
      (Icons.widgets_outlined, s.welcomeFeatureWidgets),
    ];

    return Row(
      children: features.map((f) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.82),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.7)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(f.$1, color: _btnColor, size: 20),
                const SizedBox(height: 4),
                Text(
                  f.$2,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStepsCard(AppStrings s) {
    final steps = [
      s.welcomeStepCreateProfile,
      s.welcomeStepConnectPartner,
      s.welcomeStepStartTogether,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocaleService.instance.isRussian ? 'Первые шаги' : 'First steps',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade500,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _btnColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _btnColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    steps[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildButtons(BuildContext context, AppStrings s) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton(
            onPressed: () async {
              await userData.markWelcomeSeen();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => SetupScreen(userData: userData),
                  transitionsBuilder: (_, animation, __, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  transitionDuration: const Duration(milliseconds: 400),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _btnColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              elevation: 8,
              shadowColor: _btnColor.withOpacity(0.35),
            ),
            child: Text(
              s.createAccount,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 58,
          child: OutlinedButton(
            onPressed: () async {
              await userData.markWelcomeSeen();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => LoginScreen(userData: userData),
                  transitionsBuilder: (_, animation, __, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  transitionDuration: const Duration(milliseconds: 400),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _btnColor,
              side: BorderSide(color: _btnColor, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
            ),
            child: Text(
              s.alreadyHaveAccount,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
