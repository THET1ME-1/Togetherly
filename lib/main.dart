import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'models/user_data.dart';
import 'services/deep_link_service.dart';
import 'services/firebase_service.dart';
import 'services/locale_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase — инициализация
  await Firebase.initializeApp();

  // Deep links — инициализация
  DeepLinkService().init();

  // FCM — push-уведомления
  FirebaseService().initFCM();

  // Locale — инициализация (определяет язык по региону или сохранённым настройкам)
  await LocaleService.instance.init();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  runApp(const LoveApp());
}

class LoveApp extends StatefulWidget {
  const LoveApp({super.key});

  @override
  State<LoveApp> createState() => _LoveAppState();
}

class _LoveAppState extends State<LoveApp> {
  final UserData _userData = UserData();
  bool _loading = true;

  // Cache theme to avoid recreating on every build
  static final ThemeData _cachedTheme = ThemeData(
    textTheme: GoogleFonts.plusJakartaSansTextTheme(),
    scaffoldBackgroundColor: const Color(0xFFF7F3F0),
    useMaterial3: true,
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _init() async {
    try {
      // Загружаем локальный профиль из SharedPreferences.
      await _userData.loadFromPrefs();

      // Если пользователь зарегистрирован, но Firebase Auth не имеет
      // активной сессии (например, после перезапуска процесса),
      // пробуем тихо восстановить Google-аккаунт без диалога.
      if (_userData.isRegistered && !FirebaseService().isLoggedIn) {
        debugPrint('Auth session lost, trying silent sign-in...');
        await FirebaseService().signInSilently();
        // Если тихий вход удался — isLoggedIn теперь true.
        // Если нет — пользователь попадёт на экран входа после dispose
        // пустого uid (FirebaseService запросы будут отклоняться).
      }
    } catch (_) {
      // Даже при ошибке убираем спиннер
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) => MaterialApp(
        title: 'Love App',
        debugShowCheckedModeBanner: false,
        theme: _cachedTheme,
        home: _loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : ListenableBuilder(
                listenable: _userData,
                builder: (context, _) => _buildInitialScreen(),
              ),
      ),
    );
  }

  Widget _buildInitialScreen() {
    // 1. Первый запуск — показываем welcome
    if (!_userData.hasSeenWelcome) {
      return WelcomeScreen(userData: _userData);
    }
    // 2. Профиль есть локально — сразу домой.
    //    Firebase сессия восстановлена в _init() через signInSilently().
    if (_userData.isRegistered) {
      return HomeScreen(userData: _userData);
    }
    // 3. Профиль не заполнен — на экран входа
    return WelcomeScreen(userData: _userData);
  }
}
