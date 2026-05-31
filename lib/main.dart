import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:home_widget/home_widget.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/user_data.dart';
import 'services/analytics_service.dart';
import 'services/deep_link_service.dart';
import 'services/firebase_service.dart';
import 'services/locale_service.dart';
import 'services/mascot_inactivity_notification_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/common/m3_loading.dart';

/// Запрашивает согласие GDPR (UMP), затем инициализирует AdMob SDK.
/// МobileAds.initialize() ДОЛЖЕН вызываться ПОСЛЕ завершения consent flow,
/// иначе на EEA-устройствах SDK стартует без согласия и реклама блокируется.
Future<void> _initConsentAndAds() async {
  final params = ConsentRequestParameters(
    consentDebugSettings: kDebugMode
        ? ConsentDebugSettings(
            debugGeography: DebugGeography.debugGeographyEea,
            testIdentifiers: <String>[],
          )
        : null,
  );

  final completer = Completer<void>();

  ConsentInformation.instance.requestConsentInfoUpdate(
    params,
    () async {
      try {
        await ConsentForm.loadAndShowConsentFormIfRequired(
          (error) {
            if (error != null) debugPrint('UMP form error: $error');
          },
        );
      } finally {
        completer.complete();
      }
    },
    (FormError error) {
      debugPrint('UMP update error: $error');
      completer.complete();
    },
  );

  // Таймаут 5 с — не блокируем запуск если UMP завис
  await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {});

  try {
    await MobileAds.instance.initialize();
    if (kDebugMode) {
      MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: <String>[]),
      );
    }
  } catch (e) {
    debugPrint('AdMob init failed: $e');
  }
}

/// Top-level background handler — должен быть функцией верхнего уровня.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await FirebaseService.handleBackgroundMessage(message);
}

/// Вызывается нативным виджетом (LoveWidgetProvider.onUpdate) через
/// HomeWidgetBackgroundReceiver, когда процесс Flutter мёртв.
/// Тянет свежие данные из Firestore и обновляет SharedPreferences виджета,
/// чтобы парный виджет показывал актуальный статус/настроение без открытия приложения.
@pragma('vm:entry-point')
Future<void> _homeWidgetBackgroundCallback(Uri? uri) async {
  if (!Platform.isAndroid || uri == null) return;

  final host = uri.host.trim().toLowerCase();
  if (host.isEmpty || host != 'refresh') return;

  try {
    await Firebase.initializeApp();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final groupId =
        await HomeWidget.getWidgetData<String>('love_widget_group_id') ?? '';
    final partnerUid =
        await HomeWidget.getWidgetData<String>('love_widget_partner_uid') ?? '';
    if (groupId.isEmpty) return;

    final db = FirebaseFirestore.instance;

    // Fetch my data
    final mySnap = await db
        .collection('groups')
        .doc(groupId)
        .collection('widgetData')
        .doc(user.uid)
        .get()
        .timeout(const Duration(seconds: 10));

    if (mySnap.exists && mySnap.data() != null) {
      final d = mySnap.data()!;
      await Future.wait([
        HomeWidget.saveWidgetData<String>('my_status', d['status'] as String? ?? ''),
        HomeWidget.saveWidgetData<String>('my_mood', d['moodLabel'] as String? ?? ''),
        HomeWidget.saveWidgetData<String>('my_message', d['message'] as String? ?? ''),
        HomeWidget.saveWidgetData<String>('my_music_title', d['musicTitle'] as String? ?? ''),
        HomeWidget.saveWidgetData<String>('my_music_artist', d['musicArtist'] as String? ?? ''),
      ]);
    }

    // Fetch partner data
    if (partnerUid.isNotEmpty) {
      final partnerSnap = await db
          .collection('groups')
          .doc(groupId)
          .collection('widgetData')
          .doc(partnerUid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (partnerSnap.exists && partnerSnap.data() != null) {
        final d = partnerSnap.data()!;
        await Future.wait([
          HomeWidget.saveWidgetData<String>('partner_status', d['status'] as String? ?? ''),
          HomeWidget.saveWidgetData<String>('partner_mood', d['moodLabel'] as String? ?? ''),
          HomeWidget.saveWidgetData<String>('partner_message', d['message'] as String? ?? ''),
          HomeWidget.saveWidgetData<String>('partner_music_title', d['musicTitle'] as String? ?? ''),
          HomeWidget.saveWidgetData<String>('partner_music_artist', d['musicArtist'] as String? ?? ''),
        ]);
      }
    }

    await HomeWidget.updateWidget(
      name: 'LoveWidgetProvider',
      androidName: 'LoveWidgetProvider',
    );
  } catch (e) {
    debugPrint('_homeWidgetBackgroundCallback failed: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Принудительно используем системный Android Photo Picker (ACTION_PICK_IMAGES)
  // вместо legacy ACTION_GET_CONTENT, который на MIUI открывает файловый
  // проводник (DocumentsUI) вместо галереи.
  final imagePickerImpl = ImagePickerPlatform.instance;
  if (imagePickerImpl is ImagePickerAndroid) {
    imagePickerImpl.useAndroidPhotoPicker = true;
  }

  // Firebase — инициализация
  await Firebase.initializeApp();

  // Google UMP + AdMob — consent должен быть получен ДО инициализации SDK
  if (Platform.isAndroid || Platform.isIOS) {
    await _initConsentAndAds();
  }

  // При первом запуске после установки — принудительно выходим из сессии
  // и очищаем SharedPreferences. На iOS Firebase Auth хранит токен в Keychain,
  // который переживает удаление приложения — поэтому signOut() вызывается
  // безусловно, без проверки isLoggedIn.
  final prefs = await SharedPreferences.getInstance();
  const kInstallKey = 'app_installed_v1';
  if (!prefs.containsKey(kInstallKey)) {
    try {
      await FirebaseService().signOut();
    } catch (_) {}
    await prefs.clear();
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

  // На Samsung One UI / aggressive battery saver путь
  // HomeWidgetBackgroundReceiver -> JobIntentService нестабилен
  // (особенно в home_widget 0.7.x). Для наших Android-виджетов достаточно
  // launch intent + явных updateWidget(), поэтому не регистрируем
  // background interactivity callback и не провоцируем enqueueWork crash.
  if (!Platform.isAndroid) {
    HomeWidget.registerInteractivityCallback(_homeWidgetBackgroundCallback);
  }

  // Включаем офлайн-кеш Firestore
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Touch FirebaseAnalytics so the native SDK starts collecting auto events
  // (first_open, session_start, screen_view, app_remove, etc.). The custom
  // product events live in AnalyticsService.
  AnalyticsService.instance;
  // Bind userId to the current auth state so events are attributable.
  unawaited(
    AnalyticsService.instance.setUserId(FirebaseService().uid),
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

  // Synchronise Flutter's window with MainActivity's setDecorFitsSystemWindows(false).
  // Without this call Flutter and Android disagree about where gesture exclusion
  // zones are, causing system swipe gestures (back, home) to be intercepted by
  // Flutter's own gesture arena and bounce the user back into the app.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      // false = don't let Android paint a contrast scrim over the nav bar;
      // that scrim overlaps the gesture zone and can interfere with swipe detection.
      systemNavigationBarContrastEnforced: false,
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

      // Выдаём иконки-награды спонсорам и помощникам.
      // grantSpecialBadge только ДОБАВЛЯЕТ иконку в доступные и закрепляет её
      // лишь если у пользователя ещё нет выбранной иконки — поэтому свободный
      // выбор иконки пользователем больше не перезатирается при каждом запуске.
      const sponsorEmails = {
        'badzoff@gmail.com',
        'alena.petukhova1@gmail.com',
        'romanhilp22@gmail.com',
      };
      const helperEmails = {
        'ashatilov2008@gmail.com',
      };
      if (sponsorEmails.contains(_userData.email)) {
        await _userData.grantSpecialBadge('Sponsor');
      } else if (helperEmails.contains(_userData.email)) {
        await _userData.grantSpecialBadge('Helper');
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
        navigatorObservers: [AnalyticsService.instance.observer],
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
