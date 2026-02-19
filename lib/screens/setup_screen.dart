import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_data.dart';
import '../services/firebase_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

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

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  // Colors based on gender
  Color get _accent {
    if (_selectedGender == Gender.male) return const Color(0xFF4A90D9);
    if (_selectedGender == Gender.female) return const Color(0xFFEE2B6C);
    return const Color(0xFFEE2B6C);
  }

  Color get _accentLight {
    if (_selectedGender == Gender.male) return const Color(0xFFE3F0FF);
    if (_selectedGender == Gender.female) return const Color(0xFFFEEAF1);
    return const Color(0xFFFEEAF1);
  }

  List<Color> get _bgGradient {
    if (_selectedGender == Gender.male) {
      return [
        const Color(0xFFE8F0FE),
        const Color(0xFFEDF3FB),
        const Color(0xFFF2F6FA),
      ];
    }
    return [
      const Color(0xFFF2EDE8),
      const Color(0xFFF5F0EC),
      const Color(0xFFF8F5F2),
    ];
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
        // Try to load existing user profile from Firestore
        final profile = await fb.loadUserProfile();

        if (profile != null &&
            profile['displayName'] != null &&
            profile['gender'] != null) {
          // User already has a profile in Firestore - auto-register and go to home
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
          _showError('Google не отвечает. Проверьте интернет.');
        } else {
          _showError('Ошибка входа через Google: $errorMsg');
        }
      }
    }
  }

  Future<void> _completeSetup() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty) {
      _showError('Введите ваше имя');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      _showError('Введите корректный email');
      return;
    }
    if (_selectedGender == null) {
      _showError('Выберите пол');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final fb = FirebaseService();

      // Если пользователь не залогинен (ввёл данные вручную), создаём аккаунт
      if (!fb.isLoggedIn) {
        // Проверяем пароль только для ручной регистрации
        if (password.length < 6) {
          _showError('Пароль должен быть минимум 6 символов');
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
        // Проверяем, не существует ли уже аккаунт с таким email
        if (errorMsg.contains('email-already-in-use')) {
          _showEmailExistsDialog();
        } else if (errorMsg.contains('TimeoutException')) {
          _showError('Сервер не отвечает. Проверьте интернет.');
        } else {
          _showError('Ошибка регистрации: $errorMsg');
        }
      }
    }
  }

  /// Генерирует случайный пароль для автоматической регистрации
  String _generateRandomPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()';
    final random = Random();
    return List.generate(20, (_) => chars[random.nextInt(chars.length)]).join();
  }

  void _showEmailExistsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Аккаунт существует',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Этот email уже зарегистрирован. Хотите войти в существующий аккаунт?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Отмена',
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
            child: const Text('Войти'),
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
      imageQuality: 85,
      maxWidth: 512,
      maxHeight: 512,
    );

    if (image == null || !mounted) return;

    // Сохраняем локально для превью и последующей загрузки после регистрации
    setState(() {
      _selectedAvatarFile = image;
      _avatarUrl = ''; // Очищаем URL, так как показываем локальный файл
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _bgGradient,
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: _step == 0 ? _buildGenderStep() : _buildRegistrationStep(),
          ),
        ),
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
            'Кто вы?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Выберите пол для настройки темы',
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
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Продолжить',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 20),
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
    final color = isMale ? const Color(0xFF4A90D9) : const Color(0xFFEE2B6C);
    final bgColor = isMale ? const Color(0xFFE3F0FF) : const Color(0xFFFEEAF1);
    final icon = isMale ? Icons.male_rounded : Icons.female_rounded;
    final label = isMale ? 'Парень' : 'Девушка';

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
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 36),
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
          const SizedBox(height: 24),
          // Avatar
          GestureDetector(
            onTap: _pickAvatar,
            child: Stack(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accentLight,
                    border: Border.all(
                      color: _accent.withOpacity(0.2),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
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
                          child: Image.network(
                            _avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.person_rounded,
                              color: _accent.withOpacity(0.5),
                              size: 40,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.person_rounded,
                          color: _accent.withOpacity(0.5),
                          size: 40,
                        ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Создайте профиль',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Войдите через Google или\nзаполните вручную',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          // Google Sign In button
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
              child: _isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _accent,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Google "G" icon using text
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Center(
                            child: Text(
                              'G',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4285F4),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Войти через Google',
                          style: TextStyle(
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
                  'или вручную',
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
          // Name field
          _buildTextField(
            controller: _nameController,
            label: 'Имя',
            hint: 'Ваше имя',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 16),
          // Email field
          _buildTextField(
            controller: _emailController,
            label: 'Email',
            hint: 'your@email.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          // Password field
          _buildPasswordField(),
          const SizedBox(height: 36),
          // Complete button
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _completeSetup,
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
                  : const Text(
                      'Начать',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          // Login link
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Уже есть аккаунт? ',
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
                  'Войти',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                borderSide: BorderSide(color: _accent, width: 2),
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
            'Пароль',
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
              hintText: 'Минимум 6 символов',
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
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
                borderSide: BorderSide(color: _accent, width: 2),
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
