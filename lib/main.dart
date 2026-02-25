import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/user_data.dart';
import 'services/deep_link_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase — инициализация
  await Firebase.initializeApp();

  // Deep links — инициализация
  DeepLinkService().init();

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
      // Firebase Auth восстанавливает сессию асинхронно сам по себе —
      // authStateChanges() обновит StreamBuilder когда будет готов.
      await _userData.loadFromPrefs();
    } catch (_) {
      // Даже при ошибке убираем спиннер
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Love App',
      debugShowCheckedModeBanner: false,
      theme: _cachedTheme,
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : ListenableBuilder(
              listenable: _userData,
              builder: (context, _) {
                // Слушаем Firebase Auth для реакции на принудительный выход
                // (смена пароля на сервере, удаление аккаунта и т.д.)
                return StreamBuilder<User?>(
                  stream: FirebaseAuth.instance.authStateChanges(),
                  builder: (context, snapshot) {
                    // Если Firebase сообщил о выходе И локальные данные были
                    // заполнены — сбрасываем сессию
                    if (snapshot.connectionState != ConnectionState.waiting &&
                        snapshot.data == null &&
                        _userData.isRegistered) {
                      // Откладываем на следующий кадр чтобы не вызвать
                      // setState во время build
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _userData.logout();
                      });
                    }
                    return _buildInitialScreen();
                  },
                );
              },
            ),
    );
  }

  Widget _buildInitialScreen() {
    // 1. Первый запуск — показываем welcome
    if (!_userData.hasSeenWelcome) {
      return WelcomeScreen(userData: _userData);
    }
    // 2. Профиль есть локально — сразу домой.
    //    Firebase Auth подтвердит сессию асинхронно; если токен реально
    //    аннулирован, StreamBuilder вызовет logout() и перенаправит сюда.
    if (_userData.isRegistered) {
      return HomeScreen(userData: _userData);
    }
    // 3. Профиль не заполнен — на экран входа
    return WelcomeScreen(userData: _userData);
  }
}
