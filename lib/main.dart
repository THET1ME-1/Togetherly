import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'config/sentry_config.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:home_widget/home_widget.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:yandex_mobileads/mobile_ads.dart' as yandex;
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'models/user_data.dart';
import 'services/analytics_service.dart';
import 'services/deep_link_service.dart';
import 'services/firebase_service.dart';
import 'services/catalog_service.dart';
import 'services/live_location_service.dart';
import 'services/locale_service.dart';
import 'services/mascot_inactivity_notification_service.dart';
import 'services/mood_pack_service.dart';
import 'services/pocketbase_service.dart';
import 'services/pb_auth_service.dart';
import 'services/pb_data_service.dart';
import 'models/widget_data.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'screens/force_update_screen.dart';
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
        await ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('UMP form error: $error');
        });
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

  // Redmi Note 12 Pro (Alex) — для тестирования рекламы в release-сборках
  const releaseTestDeviceIds = <String>['766303ABCCDC5AE221EAA39549B48EF5'];

  try {
    await MobileAds.instance.initialize();
    final testIds = [
      if (kDebugMode) ...const <String>[],
      ...releaseTestDeviceIds,
    ];
    if (testIds.isNotEmpty) {
      MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: testIds),
      );
    }
  } catch (e) {
    debugPrint('AdMob init failed: $e');
  }

  // Яндекс — резервная сеть (водопад): если AdMob не отдаёт рекламу
  // (onAdFailedToLoad), баннер/rewarded грузятся из Яндекса. Инициализируем
  // рядом с AdMob; обе SDK живут параллельно и не конфликтуют.
  try {
    await yandex.MobileAds.initialize();
  } catch (e) {
    debugPrint('Yandex Ads init failed: $e');
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
    // PB-фон: процесс мёртв → инициализируем клиент и восстанавливаем сессию
    // из SharedPreferences. ⚠️ нужен валидный PB-токен (widget_data protected).
    await PocketBaseService().init();
    final myUid = PocketBaseService().userId ?? '';
    if (myUid.isEmpty) return;

    final groupId =
        await HomeWidget.getWidgetData<String>('love_widget_group_id') ?? '';
    final partnerUid =
        await HomeWidget.getWidgetData<String>('love_widget_partner_uid') ?? '';
    if (groupId.isEmpty) return;

    // Fetch my data
    final myRec = await PbDataService().loadWidget(groupId, myUid);
    if (myRec != null) {
      final d = WidgetData.fromPb(myRec);
      await Future.wait([
        HomeWidget.saveWidgetData<String>('my_status', d.status),
        HomeWidget.saveWidgetData<String>('my_mood', d.moodLabel),
        HomeWidget.saveWidgetData<String>('my_message', d.message),
        HomeWidget.saveWidgetData<String>('my_music_title', d.musicTitle ?? ''),
        HomeWidget.saveWidgetData<String>(
          'my_music_artist',
          d.musicArtist ?? '',
        ),
      ]);
    }

    // Fetch partner data
    if (partnerUid.isNotEmpty) {
      final partnerRec = await PbDataService().loadWidget(groupId, partnerUid);
      if (partnerRec != null) {
        final d = WidgetData.fromPb(partnerRec);
        await Future.wait([
          HomeWidget.saveWidgetData<String>('partner_status', d.status),
          HomeWidget.saveWidgetData<String>('partner_mood', d.moodLabel),
          HomeWidget.saveWidgetData<String>('partner_message', d.message),
          HomeWidget.saveWidgetData<String>(
            'partner_music_title',
            d.musicTitle ?? '',
          ),
          HomeWidget.saveWidgetData<String>(
            'partner_music_artist',
            d.musicArtist ?? '',
          ),
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

/// Ошибки, прилетающие в глобальный async-обработчик из фоновых операций,
/// которые НЕ роняют приложение (выполнение продолжается, есть деградация):
///  • Firebase права/доступ: presence onDisconnect при недокаченных RTDB-правилах,
///    фоновая загрузка в Storage без прав;
///  • google_fonts: офлайн-загрузка шрифта с fonts.gstatic.com падает → текст
///    рисуется системным шрифтом, не краш.
/// Помечаем их non-fatal, чтобы не путать с настоящими падениями.
bool _isBenignBackgroundError(Object error) {
  final s = error.toString();
  return s.contains('permission-denied') ||
      s.contains('permission_denied') ||
      s.contains('firebase_storage/unauthorized') ||
      s.contains('Failed to load font') ||
      // На случай редкого варианта Rubik, не вошедшего в бандл: текст просто
      // рисуется системным шрифтом, не краш.
      s.contains('allowRuntimeFetching');
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

  // Шрифт Rubik зашит в сборку (assets google_fonts/) — запрещаем загрузку с
  // fonts.gstatic.com во время работы. Это убирает сетевую зависимость, мерцание
  // шрифта при старте и офлайн-ошибки «Failed to load font».
  GoogleFonts.config.allowRuntimeFetching = false;

  // PocketBase — поднимаем клиент и восстанавливаем сессию из SharedPreferences
  // (миграция Firebase→PB). Сессия переживает перезапуск процесса. signInSilently
  // лишь освежает токен, если он валиден. Firebase пока инициализируется рядом:
  // остальные слои (данные/realtime/медиа/пуш) ещё на нём — его инициализацию,
  // Crashlytics, Messaging и Supabase убираем ПОСЛЕДНИМ шагом cutover'а, когда
  // все слои переведены (см. pocketbase/CUTOVER.md §1, §7).
  await PocketBaseService().init();
  await PbAuthService().signInSilently();

  // Firebase — инициализация
  await Firebase.initializeApp();

  // Крашрепортинг — self-hosted Bugsink (Sentry-совместимый, наш VPS), замена
  // Firebase Crashlytics. Перехватываем:
  //  • FlutterError.onError — синхронные ошибки фреймворка (build/layout/paint);
  //  • PlatformDispatcher.onError — необработанные асинхронные ошибки (Future/
  //    Stream), которые иначе молча гасились.
  // В debug DSN пустой → SDK no-op (не шлём тестовые краши на прод-бэкенд).
  await SentryFlutter.init((options) {
    options.dsn = kDebugMode ? '' : SentryConfig.dsn;
    options.environment = kDebugMode ? 'debug' : 'production';
    options.tracesSampleRate = 0.0; // только краши, без performance-трейсинга
    options.attachStacktrace = true;
  });
  Sentry.configureScope(
    (scope) => scope.setUser(SentryUser(id: PocketBaseService().userId ?? '')),
  );
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(Sentry.captureException(details.exception, stackTrace: details.stack));
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    // Возвращаем true → приложение НЕ падает, выполнение продолжается. Часть
    // ошибок здесь — из фоновых операций (presence, фоновая загрузка медиа) и
    // крашами не являются: помечаем их level=warning, остальное — fatal, чтобы
    // не завышать счётчик падений.
    final fatal = !_isBenignBackgroundError(error);
    unawaited(Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: (scope) =>
          scope.level = fatal ? SentryLevel.fatal : SentryLevel.warning,
    ));
    return true;
  };

  // Supabase убран (миграция на PocketBase). Прежний слой Supabase был
  // переходным экспериментом дуал-райта; его инициализация удалена. Все вызовы
  // SupabaseService защищены `isReady` и становятся no-op без init, так что
  // FirebaseService продолжает работать на Firebase до полного перехода на PB.
  // Force-update порог теперь читается из PocketBase (`app_config.min_build`).

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
      PocketBaseService().signOut();
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
      if (PocketBaseService().isLoggedIn) {
        PocketBaseService().signOut();
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

  // Аналитика отключена (firebase_analytics убран при уходе с Firebase) —
  // AnalyticsService теперь no-op shell. Привязку userId оставляем как заглушку
  // на случай будущей серверной аналитики на PocketBase.
  unawaited(AnalyticsService.instance.setUserId(PocketBaseService().userId));

  // Deep links — инициализация
  DeepLinkService().init();

  // FCM — push-уведомления
  FirebaseService().initFCM();

  // Локальное напоминание, если пользователь долго не открывает приложение
  await MascotInactivityNotificationService.instance.init();
  await MascotInactivityNotificationService.instance.markAppOpened();

  // Locale — инициализация (определяет язык по региону или сохранённым настройкам)
  await LocaleService.instance.init();

  // Восстанавливаем флаг шеринга геопозиции (карта «Где мы»). Сам трекинг
  // стартует из home_screen после привязки к группе (resumeIfEnabled).
  await LiveLocationService.instance.init();

  // Выбранный пак настроений (локальный выбор, как язык) — грузим заранее,
  // чтобы пикер сразу открывался на нужном наборе без мигания.
  await MoodPackService.instance.load();

  // Удалённый каталог контента (паки настроений из Supabase) — поднимаем кэш с
  // диска мгновенно, свежий список тянем фоном. Новые паки/эмоции приезжают без
  // обновления приложения. Офлайн/без credentials — остаются встроенные паки.
  await CatalogService.instance.init();

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
  // Установленная сборка ниже минимально поддерживаемой (PocketBase
  // app_config.min_build) → блокирующий экран обновления. fail-open: при любой
  // ошибке/без конфига остаётся false и никого не блокирует.
  bool _forceUpdate = false;
  AppLifecycleListener? _lifecycleListener;

  // Тема пересобирается при смене темы приложения (акцент берётся из активной
  // AppTheme). Кэшируем по акценту, чтобы не пересоздавать на каждый
  // notifyListeners() UserData (монеты, присутствие и т.п.).
  Color? _lastAccent;
  ThemeData? _lastTheme;

  ThemeData _themeFor(Color accent) {
    if (_lastTheme == null || _lastAccent != accent) {
      _lastAccent = accent;
      _lastTheme = _buildTheme(accent);
    }
    return _lastTheme!;
  }

  /// Единый стиль для всех меню (диалоги, bottom-sheet, snackbar, popup-меню).
  /// Цвета — от акцента активной темы, форма/скругления — из общих токенов.
  static ThemeData _buildTheme(Color accent) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(primary: accent);

    const titleColor = Color(0xFF2A2A2A);
    const bodyColor = Color(0xFF555555);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: GoogleFonts.rubikTextTheme(),
      scaffoldBackgroundColor: const Color(0xFFF7F3F0),

      // ── Диалоги ────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: GoogleFonts.rubik(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: titleColor,
        ),
        contentTextStyle: GoogleFonts.rubik(
          fontSize: 15,
          height: 1.4,
          color: bodyColor,
        ),
      ),

      // ── Bottom-sheet ───────────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        modalElevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      // ── SnackBar ───────────────────────────────────────────────────────
      // Тёмная нейтральная подложка — единая и читаемая на всех 20 темах;
      // акцент темы выводим в цвете кнопки действия.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2E2A2C),
        contentTextStyle: GoogleFonts.rubik(
          color: Colors.white,
          fontSize: 14,
        ),
        actionTextColor: scheme.inversePrimary,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      // ── Popup-меню ─────────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _init();
    // Отслеживаем жизненный цикл приложения для обновления статуса присутствия
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        // Онлайн-презенс ведёт PresenceService (lifecycle-aware).
        MascotInactivityNotificationService.instance.markAppOpened();
      },
      onPause: () {
        MascotInactivityNotificationService.instance
            .scheduleReminderAfterOneDay();
      },
      onDetach: () {
        MascotInactivityNotificationService.instance
            .scheduleReminderAfterOneDay();
      },
      onHide: () {
        MascotInactivityNotificationService.instance
            .scheduleReminderAfterOneDay();
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
      // Force-update kill-switch: если сборка ниже min_build из PocketBase
      // (`app_config`) — дальше покажем блокирующий ForceUpdateScreen. Только
      // Android (на iOS обновления гонит App Store). fail-open: minBuild=0 ⇒ не
      // блокируем.
      if (Platform.isAndroid) {
        try {
          final minBuild = await PbDataService().fetchMinSupportedBuild();
          if (minBuild > 0) {
            final info = await PackageInfo.fromPlatform();
            final current = int.tryParse(info.buildNumber) ?? 0;
            _forceUpdate = current < minBuild;
          }
        } catch (_) {
          // Любая ошибка чтения конфига — не блокируем пользователя.
        }
      }

      // Запоминаем, была ли сессия активна ДО loadFromPrefs: внутри него
      // серверная синхронизация коинов/тем выполняется только при уже
      // активной сессии (isLoggedIn). При тихом входе сессия поднимается
      // ниже — поэтому при wasLoggedIn == false синк надо повторить вручную.
      final wasLoggedIn = PocketBaseService().isLoggedIn;

      // Загружаем локальный профиль из SharedPreferences.
      await _userData.loadFromPrefs();

      // Тихий вход в PocketBase уже выполнен в main() до runApp
      // (PbAuthService().signInSilently). Firebase-сессия на cutover не нужна.

      // Сессию подняли только что (loadFromPrefs синк пропустил, т.к. на тот
      // момент мы не были залогинены) → подтягиваем авторитетный баланс/темы
      // с сервера. Без этого весь сеанс показывались бы устаревшие локальные
      // значения, а серверные начисления (реклама, ежедневный вход, покупки)
      // молча применялись бы поверх неактуального состояния — отсюда симптомы
      // «монеты пропадают/возвращаются, награды и покупки не сохраняются».
      if (!wasLoggedIn &&
          _userData.isRegistered &&
          PocketBaseService().isLoggedIn) {
        await _userData.syncFromServer();
      }

      // Онлайн-презенс ведёт PresenceService (стартует на home-экране).

      // Выдаём иконки-награды спонсорам и помощникам.
      // grantSpecialBadge только ДОБАВЛЯЕТ иконку в доступные и закрепляет её
      // лишь если у пользователя ещё нет выбранной иконки — поэтому свободный
      // выбор иконки пользователем больше не перезатирается при каждом запуске.
      const sponsorEmails = {
        'badzoff@gmail.com',
        'alena.petukhova1@gmail.com',
        'romanhilp22@gmail.com',
        'nakotumari@gmail.com',
        'lrt56k@mail.ru',
      };
      const helperEmails = {'ashatilov2008@gmail.com'};
      if (sponsorEmails.contains(_userData.email)) {
        final granted = await _userData.grantSpecialBadge('Sponsor');
        if (granted) {
          await FirebaseService().showLocalNotification(
            id: 8801,
            title: '🎉 Вам вручён значок «Спонсор»!',
            body:
                'Спасибо за поддержку — теперь рядом с вашим именем '
                'красуется особый бейдж 💖',
          );
        }
      } else if (helperEmails.contains(_userData.email)) {
        final granted = await _userData.grantSpecialBadge('Helper');
        if (granted) {
          await FirebaseService().showLocalNotification(
            id: 8802,
            title: '🎉 Вам вручён значок «Помощник»!',
            body: 'Спасибо за помощь проекту — особый бейдж теперь ваш 💖',
          );
        }
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
      // Слушаем язык И профиль: смена темы (в _userData) пересобирает ThemeData,
      // поэтому единый стиль меню сразу подхватывает новый акцент.
      listenable: Listenable.merge([LocaleService.instance, _userData]),
      builder: (context, _) => MaterialApp(
        title: 'Togetherly',
        debugShowCheckedModeBanner: false,
        theme: _themeFor(_userData.themeAccent),
        navigatorObservers: [AnalyticsService.instance.observer],
        home: _loading
            ? const Scaffold(body: M3PageLoading(color: Color(0xFFFF7E8B)))
            : _buildInitialScreen(),
      ),
    );
  }

  Widget _buildInitialScreen() {
    // 0. Обязательное обновление — блокирующий экран поверх всего.
    if (_forceUpdate) {
      return const ForceUpdateScreen();
    }
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
