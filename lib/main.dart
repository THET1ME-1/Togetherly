import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/user_data.dart';
import 'services/deep_link_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase — инициализация
  await Firebase.initializeApp();

  // Ждём первый auth state (восстановление сессии)
  await FirebaseAuth.instance.authStateChanges().first;

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
    scaffoldBackgroundColor: const Color(0xFFF8F6F6),
    useMaterial3: true,
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
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
          : _buildInitialScreen(),
    );
  }

  Widget _buildInitialScreen() {
    // 1. First launch ever — show welcome
    if (!_userData.hasSeenWelcome) {
      return WelcomeScreen(userData: _userData);
    }
    // 2. Seen welcome but not registered — show setup
    if (!_userData.isRegistered) {
      return SetupScreen(userData: _userData);
    }
    // 3. Fully registered — go home
    return HomeScreen(userData: _userData);
  }
}
