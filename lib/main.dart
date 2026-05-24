import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/user_data.dart';
import 'services/deep_link_service.dart';
import 'services/firebase_service.dart';
import 'services/locale_service.dart';
import 'services/mascot_inactivity_notification_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/common/m3_loading.dart';

/// Top-level background handler — должен быть функцией верхнего уровня.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await FirebaseService.handleBackgroundMessage(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase — инициализация
  await Firebase.initializeApp();

  // При первом запуске после установки — выходим из любой сохранённой сессии.
  // SharedPreferences очищаются при удалении приложения, поэтому отсутствие
  // флага означает свежую установку. Это предотвращает подхват устаревших
  // pairIds из Firestore, оставшихся от debug-сессий.
  final prefs = await SharedPreferences.getInstance();
  const kInstallKey = 'app_installed_v1';
  if (!prefs.containsKey(kInstallKey)) {
    try {
      if (FirebaseService().isLoggedIn) {
        await FirebaseService().signOut();
      }
    } catch (_) {}
    await prefs.setBool(kInstallKey, true);
  }

  // Debug → Release переход: при апгрейде SharedPreferences НЕ очищаются,
  // поэтому kInstallKey уже есть и выхода из аккаунта не происходит.
  // Если предыдущая сессия была debug, а текущая release — делаем signOut,
  // чтобы стейт debug-тестирования не засорял production-окружение.
  const kLastBuildMode = 'last_build_mode_v1';
  final lastBuildMode = prefs.getString(kLastBuildMode) ?? '';
  const currentBuildMode = kDebugMode ? 'debug' : 'release';
  if (lastBuildMode == 'debug' && currentBuildMode == 'release') {
    try {
      if (FirebaseService().isLoggedIn) {
        await FirebaseService().signOut();
      }
    } catch (_) {}
  }
  await prefs.setString(kLastBuildMode, currentBuildMode);

  // FCM background handler — регистрируем до чего угодно
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Включаем офлайн-кеш Firestore
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Deep links — инициализация
  DeepLinkService().init();

  // FCM — push-уведомления
  FirebaseService().initFCM();

  // Локальное напоминание, если пользователь долго не открывает приложение
  await MascotInactivityNotificationService.instance.init();
  await MascotInactivityNotificationService.instance.markAppOpened();

  // Locale — инициализация (определяет язык по региону или сохранённым настройкам)
  await LocaleService.instance.init();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: true,
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
  AppLifecycleListener? _lifecycleListener;

  // Cache theme to avoid recreating on every build
  static final ThemeData _cachedTheme = ThemeData(
    textTheme: GoogleFonts.rubikTextTheme(),
    scaffoldBackgroundColor: const Color(0xFFF7F3F0),
    useMaterial3: true,
  );

  @override
  void initState() {
    super.initState();
    _init();
    // Отслеживаем жизненный цикл приложения для обновления статуса присутствия
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        FirebaseService().setOnlineStatus(true);
        MascotInactivityNotificationService.instance.markAppOpened();
      },
      onPause: () {
        FirebaseService().setOnlineStatus(false);
        MascotInactivityNotificationService.instance.scheduleReminderAfterOneDay();
      },
      onDetach: () {
        FirebaseService().setOnlineStatus(false);
        MascotInactivityNotificationService.instance.scheduleReminderAfterOneDay();
      },
      onHide: () {
        FirebaseService().setOnlineStatus(false);
        MascotInactivityNotificationService.instance.scheduleReminderAfterOneDay();
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
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

      // Устанавливаем статус "онлайн" при запуске
      if (FirebaseService().isLoggedIn) {
        FirebaseService().setOnlineStatus(true);
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
        title: 'Togetherly',
        debugShowCheckedModeBanner: false,
        theme: _cachedTheme,
        home: _loading
            ? const Scaffold(body: M3PageLoading(color: Color(0xFFFF7E8B)))
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
