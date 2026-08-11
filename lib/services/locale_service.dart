import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dict_strings.dart';

import 'package:love_app/config/update_notes.dart';
import '../screens/postcard/models/postcard_template.dart';
// Немецкий: словарь плюс свои числительные, подстановки и списки дат.
part 'strings_de.dart';
part 'strings_fr.dart';
part 'strings_es.dart';
part 'strings_it.dart';
part 'strings_pt.dart';

/// Языки интерфейса. Набор тот же, что в Wickly и Kadr.
///
/// Порядок значений менять нельзя: язык хранится в prefs строкой, но `index`
/// уезжает в аналитику и в снимки настроек.
enum AppLanguage {
  ru('ru', 'Русский'),
  en('en', 'English'),
  de('de', 'Deutsch'),
  fr('fr', 'Français'),
  es('es', 'Español'),
  it('it', 'Italiano'),
  pt('pt', 'Português');

  const AppLanguage(this.code, this.label);

  /// Код языка — он же колонка в словаре `kStrings`.
  final String code;

  /// Название на самом языке: список выбора читают те, кто нашего языка не знает.
  final String label;

  static AppLanguage? byCode(String code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return null;
  }
}

/// Язык интерфейса: выбор человека, иначе догадка по локали устройства.
///
/// Строки живут в словаре `kStrings` (см. `lib/dict_strings.dart`), поэтому язык
/// без перевода не ломает экран: `trDict` откатывается на английский. Из-за
/// этого новый язык добавляется записью в словаре, а не классом на полторы
/// тысячи членов — семь таких классов файл бы не пережил.
class LocaleService extends ChangeNotifier {
  LocaleService._();
  static final LocaleService _instance = LocaleService._();
  static LocaleService get instance => _instance;

  /// Short accessor used everywhere: `S.of`
  static AppStrings get current => _instance.strings;

  AppLanguage _language = AppLanguage.en;
  bool _initialized = false;

  AppLanguage get language => _language;
  bool get isRussian => _language == AppLanguage.ru;
  bool get isEnglish => _language == AppLanguage.en;

  /// Что показывать в `MaterialApp.supportedLocales`: без этого системные части
  /// (выбор даты, меню копирования) остаются английскими при любом переводе.
  static List<ui.Locale> get supportedLocales => [
    for (final l in AppLanguage.values) ui.Locale(l.code),
  ];

  static const Map<AppLanguage, AppStrings> _byLanguage = {
    AppLanguage.ru: _RuStrings(),
    AppLanguage.en: _EnStrings(),
    AppLanguage.de: _DeStrings(),
    AppLanguage.fr: _FrStrings(),
    AppLanguage.es: _EsStrings(),
    AppLanguage.it: _ItStrings(),
    AppLanguage.pt: _PtStrings(),
  };

  AppStrings get strings => _byLanguage[_language] ?? const _EnStrings();

  /// Язык устройства → наш язык. Регион важен там, где язык системы английский,
  /// а страна говорит иначе: латиноамериканская `es-419`, бразильская `pt-BR`,
  /// австрийская `de-AT` приходят разными кодами, а язык у них один.
  static AppLanguage detect(ui.Locale locale) {
    final byLang = AppLanguage.byCode(locale.languageCode.toLowerCase());
    if (byLang != null) return byLang;
    const byCountry = <String, AppLanguage>{
      'RU': AppLanguage.ru,
      'BY': AppLanguage.ru,
      'KZ': AppLanguage.ru,
      'KG': AppLanguage.ru,
      'UA': AppLanguage.ru,
      'DE': AppLanguage.de,
      'AT': AppLanguage.de,
      'CH': AppLanguage.de,
      'LI': AppLanguage.de,
      'FR': AppLanguage.fr,
      'BE': AppLanguage.fr,
      'LU': AppLanguage.fr,
      'MC': AppLanguage.fr,
      'ES': AppLanguage.es,
      'MX': AppLanguage.es,
      'AR': AppLanguage.es,
      'CO': AppLanguage.es,
      'CL': AppLanguage.es,
      'PE': AppLanguage.es,
      'VE': AppLanguage.es,
      'EC': AppLanguage.es,
      'GT': AppLanguage.es,
      'IT': AppLanguage.it,
      'SM': AppLanguage.it,
      'PT': AppLanguage.pt,
      'BR': AppLanguage.pt,
      'AO': AppLanguage.pt,
      'MZ': AppLanguage.pt,
    };
    return byCountry[locale.countryCode?.toUpperCase()] ?? AppLanguage.en;
  }

  /// Initialize: load saved preference or detect from device locale.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('app_language');
      if (saved != null) {
        // Прежние сборки писали сюда 'ru' или 'en', новые — любой из семи кодов.
        _language = AppLanguage.byCode(saved) ?? AppLanguage.en;
      } else {
        _language = detect(ui.PlatformDispatcher.instance.locale);
        // Персистим определённый по локали язык, чтобы фоновые изоляты
        // (WorkManager / foreground-сервис) читали конкретное значение из
        // prefs, а не дефолтный EN — иначе mood-виджет обновляется в фоне с
        // английскими метками. PlatformDispatcher.locale в headless-изоляте
        // ненадёжен, prefs шарятся между изолятами и надёжны.
        await prefs.setString('app_language', _language.code);
      }
    } catch (_) {
      _language = AppLanguage.en;
    }
    _initialized = true;
    notifyListeners();
  }

  /// Change language and persist.
  Future<void> setLanguage(AppLanguage lang) async {
    if (_language == lang) return;
    _language = lang;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_language', lang.code);
    } catch (_) {}
    notifyListeners();
  }

  String get languageLabel => _language.label;
}

// ══════════════════════════════════════════════════════════════════════════════
// ABSTRACT STRINGS
// ══════════════════════════════════════════════════════════════════════════════

abstract class AppStrings {
  const AppStrings();

  // ── Common ──
  String get save;
  String get cancel;
  String get delete;
  String get edit;
  String get add;
  String get done;
  String get loading;
  String get error;
  String get ok;
  String get yes;
  String get no;
  String get close;
  String get back;
  String get reset;
  String get clear;

  // ── Welcome Screen ──
  String get welcomeTitle1;
  String get welcomeTitle2;
  String get welcomeSubtitle;
  String get welcomeFeatureMemories;
  String get welcomeFeatureMood;
  String get welcomeFeatureWidgets;
  String get welcomeStepCreateProfile;
  String get welcomeStepConnectPartner;
  String get welcomeStepStartTogether;
  String get createAccount;
  String get alreadyHaveAccount;
  String get privateSecure;
  String get welcomeNext;

  // ── Login Screen ──
  String get welcomeBack;
  String get loginToAccount;
  String get signInWithGoogle;
  String get or;
  String get email;
  String get yourEmail;
  String get password;
  String get yourPassword;
  String get login;
  String get noAccount;
  String get create;
  String get invalidEmail;
  String get enterPassword;
  String get loginFailed;
  String get profileNotFound;
  String get userNotFound;
  String get wrongPassword;
  String get invalidEmailFormat;
  String get tooManyAttempts;
  String get serverNotResponding;

  /// Соединение ломают по дороге (TLS не доходит целым).
  String get connectionBlocked;
  String get googleNotResponding;
  String loginError(String e);
  String googleLoginError(String e);

  // ── Setup Screen ──
  String get whoAreYou;
  String get selectGenderForTheme;
  String get boy;
  String get girl;
  String get continueBtn;
  String get createProfile;
  String get signInGoogleOrManual;
  String get orManually;
  String get name;
  String get yourName;
  String get minCharsPassword;
  String get start;
  String get alreadyHaveAccountQuestion;
  String get enterYourName;
  String get enterValidEmail;
  String get selectGender;
  String get passwordMin6;
  String get accountExists;
  String get emailAlreadyRegistered;
  String registrationError(String e);
  // Согласие на онбординге собирается из частей: чекбокс «Я принимаю
  // <Условия использования> и <Политику конфиденциальности>», где обе ссылки
  // кликабельны (требование сторов к UGC-приложениям).
  String get agreeToTermsPrefix;
  String get termsOfUse;
  String get agreeToTermsAnd;
  String get privacyPolicyLink;
  String get forgotPassword;
  String passwordResetSent(String email);
  String get passwordResetError;
  String get showPassword;
  String get hidePassword;
  String get min8Chars;
  String get oneUppercase;
  String get oneSpecialChar;
  String get fullName;
  String get createAccountBtn;
  String get continueWithGoogle;
  String get continueWithApple;
  String get signInWith;
  String get signUpWith;
  String get rememberMe;
  String get alreadyHaveAccountLogin;
  String get passwordRequirements;

  // ── Home Screen ──
  String get home;
  String get widgets;
  String get connect;
  String get profile;
  String get solo;
  String get waitingForConnection;
  String daysLabel(String suffix);
  String monthsLabel(String suffix);
  String timeLabel(String suffix);
  String get inLove;
  String get together;
  String get days;
  String get months;
  String get time;
  String get inviteYourPartner;
  String get shareLinkCodeQr;
  String get relationshipMemoryLane;
  String get memoriesWillAppear;
  String get connectWithPartnerToStart;
  String partnerIsMood(String name, String mood);
  String get answerSent;
  String get dailyReflection;
  String get today;
  String get answerPrompt;
  String get editAnswer;
  String get clearMood;
  String get removeMood;
  String get howAreYouFeeling;
  String get partnerWillSeeMood;
  String moodDateLabel(String dateLabel);
  String get indicateMoodForDay;
  // ── Разделы сетки настроений ──
  String get moodBandBright;
  String get moodBandEven;
  String get moodBandSad;
  String get moodBandHeavy;

  /// Подпись художника под сеткой пака: «Рисунки — noia_aa».
  String moodPackAuthor(String name);
  // ── Самочувствие («болячки») ──
  String get moodTabLabel;
  String get ailmentTabLabel;
  String get ailmentPickerSubtitle;
  String get clearAilment;
  String partnerAilmentBanner(String name, String label);
  String get relationshipStatus;
  String get chooseHowToConnect;
  String get inLoveStatus;
  String get perfectForCouples;
  String get married;
  String get forMarriedPartners;
  String get friends;
  String get connectWithBestFriend;
  String get bestBuddies;
  String get forInseparableCompanions;
  String get addCustomStatus;
  String get editCustomStatus;
  String get addCaption;
  String get optionalDescribe;
  String get writeSmth;
  String get skip;
  String get post;
  String get posting;
  String get failedUploadPhoto;
  String get memoryNotSaved;
  String get achievementUnlocked;
  String get achievementsTitle;

  /// Короткая подпись плитки в профиле — «Достижения пары» там не помещается.
  String get achievementsShort;
  String get achMetricDays;
  String get achMetricMemories;
  String get achMetricMessages;
  String get achMetricDrawings;
  String get achMetricStreak;
  String get achFilterAll;
  String get achFilterUnlocked;
  String get achFilterInProgress;
  String get achNothingHere;
  String achProgressOf(int value, int target);
  String get achievementDone;
  String achievementsUnlockedOf(int unlocked, int total);
  String get markSecret;
  String get unmarkSecret;
  String get markedSecret;
  String get unmarkedSecret;
  String get secretMemories;
  String get enterPinTitle;
  String get setPinTitle;
  String get setPinHint;
  String get wrongPin;
  String get pinTooShort;
  String get pinDone;
  String get timeCapsule;
  String get capsuleIntro;
  String get capsuleLetterHint;
  String get capsuleAttachPhoto;
  String get capsuleOpenDate;
  String get change;
  String capsuleOpensIn(int days);
  String get capsulePreset1m;
  String get capsulePreset6m;
  String get capsulePreset1y;
  String get capsuleSeal;
  String get capsuleNeedsContent;
  String get capsuleNeedsFutureDate;
  String capsuleOpensOn(String date);
  String capsuleFrom(String name);
  String capsuleNotReady(String date);
  String get capsuleAddSub;
  String get capsuleCreated;
  String get capsuleOpenedTitle;
  String get capsuleOpenedBody;
  String capsuleOpenedBodyNamed(String title);
  String get postedToMemoryLane;
  String get moodCalendar;
  String get seeAll;
  String get addMemory;
  String get viewAll;

  // ── Widget Screen ──
  String get widgetsTitle;
  String get resetBtn;
  String get desktopPreview;
  String get me;
  String get partner;
  String get noStatus;
  String get myWidget;
  String get tapToEdit;
  String get editBtn;
  String widgetOfPartner(String name);
  String get emptyYet;
  String get updated;
  String get live;
  String get mood;
  String get status;
  String get message;
  String get photo;
  String get photoUploaded;
  String get widgetPhotoOwnerOnlyHint;
  String get music;
  String get addBtn;
  String get widgetSettings;
  String get photoToMemoryLane;
  String get autoSavePhotoToMemories;
  String get messagestoMemoryLane;
  String get autoSaveMessages;
  String get musicToMemoryLane;
  String get autoSaveTracks;
  String get moodToCalendar;
  String get autoMarkMoodCalendar;
  String get connectPartnerForWidgets;
  String get chooseMood;
  String get statusHint;
  String get messageHint;
  String get chooseSource;
  String get camera;
  String get gallery;
  String get musicTitle;
  String get trackName;
  String get artist;
  String get linkOptional;
  String get uploadingPhoto;
  String get resetWidget;
  String get resetWidgetConfirm;
  String get notPairedWidgets;
  String get notPairedWidgetsDesc;

  // ── Profile Screen ──
  String get user;
  String get noEmail;
  String get gender;
  String get male;
  String get female;
  String get genderPreferNotSay;
  String get genderCustom;
  String get genderCustomHint;
  String get genderNotSet;
  String get information;
  String get theme;
  String get relationships;
  String get statusLabel;
  String get partnerLabel;
  String get notSelected;
  String daysTogetherLabel(String days);
  String get invitePartnerToCount;
  String get anniversaryDate;
  String get anniversaryWheelHint;
  String get firstKissDate;
  String get myBirthday;
  String get partnerBirthday;
  String get notifCelebrations;
  String get notifCelebrationsHint;
  String get anniversaryTodayTitle;
  String get anniversaryTodayBody;
  String get birthdayTodayTitle;
  String get birthdayTodayBody;
  String get anniversaryTomorrowTitle;
  String get anniversaryTomorrowBody;
  String get birthdayTomorrowTitle;
  String get birthdayTomorrowBody;
  String get celebrationBannerAnniversary;
  String get celebrationBannerBirthday;
  String get daysUntilAnniversary;
  String get daysUntilBirthday;
  String get inLoveRelType;
  String get marriedRelType;
  String get friendsRelType;
  String get bestFriendsRelType;
  String get customStatus;
  String get relationshipType;
  String get selectPartner;
  String get noConnectedPartners;
  String get settings;
  String get editProfile;
  String get notifications;
  String get privacy;
  String get aboutApp;
  String get supportAuthors;
  String get supportIntro;
  String get logout;
  String get logoutQuestion;
  String get logoutConfirm;
  String get logoutBtn;
  String get deleteAccount;
  String get deleteAccountQuestion;
  String get deleteAccountConfirm;
  String get deleteAccountBtn;
  String get deleteAccountReauth;
  String get deleteAccountError;
  String get chooseColorTheme;
  String get appearanceTitle;
  String get paletteLabel;
  String get themeModeLabel;
  String get themeStyleLabel;
  String get themeModeLight;
  String get themeModeDark;
  String get themeModeSystem;
  String get themeFlavorSoft;
  String get themeFlavorJuicy;
  String get themeFlavorExact;
  String get amoledLabel;
  String get levelTasksGroup;
  String get themeNamePink;
  String get themeNamePurple;
  String get themeNameBlue;
  String get themeNamePeach;
  String get themeNameSage;
  String get themeNameMidnight;
  String get themeNameLavender;
  String get themeNameCherry;
  String get themeNameMint;
  String get themeNameSunset;
  String get themeNameMonochrome;
  String get themeNameForest;
  String get themeNameOcean;
  String get themeNameHoney;
  String get themeNameLemon;
  String get themeNameSand;
  String get themeNameAurora;
  String get themeNameBordeaux;
  String get themeNameTeal;
  String get themeNameNord;
  String get themeNameCharcoalTeal;
  String get themeNameCoffee;
  String get themeNameForestDark;
  String get themeNameGarnet;
  String get themeNameDarkHoney;
  String premiumThemeLocked(int price);
  String get coinBalance;
  String get coinShopTitle;
  String get coinShopSubtitle;

  /// Тот же лист на iPhone. Покупок там нет вовсе, поэтому слово «магазин»
  /// обещает то, чего внутри не будет: остаются только способы заработать.
  String get coinEarnTitle;
  String get coinEarnSubtitle;
  String get buyThemeTitle;
  String buyThemeDescription(String themeName, int price);
  String get buyThemeConfirm;
  String get notEnoughCoins;
  String get themePurchased;
  // ── Профильные иконки ──
  String get iconShopTitle;
  String get iconShopSubtitle;
  String get noIconOption;
  String get iconRewardOnly;
  String get iconRewardHint;
  String get iconPurchased;
  String get watchAdTitle;
  String get watchAdSubtitle;
  String get adNotReady;
  String get adRewardLimitReached;
  String get rewardPending;
  String get changesApplyImmediately;

  // ── Бесплатные монеты ──
  String get dailyBonusTitle;
  String get dailyBonusSubtitle;
  String coinEarned(int amount);
  String get memoryRewardTitle;
  String get memoryRewardSubtitle;
  String get partnerInviteRewardTitle;
  String get partnerInviteRewardSubtitle;
  String get moodStreakRewardTitle;
  String get moodStreakRewardSubtitle;
  String get earnCoinsSection;

  // ── IAP — покупка монет ──
  String get coinPacksSectionTitle;
  String coinPackTitle(int coins);
  String get coinPurchaseSuccess;
  String coinPurchaseSuccessAmount(int coins);
  String get coinPurchasePending;
  String get coinPurchaseCancelled;
  String get coinPurchaseError;
  String get coinStoreUnavailable;
  String get restorePurchasesTitle;
  String get restorePurchasesSuccess;
  String get restorePurchasesError;
  String get editProfileTitle;
  String get uploading;
  String get userNotAuthorized;
  String get failedUploadImage;
  String get avatarUpdated;
  String get nameUpdated;
  String uploadError(String e);
  String get language;
  String get selectLanguage;
  String get blobAnimation;

  // ── Mood Calendar Screen ──
  String get moodCalendarTitle;
  String get moodSettings;
  String get moodMultiplePerDay;
  String get moodMultiplePerDaySubtitle;
  String get zoomIn;
  String get zoomOut;
  String get week;
  String get month;
  String get year;
  String get myMood;
  String partnerMood(String name);
  String get moods;

  // ── Home Screen (continued) ──
  String get emoji;
  String get label;
  String get egSoulmates;
  String get shareYourThoughts;
  String get draw;
  String get calendar;
  String get noMemoriesYet;

  // ── Draw Screen ──
  String get drawTogether;
  String get brush;
  String get eraser;
  String get panTool;
  String get fillBg;
  String get rotateCanvas;
  String get drawLine;
  String get drawRect;
  String get drawCircle;
  String get drawTriangle;
  String get fillShapes;
  String get insertPhoto;
  String get photoRequiresPartner;
  String get photoFromGallery;
  String get photoFromCamera;
  String get undoAction;
  String get redoAction;
  String get clearCanvas;
  String get clearCanvasConfirm;
  String get deletePhoto;
  String get mascotBoyName;
  String get mascotGirlName;
  String get mascotSpikyName;
  String get mascotLuluName;
  String get mascotIskrikName;
  String get mascotZhuzhaName;
  String get saveDrawing;
  String get shareDrawing;
  String drawingSavedTo(String path);
  String get failedToSaveDrawing;
  String get failedToShareDrawing;
  String get strokeThickness;
  String get drawHint;
  String partnerIsDrawing(String name);
  String get addFirstMemory;
  String get video;
  String get videoLabel;
  String get location;
  String get audio;
  List<String> get reflectionQuestions;

  // ── Draw Gallery / Canvas ──
  String get palmTool;
  String get drawingMode;
  String get newCanvas;
  String get myDrawings;
  String get untitledCanvas;
  String get renameCanvas;
  String get deleteCanvas;
  String get deleteCanvasConfirm;
  String get canvasNameLabel;
  String get noDrawingsYet;

  // ── Connect Partner Screen ──
  String get newGroup;
  String get waiting;
  String get deleteGroupConfirm;
  String get deleteGroupTitle;
  String get removeGroup;
  String get connected;
  String groupOf(int count);
  String membersCount(int count);
  String get member;
  String get online;
  String get offline;
  String get chatOnline;
  String get chatTypingShort;
  String get inviteMore;
  String get scanQr;
  String get disconnect;
  String get connectYourPartner;
  String get shareInviteCodeDesc;
  String get yourInviteCode;
  String get copy;
  String get share;
  String get codeCopied;
  String shareInviteText(String code, String link);
  String get loveAppInvitation;
  String get newCodeGenerated;
  String get showQr;
  String get haveACode;

  // ── Первый экран после регистрации: позвать половину ──
  String get inviteHeroTitle;
  String get inviteHeroBody;
  String get sendInvitation;
  String get haveCode;
  String get staySolo;
  String get later;
  String get tapToCopy;
  String get inviteCodeLoading;
  String get inviteQrTitle;
  String get inviteQrHint;
  String get enterPartnerCode;
  String get inviteCodeNotFound;

  // ── Первые действия новичка ──
  String get onboardingTitle;
  String onboardingLeft(int left);
  String get onboardingDone;
  String get onboardingStepPhoto;
  String get onboardingStepMood;
  String get onboardingStepWidget;
  String onboardingNext(String step);
  String get onboardingSkip;

  // ── Чат: пустой экран и подсказки к кнопкам ──
  String get chatEmptyTitle;
  String get chatEmptyBody;
  String get chatEmptyGhostTheirs;
  String get chatEmptyGhostMine;
  String get chatPinTooltip;
  String get chatStyleTooltip;
  String get chatLookMaterial;
  String get chatLookCozy;
  String get chatLookMaterialOn;
  String get chatLookCozyOn;

  /// Подпись под полем заголовка в форме записи.
  String get titleFieldHint;

  /// Название типа записи в открытом воспоминании.
  String memoryTypeName(String type);

  // ── Выбор символа таймера ──
  String get symbolPickerTitle;
  String get symbolPickerAll;
  String get countdownModeHint;
  String get setAsMainHint;
  String timerDaysCount(int days);
  String get symbolSearchHint;
  String get symbolSearchEmpty;
  String symbolSearchFound(int count);
  String get symbolSetHint;
  String get symbolSetLove;
  String get symbolSetHolidays;
  String get symbolSetHome;
  String get symbolSetRoad;
  String get symbolSetWork;

  // ── Названия фонов чата (узоры рисуются кодом) ──
  String get chatBgPlain;
  String get chatBgDawn;
  String get chatBgHearts;
  String get chatBgWeave;
  String get chatBgDots;
  String get chatBgBubbles;
  String get chatBgNight;

  // ── Приглашение партнёра в слоте подсказки ──
  String get needsPartnerHint;
  String get inviteReminderTitle;
  String get inviteReminderBody;
  String get invitePromptTitle;
  String get invitePromptBody;
  String get invitePromptAction;

  // ── Партнёр давно не заходил ──
  String quietPartnerTitle(String name, int days);
  String get quietPartnerBody;
  String get quietPartnerAction;
  String get quietPartnerSent;

  String get connectPartnerBtn;
  String get inviteMoreMembers;
  String membersOfMax(int current, int max);
  String shareGroupInviteText(String code, String link);
  String get groupInvitation;
  String connectedWithCouple(String name);
  String marriedTo(String name);
  String friendsWith(String name);
  String buddiesWith(String name);
  String customRelWith(String label, String name);
  String get joinAnotherGroup;
  String get enterCodeScanQr;
  String get enterCode;
  String get invalidCodeTryAgain;
  String get joinGroup;
  String get cantInviteSelf;
  String get codeNotFound;
  String get scanToConnect;
  String get scanPartnersQr;
  String get qrPointAtCode;
  String get qrScannerUnavailable;
  String get qrScannerUnavailableHint;
  String get qrEnterCodeManually;
  String get addNewConnection;
  String get chooseTypeForConnection;
  String get yourCustomType;
  String get newConnectionAdded;
  String get deleteConnection;
  String get deleteConnectionDesc;
  String get connectionRemoved;
  String get disconnectQuestion;
  String get disconnectDesc;
  String get renamePartner;
  String get renamePartnerHint;
  String get resetNickname;
  String joinMeLinkText(String link);
  String get custom;
  String membersCountBracket(int count);

  // ── Memory Lane Screen ──
  String get memoryLane;
  String get addMemoryBtn;

  /// Кнопка внизу формы записи.
  String get addMemoryToFeed;
  String get pinned;

  // ── Timer Card ──
  String get timers;
  String get failedUploadBackground;

  // -- Mini Mood Calendar --
  String get todayLabel;

  // ── Date helpers ──
  String get todayDate;
  String get yesterday;
  List<String> get shortMonths;
  List<String> get shortWeekdays;

  // ── I Miss You / Vibes ──
  String get iMissYou;
  String get iMissYouSent;
  String missYouNotifTitle(String name);
  String get missYouNotifBody;
  String missYouStreak(int count);
  String get thinkingOfYou;
  String get wantHug;
  String get vibeSent;
  String get customVibe;
  String get customVibeTitle;
  String get customVibeHint;
  String thinkingOfYouNotifTitle(String name);
  String wantHugNotifTitle(String name);
  String customVibeNotifTitle(String name);

  // ── Экран «Скучаю» ──
  String get missYouTitle;
  String get missYouSendHint;
  String get missYouYou;
  String get missYouPartner;
  String get missYouMore;
  String get missYouLatest;
  String get missYouReplyBack;
  String get missYouWeekTitle;
  String get missYouWeekEmpty;
  String get missYouWishRemoved;

  // ── Photo Card ──
  String get sharedAPicture;
  String kmFromYou(String km);
  String get openInMaps;
  String get justNow;
  String minutesAgo(int m);
  String hoursAgo(int h);
  String daysAgo(int d);

  // ── Memory Lane Feed ──
  String get sharedAVideo;
  String get sharedAVideoLink;
  String get sharedAThought;
  String get sharedALocation;
  String get sharedMusic;
  String get vibesTo;
  String get setARoute;
  String get isListening;
  String get playTrack;
  String get note;

  // ── Memory Lane (extended) ──
  String get noMemoriesYetDesc;
  String get unpinMemory;
  String get pinMemory;
  String get saveToDevice;
  String get editMemory;
  String get deleteMemory;
  String get deleteMemoryQuestion;
  String get actionCannotBeUndone;
  String get editMemoryTitle;
  String get titleOptional;
  String get description;
  String get locationName;
  String get changeLocationOnMap;
  String get pickLocationOnMap;
  String get saveChanges;
  String get addMemoryTitle;
  String get chooseWhatToShare;
  String newMemory(String type);
  String get memoryDetails;
  String get writeYourNote;
  String get descriptionOptional;
  String get locationNameHint;
  String get locationSet;
  String get useCurrent;
  String get pickOnMap;
  String get songDetails;
  String get songName;
  String get artistsCommaSeparated;
  String get egArtists;
  String get source;
  String get streamingLink;
  String get fetched;
  String get pasteLinkFromService;
  String get autoFetchSongInfo;
  String get musicMetaNotFound;
  String get orDivider;
  String get fileSelected;
  String get pickAudioFromDevice;
  String get uploadingMemory;
  String get failedUploadPhotos;
  String get failedUploadVideo;
  String get memoryAddedSuccess;
  String failedAddMemory(String e);
  String get noMediaUrl;
  String get downloading;
  String get savedToGallery;
  String savedToPath(String path);
  String downloadFailed(String e);
  String failedSelectPhotos(String e);
  String failedSelectVideo(String e);
  String get locationServicesDisabled;
  String get locationPermissionDenied;
  String get cameraPermissionDenied;
  String get failedGetLocation;
  String get tapToSelectPhotos;
  String get tapToSelectVideo;
  String get adultContent;
  String get photoBlurred;
  String get fromGallery;
  String get byLink;
  String get videoLink;
  // ── Books ──
  String get books;
  String get bookSearchHint;
  String get searchBooksPrompt;
  String get noBooksFound;
  String get bookSearchFailed;
  String get bookSearchFailedHint;
  String get bookEnterManually;
  String get bookManualEntryHint;
  String get sharedABook;
  String get bookAuthorLabel;
  String get bookAuthorHint;
  String get bookTitleHint;
  String get bookDetails;
  String get bookReadMore;
  String get bookSearchAgain;

  // ── Movies & series ──
  String get movies;
  String get movieSearchHint;
  String get searchMoviesPrompt;
  String get noMoviesFound;
  String get movieSearchFailed;
  String get movieSearchFailedHint;
  String get movieEnterManually;
  String get movieManualEntryHint;
  String get movieNoToken;
  String get sharedAMovie;
  String get movieTitleHint;
  String get movieOriginalTitleHint;
  String get movieDetails;
  String get movieReadMore;
  String get movieSearchAgain;

  // ── Rating & review (books / movies) ──
  String get yourRating;
  String get ratingNotRated;
  String get ratingHint;
  String get ratingMasterpiece;
  String get ratingExcellent;
  String get ratingGood;
  String get ratingMixed;
  String get ratingBad;
  String get ratingAwful;
  String get yourReview;
  String get reviewHint;

  // ── Memory date picker ──
  String get memoryDateLabel;
  String get memoryDateNow;

  /// Короткая подпись чипа даты в форме записи.
  String get dateNowLabel;
  String get memoryDatePickDate;
  String get memoryDatePickTime;
  String get memoryDateClear;
  String get fetchData;
  String get supportedPlatformsHint;
  String get supportedPlatforms;
  String get pasteLinkSupported;
  String get gotIt;
  String get sideActionTitle;
  String get sideActionOpenFeed;
  String get sideActionCreatePin;
  String get sideActionHint;
  String get supportedServices;
  String get pasteLinkFromSupported;
  String get selectTextAndPress;
  String get spoiler;
  String get deleteComment;
  String get deleteCommentQuestion;
  String get comments;
  String get writeAComment;
  String get noCommentsYet;
  String nPhotos(int count);
  String get noPhotoAttached;
  String get unknownLocation;
  String get openInGoogleMaps;
  String get audioFile;
  String get unknownTrack;
  String get noAudioUrl;
  String get cannotPlayAudio;
  String openIn(String name);
  String get tapToOpen;
  String get videoBadge;
  String get updateAvailableTitle;
  String get updateAvailableSubtitle;
  String get updateWhatsNew;
  String get updateButton;
  String get updateLaterButton;
  String get updateRestartButton;
  String get forceUpdateTitle;
  String get forceUpdateBody;
  String get forceUpdateButton;
  String get noteBadge;
  String get youtubeBadge;
  String get photoNotUploaded;
  List<String> get fullMonths;
  String formatDateAt(String month, int day, int year, String time);

  // ── Relationship Status Screen ──
  String get noActiveConnection;
  String get chooseAStatus;
  String get customStatuses;
  String get currentStatus;
  String get notSet;
  String get clearStatus;
  String statusSetTo(String status);
  String failedSetStatus(String e);
  String get statusCleared;
  String failedClearStatus(String e);
  String get customStatusAdded;
  String failedAddStatus(String e);
  String get statusUpdated;
  String failedUpdateStatus(String e);
  String get deleteStatus;
  String deleteStatusConfirm(String label);
  String get statusDeleted;
  String failedDeleteStatus(String e);
  String get editStatus;
  String get emojiLabel;
  String get emojiHint;
  String get labelField;
  String get egLivingTogether;
  String get update;

  // ── Map Picker Screen ──
  String get selectLocationOnMap;
  String get selectedLocation;
  String get selectLocation;
  String get confirm;
  String get gettingAddress;
  String get tapOnMapToSelect;
  String get failedGetCurrentLocation;

  // ── Mood Calendar (extended) ──
  String get averageMood;
  String get great;
  String get good;
  String get okay;
  String get bad;
  String get awful;
  String get notEnoughData;
  String moodRecorded(String label);
  String get noMoodRecorded;
  String get moodScorePrefix;
  List<String> get shortWeekdaysSingleChar;
  List<String> get longWeekdays;

  // ── Timer / Expandable Timer Card ──
  String get noTimers;
  String get createTimer;
  String get editTimer;
  String get timerNameLabel;
  String get egAnniversary;
  String get targetDate;
  String get startDate;
  String get dateFormatHint;
  String get symbolLabel;
  String get countdownMode;
  String get countdownPastDateWarning;
  String get setAsMain;
  String get saveSettings;
  String get deleteTimerQuestion;
  String timerDeleteConfirm(String name);

  // ── Petal Timer Dial ──
  String get yearsLabel;
  String get monthsShortLabel;
  String get daysShortLabel;
  String get hoursLabel;
  String get minLabel;
  String get secLabel;

  // ── Widget Screen (extended) ──
  String get homeScreenWidgets;
  String get addToHomeScreen;
  String get addWidgetFromHomeHint;
  String get setAsPhotoOfDay;
  String get widgetAddedToHome;
  String failedAddWidget(String e);
  String get daysTogetherStat;
  String get memoriesStat;
  String get drawingsStat;
  String get missYousStat;
  String get daysLeft;
  String get daysElapsed;
  String get noTimersWidget;
  String get photoOfDay;
  String get mine;
  String get onWidget;
  String get randomSource;
  String get ownPhoto;
  String get saveToMemoryLane;
  String get regenerate;
  String get none;
  String yearsAlready(int years);
  String get pairWidgetTitle;
  String get pairWidgetSubtitle;
  String get daysCounterSubtitle;
  String get timerWidgetTitle;
  String get timerWidgetSubtitle;
  String get photoDayRandomSubtitle;
  String get photoDayCustomSubtitle;
  String get photoDayPartnerSubtitle;
  String get moodWidgetSubtitle;
  String get relationshipStatsSubtitle;
  String get daysCounterLabel;
  String get addTimerHint;
  String get noTimersAddHint;
  String get soloTimerBannerTitle;
  String get soloTimerBannerSubtitle;
  String get selectTimerForWidget;
  String get daysShortLeft;
  String get daysShortElapsed;
  String get partnerPhotoWillAppear;
  String get choosePhotoBelow;
  String get randomPhotoFromMemories;
  String get photoSource;
  String get fromMemories;
  String get fromGalleryLabel;
  String get widgetModeMine;
  String get widgetModePartner;
  String get widgetInstances;
  String get widgetNotAddedYet;
  String widgetSlotTitle(int index);
  String get addedWidgetsWillAppearHere;
  String get addSeparateWidgetHint;
  String get widgetDisplaySource;
  String get widgetDisplayPhoto;
  String get noPhotoSelected;

  // ── Profile (extended) ──
  String get exportMemories;
  String get resetMissYouCount;
  String get resetMissYouConfirmTitle;
  String get resetMissYouConfirmBody;
  String get noActiveGroupForExport;
  String get creatingArchive;
  String exportError(String e);
  String get relationshipStats;

  // ── Home Screen (extended) ──
  String get startWithBlankCanvas;
  String get openSavedDrawing;
  String get newPhoto;
  String get titleHint;
  String get descriptionOptionalHint;
  String get setAsWidgetPhoto;

  // ── Mini Mood Calendar (extended) ──
  List<String> get shortWeekdaysUpper;

  // ── Notification Settings ──
  String get notifMissYou;
  String get notifMissYouSub;
  String get notifNewMemory;
  String get notifNewMemorySub;
  String get notifMood;
  String get notifMoodSub;
  String get notifChat;
  String get notifChatSub;

  /// Подпись над рекламным блоком.
  String get adLabel;

  String get notifDaysTogether;
  String get notifDaysTogetherSub;

  /// Подпись того же тумблера на iPhone: постоянной плашки там нет,
  /// счётчик приходит утренним уведомлением.
  String get notifDaysTogetherSubIos;
  String daysTogetherNotifBody(int days);
  String get daysTogetherNotifTagline;
  String get openSystemSettings;
  String get notifSystemSettingsHint;

  // ── Chat ──
  String get chatTitle;
  String get chatHint;

  // ── Голосовые сообщения ──
  /// Подсказка под полосой записи, пока палец держит микрофон.
  String get voiceSlideHints;

  /// Палец увели влево: отпустишь — запись пропадёт.
  String get voiceReleaseToCancel;

  /// Палец увели вверх: отпустишь — запись останется идти без пальца.
  String get voiceReleaseToLock;

  /// Подпись голосового там, где нужен текст (цитата ответа, список связей).
  String get voiceMessage;

  /// Отпустили слишком быстро — записывать нечего.
  String get voiceTooShort;

  /// Микрофон не дали.
  String get voiceNoPermission;

  /// Записать не вышло: микрофон занят или платформа отказала.
  String get voiceFailed;

  /// Дошли до предела длительности.
  String get voiceLimitReached;

  /// Партнёр послушал наше голосовое.
  String get voiceHeard;

  // ── Пара с пустым местом («он в армии») ──
  String get waitingSetupTitle;
  String get waitingEditTitle;
  String get waitingSetupHint;
  String get waitingNameLabel;
  String get waitingReturnDate;
  String get waitingCreateAction;
  String get waitingCreateFailed;
  String get waitingBadge;
  String get waitingCodeTitle;
  String get waitingCodeHint;
  String get waitingCodeCopied;
  String get waitingResetCode;
  String get waitingResetCodeHint;
  String get waitingClaimTitle;
  String get waitingClaimAsk;
  String get waitingClaimYes;
  String get waitingClaimNo;
  String get waitingPendingTitle;
  String get waitingPendingHint;
  String get waitingRejected;
  String get waitingApproved;
  String get waitingUntilReturn;
  String get waitingHomeToday;

  /// Сколько дней осталось до возвращения.
  String waitingDaysLeft(int days);

  /// Развилка в листе: ждём конкретного человека или пока некого назвать.
  String get waitingWhoLabel;
  String get waitingKnowWho;
  String get waitingDontKnowWho;

  /// Имя второго места, когда человек его не назвал. Пустым его не оставить:
  /// сервер требует имя, а карточка пары рисует по нему первую букву.
  String get waitingUnknownName;
  String get waitingUnknownHint;

  /// Вход в «пару заранее» с экрана приглашения — для тех, кому некого позвать.
  String get waitingSoloTitle;
  String get waitingSoloBody;
  String get waitingSoloAction;
  String get chatEmpty;
  String get chatEditMessage;
  String get chatDeleteMessage;
  String get chatReply;
  String chatReplyingTo(String name);
  String chatTyping(String name);
  String get chatEdited;
  String get chatDeletedPlaceholder;
  String get chatSendFailed;
  String get chatAttachPin;
  String get chatSave;
  String chatNotifTitle(String name);
  String moodNotifTitle(String name);
  String chatDeleteConfirm(String text);

  /// Разделитель непрочитанных в чате (как в Telegram).
  String get chatNewMessages;

  /// Заголовок-разделитель по дате в чате: «Сегодня»/«Вчера»/«5 июня».
  String chatDateHeader(DateTime day);

  /// Лист оформления сообщения: подписи слоёв и кнопок.
  /// Пиксель-арт: диалог выбора сетки при создании холста.
  String get pixelCanvasTitle;
  String get pixelCanvasHint;
  String get pixelWidth;
  String get pixelHeight;
  String get plainCanvas;
  String get pixelCanvasCreate;
  String pixelCanvasSummary(int cells, int px);
  String get pixelGridShow;
  String get pixelGridHide;

  /// Галерея холстов: заголовок во весь верх и строка под ним.
  String get canvasesTitle;
  String canvasesSubtitle(int count, String lastDate);

  /// Экран выбора сетки пиксель-арта.
  String get pixelScreenTitle;
  String get pixelCanvasCreateAction;
  String get plainCanvasSubtitle;
  String get pixelCanvasSubtitle;

  /// Массовые действия в галерее холстов.
  /// Секции каталога виджетов.
  String get widgetsCurrentSection;
  String get widgetsCurrentSubtitle;
  String get widgetsNewSection;
  String get widgetsNewSubtitle;

  /// Виджет «Вместе» из нового каталога.
  String get tgTogetherTitle;
  String get tgTogetherSubtitle;
  String get tgNoteTitle;
  String get tgNoteSubtitle;
  String get tgNotePaperTitle;
  String get tgNotePaperSubtitle;
  String get tgMissTitle;
  String get tgMissSubtitle;

  /// Выбор размера в карточке каталога и подписи внутри превью.
  String get tgSizeHintCompact;
  String get tgSizeHintWide;
  String get tgSizeHintLarge;
  String get tgSizeHintStrip;
  String tgDaysTogetherCaption(int days);
  String tgMonthsCaption(int months);
  String get tgNextSection;
  String tgDaysMilestone(int days);
  String tgYearsMilestone(int years);
  String tgInDays(int days);
  String tgUntilMilestone(int target, int left);
  String tgMissAddressee(String name);
  String get tgMissSend;
  String get tgMissStripHint;

  /// Виджеты «Настроение» и «До встречи» из нового каталога.
  String get tgMoodTitle;
  String get tgMoodSubtitle;
  String get tgMoodToday;
  String get tgMoodMe;
  String get tgMoodPartner;
  String get tgMoodNotSet;
  String get tgMoodWeekTitle;
  String tgMoodMatched(int days);
  String get tgCountdownTitle;
  String get tgCountdownSubtitle;
  String get tgCountdownEmpty;
  String tgCountdownDaysLeft(int days);
  String get tgCountdownDays;
  String get tgCountdownHours;
  String get tgCountdownMinutes;
  String get tgSizeHintToday;
  String get tgSizeHintWeek;

  /// Виджеты «Кольцо года» и «Календарь лет».
  String get tgRingTitle;
  String get tgRingSubtitle;
  String get tgGridTitle;
  String get tgGridSubtitle;
  String get tgYearNoStartDate;
  String get tgYearMonthsLabel;
  String get tgYearMemoriesLabel;
  String tgYearDaysWord(int days);
  String tgYearDaysTogether(int days);
  String tgYearDaysLeft(int days);
  String tgYearToAnniversary(int year);
  String tgYearToAnniversaryShort(int year, int days);
  String tgYearCurrentYearShort(int year, int days);
  String tgYearOrdinalLabel(int year);
  String tgYearsAndDays(int years, int days);
  String tgYearSince(String date);

  /// Экран настроек, вынесенный из профиля.
  String get settingsTitle;
  String get settingsOpen;
  String get settingsOpenHint;
  String get settingsAppearanceHint;
  String get settingsNotificationsHint;
  String get settingsLockMoodHint;
  String get settingsDataSection;
  String get settingsExportHint;
  String get settingsResetMissHint;
  String get settingsPrivacyHint;
  String get settingsCoinsHint;
  String get settingsSupportHint;
  String get settingsAccountSection;
  String get settingsDeleteHint;

  /// Сон маскотов: у каждого персонажа своё окно ночной сцены.
  String get mascotSleepTitle;
  String get mascotSleepHint;
  String get mascotSleepEmpty;
  String get mascotSleepFrom;
  String get mascotSleepTo;
  String get mascotSleepOff;
  String get mascotNightAwake;
  String mascotSleepRange(String from, String to);
  String mascotNightRange(String from, String to);

  /// Календарь цикла.
  String get cycleTitle;

  /// Заголовок блока цикла в календаре партнёрши.
  String cycleOf(String name);
  String get cycleSettingsHint;
  String get cycleShareWithPartner;
  String get cycleShareHint;
  String get cycleWipe;
  String get cycleWipeHint;
  String get cycleConsentTitle;
  String get cycleConsentBody;
  String get cycleConsentAgree;
  String get cycleConsentLater;
  String get cycleConsentWithdraw;
  String get cycleConsentWithdrawHint;
  String get exportMyData;
  String get exportMyDataHint;
  String get exportMyDataReady;
  String get exportMyDataFailed;
  String get cycleWipeConfirm;
  String get cycleNoDataTitle;
  String get cycleNoDataHint;
  String get cycleExpectedToday;
  String cycleDaysLeft(int days);
  String cycleDayOfCycle(int day);
  String cycleOverdue(int days);
  String get cycleOverdueHint;
  String get cycleIrregularWarning;
  String get cycleMarkPeriod;
  String get cycleMarkPeriodHint;
  String get cycleMarkIntimacy;
  String get cycleMarkIntimacyHint;
  String get cycleAnalyticsTitle;
  String cycleAnalyticsHint(int cycles);
  String get cycleAverageLength;
  String get cycleAveragePeriod;
  String get cycleNextPeriod;
  String get cycleFertileWindow;
  String cycleDaysValue(int days);
  String get cycleDaysUnit;
  String get cycleAverageShort;
  String get cycleRangeShort;
  String get cycleRegularity;
  String get cycleRegularityOk;
  String get cycleRegularityLow;
  String get cycleChartLengths;
  String get cycleChartDurations;
  String get cycleLegendPeriod;
  String get cycleLegendPredicted;
  String get cycleLegendOvulation;
  String get cycleLegendFertile;
  String get cycleLegendIntimacy;
  List<String> get cycleWeekdayShorts;
  List<String> get cycleMonthNames;
  List<String> get cycleMonthsGenitive;

  /// Советы на дни месячных (лента под блоком цикла).
  String get cycleTipsTitle;
  String get cycleTipWarmTitle;
  String get cycleTipWarmBody;
  String get cycleTipFeetTitle;
  String get cycleTipFeetBody;
  String get cycleTipPainTitle;
  String get cycleTipPainBody;
  String get cycleTipShowerTitle;
  String get cycleTipShowerBody;
  String get cycleTipChangeTitle;
  String get cycleTipChangeBody;
  String get cycleTipIronTitle;
  String get cycleTipIronBody;
  String get cycleTipRestTitle;
  String get cycleTipRestBody;

  /// Лист дня в календаре: что отмечаем на этот день.
  String dayLogDate(DateTime day);
  String dayLogWeekday(DateTime day);
  String get dayLogWhat;
  String get dayLogNotMarked;
  String get dayLogTodayOnly;
  String get cycleSheetHint;
  String cyclePeriodDayLabel(int day);
  String get cycleSexMarked;

  /// Рисование: слои и фоны листа.
  String get drawLayers;
  String get drawLayerAdd;
  String get drawLayerHide;
  String get drawLayerShow;
  String get drawLayerDelete;
  String get drawLayerDeleteConfirm;
  String drawLayerName(int index);
  String drawLayerStrokes(int count);
  String get drawBackgrounds;
  String drawBackgroundName(String id);

  /// Togetherly+ — разовая покупка через lava.top.
  String get plusTitle;
  String get plusHeroTitle;
  String get plusHeroBody;
  String get plusActiveTitle;
  String get plusActiveBody;
  String get plusNoAdsTitle;
  String get plusNoAdsBody;
  String get plusThemesTitle;
  String get plusThemesBody;
  String get plusCycleTitle;
  String get plusCycleBody;
  String get plusWidgetsTitle;
  String get plusWidgetsBody;
  String get plusColoringTitle;
  String get plusColoringBody;
  String get plusWishesTitle;
  String get plusWishesBody;
  String get plusTipsTitle;
  String get plusTipsBody;
  String get plusVideoTitle;
  String get plusVideoBody;
  String get plusBuy;
  String get plusHaveCode;
  String get plusHowItWorks;
  String get plusPortableNote;
  String get plusUnavailableHere;
  String get plusStoreUnavailable;
  String memoryFileTooBig(int limitMb);
  String get statsTitle;
  String get pickerDateTab;
  String get pcTicketRoute;
  String get pcNameTicket;
  String get pcNameReceipt;
  String get pcNameTelegram;
  String get pcNameParcel;
  String get pcMsgTicket;
  String get pcReceiptTotal;
  String pcReceiptShift(int days);
  String pcReceiptItems(PostcardStats stats);
  String get pcLabelReceiptItems;
  String get pcMsgReceipt;
  String get pcTelegramTitle;
  String get pcMsgTelegram;
  String get pcParcelCare;
  String get pcParcelTo;
  String pcMsgParcel(String from, int days);
  String get redeemCodeAlphabet;
  String get pickerTimeTab;
  String get statsDaysTogether;
  String get statsMemories;
  String get statsDrawings;
  String get statsStreak;
  String get statsXp;
  String get statsMoodMonth;
  String get statsMoodMine;
  String get statsMoodPartner;
  String statsMoodMarks(int n);
  String get statsTipsTitle;
  String get statsEntryTitle;
  String get statsEntrySubtitle;
  String get statsFullLink;
  String get statsFullLinkHint;
  String memoryFileTooBigPlusHint(int limitMb);
  String get plusPurchased;
  String get plusPurchasePending;
  String get plusPurchaseFailed;
  String get plusCodeHint;
  String get plusCodeApply;
  String get plusCodeOk;
  String get plusCodeFailed;
  String get plusLockedTipsTitle;
  String get plusLockedTipsBody;
  String get plusUnlock;

  /// Общий фон чата — часть Togetherly+.
  String get chatBgSharedHint;
  String get chatBgUploading;
  String get chatBgSharedDone;
  String get exportTakesTime;
  String selectedCount(int n);
  String get selectAll;
  String deleteCanvasesTitle(int n);
  String deleteCanvasesConfirm(int n);
  String get chatStyleFace;
  String get chatStyleBackground;
  String get chatStyleTextColor;
  String get chatStyleAuto;
  String get chatStyleTheme;
  String get chatBgTitle;
  String get chatBgSet;
  String get chatBgChange;
  String get chatBgRemove;
  String chatBgConfirmBody(int price);
  String get chatBgCharged;

  // ── Lock Screen Mood ──
  String get lockScreenMood;
  String get lockScreenMoodSubtitle;
  String get lockScreenMoodToggle;
  String get lockScreenMoodToggleSub;
  String get lockScreenMoodNoMood;
  String get lockScreenMoodSetHint;

  // ── Photo Grid Widget ──
  String get photoGridWidget;
  String get photoGridWidgetSubtitle;
  String get photoGridCount;
  String get photoGridSelectPhotos;
  String get photoGridAddPhoto;
  String get photoGridCountLabel;

  // ── Memory Lane Gallery ──
  String get goToPin;
  String get openPhotoGallery;
  String get allMediaGallery;
  String get loadMore;

  // ── Home screen / photo caption dialog / mascot card ──
  String get previewLabel;
  String get photoSent;
  String get partnerFallback;
  String get captionDestMemories;
  String get captionDestMemoriesSub;
  String get captionDestPairWidget;
  String captionDestPairWidgetSub(String partner);
  String get captionDestPartnerWidget;
  String captionDestPartnerWidgetSub(String partner);
  String get groupMascot;
  String get tapForGallery;
  String get selectMascot;
  String get showLabel;
  String streakLabel(int days);

  // ── Widget screen ──
  String get widgetStreakTitle;
  String get widgetStreakSubtitle;
  String get widgetPetalTimerTitle;
  String get widgetPetalTimerSubtitle;
  String get widgetPhotoTitle;
  String get widgetPhotoSubtitle;
  String get streakTogetherCaps;
  String get daysInARow;
  String get keepItUp;
  String get ourPhotosInsteadOfDrawing;
  String get daysPhotosDescription;
  String unlockForCoins(int price);
  String get showOurPhotos;
  String get partnerNoProfilePhoto;
  String get addYourProfilePhoto;
  String notEnoughCoinsNeed(int price);
  String get daysPhotosDone;
  String get purchaseFailedTryLater;
  String personalPhotosHelp(String partner);
  String get personalPhotosHelpShort;
  String get uploadedPhotosToMemoryLane;
  String partnerSharesPhotosHelp(String partner, int count);
  String partnerNotSharedHelp(String partner);
  String get selectPhotosForPartner;
  String youSharePhotosWithPartner(String partner, int count);
  String get stopSharingPhotos;
  String get photosForPartnerRemoved;
  String photosUnit(int n);
  String get noPhotosFromPartner;
  String get noPhotosAdded;
  String get onePhotoNoCarousel;
  String photoCountOnUnlock(int count);
  String photoCountInterval(int count, String interval);
  String intervalLabel(int minutes);
  String get partnerPhotoTitle;
  String partnerSharedCountHelp(int count);
  String get partnerSharedOnePhoto;
  String get partnerNotSharedYet;
  String get changePhotosLabel;
  String get onUnlockOption;
  String get byTimeOption;
  String get every15Minutes;
  String get every30Minutes;
  String get everyHourOption;
  String get every3HoursOption;
  String get createPostcardTitle;
  String get createPostcardSubtitle;
  String get whereToSendPhoto;
  String get sendLabel;
  String get widgetPhotoCaption;

  // ── Mascot gallery ──
  String get mascotSaveFailed;
  String get mascotLoadFailed;
  String get transparentBgTitle;
  String get transparentBgBody;
  String get mascotNameTitle;
  String get enterNameHint;
  String get mascotLimitReached;
  String mascotDeactivated(String name);
  String mascotActivated(String name);
  String get rename;
  String get deleteMascotTitle;
  String deleteMascotBody(String name);
  String recordStreakDays(int days);
  String get deactivateLabel;
  String get makeActiveLabel;
  String get editLabel;
  String get exportPng;
  String get groupMascots;
  String mascotsCount(int count, int max);
  String get limitLabel;
  String get mascotsLoadFailedMultiline;
  String get artistCredit;
  String get uploadPhotoTooltip;
  String get drawLabel;
  String get streakBroken;
  String get streakKeepHint;
  String get streakStartHint;
  String get fromUs;
  String recordStreakBadge(int days);

  // ── Mascot draw screen ──
  String get drawSomethingFirst;
  String genericError(String e);
  String get drawMascotTitle;
  String get toolBrush;
  String get toolPencil;
  String get toolMarker;
  String get toolEraser;
  String get toolFill;
  String get toolLine;
  String get toolRect;
  String get toolCircle;
  String get toolTriangle;
  String get fillAction;
  String get resetSize;
  String get undoLabel;
  String get redoLabel;
  String get underlayLabel;
  String get drawHintEdit;
  String get drawHintDraw;

  /// Раскраска вдвоём.
  String get coloringTitle;
  String get coloringSubtitle;
  String get coloringOwnAdd;
  String get coloringOwnProcessing;
  String get coloringOwnDefaultName;
  String get coloringModeSurprise;
  String get coloringModeTogether;
  String get coloringModeSurpriseHint;
  String get coloringModeTogetherHint;
  String get coloringOtherHalf;
  String get coloringMyHalf;
  String get coloringPartnerHalfHidden;
  String coloringPartnerColoring(String name);
  String get coloringDoneBtn;
  String get coloringNotDoneBtn;
  String get coloringWaitingTitle;
  String coloringWaitingHint(String name);
  String get coloringRevealTitle;
  String get coloringShare;
  String get coloringSave;
  String get coloringToMemories;
  String get coloringSaved;
  String get coloringNew;
  String get colorLabel;

  /// Колор-пикер рисования.
  String get eyedropper;
  String get eyedropperHint;
  String get recentColors;
  String get customColor;
  String get hueLabel;
  String get saturationLabel;
  String get brightnessLabel;
  String get selectAction;

  // ── Postcard templates ──
  String get pcNamesFallback;
  String get pcLabelNames;
  String get pcLabelDaysCaption;
  String get pcLabelMessage;
  String get pcLabelCaption;
  String get pcLabelPolaroidCaption;
  String get pcLabelMessageAlt;
  String get pcDaysTogether;
  String get pcMsgTogether;
  String get pcDaysOfLove;
  String get pcMsgPolaroid;
  String get pcDaysNearby;
  String get pcMsgBloom;
  String get pcNightsUnderSky;
  String get pcMsgNightSky;

  // ── Photo carousel editor ──
  String get addOneToTenPhotos;
  String photoCountCarousel(int count);
  String get addMorePhotosCarouselHint;
  String get dragToReorder;
  String photoNumber(int n);
  String get mainPhoto;
  String positionNumber(int n);
  String get addMore;
  String get fromDevice;
  String get fromFeed;

  // ── Profile screen ──
  String get cropAvatarTitle;
  String get avatarTitle;
  String get appIconTitle;
  String get appIconUpdateHint;
  String get appIconChangeFailed;
  String get viewAction;
  String get enterDateFormat;
  String yearRange(int first, int last);
  String get enterTimeFormat;
  String get dateHintFormat;
  String get timeHintFormat;
  String get openCalendar;

  // ── Memory Lane screen ──
  String get refreshTooltip;
  String get memoriesMapTooltip;
  String kpRating(String rating);
  String get editLocation;
  String get addLocation;
  String get photoVideoNote;
  String distanceLabel(double meters);
  String get appNotInstalled;
  String get watchTogether;
  String watchWithPartner(String name);
  String get watchRoomOpensForBoth;
  String get watchAfterShortAd;
  String get watchOpenOnSite;
  String get watchOnSiteHint;
  String get watchPartnerInBrowser;
  String get watchRecent;
  String get watchOurVideos;
  String watchVideoAdd(int mb);
  String get watchVideoUploading;
  String watchVideoTooBig(int mb);
  String get watchVideoFormatUnsupported;
  String get watchPickFileAgain;
  String get watchHeroTitle;
  String get watchHeroText;
  String get linkCopied;
  String get copyLink;

  // ── Watch Together ──
  String get watchTogetherAdPrompt;
  String get watchAction;
  String get youtubeLinkHint;
  String get startAction;
  String get youtubeLinkInvalid;
  String invitesToWatchTogether(String hostName);
  String get joinAction;
  String get partnerEndedWatchTogether;
  String get videoCannotWatchTogether;
  String get videoEmbedBlockedHint;
  String get chooseAnother;
  String get openOnYoutube;
  String get watchingTogether;
  String get partnerJoined;
  String get waitingForPartner;
  String get syncedPlaying;
  String get syncedPaused;
  String get writeFirstMessage;
  String get messageInputHint;

  // ── Memory photo picker ──
  String get selectOnePhoto;
  String get maxSelected;
  String selectUpToPhotos(int n);
  String get selectPhotosPrompt;
  String addWithCount(int n);
  String get failedToLoadMemories;
  String get noPhotosInMemoryLane;
  String get inWidget;

  // ── Postcard editor ──
  String get postcardTitle;
  String failedToSave(Object e);
  String get changePhoto;
  String get addPhotoFromGallery;
  String get tapAnyTextToEdit;
  String get creating;
  String get sharePostcard;

  // ── Memories map ──
  String get noGeoMemories;
  String get addLocationHint;
  String get placeFallback;
  String memoriesUnit(int n);

  // ── Welcome slides ──
  String get welcomeSlide1Title;
  String get welcomeSlide2Title;
  String get welcomeSlide3Title;

  // ── Memory photo form ──
  String get newEntry;
  String get photoVideo;
  String get cropPhotoAction;
  String get cropPhotoHint;
  String get optionalTapToSelect;
  String itemsShort(int n);

  // ── Misc widgets ──
  String get dragHint;
  String get addPhoto;
  String get groupMascotBanner;
  String get goToGallery;
  String get hide;
  String coinsPlus(int n);
  String moodScoreLabel(int score, int max);
  List<String> get monthAbbrev;

  // ── Map picker ──
  String get placeOrCoordsHint;
  String get goToCoordinates;

  // ── Misc ──
  String get chatBgSaveFailed;
  String get timeFormatHint;
  String get bookTitleLanguageHint;

  // ── Live location map ──
  String get liveMapTitle;
  String get liveMapEnableCta;
  String get liveMapEnableHint;
  String get liveMapStopCta;
  String get liveMapStopped;
  String get liveMapPermissionDenied;
  String get liveMapWaitingPartner;
  String get liveMapYou;
  String get liveMapCenterMe;
  String get liveMapShowBoth;
  String get liveMapOpenFull;
  String get liveMapNotPaired;
  String get liveLocationServiceTitle;
  String get liveLocationServiceText;
  String get liveLocationJustNow;
  String liveLocationAgo(String value);
  String get unitCm;
  String get unitM;
  String get unitKm;
  String get unitMinShort;
  String get unitHourShort;
  String get unitDayShort;

  // Получение подарка
  String giftFromPartner(String name);
  String get giftAccepted;
  String giftBunnyMisses(int misses);
  String get giftIncomingTitle;
  String giftIncomingCount(int n);
  String get giftNoteHint;
  String get giftNoteSkip;
  String get giftNoteSend;
  String get giftWishHint;
  String get giftWishSend;
  String get giftWishEmpty;
  String giftMutualBonus(int coins);
  String giftSunriseGreeting(String name);
  String get supportTitle;
  String supportCopied(String email);
  String get redeemCodeTitle;
  String get redeemCodeSubtitle;
  String get redeemCodeHint;
  String get redeemCodeApply;
  String redeemCodeDone(int coins);
  String get redeemCodeAlready;
  String get redeemCodeFailed;
  String get giftAccept;
  String get giftDecline;
  String get giftFlipCoin;
  String get giftFlipYou;
  String get giftFlipPartner;

  // Профиль партнёра
  String get partnerGiftsTitle;
  String get partnerGiftsEmpty;
  String get partnerMissTitle;
  String get partnerMissEmpty;

  /// Заголовки тех же блоков в личном профиле («вам дарили», «вы скучаете»).
  String get selfGiftsTitle;
  String get selfMissTitle;

  /// Подпись карточки-входа в профиль партнёра на странице «Профиль».
  String get openPartnerProfile;
  String partnerGiftsChip(int count);
  String partnerMissChip(int count);
  String partnerDaysTogether(int days);
  String partnerMissPeak(String weekday);
  String weekdayShort(int weekday);
  String weekdayLong(int weekday);

  // Подарки
  String giftPushBody(String giftName);
  String get giftShopTitle;
  String get giftSent;
  String get giftNotEnoughCoins;
  String get giftNoConnection;
  String get giftFailed;
}

// ══════════════════════════════════════════════════════════════════════════════
// RUSSIAN STRINGS
// ══════════════════════════════════════════════════════════════════════════════

/// Склонение существительного при числе: 1 день, 2 дня, 5 дней.
/// Исключение — 11…14, они всегда берут форму множественного числа.
String _ruPlural(int n, String one, String few, String many) {
  final abs = n.abs();
  final tens = abs % 100;
  if (tens >= 11 && tens <= 14) return many;
  switch (abs % 10) {
    case 1:
      return one;
    case 2:
    case 3:
    case 4:
      return few;
    default:
      return many;
  }
}

class _RuStrings extends DictStrings {
  const _RuStrings() : super('ru');

  // ── Common ──

  // ── Welcome ──

  // ── Login ──

  @override
  String loginError(String e) => 'Ошибка входа: $e';
  @override
  String googleLoginError(String e) => 'Ошибка входа через Google: $e';

  // ── Setup ──
  @override
  String registrationError(String e) => 'Ошибка регистрации: $e';
  @override
  String passwordResetSent(String email) =>
      'Письмо для сброса пароля отправлено на $email. '
      'Проверьте почту и папку «Спам».';

  // ── Home ──
  @override
  String daysLabel(String suffix) => 'ДНЕЙ $suffix';
  @override
  String monthsLabel(String suffix) => 'МЕСЯЦЕВ $suffix';
  @override
  String timeLabel(String suffix) => 'ВРЕМЯ $suffix';
  @override
  String partnerIsMood(String name, String mood) => '$name — $mood';
  @override
  String moodPackAuthor(String name) => 'Рисунки — $name';
  @override
  String partnerAilmentBanner(String name, String label) =>
      '$name приболел(а): $label';
  @override
  String moodDateLabel(String dateLabel) => 'Настроение — $dateLabel';
  @override
  String achProgressOf(int value, int target) => '$value из $target';
  @override
  String achievementsUnlockedOf(int unlocked, int total) =>
      'Открыто $unlocked из $total';
  @override
  String capsuleOpensIn(int days) =>
      days <= 0 ? 'откроется сегодня' : 'через $days дн.';
  @override
  String capsuleOpensOn(String date) => 'Откроется $date';
  @override
  String capsuleFrom(String name) => 'от $name';
  @override
  String capsuleNotReady(String date) => 'Ещё рано 🙈 Откроется $date';
  @override
  String capsuleOpenedBodyNamed(String title) => '«$title» ждёт тебя в ленте';

  // ── Widget Screen ──
  @override
  String widgetOfPartner(String name) => 'Виджет $name';

  // ── Profile ──
  @override
  String daysTogetherLabel(String days) => '$days дней';
  @override
  String premiumThemeLocked(int price) =>
      'Премиум-тема за $price монет — открой в магазине';

  @override
  String buyThemeDescription(String themeName, int price) =>
      'Разблокировать тему «$themeName» за $price монет?';
  @override
  String coinPackTitle(int coins) => '$coins монет';
  @override
  String coinPurchaseSuccessAmount(int coins) => '+$coins монет зачислено';
  @override
  String coinEarned(int amount) => '+$amount монет получено!';
  @override
  String uploadError(String e) => 'Ошибка загрузки: $e';

  // ── Mood Calendar ──
  @override
  String partnerMood(String name) => 'Настроения $name';

  // ── Home (continued) ──

  // ── Draw Screen ──
  @override
  String drawingSavedTo(String path) => 'Рисунок сохранён: $path';
  @override
  String partnerIsDrawing(String name) => '$name рисует…';
  @override
  List<String> get reflectionQuestions => [
    'Какая маленькая вещь, которую партнёр сделал сегодня, дала вам почувствовать себя ценным?',
    'Какой момент с партнёром заставил вас улыбнуться сегодня?',
    'Что вы восхищаете в партнёре прямо сейчас?',
    'За что в ваших отношениях вы благодарны сегодня?',
    'Какое воспоминание с партнёром вы снова и снова вспоминаете?',
    'Чем партнёр удивил вас в последнее время?',
    'Что делает вашего партнёра уникальным для вас?',
    'Как партнёр поддержал вас сегодня?',
    'Что вы хотите, чтобы партнёр узнал сегодня?',
    'В какое приключение вы хотели бы отправиться вместе?',
    'Какая песня напоминает вам о партнёре и почему?',
    'Что самое лучшее в том, чтобы быть вместе?',
    'Какой маленький добрый поступок партнёра значил больше всего?',
    'Что нового вы узнали о партнёре?',
    'Какая цель у вас общая?',
    'Что вам нравится делать вместе?',
    'Когда вы последний раз чувствовали настоящую связь с партнёром?',
    'Что сделает завтрашний день особенным для обоих?',
    'Какой комплимент вы хотите сделать партнёру сегодня?',
    'Какая привычка партнёра вам втайне нравится?',
  ];

  // ── Draw Gallery / Canvas ──

  // ── Connect Partner ──
  @override
  String groupOf(int count) => 'Группа из $count';
  @override
  String membersCount(int count) => 'УЧАСТНИКИ · $count';
  @override
  String shareInviteText(String code, String link) =>
      'Присоединяйся ко мне в Togetherly! Используй код: $code\n\nИли нажми: $link';

  @override
  String onboardingLeft(int left) => left == 1
      ? 'Остался один шаг'
      : (left < 5 ? 'Осталось $left шага' : 'Осталось $left шагов');
  @override
  String onboardingNext(String step) => 'Остался шаг: $step';

  @override
  String memoryTypeName(String type) => switch (type) {
    'photo' => 'Фотография',
    'video' => 'Видео',
    'location' => 'Локация',
    'music' => 'Музыка',
    'text' => 'Заметка',
    'videoLink' => 'Видео по ссылке',
    'book' => 'Книга',
    _ => 'Кино',
  };
  @override
  String timerDaysCount(int days) => '$days ${_daysWord(days)}';
  @override
  String symbolSearchFound(int count) => 'Найдено: $count';

  @override
  String quietPartnerTitle(String name, int days) {
    final d = days == 1 ? 'день' : (days > 1 && days < 5 ? 'дня' : 'дней');
    return '$name не заходит $days $d';
  }

  @override
  String membersOfMax(int current, int max) => '$current/$max участников';
  @override
  String shareGroupInviteText(String code, String link) =>
      'Присоединяйся к нашей группе в Togetherly! Используй код: $code\n\nИли нажми: $link';
  @override
  String connectedWithCouple(String name) => 'Вы с $name теперь вместе!';
  @override
  String marriedTo(String name) => 'Вы с $name женаты! 💍';
  @override
  String friendsWith(String name) => 'Вы с $name теперь друзья!';
  @override
  String buddiesWith(String name) => 'Вы с $name теперь лучшие друзья!';
  @override
  String customRelWith(String label, String name) =>
      'Вы с $name теперь $label!';
  @override
  String joinMeLinkText(String link) =>
      'Присоединяйся ко мне в Togetherly! $link';
  @override
  String membersCountBracket(int count) => 'УЧАСТНИКИ ($count)';

  // ── Memory Lane ──

  // ── Timer Card ──

  // ── Mini Mood Calendar ──

  // ── Date helpers ──
  @override
  List<String> get shortMonths => [
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];
  @override
  List<String> get shortWeekdays => ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  // ── I Miss You / Vibes ──
  @override
  String missYouNotifTitle(String name) => '$name скучает по вам';
  @override
  String missYouStreak(int count) => '🔥 $count';
  @override
  String thinkingOfYouNotifTitle(String name) => '$name думает о тебе 💭';
  @override
  String wantHugNotifTitle(String name) => '$name хочет обнять тебя 🤗';
  @override
  String customVibeNotifTitle(String name) => name;

  // ── Photo Card ──
  @override
  String kmFromYou(String km) => '$km от вас';
  @override
  String minutesAgo(int m) => '$m мин. назад';
  @override
  String hoursAgo(int h) => '$h ч. назад';
  @override
  String daysAgo(int d) => '$d д. назад';

  // ── Memory Lane Feed ──

  // ── Memory Lane (extended) ──
  @override
  String newMemory(String type) => 'Новое: $type';
  @override
  String failedAddMemory(String e) => 'Не удалось добавить: $e';
  @override
  String savedToPath(String path) => 'Сохранено: $path';
  @override
  String downloadFailed(String e) => 'Ошибка скачивания: $e';
  @override
  String failedSelectPhotos(String e) => 'Не удалось выбрать фото: $e';
  @override
  String failedSelectVideo(String e) => 'Не удалось выбрать видео: $e';
  @override
  String nPhotos(int count) => '$count фото';
  @override
  String openIn(String name) => 'Открыть в $name';
  @override
  String get updateWhatsNew => ruWhatsNew;
  @override
  List<String> get fullMonths => [
    '',
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];
  @override
  String formatDateAt(String month, int day, int year, String time) =>
      '$day $month $year в $time';

  // ── Relationship Status Screen ──
  @override
  String statusSetTo(String status) => 'Статус: $status';
  @override
  String failedSetStatus(String e) => 'Ошибка установки статуса: $e';
  @override
  String failedClearStatus(String e) => 'Ошибка очистки статуса: $e';
  @override
  String failedAddStatus(String e) => 'Ошибка добавления статуса: $e';
  @override
  String failedUpdateStatus(String e) => 'Ошибка обновления статуса: $e';
  @override
  String deleteStatusConfirm(String label) =>
      'Вы уверены, что хотите удалить «$label»?';
  @override
  String failedDeleteStatus(String e) => 'Ошибка удаления статуса: $e';

  // ── Map Picker Screen ──

  // ── Mood Calendar (extended) ──
  @override
  String moodRecorded(String label) => '$label записано!';
  @override
  List<String> get shortWeekdaysSingleChar => [
    'П',
    'В',
    'С',
    'Ч',
    'П',
    'С',
    'В',
  ];
  @override
  List<String> get longWeekdays => [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  // ── Timer / Expandable Timer Card ──
  @override
  String timerDeleteConfirm(String name) => '«$name» будет удалён навсегда.';

  // ── Petal Timer Dial ──

  // ── Widget Screen (extended) ──
  @override
  String failedAddWidget(String e) => 'Не удалось добавить виджет: $e';
  @override
  String yearsAlready(int years) {
    String form;
    if (years % 10 == 1 && years % 100 != 11) {
      form = '$years год уже ❤️';
    } else if (years % 10 >= 2 &&
        years % 10 <= 4 &&
        (years % 100 < 10 || years % 100 >= 20)) {
      form = '$years года уже ❤️';
    } else {
      form = '$years лет уже ❤️';
    }
    return form;
  }

  @override
  String widgetSlotTitle(int index) => 'Виджет ${index + 1}';

  // ── Profile (extended) ──
  String get cycleConsentBody =>
      'Даты цикла и самочувствия — данные о здоровье, поэтому спрашиваем '
      'отдельно. Они хранятся на нашем сервере, партнёру видны только если вы '
      'сами это включите, и удаляются в один тап. Согласие можно отозвать в '
      'настройках — отметки сотрутся вместе с ним.';
  String get cycleConsentAgree => 'Согласен, вести цикл';
  String get cycleConsentLater => 'Не сейчас';
  String get cycleConsentWithdraw => 'Отозвать согласие на цикл';
  String get cycleConsentWithdrawHint => 'Раздел закроется, отметки сотрутся';
  String get exportMyData => 'Мои данные';
  String get exportMyDataHint => 'Скачать архив со всем, что мы храним';
  String get exportMyDataReady => 'Архив готов';
  String get exportMyDataFailed => 'Не получилось собрать архив';
  String get exportMemories => 'Экспорт воспоминаний';
  @override
  String exportError(String e) => 'Ошибка при экспорте: $e';

  // ── Home Screen (extended) ──

  // ── Mini Mood Calendar (extended) ──
  @override
  List<String> get shortWeekdaysUpper => [
    'ПН',
    'ВТ',
    'СР',
    'ЧТ',
    'ПТ',
    'СБ',
    'ВС',
  ];

  // ── Notification Settings ──
  @override
  String daysTogetherNotifBody(int days) {
    final mod10 = days % 10;
    final mod100 = days % 100;
    final word = (mod10 == 1 && mod100 != 11)
        ? 'день'
        : (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14))
        ? 'дня'
        : 'дней';
    return 'Вы вместе уже $days $word ❤️';
  }

  // ── Chat ──

  @override
  String waitingDaysLeft(int days) {
    final n = days.abs();
    final mod10 = n % 10, mod100 = n % 100;
    final word = (mod10 == 1 && mod100 != 11)
        ? 'день'
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
        ? 'дня'
        : 'дней';
    return '$n $word';
  }

  @override
  String chatReplyingTo(String name) => 'В ответ $name';
  @override
  String chatTyping(String name) => '$name печатает…';
  @override
  String chatNotifTitle(String name) => '$name пишет вам 💬';
  @override
  String moodNotifTitle(String name) => '$name сменил(а) настроение';
  @override
  String chatDateHeader(DateTime day) {
    final now = DateTime.now();
    final d0 = DateTime(day.year, day.month, day.day);
    final diff = DateTime(now.year, now.month, now.day).difference(d0).inDays;
    if (diff == 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    final base = '${day.day} ${months[day.month - 1]}';
    return day.year == now.year ? base : '$base ${day.year}';
  }

  @override
  String chatDeleteConfirm(String text) => 'Удалить это сообщение?';
  @override
  String pixelCanvasSummary(int cells, int px) =>
      '$cells клеток · пиксель $px px в выгрузке';
  @override
  String canvasesSubtitle(int count, String lastDate) {
    final word = count % 10 == 1 && count % 100 != 11
        ? 'рисунок'
        : (count % 10 >= 2 &&
                  count % 10 <= 4 &&
                  (count % 100 < 10 || count % 100 >= 20)
              ? 'рисунка'
              : 'рисунков');
    return '$count $word · последний $lastDate';
  }

  @override
  String tgDaysTogetherCaption(int days) =>
      '${_ruPlural(days, 'день', 'дня', 'дней')} вместе';
  @override
  String tgMonthsCaption(int months) =>
      _ruPlural(months, 'месяц', 'месяца', 'месяцев');
  @override
  String tgDaysMilestone(int days) =>
      '$days ${_ruPlural(days, 'день', 'дня', 'дней')}';
  @override
  String tgYearsMilestone(int years) =>
      '$years ${_ruPlural(years, 'год', 'года', 'лет')}';
  @override
  String tgInDays(int days) =>
      'через $days ${_ruPlural(days, 'день', 'дня', 'дней')}';
  @override
  String tgUntilMilestone(int target, int left) =>
      'До ${tgDaysMilestone(target)} — ${tgInDays(left)}';
  @override
  String tgMissAddressee(String name) => name;
  @override
  String tgMoodMatched(int days) => 'совпало $days из 7';
  @override
  String tgCountdownDaysLeft(int days) =>
      '${_ruPlural(days, 'день', 'дня', 'дней')} до встречи';
  @override
  String tgYearDaysWord(int days) => _ruPlural(days, 'День', 'Дня', 'Дней');
  @override
  String tgYearDaysTogether(int days) =>
      '${_ruPlural(days, 'День', 'Дня', 'Дней')} вместе';
  @override
  String tgYearDaysLeft(int days) =>
      'Ещё $days ${_ruPlural(days, 'день', 'дня', 'дней')}';
  @override
  String tgYearToAnniversary(int year) =>
      'До $year ${_ruPlural(year, 'года', 'лет', 'лет')}';
  @override
  String tgYearToAnniversaryShort(int year, int days) =>
      'До $year ${_ruPlural(year, 'года', 'лет', 'лет')} — $days';
  @override
  String tgYearCurrentYearShort(int year, int days) =>
      '$year-й год · ещё $days';
  @override
  String tgYearOrdinalLabel(int year) {
    const words = [
      'ПЕРВЫЙ',
      'ВТОРОЙ',
      'ТРЕТИЙ',
      'ЧЕТВЁРТЫЙ',
      'ПЯТЫЙ',
      'ШЕСТОЙ',
      'СЕДЬМОЙ',
      'ВОСЬМОЙ',
      'ДЕВЯТЫЙ',
      'ДЕСЯТЫЙ',
    ];
    final word = year >= 1 && year <= words.length
        ? words[year - 1]
        : '$year-Й';
    return '$word ГОД ВМЕСТЕ';
  }

  @override
  String tgYearsAndDays(int years, int days) =>
      '$years ${_ruPlural(years, 'ГОД', 'ГОДА', 'ЛЕТ')} '
      '$days ${_ruPlural(days, 'ДЕНЬ', 'ДНЯ', 'ДНЕЙ')}';
  @override
  String tgYearSince(String date) => 'С $date';
  @override
  String mascotSleepRange(String from, String to) => 'Спит с $from до $to';
  @override
  String mascotNightRange(String from, String to) => 'Светит с $from до $to';

  @override
  String cycleOf(String name) => 'Цикл $name';
  @override
  String cycleDaysLeft(int days) =>
      'Через ${_ruPlural(days, 'день', 'дня', 'дней')}';
  @override
  String cycleDayOfCycle(int day) => '$day-й день цикла';
  @override
  String cycleOverdue(int days) =>
      'Задержка ${_ruPlural(days, 'день', 'дня', 'дней')}';
  @override
  String cycleAnalyticsHint(int cycles) =>
      'по ${_ruPlural(cycles, 'последнему циклу', 'последним циклам', 'последним циклам')}';
  @override
  String cycleDaysValue(int days) =>
      '$days ${_ruPlural(days, 'день', 'дня', 'дней')}';
  @override
  List<String> get cycleWeekdayShorts => const [
    'пн',
    'вт',
    'ср',
    'чт',
    'пт',
    'сб',
    'вс',
  ];
  @override
  List<String> get cycleMonthNames => const [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];
  @override
  List<String> get cycleMonthsGenitive => const [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  @override
  String dayLogDate(DateTime day) =>
      '${day.day} ${cycleMonthsGenitive[day.month - 1]}';
  @override
  String dayLogWeekday(DateTime day) => const [
    'понедельник',
    'вторник',
    'среда',
    'четверг',
    'пятница',
    'суббота',
    'воскресенье',
  ][day.weekday - 1];
  @override
  String cyclePeriodDayLabel(int day) => 'месячные, $day-й день';
  @override
  String drawLayerName(int index) => 'Слой $index';
  @override
  String drawLayerStrokes(int count) => count == 0
      ? 'пусто'
      : '$count ${_ruPlural(count, 'штрих', 'штриха', 'штрихов')}';
  @override
  String drawBackgroundName(String id) => switch (id) {
    'plain' => 'Чистый',
    'grid' => 'Клетка',
    'dots' => 'Точки',
    'notebook' => 'Тетрадь',
    'millimeter' => 'Миллиметровка',
    'kraft' => 'Крафт',
    'chalkboard' => 'Доска',
    'music' => 'Ноты',
    'stars' => 'Звёзды',
    'hearts' => 'Сердечки',
    'watercolor' => 'Акварель',
    'film' => 'Плёнка',
    _ => id,
  };
  @override
  String memoryFileTooBig(int limitMb) =>
      'Файл тяжелее $limitMb МБ — такой не загрузится';
  @override
  String pcReceiptShift(int days) => 'смена №$days';
  @override
  String pcReceiptItems(PostcardStats stats) {
    // Только то, что приложение действительно посчитало. Нулевые строки не
    // печатаем: чек с «Рисунков — 0» выглядит упрёком, а не подарком.
    final lines = <String>[];
    if (stats.memories > 0) lines.add('Воспоминаний — ${stats.memories}');
    if (stats.drawings > 0) lines.add('Рисунков — ${stats.drawings}');
    if (stats.missYou > 0) lines.add('«Я скучаю» — ${stats.missYou}');
    if (stats.streak > 0) lines.add('Дней подряд — ${stats.streak}');
    if (lines.isEmpty) lines.add('Всё только начинается — 1');
    return lines.join('\n');
  }

  @override
  String pcMsgParcel(String from, int days) =>
      'От кого: ${from.isEmpty ? 'меня' : from}\n'
      'Содержимое: $days дней, всё целое';
  @override
  String statsMoodMarks(int n) => 'Отметок за 30 дней: $n';
  @override
  String memoryFileTooBigPlusHint(int limitMb) =>
      'Файл тяжелее $limitMb МБ. С Togetherly+ потолок вдвое выше';
  @override
  String selectedCount(int n) => 'Выбрано $n';
  @override
  String deleteCanvasesTitle(int n) =>
      n == 1 ? 'Удалить холст?' : 'Удалить $n холстов?';
  @override
  String deleteCanvasesConfirm(int n) => n == 1
      ? 'Рисунок исчезнет у обоих. Вернуть его будет нельзя.'
      : 'Рисунки исчезнут у обоих. Вернуть их будет нельзя.';
  @override
  String chatBgConfirmBody(int price) =>
      'Установить своё фото на фон чата за $price 🪙?\n\n'
      'Каждая последующая смена фона тоже стоит $price 🪙.';
  @override
  String captionDestPairWidgetSub(String partner) =>
      'Фото в «Моём виджете» — видно тебе и $partner';
  @override
  String captionDestPartnerWidgetSub(String partner) =>
      'Отдельный виджет с фото для $partner';
  @override
  String streakLabel(int days) {
    String unit;
    if (days % 100 >= 11 && days % 100 <= 14) {
      unit = 'дней';
    } else {
      switch (days % 10) {
        case 1:
          unit = 'день';
          break;
        case 2:
        case 3:
        case 4:
          unit = 'дня';
          break;
        default:
          unit = 'дней';
      }
    }
    return 'Серия: $days $unit';
  }

  // ── Widget screen ──
  @override
  String unlockForCoins(int price) => 'Разблокировать — $price 🪙';
  @override
  String notEnoughCoinsNeed(int price) =>
      'Недостаточно монет — нужно $price 🪙';
  @override
  String personalPhotosHelp(String partner) =>
      'Личные фото — от 1 до 10 на каждый виджет. С двух фото включается '
      'карусель: смена при разблокировке или по таймеру.\n\nЭти фото видны '
      'только тебе. Чтобы поделиться с $partner, открой «Фото партнёра» → '
      '«Выбрать фото для партнёра».';
  @override
  String partnerSharesPhotosHelp(String partner, int count) =>
      'Этот виджет показывает фото, которыми делится $partner '
      '($count ${photosUnit(count)}). Менять их может только $partner.';
  @override
  String partnerNotSharedHelp(String partner) =>
      '$partner ещё не поделился(ась) фото. Чтобы они здесь появились, '
      '$partner нужно открыть «Фото партнёра» и нажать «Выбрать фото для '
      'партнёра» — обычный «Фото-виджет» виден только владельцу.';
  @override
  String youSharePhotosWithPartner(String partner, int count) =>
      '$partner видит ваши фото: $count';
  @override
  String photosUnit(int n) => 'фото';
  @override
  String photoCountOnUnlock(int count) => '$count фото · при разблокировке';
  @override
  String photoCountInterval(int count, String interval) =>
      '$count фото · $interval';
  @override
  String intervalLabel(int minutes) {
    switch (minutes) {
      case 15:
        return 'каждые 15 мин';
      case 30:
        return 'каждые 30 мин';
      case 60:
        return 'каждый час';
      case 180:
        return 'каждые 3 часа';
      default:
        return 'каждые $minutes мин';
    }
  }

  @override
  String partnerSharedCountHelp(int count) =>
      'Партнёр поделился $count фото — выберите как они будут меняться на '
      'этом виджете.';

  // ── Mascot gallery ──
  @override
  String mascotDeactivated(String name) => '$name деактивирован';
  @override
  String mascotActivated(String name) => '$name теперь активен';
  @override
  String deleteMascotBody(String name) => '«$name» будет удалён навсегда.';
  @override
  String recordStreakDays(int days) => 'Рекорд: $days дн.';
  @override
  String mascotsCount(int count, int max) => '$count / $max маскотов';
  @override
  String recordStreakBadge(int days) => '$days дн.';

  // ── Mascot draw screen ──
  @override
  String genericError(String e) => 'Ошибка: $e';
  @override
  String coloringPartnerColoring(String name) => '$name красит';
  @override
  String coloringWaitingHint(String name) =>
      'откроем, как только $name нажмёт «Готово»';

  // ── Postcard templates ──

  // ── Photo carousel editor ──
  @override
  String photoCountCarousel(int count) => '$count фото · карусель';
  @override
  String photoNumber(int n) => 'Фото $n';
  @override
  String positionNumber(int n) => 'Позиция $n';

  // ── Profile screen ──
  @override
  String yearRange(int first, int last) => 'Год от $first до $last';
  @override
  String kpRating(String rating) => 'КП $rating';
  @override
  String distanceLabel(double meters) => meters < 1000
      ? '${meters.round()} м'
      : '${(meters / 1000).toStringAsFixed(1)} км';
  @override
  String watchWithPartner(String name) => 'Смотреть с $name';
  @override
  String watchVideoAdd(int mb) => 'Загрузить до $mb МБ';
  @override
  String watchVideoTooBig(int mb) =>
      'Видео больше $mb МБ: сожмите его или выберите короче';
  @override
  String invitesToWatchTogether(String hostName) =>
      '$hostName зовёт смотреть вместе';
  @override
  String selectUpToPhotos(int n) => 'Выберите до $n фото';
  @override
  String addWithCount(int n) => 'Добавить ($n)';
  @override
  String failedToSave(Object e) => 'Не удалось сохранить: $e';
  @override
  String itemsShort(int n) => '$n элем.';
  @override
  String coinsPlus(int n) {
    // «+1 монет» резало глаз на каждой награде — считаем окончание по числу.
    final tens = n % 100;
    final ones = n % 10;
    final word = (tens >= 11 && tens <= 14)
        ? 'монет'
        : (ones == 1
              ? 'монета'
              : (ones >= 2 && ones <= 4 ? 'монеты' : 'монет'));
    return '+$n $word';
  }

  @override
  String moodScoreLabel(int score, int max) =>
      '$moodScorePrefix $score из $max';
  @override
  List<String> get monthAbbrev => const [
    'янв',
    'фев',
    'мар',
    'апр',
    'мая',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];
  @override
  String memoriesUnit(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'воспоминание';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'воспоминания';
    }
    return 'воспоминаний';
  }

  // ── Live location map ──
  @override
  String liveLocationAgo(String value) => '$value назад';

  // Получение подарка
  @override
  String giftFromPartner(String name) => 'Подарок от $name';
  @override
  String giftBunnyMisses(int misses) =>
      misses == 1 ? 'Ускользнул!' : 'Ускользнул ещё раз, лови!';
  @override
  String giftIncomingCount(int n) => n == 1 ? 'ждёт тебя' : 'ждут тебя: $n';
  @override
  String giftMutualBonus(int coins) => 'Успели вовремя: обоим по $coins';
  @override
  String giftSunriseGreeting(String name) =>
      'Доброе утро! $name подарил тебе рассвет';
  @override
  String supportCopied(String email) => 'Почта скопирована: $email';
  @override
  String redeemCodeDone(int coins) => 'Зачислено $coins монет';

  // Профиль партнёра
  @override
  String partnerGiftsChip(int count) => '$count';
  @override
  String partnerMissChip(int count) => '$count';
  @override
  String partnerDaysTogether(int days) => 'вместе $days ${_daysWord(days)}';
  @override
  String partnerMissPeak(String weekday) => 'Чаще всего — $weekday';
  @override
  String weekdayShort(int weekday) =>
      const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][weekday - 1];
  @override
  String weekdayLong(int weekday) => const [
    'по понедельникам',
    'по вторникам',
    'по средам',
    'по четвергам',
    'по пятницам',
    'по субботам',
    'по воскресеньям',
  ][weekday - 1];

  String _daysWord(int n) {
    final t = n % 100;
    if (t >= 11 && t <= 14) return 'дней';
    switch (n % 10) {
      case 1:
        return 'день';
      case 2:
      case 3:
      case 4:
        return 'дня';
      default:
        return 'дней';
    }
  }

  // Подарки
  @override
  String giftPushBody(String giftName) => 'Прислал подарок: $giftName';
}

class _EnStrings extends DictStrings {
  const _EnStrings([super.langCode = 'en']);

  // ── Common ──

  // ── Welcome ──

  // ── Login ──
  @override
  String loginError(String e) => 'Login error: $e';
  @override
  String googleLoginError(String e) => 'Google sign-in error: $e';

  // ── Setup ──
  @override
  String registrationError(String e) => 'Registration error: $e';
  @override
  String passwordResetSent(String email) =>
      'Password reset email sent to $email. '
      'Check your inbox and spam folder.';

  // ── Home ──
  @override
  String daysLabel(String suffix) => 'DAYS $suffix';
  @override
  String monthsLabel(String suffix) => 'MONTHS $suffix';
  @override
  String timeLabel(String suffix) => 'TIME $suffix';
  @override
  String partnerIsMood(String name, String mood) => '$name is $mood';
  @override
  String moodPackAuthor(String name) => 'Art by $name';
  @override
  String partnerAilmentBanner(String name, String label) =>
      '$name is unwell: $label';
  @override
  String moodDateLabel(String dateLabel) => 'Mood — $dateLabel';
  @override
  String achProgressOf(int value, int target) => '$value of $target';
  @override
  String achievementsUnlockedOf(int unlocked, int total) =>
      'Unlocked $unlocked of $total';
  @override
  String capsuleOpensIn(int days) =>
      days <= 0 ? 'opens today' : 'in $days days';
  @override
  String capsuleOpensOn(String date) => 'Opens $date';
  @override
  String capsuleFrom(String name) => 'from $name';
  @override
  String capsuleNotReady(String date) => 'Not yet 🙈 Opens $date';
  @override
  String capsuleOpenedBodyNamed(String title) =>
      '"$title" is waiting in your feed';

  // ── Widget Screen ──
  @override
  String widgetOfPartner(String name) => '$name\'s Widget';

  // ── Profile ──
  @override
  String daysTogetherLabel(String days) => '$days days';
  @override
  String premiumThemeLocked(int price) =>
      'Premium theme — $price coins, unlock it in the Coin shop';

  @override
  String buyThemeDescription(String themeName, int price) =>
      'Unlock the "$themeName" theme for $price coins?';
  @override
  String coinPackTitle(int coins) => '$coins coins';
  @override
  String coinPurchaseSuccessAmount(int coins) => '+$coins coins credited';
  @override
  String coinEarned(int amount) => '+$amount coins earned!';
  @override
  String uploadError(String e) => 'Upload error: $e';

  // ── Mood Calendar ──
  @override
  String partnerMood(String name) => '$name\'s Mood';

  // ── Home (continued) ──

  // ── Draw Screen ──
  @override
  String drawingSavedTo(String path) => 'Drawing saved to: $path';
  @override
  String partnerIsDrawing(String name) => '$name is drawing…';
  @override
  List<String> get reflectionQuestions => [
    'What is one small thing your partner did today that made you feel appreciated?',
    'What moment with your partner made you smile today?',
    'What is something you admire about your partner right now?',
    'What is one thing you are grateful for in your relationship today?',
    'What is a memory with your partner you keep coming back to?',
    'What is one way your partner surprised you recently?',
    'What makes your partner unique to you?',
    'How did your partner support you today?',
    'What is one thing you want your partner to know today?',
    'What adventure would you love to go on with your partner?',
    'What song reminds you of your partner and why?',
    'What is the best thing about being with your partner?',
    'What small act of kindness from your partner meant the most lately?',
    'What is something new you have learned about your partner?',
    'What is a goal you both share?',
    'What is one thing you love doing together?',
    'When did you last feel truly connected to your partner?',
    'What would make tomorrow special for both of you?',
    'What compliment do you want to give your partner today?',
    'What is one habit of your partner you secretly adore?',
  ];

  // ── Draw Gallery / Canvas ──

  // ── Connect Partner ──
  @override
  String groupOf(int count) => 'Group of $count';
  @override
  String membersCount(int count) => 'MEMBERS · $count';
  @override
  String shareInviteText(String code, String link) =>
      'Join me on Togetherly! Use code: $code\n\nOr click: $link';

  @override
  String onboardingLeft(int left) =>
      left == 1 ? 'One step left' : '$left steps left';
  @override
  String onboardingNext(String step) => 'One step left: $step';

  @override
  String memoryTypeName(String type) => switch (type) {
    'photo' => 'Photo',
    'video' => 'Video',
    'location' => 'Location',
    'music' => 'Music',
    'text' => 'Note',
    'videoLink' => 'Video link',
    'book' => 'Book',
    _ => 'Movie',
  };
  @override
  String timerDaysCount(int days) => days == 1 ? '1 day' : '$days days';
  @override
  String symbolSearchFound(int count) => 'Found: $count';

  @override
  String quietPartnerTitle(String name, int days) => days == 1
      ? '$name has been away a day'
      : '$name has been away $days days';

  @override
  String membersOfMax(int current, int max) => '$current/$max members';
  @override
  String shareGroupInviteText(String code, String link) =>
      'Join our group on Togetherly! Use code: $code\n\nOr click: $link';
  @override
  String connectedWithCouple(String name) => "You're connected with $name!";
  @override
  String marriedTo(String name) => "You're married to $name! 💍";
  @override
  String friendsWith(String name) => "You're now friends with $name!";
  @override
  String buddiesWith(String name) => "You're now buddies with $name!";
  @override
  String customRelWith(String label, String name) =>
      "You're now $label with $name!";
  @override
  String joinMeLinkText(String link) => 'Join me on Togetherly! $link';
  @override
  String membersCountBracket(int count) => 'MEMBERS ($count)';

  // ── Memory Lane ──

  // ── Timer Card ──

  // ── Mini Mood Calendar ──

  // ── Date helpers ──
  @override
  List<String> get shortMonths => [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  @override
  List<String> get shortWeekdays => [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  // ── I Miss You / Vibes ──
  @override
  String missYouNotifTitle(String name) => '$name misses you';
  @override
  String missYouStreak(int count) => '🔥 $count';
  @override
  String thinkingOfYouNotifTitle(String name) => '$name is thinking of you 💭';
  @override
  String wantHugNotifTitle(String name) => '$name wants to hug you 🤗';
  @override
  String customVibeNotifTitle(String name) => name;

  // ── Photo Card ──
  @override
  String kmFromYou(String km) => '$km from you';
  @override
  String minutesAgo(int m) => '${m}m ago';
  @override
  String hoursAgo(int h) => '${h}h ago';
  @override
  String daysAgo(int d) => '${d}d ago';

  // ── Memory Lane Feed ──

  // ── Memory Lane (extended) ──
  @override
  String newMemory(String type) => 'New $type';
  @override
  String failedAddMemory(String e) => 'Failed to add memory: $e';
  @override
  String savedToPath(String path) => 'Saved to $path';
  @override
  String downloadFailed(String e) => 'Download failed: $e';
  @override
  String failedSelectPhotos(String e) => 'Failed to select photos: $e';
  @override
  String failedSelectVideo(String e) => 'Failed to select video: $e';
  @override
  String nPhotos(int count) => '$count photos';
  @override
  String openIn(String name) => 'Open in $name';
  @override
  String get updateWhatsNew => enWhatsNew;
  @override
  List<String> get fullMonths => [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  @override
  String formatDateAt(String month, int day, int year, String time) =>
      '$month $day, $year at $time';

  // ── Relationship Status Screen ──
  @override
  String statusSetTo(String status) => 'Status set to: $status';
  @override
  String failedSetStatus(String e) => 'Failed to set status: $e';
  @override
  String failedClearStatus(String e) => 'Failed to clear status: $e';
  @override
  String failedAddStatus(String e) => 'Failed to add status: $e';
  @override
  String failedUpdateStatus(String e) => 'Failed to update status: $e';
  @override
  String deleteStatusConfirm(String label) =>
      'Are you sure you want to delete "$label"?';
  @override
  String failedDeleteStatus(String e) => 'Failed to delete status: $e';

  // ── Map Picker Screen ──

  // ── Mood Calendar (extended) ──
  @override
  String moodRecorded(String label) => '$label recorded!';
  @override
  List<String> get shortWeekdaysSingleChar => [
    'M',
    'T',
    'W',
    'T',
    'F',
    'S',
    'S',
  ];
  @override
  List<String> get longWeekdays => [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  // ── Timer / Expandable Timer Card ──
  @override
  String timerDeleteConfirm(String name) => '"$name" will be gone forever.';

  // ── Petal Timer Dial ──

  // ── Widget Screen (extended) ──
  @override
  String failedAddWidget(String e) => 'Failed to add widget: $e';
  @override
  String yearsAlready(int years) => '$years years already ❤️';
  @override
  String widgetSlotTitle(int index) => 'Widget ${index + 1}';

  // ── Profile (extended) ──
  String get cycleConsentBody =>
      'Cycle dates and well-being are health data, so we ask separately. They '
      'are stored on our server, your partner sees them only if you turn that '
      'on, and they are deleted in one tap. You can withdraw consent in '
      'settings — the entries go with it.';
  String get cycleConsentAgree => 'Agree and track';
  String get cycleConsentLater => 'Not now';
  String get cycleConsentWithdraw => 'Withdraw cycle consent';
  String get cycleConsentWithdrawHint =>
      'The section closes, entries are erased';
  String get exportMyData => 'My data';
  String get exportMyDataHint => 'Download an archive of everything we store';
  String get exportMyDataReady => 'Archive ready';
  String get exportMyDataFailed => "Couldn't build the archive";
  String get exportMemories => 'Export Memories';
  @override
  String exportError(String e) => 'Error during export: $e';

  // ── Home Screen (extended) ──

  // ── Mini Mood Calendar (extended) ──
  @override
  List<String> get shortWeekdaysUpper => [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN',
  ];

  // ── Notification Settings ──
  @override
  String daysTogetherNotifBody(int days) =>
      "You've been together $days ${days == 1 ? 'day' : 'days'} ❤️";

  // ── Chat ──

  @override
  String waitingDaysLeft(int days) {
    final n = days.abs();
    return n == 1 ? '1 day' : '$n days';
  }

  @override
  String chatReplyingTo(String name) => 'Replying to $name';
  @override
  String chatTyping(String name) => '$name is typing…';
  @override
  String chatNotifTitle(String name) => '$name messages you 💬';
  @override
  String moodNotifTitle(String name) => '$name changed their mood';
  @override
  String chatDateHeader(DateTime day) {
    final now = DateTime.now();
    final d0 = DateTime(day.year, day.month, day.day);
    final diff = DateTime(now.year, now.month, now.day).difference(d0).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final base = '${months[day.month - 1]} ${day.day}';
    return day.year == now.year ? base : '$base, ${day.year}';
  }

  @override
  String chatDeleteConfirm(String text) => 'Delete this message?';
  @override
  String pixelCanvasSummary(int cells, int px) =>
      '$cells cells · $px px per pixel on export';
  @override
  String canvasesSubtitle(int count, String lastDate) =>
      '$count drawing${count == 1 ? '' : 's'} · last $lastDate';
  @override
  String tgDaysTogetherCaption(int days) =>
      days == 1 ? 'day together' : 'days together';
  @override
  String tgMonthsCaption(int months) => months == 1 ? 'month' : 'months';
  @override
  String tgDaysMilestone(int days) => '$days ${days == 1 ? 'day' : 'days'}';
  @override
  String tgYearsMilestone(int years) =>
      '$years ${years == 1 ? 'year' : 'years'}';
  @override
  String tgInDays(int days) => 'in $days ${days == 1 ? 'day' : 'days'}';
  @override
  String tgUntilMilestone(int target, int left) =>
      'Until ${tgDaysMilestone(target)} — ${tgInDays(left)}';
  @override
  String tgMissAddressee(String name) => 'To $name';
  @override
  String tgMoodMatched(int days) => 'matched $days of 7';
  @override
  String tgCountdownDaysLeft(int days) =>
      '${days == 1 ? 'day' : 'days'} until we meet';
  @override
  String tgYearDaysWord(int days) => days == 1 ? 'Day' : 'Days';
  @override
  String tgYearDaysTogether(int days) =>
      '${days == 1 ? 'Day' : 'Days'} together';
  @override
  String tgYearDaysLeft(int days) => '$days ${days == 1 ? 'day' : 'days'} left';
  @override
  String tgYearToAnniversary(int year) => 'To year $year';
  @override
  String tgYearToAnniversaryShort(int year, int days) =>
      'To year $year — $days';
  @override
  String tgYearCurrentYearShort(int year, int days) =>
      'Year $year · $days left';
  @override
  String tgYearOrdinalLabel(int year) => 'YEAR $year TOGETHER';
  @override
  String tgYearsAndDays(int years, int days) =>
      '$years ${years == 1 ? 'YEAR' : 'YEARS'} '
      '$days ${days == 1 ? 'DAY' : 'DAYS'}';
  @override
  String tgYearSince(String date) => 'Since $date';
  @override
  String mascotSleepRange(String from, String to) => 'Sleeps from $from to $to';
  @override
  String mascotNightRange(String from, String to) => 'Glows from $from to $to';

  @override
  String cycleOf(String name) => '$name\'s cycle';
  @override
  String cycleDaysLeft(int days) => 'In $days ${days == 1 ? 'day' : 'days'}';
  @override
  String cycleDayOfCycle(int day) => 'Day $day of the cycle';
  @override
  String cycleOverdue(int days) => '$days ${days == 1 ? 'day' : 'days'} late';
  @override
  String cycleAnalyticsHint(int cycles) =>
      'over the last $cycles ${cycles == 1 ? 'cycle' : 'cycles'}';
  @override
  String cycleDaysValue(int days) => '$days ${days == 1 ? 'day' : 'days'}';
  @override
  List<String> get cycleWeekdayShorts => const [
    'Mo',
    'Tu',
    'We',
    'Th',
    'Fr',
    'Sa',
    'Su',
  ];
  @override
  List<String> get cycleMonthNames => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  @override
  List<String> get cycleMonthsGenitive => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  @override
  String dayLogDate(DateTime day) =>
      '${cycleMonthsGenitive[day.month - 1]} ${day.day}';
  @override
  String dayLogWeekday(DateTime day) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][day.weekday - 1];
  @override
  String cyclePeriodDayLabel(int day) => 'period, day $day';
  @override
  String drawLayerName(int index) => 'Layer $index';
  @override
  String drawLayerStrokes(int count) =>
      count == 0 ? 'empty' : '$count ${count == 1 ? 'stroke' : 'strokes'}';
  @override
  String drawBackgroundName(String id) => switch (id) {
    'plain' => 'Plain',
    'grid' => 'Grid',
    'dots' => 'Dots',
    'notebook' => 'Notebook',
    'millimeter' => 'Graph paper',
    'kraft' => 'Kraft',
    'chalkboard' => 'Chalkboard',
    'music' => 'Sheet music',
    'stars' => 'Stars',
    'hearts' => 'Hearts',
    'watercolor' => 'Watercolour',
    'film' => 'Film',
    _ => id,
  };
  @override
  String memoryFileTooBig(int limitMb) =>
      'The file is over $limitMb MB — it will not upload';
  @override
  String pcReceiptShift(int days) => 'shift #$days';
  @override
  String pcReceiptItems(PostcardStats stats) {
    final lines = <String>[];
    if (stats.memories > 0) lines.add('Memories — ${stats.memories}');
    if (stats.drawings > 0) lines.add('Drawings — ${stats.drawings}');
    if (stats.missYou > 0) lines.add('Miss you — ${stats.missYou}');
    if (stats.streak > 0) lines.add('Days in a row — ${stats.streak}');
    if (lines.isEmpty) lines.add('It is only starting — 1');
    return lines.join('\n');
  }

  @override
  String pcMsgParcel(String from, int days) =>
      'From: ${from.isEmpty ? 'me' : from}\n'
      'Contents: $days days, all intact';
  @override
  String statsMoodMarks(int n) => 'Marks in 30 days: $n';
  @override
  String memoryFileTooBigPlusHint(int limitMb) =>
      'The file is over $limitMb MB. Togetherly+ doubles the cap';
  @override
  String selectedCount(int n) => 'Selected $n';
  @override
  String deleteCanvasesTitle(int n) =>
      n == 1 ? 'Delete canvas?' : 'Delete $n canvases?';
  @override
  String deleteCanvasesConfirm(int n) => n == 1
      ? 'The drawing disappears for both of you. This cannot be undone.'
      : 'The drawings disappear for both of you. This cannot be undone.';
  @override
  String chatBgConfirmBody(int price) =>
      'Set your photo as the chat background for $price 🪙?\n\n'
      'Every future change also costs $price 🪙.';
  @override
  String captionDestPairWidgetSub(String partner) =>
      'Photo in "My widget" — visible to you and $partner';
  @override
  String captionDestPartnerWidgetSub(String partner) =>
      'A separate widget with a photo for $partner';
  @override
  String streakLabel(int days) => 'Streak: $days ${days == 1 ? 'day' : 'days'}';

  // ── Widget screen ──
  @override
  String unlockForCoins(int price) => 'Unlock — $price 🪙';
  @override
  String notEnoughCoinsNeed(int price) =>
      'Not enough coins — you need $price 🪙';
  @override
  String personalPhotosHelp(String partner) =>
      'Personal photos — 1 to 10 per widget. With two or more photos a '
      'carousel turns on: it changes on unlock or by timer.\n\nThese photos '
      'are visible only to you. To share with $partner, open “Partner photo” → '
      '“Choose photos for partner”.';
  @override
  String partnerSharesPhotosHelp(String partner, int count) =>
      'This widget shows photos shared by $partner '
      '($count ${photosUnit(count)}). Only $partner can change them.';
  @override
  String partnerNotSharedHelp(String partner) =>
      '$partner hasn’t shared any photos yet. For them to appear here, '
      '$partner needs to open “Partner photo” and tap “Choose photos for '
      'partner” — the regular “Photo widget” is visible only to its owner.';
  @override
  String youSharePhotosWithPartner(String partner, int count) =>
      '$partner sees $count of your ${photosUnit(count)}';
  @override
  String photosUnit(int n) => n == 1 ? 'photo' : 'photos';
  @override
  String photoCountOnUnlock(int count) => '$count photos · on unlock';
  @override
  String photoCountInterval(int count, String interval) =>
      '$count photos · $interval';
  @override
  String intervalLabel(int minutes) {
    switch (minutes) {
      case 15:
        return 'every 15 min';
      case 30:
        return 'every 30 min';
      case 60:
        return 'every hour';
      case 180:
        return 'every 3 hours';
      default:
        return 'every $minutes min';
    }
  }

  @override
  String partnerSharedCountHelp(int count) =>
      'Your partner shared $count photos — choose how they rotate on this '
      'widget.';

  // ── Mascot gallery ──
  @override
  String mascotDeactivated(String name) => '$name deactivated';
  @override
  String mascotActivated(String name) => '$name is now active';
  @override
  String deleteMascotBody(String name) =>
      '“$name” will be deleted permanently.';
  @override
  String recordStreakDays(int days) => 'Record: $days d.';
  @override
  String mascotsCount(int count, int max) => '$count / $max mascots';
  @override
  String recordStreakBadge(int days) => '$days d.';

  // ── Mascot draw screen ──
  @override
  String genericError(String e) => 'Error: $e';
  @override
  String coloringPartnerColoring(String name) => '$name is colouring';
  @override
  String coloringWaitingHint(String name) =>
      'we will open it as soon as $name taps Done';

  // ── Postcard templates ──

  // ── Photo carousel editor ──
  @override
  String photoCountCarousel(int count) => '$count photos · carousel';
  @override
  String photoNumber(int n) => 'Photo $n';
  @override
  String positionNumber(int n) => 'Position $n';

  // ── Profile screen ──
  @override
  String yearRange(int first, int last) => 'Year from $first to $last';
  @override
  String kpRating(String rating) => 'KP $rating';
  @override
  String distanceLabel(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';
  @override
  String watchWithPartner(String name) => 'Watch with $name';
  @override
  String watchVideoAdd(int mb) => 'Upload up to $mb MB';
  @override
  String watchVideoTooBig(int mb) =>
      'The video is over $mb MB: compress it or pick a shorter one';
  @override
  String invitesToWatchTogether(String hostName) =>
      '$hostName invites you to watch together';
  @override
  String selectUpToPhotos(int n) => 'Select up to $n ${photosUnit(n)}';
  @override
  String addWithCount(int n) => 'Add ($n)';
  @override
  String failedToSave(Object e) => 'Failed to save: $e';
  @override
  String itemsShort(int n) => '$n items';
  @override
  String coinsPlus(int n) => '+$n ${n == 1 ? 'coin' : 'coins'}';
  @override
  String moodScoreLabel(int score, int max) =>
      '$moodScorePrefix $score of $max';
  @override
  List<String> get monthAbbrev => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  @override
  String memoriesUnit(int n) => n == 1 ? 'memory' : 'memories';

  // ── Live location map ──
  @override
  String liveLocationAgo(String value) => '$value ago';

  // Receiving a gift
  @override
  String giftFromPartner(String name) => 'A gift from $name';
  @override
  String giftBunnyMisses(int misses) =>
      misses == 1 ? 'It slipped away!' : 'Slipped again, catch it!';
  @override
  String giftIncomingCount(int n) => n == 1 ? 'is waiting' : '$n are waiting';
  @override
  String giftMutualBonus(int coins) => 'Right on time: $coins each';
  @override
  String giftSunriseGreeting(String name) =>
      'Good morning! $name sent you a sunrise';
  @override
  String supportCopied(String email) => 'Address copied: $email';
  @override
  String redeemCodeDone(int coins) => '$coins coins added';

  // Partner profile
  @override
  String partnerGiftsChip(int count) => '$count';
  @override
  String partnerMissChip(int count) => '$count';
  @override
  String partnerDaysTogether(int days) =>
      days == 1 ? 'together 1 day' : 'together $days days';
  @override
  String partnerMissPeak(String weekday) => 'Most often on $weekday';
  @override
  String weekdayShort(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];
  @override
  String weekdayLong(int weekday) => const [
    'Mondays',
    'Tuesdays',
    'Wednesdays',
    'Thursdays',
    'Fridays',
    'Saturdays',
    'Sundays',
  ][weekday - 1];

  // Gifts
  @override
  String giftPushBody(String giftName) => 'Sent you a gift: $giftName';
}

// ══════════════════════════════════════════════════════════════════════════════
// ЯЗЫКИ БЕЗ СВОЕЙ РЕАЛИЗАЦИИ
// ══════════════════════════════════════════════════════════════════════════════
//
// Простые строки эти языки берут из словаря по своему коду — там перевод и
// живёт. Наследуют они английский, потому что кроме словаря в классе остаётся
// то, что словарём не выражается: методы с числительными и списки месяцев и
// дней недели. Пока их не перевели, немец увидит английское «3 days» и
// «January» — надпись на месте, экран цел.
//
// Перевести числительные для языка значит переопределить здесь его методы; до
// тех порядок такой: словарь наполняется первым, он закрывает 1419 строк из
// 1600.




