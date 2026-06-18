import 'dart:io';
import '../widgets/storage_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../models/user_data.dart';
import '../services/firebase_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';
import '../services/locale_service.dart';


class SetupScreen extends StatefulWidget {
  final UserData userData;
  const SetupScreen({super.key, required this.userData});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with SingleTickerProviderStateMixin {
  // Step: 0 = gender, 1 = registration
  int _step = 0;
  Gender? _selectedGender;
  bool _isLoading = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _avatarUrl = '';
  XFile? _selectedAvatarFile; // Локальный файл для загрузки после регистрации
  bool _obscurePassword = true;
  bool _agreeToTerms = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  // Colors based on gender
  Color get _accent {
    if (_selectedGender == Gender.male) return const Color(0xFF7898BF);
    return const Color(0xFFFF7E8B);
  }

  Color get _accentLight {
    if (_selectedGender == Gender.male) return const Color(0xFFEAF2FA);
    return const Color(0xFFFEEAF1);
  }

  String get _bgImageUrl {
    if (_selectedGender == Gender.male) {
      return 'https://firebasestorage.googleapis.com/v0/b/togetherly-d4856.firebasestorage.app/o/wallpapers%2Fblue-background.webp?alt=media';
    }
    return 'https://firebasestorage.googleapis.com/v0/b/togetherly-d4856.firebasestorage.app/o/wallpapers%2Fpink-background.webp?alt=media';
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    _fadeController.reverse().then((_) {
      setState(() => _step = step);
      _fadeController.forward();
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final fb = FirebaseService();
      final user = await fb.signInWithGoogle();
      if (user != null) {
        // Try to load existing user profile from Firestore — force server to bypass stale cache
        final profile = await fb.loadUserProfile(fromServer: true);

        if (profile != null &&
            profile['displayName'] != null &&
            profile['gender'] != null) {
          // User already has a profile in Firestore - auto-register and go to home
          final displayName = profile['displayName'] as String;
          final email = profile['email'] as String? ?? user.email ?? '';
          final firestoreAvatar = profile['avatarUrl'] as String? ?? '';
          final avatarUrl =
              firestoreAvatar.isNotEmpty ? firestoreAvatar : (user.photoURL ?? '');
          final genderStr = profile['gender'] as String;
          final gender = genderStr == 'male' ? Gender.male : Gender.female;

          await widget.userData.register(
            displayName: displayName,
            email: email,
            gender: gender,
            avatarUrl: avatarUrl,
            isReturningUser: true, // не обнулять данные пары
          );

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
          // New user via Google — register immediately and go to home
          final displayName = user.displayName ?? '';
          final email = user.email ?? '';
          final avatarUrl = user.photoURL ?? '';
          final gender = _selectedGender ?? Gender.female;

          // Save profile to Firestore
          await fb.saveUserProfile(
            displayName: displayName,
            email: email,
            avatarUrl: avatarUrl,
            gender: gender == Gender.male ? 'male' : 'female',
          );

          await widget.userData.register(
            displayName: displayName,
            email: email,
            gender: gender,
            avatarUrl: avatarUrl,
          );

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
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final errorMsg = e.toString();
        if (errorMsg.contains('TimeoutException')) {
          _showError(LocaleService.current.serverNotResponding);
        } else {
          _showError(LocaleService.current.googleLoginError(errorMsg));
        }
      }
    }
  }

  Future<void> _completeSetup() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty) {
      _showError(LocaleService.current.enterYourName);
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      _showError(LocaleService.current.enterValidEmail);
      return;
    }
    if (_selectedGender == null) {
      _showError(LocaleService.current.selectGender);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final fb = FirebaseService();

      // Если пользователь не залогинен (ввёл данные вручную), создаём аккаунт
      if (!fb.isLoggedIn) {
        // Проверяем пароль только для ручной регистрации: 8 символов +
        // заглавная буква + спецсимвол (те же правила, что индикаторы под полем).
        final pwdOk = password.length >= 8 &&
            password.contains(RegExp(r'[A-Z]')) &&
            password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));
        if (!pwdOk) {
          _showError(
            '${LocaleService.current.min8Chars}, '
            '${LocaleService.current.oneUppercase}, '
            '${LocaleService.current.oneSpecialChar}',
          );
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        await fb.signUpWithEmailPassword(
          email: email,
          password: password,
          displayName: name,
        );
      }

      // Загружаем аватарку, если выбрана
      String finalAvatarUrl = _avatarUrl;
      if (_selectedAvatarFile != null) {
        final userId = fb.currentUser?.uid ?? '';
        if (userId.isNotEmpty) {
          final ext = _selectedAvatarFile!.path.split('.').last;
          final destination = 'avatars/$userId/profile.$ext';
          final uploadedUrl = await fb.uploadFile(
            _selectedAvatarFile!.path,
            destination,
          );
          if (uploadedUrl != null) {
            finalAvatarUrl = uploadedUrl;
          }
        }
      }

      // Регистрируем пользователя в приложении
      await widget.userData.register(
        displayName: name,
        email: email,
        gender: _selectedGender!,
        avatarUrl: finalAvatarUrl,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => HomeScreen(userData: widget.userData),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final errorMsg = e.toString();
        final s = LocaleService.current;
        // Проверяем, не существует ли уже аккаунт с таким email
        if (errorMsg.contains('email-already-in-use')) {
          _showEmailExistsDialog();
        } else if (errorMsg.contains('TimeoutException') ||
            errorMsg.contains('network-request-failed') ||
            errorMsg.contains('internal-error') ||
            errorMsg.contains('timeout')) {
          // Частый кейс из России: нестабильное/VPN-соединение. Понятный текст
          // вместо сырого исключения — и сервис уже сделал ретраи.
          _showError(s.serverNotResponding);
        } else if (errorMsg.contains('weak-password')) {
          _showError(s.passwordMin6);
        } else if (errorMsg.contains('invalid-email')) {
          _showError(s.invalidEmailFormat);
        } else if (errorMsg.contains('too-many-requests')) {
          _showError(s.tooManyAttempts);
        } else {
          _showError(s.registrationError(errorMsg));
        }
      }
    }
  }

  void _showEmailExistsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          LocaleService.current.accountExists,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(LocaleService.current.emailAlreadyRegistered),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              LocaleService.current.cancel,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) =>
                      LoginScreen(userData: widget.userData),
                  transitionsBuilder: (_, animation, __, child) =>
                      FadeTransition(opacity: animation, child: child),
                  transitionDuration: const Duration(milliseconds: 300),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(LocaleService.current.login),
          ),
        ],
      ),
    );
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

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (image == null || !mounted) return;

    // Обрезаем до круга (аватарка)
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: image.path,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          cropStyle: CropStyle.circle,
          toolbarTitle: LocaleService.current.cropAvatarTitle,
          toolbarColor: const Color(0xFF1A1A2E),
          toolbarWidgetColor: Colors.white,
          statusBarColor: const Color(0xFF1A1A2E),
          backgroundColor: const Color(0xFF0D0D1A),
          activeControlsWidgetColor: _accent,
          cropFrameColor: _accent,
          cropGridColor: Colors.transparent,
          dimmedLayerColor: const Color(0xCC0D0D1A),
          showCropGrid: false,
          lockAspectRatio: true,
          initAspectRatio: CropAspectRatioPreset.square,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          cropStyle: CropStyle.circle,
          title: LocaleService.current.avatarTitle,
          doneButtonTitle: LocaleService.current.done,
          cancelButtonTitle: LocaleService.current.cancel,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          rotateButtonsHidden: false,
          hidesNavigationBar: true,
        ),
      ],
    );

    if (croppedFile == null || !mounted) return;

    // Сохраняем локально для превью и последующей загрузки после регистрации
    setState(() {
      _selectedAvatarFile = XFile(croppedFile.path);
      _avatarUrl = ''; // Очищаем URL, так как показываем локальный файл
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: StorageImage(
              key: ValueKey(_bgImageUrl),
              imageUrl: _bgImageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              placeholder: (_, __) =>
                  const ColoredBox(color: Color(0xFFFFF0EA)),
              errorWidget: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFFFFF0EA)),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _step == 0 ? _buildGenderStep() : _buildRegistrationStep(),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  STEP 1: GENDER SELECTION
  // ═══════════════════════════════════════════════════
  Widget _buildGenderStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Back button
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pushReplacement(
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) =>
                        WelcomeScreen(userData: widget.userData),
                    transitionsBuilder: (_, animation, __, child) =>
                        FadeTransition(opacity: animation, child: child),
                    transitionDuration: const Duration(milliseconds: 400),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.grey.shade700,
                  size: 20,
                ),
              ),
            ),
          ),
          const Spacer(flex: 2),
          // Icon
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _accentLight.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.wc_rounded, color: _accent, size: 36),
          ),
          const SizedBox(height: 32),
          Text(
            LocaleService.current.whoAreYou,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            LocaleService.current.selectGenderForTheme,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 48),
          // Gender cards
          Row(
            children: [
              Expanded(child: _genderCard(Gender.male)),
              const SizedBox(width: 16),
              Expanded(child: _genderCard(Gender.female)),
            ],
          ),
          const Spacer(flex: 2),
          // Continue button
          AnimatedOpacity(
            opacity: _selectedGender != null ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                onPressed: _selectedGender != null ? () => _goToStep(1) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                  elevation: 12,
                  shadowColor: _accent.withOpacity(0.4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      LocaleService.current.continueBtn,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _genderCard(Gender gender) {
    final isSelected = _selectedGender == gender;
    final isMale = gender == Gender.male;
    final color = isMale ? const Color(0xFF7898BF) : const Color(0xFFFF7E8B);
    final bgColor = isMale ? const Color(0xFFEAF2FA) : const Color(0xFFFEEAF1);
    final icon = isMale ? Icons.male_rounded : Icons.female_rounded;
    final label = isMale
        ? LocaleService.current.boy
        : LocaleService.current.girl;

    return GestureDetector(
      onTap: () => setState(() => _selectedGender = gender),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: isSelected ? bgColor : Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.4) : Colors.grey.shade200,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 12,
                  ),
                ],
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withOpacity(0.15)
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 36,
                color: isSelected ? color : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isSelected ? color : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 24,
              height: 3,
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  STEP 2: REGISTRATION
  // ═══════════════════════════════════════════════════
  Widget _buildRegistrationStep() {
    final _s = LocaleService.current;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Back button
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => _goToStep(0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.grey.shade700,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 36),
          // Title
          Text(
            _s.createAccountBtn,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 28),
          // ═══ Form Card ═══
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar (centered)
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _accentLight,
                            border: Border.all(
                              color: _accent.withOpacity(0.2),
                              width: 3,
                            ),
                          ),
                          child: _selectedAvatarFile != null
                              ? ClipOval(
                                  child: Image.file(
                                    File(_selectedAvatarFile!.path),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : _avatarUrl.isNotEmpty
                              ? ClipOval(
                                  child: StorageImage(
                                    imageUrl: _avatarUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) => Icon(
                                      Icons.person_rounded,
                                      color: _accent.withOpacity(0.5),
                                      size: 36,
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.person_rounded,
                                  color: _accent.withOpacity(0.5),
                                  size: 36,
                                ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: _accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Full Name
                _buildFormLabel(_s.fullName),
                const SizedBox(height: 8),
                _buildFormField(controller: _nameController, hint: _s.yourName),
                const SizedBox(height: 18),
                // Email
                _buildFormLabel(_s.email),
                const SizedBox(height: 8),
                _buildFormField(
                  controller: _emailController,
                  hint: 'your@email.com',
                  keyboardType: TextInputType.emailAddress,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'[а-яёА-ЯЁ]')),
                  ],
                ),
                const SizedBox(height: 18),
                // Password
                _buildFormLabel(_s.password),
                const SizedBox(height: 8),
                _buildFormPasswordField(),
                const SizedBox(height: 14),
                _buildPasswordChecks(),
                const SizedBox(height: 18),
                // Terms checkbox
                GestureDetector(
                  onTap: () => setState(() => _agreeToTerms = !_agreeToTerms),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _agreeToTerms ? _accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _agreeToTerms
                                ? _accent
                                : Colors.grey.shade400,
                            width: 2,
                          ),
                        ),
                        child: _agreeToTerms
                            ? const Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _s.agreeToTerms,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Create Account button
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton(
              onPressed: (_isLoading || !_agreeToTerms) ? null : _completeSetup,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _accent.withOpacity(0.4),
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
                      _s.createAccountBtn,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade200)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _s.or,
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
          const SizedBox(height: 20),
          // Google Sign In button
          _buildSocialButton(
            onPressed: _isLoading ? null : _signInWithGoogle,
            icon: const _GoogleLogoSmall(),
            label: _s.continueWithGoogle,
          ),
          const SizedBox(height: 28),
          // Already have account?
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${_s.alreadyHaveAccountLogin} ',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pushReplacement(
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) =>
                          LoginScreen(userData: widget.userData),
                      transitionsBuilder: (_, animation, __, child) =>
                          FadeTransition(opacity: animation, child: child),
                      transitionDuration: const Duration(milliseconds: 300),
                    ),
                  );
                },
                child: Text(
                  _s.login,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _buildFormLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
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
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
    );
  }

  Widget _buildFormPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      onChanged: (_) => setState(() {}),
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
        filled: true,
        fillColor: Colors.grey.shade50,
        suffixIcon: GestureDetector(
          onTap: () => setState(() => _obscurePassword = !_obscurePassword),
          child: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: Colors.grey.shade500,
              size: 20,
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
    );
  }

  /// Живые индикаторы требований к паролю (8 символов + заглавная + спецсимвол).
  /// Те же правила, что проверяет _completeSetup перед регистрацией.
  Widget _buildPasswordChecks() {
    final pwd = _passwordController.text;
    final s = LocaleService.current;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _passwordCheckRow(s.min8Chars, pwd.length >= 8),
        _passwordCheckRow(s.oneUppercase, pwd.contains(RegExp(r'[A-Z]'))),
        _passwordCheckRow(
          s.oneSpecialChar,
          pwd.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]')),
        ),
      ],
    );
  }

  Widget _passwordCheckRow(String label, bool passed) {
    final color = passed ? const Color(0xFF4CAF50) : Colors.grey.shade400;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          passed ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSocialButton({
    required VoidCallback? onPressed,
    required Widget icon,
    required String label,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
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
            icon,
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleLogoSmall extends StatelessWidget {
  const _GoogleLogoSmall();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}
