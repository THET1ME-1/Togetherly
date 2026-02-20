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
    // Ждём, пока Firebase Auth восстановит сессию.
    // authStateChanges() первым эмитом может дать null ещё до того,
    // как токен будет проверен — это вызывало редирект на WelcomeScreen.
    await FirebaseAuth.instance.authStateChanges().first.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
    // Теперь _fb.isLoggedIn корректен — loadFromPrefs сможет подтянуть
    // данные из Firestore, если пользователь авторизован.
    await _userData.loadFromPrefs();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Love App',
      debugShowCheckedModeBanner: false,
      theme: _cachedTheme,
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                // Firebase ещё восстанавливает сессию — показываем сплэш
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                return _buildInitialScreen(firebaseUser: snapshot.data);
              },
            ),
    );
  }

  Widget _buildInitialScreen({User? firebaseUser}) {
    // 1. Первый запуск — показываем welcome
    if (!_userData.hasSeenWelcome) {
      return WelcomeScreen(userData: _userData);
    }
    // 2. Firebase подтвердил, что сессии нет — на экран входа
    if (firebaseUser == null) {
      return WelcomeScreen(userData: _userData);
    }
    // 3. Firebase авторизован, но профиль не заполнен — на setup
    if (!_userData.isRegistered) {
      return WelcomeScreen(userData: _userData);
    }
    // 4. Всё в порядке — домой
    return HomeScreen(userData: _userData);
  }
}
