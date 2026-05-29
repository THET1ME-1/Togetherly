import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported languages
enum AppLanguage { ru, en }

/// Singleton localization manager with Russian and English support.
/// Determines default language from device locale, stores user choice.
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

  AppStrings get strings =>
      _language == AppLanguage.ru ? const _RuStrings() : const _EnStrings();

  /// Initialize: load saved preference or detect from device locale.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('app_language');
      if (saved != null) {
        _language = saved == 'ru' ? AppLanguage.ru : AppLanguage.en;
      } else {
        // Detect from device locale
        final locale = ui.PlatformDispatcher.instance.locale;
        _language = locale.languageCode == 'ru'
            ? AppLanguage.ru
            : AppLanguage.en;
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
      await prefs.setString(
        'app_language',
        lang == AppLanguage.ru ? 'ru' : 'en',
      );
    } catch (_) {}
    notifyListeners();
  }

  String get languageLabel =>
      _language == AppLanguage.ru ? 'Русский' : 'English';
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
  String get agreeToTerms;
  String get forgotPassword;
  String get showPassword;
  String get hidePassword;
  String get min8Chars;
  String get oneUppercase;
  String get oneSpecialChar;
  String get fullName;
  String get createAccountBtn;
  String get continueWithGoogle;
  String get continueWithApple;
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
  String get information;
  String get theme;
  String get relationships;
  String get statusLabel;
  String get partnerLabel;
  String get notSelected;
  String daysTogetherLabel(String days);
  String get invitePartnerToCount;
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
  String get logout;
  String get logoutQuestion;
  String get logoutConfirm;
  String get logoutBtn;
  String get chooseColorTheme;
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
  String premiumThemeLocked(int price);
  String get coinBalance;
  String get coinShopTitle;
  String get coinShopSubtitle;
  String get buyThemeTitle;
  String buyThemeDescription(String themeName, int price);
  String get buyThemeConfirm;
  String get notEnoughCoins;
  String get themePurchased;
  String get watchAdTitle;
  String get watchAdSubtitle;
  String get adNotReady;
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
  String get failedGetLocation;
  String get tapToSelectPhotos;
  String get tapToSelectVideo;
  String get adultContent;
  String get photoBlurred;
  String get fromGallery;
  String get byLink;
  String get videoLink;
  String get fetchData;
  String get supportedPlatformsHint;
  String get supportedPlatforms;
  String get pasteLinkSupported;
  String get gotIt;
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
  String get openSystemSettings;
  String get notifSystemSettingsHint;

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
}

// ══════════════════════════════════════════════════════════════════════════════
// RUSSIAN STRINGS
// ══════════════════════════════════════════════════════════════════════════════

class _RuStrings extends AppStrings {
  const _RuStrings();

  // ── Common ──
  @override
  String get save => 'Сохранить';
  @override
  String get cancel => 'Отмена';
  @override
  String get delete => 'Удалить';
  @override
  String get edit => 'Изменить';
  @override
  String get add => 'Добавить';
  @override
  String get done => 'Готово';
  @override
  String get loading => 'Загрузка...';
  @override
  String get error => 'Ошибка';
  @override
  String get ok => 'OK';
  @override
  String get yes => 'Да';
  @override
  String get no => 'Нет';
  @override
  String get close => 'Закрыть';
  @override
  String get back => 'Назад';
  @override
  String get reset => 'Сбросить';
  @override
  String get clear => 'Очистить';

  // ── Welcome ──
  @override
  String get welcomeTitle1 => 'Это пространство только\nдля ';
  @override
  String get welcomeTitle2 => 'вас двоих';
  @override
  String get welcomeSubtitle => 'Моменты, чувства, связь';
  @override
  String get welcomeFeatureMemories => 'Общие воспоминания, фото и заметки';
  @override
  String get welcomeFeatureMood => 'Настроение, статусы и маленькие ритуалы';
  @override
  String get welcomeFeatureWidgets => 'Таймеры, виджеты и карта ваших мест';
  @override
  String get welcomeStepCreateProfile => '1. Создайте профиль и войдите';
  @override
  String get welcomeStepConnectPartner =>
      '2. Подключите партнёра по ссылке, коду или QR';
  @override
  String get welcomeStepStartTogether =>
      '3. Добавьте первое воспоминание и настройте ваше пространство';
  @override
  String get createAccount => 'Создать аккаунт';
  @override
  String get alreadyHaveAccount => 'Уже есть аккаунт';
  @override
  String get privateSecure => 'ПРИВАТНО И БЕЗОПАСНО';

  // ── Login ──
  @override
  String get welcomeBack => 'С возвращением!';
  @override
  String get loginToAccount => 'Войдите в свой аккаунт';
  @override
  String get signInWithGoogle => 'Войти через Google';
  @override
  String get or => 'или';
  @override
  String get email => 'Email';
  @override
  String get yourEmail => 'Ваш email';
  @override
  String get password => 'Пароль';
  @override
  String get yourPassword => 'Ваш пароль';
  @override
  String get login => 'Войти';
  @override
  String get noAccount => 'Нет аккаунта? ';
  @override
  String get create => 'Создать';
  @override
  String get invalidEmail => 'Введите корректный email';
  @override
  String get enterPassword => 'Введите пароль';
  @override
  String get loginFailed => 'Не удалось войти. Попробуйте ещё раз.';
  @override
  String get profileNotFound => 'Профиль не найден. Зарегистрируйтесь заново.';
  @override
  String get userNotFound => 'Пользователь с таким email не найден';
  @override
  String get wrongPassword => 'Неверный пароль';
  @override
  String get invalidEmailFormat => 'Некорректный email';
  @override
  String get tooManyAttempts => 'Слишком много попыток. Попробуйте позже';
  @override
  String get serverNotResponding => 'Сервер не отвечает. Проверьте интернет.';
  @override
  String get googleNotResponding => 'Google не отвечает. Проверьте интернет.';
  @override
  String loginError(String e) => 'Ошибка входа: $e';
  @override
  String googleLoginError(String e) => 'Ошибка входа через Google: $e';

  // ── Setup ──
  @override
  String get whoAreYou => 'Кто вы?';
  @override
  String get selectGenderForTheme => 'Выберите пол для настройки темы';
  @override
  String get boy => 'Парень';
  @override
  String get girl => 'Девушка';
  @override
  String get continueBtn => 'Продолжить';
  @override
  String get createProfile => 'Создайте профиль';
  @override
  String get signInGoogleOrManual =>
      'Войдите через Google или\nзаполните вручную';
  @override
  String get orManually => 'или вручную';
  @override
  String get name => 'Имя';
  @override
  String get yourName => 'Ваше имя';
  @override
  String get minCharsPassword => 'Минимум 6 символов';
  @override
  String get start => 'Начать';
  @override
  String get alreadyHaveAccountQuestion => 'Уже есть аккаунт? ';
  @override
  String get enterYourName => 'Введите ваше имя';
  @override
  String get enterValidEmail => 'Введите корректный email';
  @override
  String get selectGender => 'Выберите пол';
  @override
  String get passwordMin6 => 'Пароль должен быть минимум 6 символов';
  @override
  String get accountExists => 'Аккаунт существует';
  @override
  String get emailAlreadyRegistered =>
      'Этот email уже зарегистрирован. Хотите войти в существующий аккаунт?';
  @override
  String registrationError(String e) => 'Ошибка регистрации: $e';
  @override
  String get agreeToTerms => 'Я принимаю условия использования';
  @override
  String get forgotPassword => 'Забыли пароль?';
  @override
  String get showPassword => 'Показать';
  @override
  String get hidePassword => 'Скрыть';
  @override
  String get min8Chars => 'Минимум 8 символов';
  @override
  String get oneUppercase => '1 заглавная буква';
  @override
  String get oneSpecialChar => '1 спец. символ';
  @override
  String get fullName => 'Полное имя';
  @override
  String get createAccountBtn => 'Создать аккаунт';
  @override
  String get continueWithGoogle => 'Продолжить через Google';
  @override
  String get continueWithApple => 'Продолжить через Apple';
  @override
  String get alreadyHaveAccountLogin => 'Уже есть аккаунт?';
  @override
  String get passwordRequirements => 'Требования к паролю';

  // ── Home ──
  @override
  String get home => 'Главная';
  @override
  String get widgets => 'Виджеты';
  @override
  String get connect => 'Связь';
  @override
  String get profile => 'Профиль';
  @override
  String get solo => 'Solo';
  @override
  String get waitingForConnection => 'ОЖИДАНИЕ ПОДКЛЮЧЕНИЯ';
  @override
  String daysLabel(String suffix) => 'ДНЕЙ $suffix';
  @override
  String monthsLabel(String suffix) => 'МЕСЯЦЕВ $suffix';
  @override
  String timeLabel(String suffix) => 'ВРЕМЯ $suffix';
  @override
  String get inLove => 'ВЛЮБЛЕНЫ';
  @override
  String get together => 'ВМЕСТЕ';
  @override
  String get days => 'Дни';
  @override
  String get months => 'Месяцы';
  @override
  String get time => 'Время';
  @override
  String get inviteYourPartner => 'Пригласить партнёра';
  @override
  String get shareLinkCodeQr => 'Поделитесь ссылкой, кодом или QR';
  @override
  String get relationshipMemoryLane => 'Лента воспоминаний';
  @override
  String get memoriesWillAppear => 'Воспоминания появятся здесь';
  @override
  String get connectWithPartnerToStart => 'Подключите партнёра, чтобы начать';
  @override
  String partnerIsMood(String name, String mood) => '$name — $mood';
  @override
  String get answerSent => 'Ответ отправлен!';
  @override
  String get dailyReflection => 'Ежедневная рефлексия';
  @override
  String get today => 'СЕГОДНЯ';
  @override
  String get answerPrompt => 'Ответить';
  @override
  String get editAnswer => 'Редакт. ответ';
  @override
  String get clearMood => 'Убрать настроение';
  @override
  String get removeMood => 'Убрать настроение';
  @override
  String get howAreYouFeeling => 'Как вы себя чувствуете?';
  @override
  String get partnerWillSeeMood => 'Партнёр увидит ваше настроение';
  @override
  String moodDateLabel(String dateLabel) => 'Настроение — $dateLabel';
  @override
  String get indicateMoodForDay => 'Укажите настроение для этого дня';
  @override
  String get relationshipStatus => 'Статус отношений';
  @override
  String get chooseHowToConnect => 'Выберите тип связи';
  @override
  String get inLoveStatus => 'Влюблённые';
  @override
  String get perfectForCouples => 'Для романтических пар';
  @override
  String get married => 'Женаты';
  @override
  String get forMarriedPartners => 'Для партнёров в браке';
  @override
  String get friends => 'Друзья';
  @override
  String get connectWithBestFriend => 'Связь с лучшим другом';
  @override
  String get bestBuddies => 'Лучшие друзья';
  @override
  String get forInseparableCompanions => 'Для неразлучных друзей';
  @override
  String get addCustomStatus => 'Добавить свой статус';
  @override
  String get editCustomStatus => 'Редактировать статус';
  @override
  String get addCaption => 'Добавить подпись';
  @override
  String get optionalDescribe => 'Необязательно — опишите момент';
  @override
  String get writeSmth => 'Напишите что-нибудь...';
  @override
  String get skip => 'Пропустить';
  @override
  String get post => 'Отправить';
  @override
  String get posting => 'Отправка...';
  @override
  String get failedUploadPhoto => 'Не удалось загрузить фото';
  @override
  String get postedToMemoryLane => 'Добавлено в ленту воспоминаний! 📸';
  @override
  String get moodCalendar => 'Календарь настроений';
  @override
  String get seeAll => 'Все';
  @override
  String get addMemory => 'Добавить';
  @override
  String get viewAll => 'Все';

  // ── Widget Screen ──
  @override
  String get widgetsTitle => 'Виджеты';
  @override
  String get resetBtn => 'Сбросить';
  @override
  String get desktopPreview => 'Превью на рабочем столе';
  @override
  String get me => 'Я';
  @override
  String get partner => 'Партнёр';
  @override
  String get noStatus => 'Нет статуса';
  @override
  String get myWidget => 'Мой виджет';
  @override
  String get tapToEdit => 'Нажми, чтобы изменить';
  @override
  String get editBtn => 'Изменить';
  @override
  String widgetOfPartner(String name) => 'Виджет $name';
  @override
  String get emptyYet => 'Пока пусто';
  @override
  String get updated => 'Обновлено';
  @override
  String get live => 'Live';
  @override
  String get mood => 'Настроение';
  @override
  String get status => 'Статус';
  @override
  String get message => 'Сообщение';
  @override
  String get photo => 'Фото';
  @override
  String get photoUploaded => 'Фото загружено';
  @override
  String get music => 'Музыка';
  @override
  String get addBtn => 'Добавить';
  @override
  String get widgetSettings => 'Настройки виджета';
  @override
  String get photoToMemoryLane => 'Фото → Лента воспоминаний';
  @override
  String get autoSavePhotoToMemories =>
      'Автоматически сохранять фото в воспоминания';
  @override
  String get messagestoMemoryLane => 'Сообщения → Лента воспоминаний';
  @override
  String get autoSaveMessages => 'Автоматически сохранять сообщения';
  @override
  String get musicToMemoryLane => 'Музыка → Лента воспоминаний';
  @override
  String get autoSaveTracks => 'Автоматически сохранять треки';
  @override
  String get moodToCalendar => 'Настроение → Календарь';
  @override
  String get autoMarkMoodCalendar =>
      'Автоматически отмечать в календаре настроений';
  @override
  String get connectPartnerForWidgets =>
      'Подключи партнёра, чтобы начать\nобмениваться виджетами';
  @override
  String get chooseMood => 'Выбери настроение';
  @override
  String get statusHint => 'Что у тебя нового?';
  @override
  String get messageHint => 'Напиши что-нибудь приятное...';
  @override
  String get chooseSource => 'Выбери источник';
  @override
  String get camera => 'Камера';
  @override
  String get gallery => 'Галерея';
  @override
  String get musicTitle => 'Музыка';
  @override
  String get trackName => 'Название трека';
  @override
  String get artist => 'Исполнитель';
  @override
  String get linkOptional => 'Ссылка (необязательно)';
  @override
  String get uploadingPhoto => 'Загружаем фото...';
  @override
  String get resetWidget => 'Сбросить виджет?';
  @override
  String get resetWidgetConfirm => 'Все данные твоего виджета будут очищены.';
  @override
  String get notPairedWidgets => 'Виджеты';
  @override
  String get notPairedWidgetsDesc =>
      'Подключи партнёра, чтобы начать\nобмениваться виджетами';

  // ── Profile ──
  @override
  String get user => 'Пользователь';
  @override
  String get noEmail => 'Нет email';
  @override
  String get gender => 'Пол';
  @override
  String get male => 'Мужской';
  @override
  String get female => 'Женский';
  @override
  String get information => 'ИНФОРМАЦИЯ';
  @override
  String get theme => 'Тема';
  @override
  String get relationships => 'ОТНОШЕНИЯ';
  @override
  String get statusLabel => 'Статус';
  @override
  String get partnerLabel => 'Партнёр';
  @override
  String get notSelected => 'Не выбран';
  @override
  String daysTogetherLabel(String days) => '$days дней';
  @override
  String get invitePartnerToCount =>
      'Пригласите партнёра, чтобы начать\nсчитать дни вместе ❤️';
  @override
  String get inLoveRelType => 'Влюблённые';
  @override
  String get marriedRelType => 'Женаты';
  @override
  String get friendsRelType => 'Друзья';
  @override
  String get bestFriendsRelType => 'Лучшие друзья';
  @override
  String get customStatus => 'Свой статус';
  @override
  String get relationshipType => 'Тип отношений';
  @override
  String get selectPartner => 'Выберите партнёра';
  @override
  String get noConnectedPartners => 'Нет подключённых партнёров';
  @override
  String get settings => 'НАСТРОЙКИ';
  @override
  String get editProfile => 'Редактировать профиль';
  @override
  String get notifications => 'Уведомления';
  @override
  String get privacy => 'Конфиденциальность';
  @override
  String get aboutApp => 'О приложении';
  @override
  String get supportAuthors => 'Поддержать авторов';
  @override
  String get logout => 'Выйти из аккаунта';
  @override
  String get logoutQuestion => 'Выйти?';
  @override
  String get logoutConfirm => 'Вы уверены, что хотите выйти из аккаунта?';
  @override
  String get logoutBtn => 'Выйти';
  @override
  String get chooseColorTheme => 'Выбери цветовую тему';
  @override
  String get themeNamePink => 'Розовая';
  @override
  String get themeNamePurple => 'Фиолетовая';
  @override
  String get themeNameBlue => 'Голубая';
  @override
  String get themeNamePeach => 'Персиковая';
  @override
  String get themeNameSage => 'Шалфейная';
  @override
  String get themeNameMidnight => 'Полуночная';
  @override
  String get themeNameLavender => 'Лавандовая';
  @override
  String get themeNameCherry => 'Вишнёвая';
  @override
  String get themeNameMint => 'Мятная';
  @override
  String get themeNameSunset => 'Закатная';
  @override
  String get themeNameMonochrome => 'Монохром';
  @override
  String get themeNameForest => 'Лесная';
  @override
  String get themeNameOcean => 'Океан';
  @override
  String premiumThemeLocked(int price) =>
      'Премиум-тема за $price монет — открой в магазине';
  @override
  String get coinBalance => 'Коины';
  @override
  String get coinShopTitle => 'Магазин Коинов';
  @override
  String get coinShopSubtitle => 'Кастомизация и приятности';
  @override
  String get buyThemeTitle => 'Купить тему?';
  @override
  String buyThemeDescription(String themeName, int price) =>
      'Разблокировать тему «$themeName» за $price монет?';
  @override
  String get buyThemeConfirm => 'Купить';
  @override
  String get notEnoughCoins => 'Недостаточно монет';
  @override
  String get themePurchased => 'Тема разблокирована';
  @override
  String get watchAdTitle => 'Посмотреть рекламу';
  @override
  String get watchAdSubtitle => 'За просмотр, до 3 раз в день';
  @override
  String get adNotReady => 'Реклама ещё загружается — попробуй через секунду';
  @override
  String get rewardPending => 'Награда зачисляется…';
  @override
  String get coinPacksSectionTitle => 'Купить монеты';
  @override
  String coinPackTitle(int coins) => '$coins монет';
  @override
  String get coinPurchaseSuccess => 'Монеты начислены!';
  @override
  String coinPurchaseSuccessAmount(int coins) => '+$coins монет зачислено';
  @override
  String get coinPurchasePending => 'Платёж обрабатывается…';
  @override
  String get coinPurchaseCancelled => 'Покупка отменена';
  @override
  String get coinPurchaseError => 'Ошибка покупки. Попробуй ещё раз';
  @override
  String get coinStoreUnavailable => 'Магазин недоступен';
  @override
  String get changesApplyImmediately => 'Изменения применяются сразу';
  @override
  String get dailyBonusTitle => 'Ежедневный вход';
  @override
  String get dailyBonusSubtitle => 'Каждый день при входе';
  @override
  String coinEarned(int amount) => '+$amount монет получено!';
  @override
  String get memoryRewardTitle => 'Добавь воспоминание';
  @override
  String get memoryRewardSubtitle => 'За новое воспоминание, раз в день';
  @override
  String get partnerInviteRewardTitle => 'Пригласи партнёра';
  @override
  String get partnerInviteRewardSubtitle => 'Единоразово при подключении';
  @override
  String get moodStreakRewardTitle => 'Стрик настроения';
  @override
  String get moodStreakRewardSubtitle => 'Оба заполняли 7 дней подряд';
  @override
  String get earnCoinsSection => 'Заработать бесплатно';
  @override
  String get editProfileTitle => 'Редактировать профиль';
  @override
  String get uploading => 'Загрузка...';
  @override
  String get userNotAuthorized => 'Ошибка: пользователь не авторизован';
  @override
  String get failedUploadImage => 'Не удалось загрузить изображение';
  @override
  String get avatarUpdated => 'Аватарка обновлена';
  @override
  String get nameUpdated => 'Имя обновлено';
  @override
  String uploadError(String e) => 'Ошибка загрузки: $e';
  @override
  String get language => 'Язык';
  @override
  String get selectLanguage => 'Выберите язык';
  @override
  String get blobAnimation => 'Blob-анимация';

  // ── Mood Calendar ──
  @override
  String get moodCalendarTitle => 'Календарь настроений';
  @override
  String get zoomIn => 'Увеличить';
  @override
  String get zoomOut => 'Уменьшить';
  @override
  String get week => 'Неделя';
  @override
  String get month => 'Месяц';
  @override
  String get year => 'Год';
  @override
  String get myMood => 'Мои настроения';
  @override
  String partnerMood(String name) => 'Настроения $name';
  @override
  String get moods => 'Настроения';

  // ── Home (continued) ──
  @override
  String get emoji => 'Эмодзи';
  @override
  String get label => 'Название';
  @override
  String get egSoulmates => 'напр., Родные души';
  @override
  String get shareYourThoughts => 'Поделитесь мыслями...';
  @override
  String get draw => 'Рисовать';
  @override
  String get calendar => 'Календарь';
  @override
  String get noMemoriesYet => 'Пока нет воспоминаний';

  // ── Draw Screen ──
  @override
  String get drawTogether => 'Рисуем вместе';
  @override
  String get brush => 'Кисть';
  @override
  String get eraser => 'Ластик';
  @override
  String get panTool => 'Рука';
  @override
  String get fillBg => 'Заливка';
  @override
  String get rotateCanvas => 'Повернуть холст';
  @override
  String get drawLine => 'Линия';
  @override
  String get drawRect => 'Прямоугольник';
  @override
  String get drawCircle => 'Круг';
  @override
  String get drawTriangle => 'Треугольник';
  @override
  String get fillShapes => 'Заливка фигур';
  @override
  String get insertPhoto => 'Вставить фото';
  @override
  String get photoRequiresPartner =>
      'Фото доступно только при совместном рисовании с партнёром';
  @override
  String get photoFromGallery => 'Из галереи';
  @override
  String get photoFromCamera => 'Сделать фото';
  @override
  String get undoAction => 'Отменить';
  @override
  String get redoAction => 'Повторить';
  @override
  String get clearCanvas => 'Очистить';
  @override
  String get clearCanvasConfirm =>
      'Очистить весь холст? Это удалит рисунки обоих.';
  @override
  String get deletePhoto => 'Удалить фото';
  @override
  String get mascotBoyName => 'Пиксик';
  @override
  String get mascotGirlName => 'Пикси';
  @override
  String get saveDrawing => 'Сохранить';
  @override
  String get shareDrawing => 'Поделиться';
  @override
  String drawingSavedTo(String path) => 'Рисунок сохранён: $path';
  @override
  String get failedToSaveDrawing => 'Не удалось сохранить рисунок';
  @override
  String get failedToShareDrawing => 'Не удалось поделиться рисунком';
  @override
  String get strokeThickness => 'Толщина';
  @override
  String get drawHint =>
      'Начните рисовать! Партнёр увидит ваши штрихи в реальном времени.';
  @override
  String partnerIsDrawing(String name) => '$name рисует…';
  @override
  String get addFirstMemory => 'Добавьте первое воспоминание в Ленту';
  @override
  String get video => 'Видео';
  @override
  String get videoLabel => 'Видео';
  @override
  String get location => 'Место';
  @override
  String get audio => 'Аудио';
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
  @override
  String get palmTool => 'Ладонь';
  @override
  String get drawingMode => 'Режим рисования';
  @override
  String get newCanvas => 'Новый холст';
  @override
  String get myDrawings => 'Мои рисунки';
  @override
  String get untitledCanvas => 'Холст';
  @override
  String get renameCanvas => 'Переименовать';
  @override
  String get deleteCanvas => 'Удалить холст';
  @override
  String get deleteCanvasConfirm =>
      'Удалить этот холст? Это действие необратимо.';
  @override
  String get canvasNameLabel => 'Название холста';
  @override
  String get noDrawingsYet => 'Рисунков пока нет';

  // ── Connect Partner ──
  @override
  String get newGroup => 'Новая';
  @override
  String get waiting => 'Ожидание...';
  @override
  String get deleteGroupConfirm => 'Удалить эту группу?';
  @override
  String get deleteGroupTitle => 'Удалить группу';
  @override
  String get removeGroup => 'Удалить';
  @override
  String get connected => 'Подключены';
  @override
  String groupOf(int count) => 'Группа из $count';
  @override
  String membersCount(int count) => 'УЧАСТНИКИ · $count';
  @override
  String get member => 'Участник';
  @override
  String get online => 'Онлайн';
  @override
  String get offline => 'Не в сети';
  @override
  String get inviteMore => 'Пригласить ещё';
  @override
  String get scanQr => 'Скан QR';
  @override
  String get disconnect => 'Отключиться';
  @override
  String get connectYourPartner => 'Подключите партнёра';
  @override
  String get shareInviteCodeDesc =>
      'Поделитесь кодом приглашения,\nчтобы партнёр присоединился';
  @override
  String get yourInviteCode => 'ВАШ КОД ПРИГЛАШЕНИЯ';
  @override
  String get copy => 'Копия';
  @override
  String get share => 'Поделиться';
  @override
  String get codeCopied => 'Код скопирован!';
  @override
  String shareInviteText(String code, String link) =>
      'Присоединяйся ко мне в Love App! Используй код: $code\n\nИли нажми: $link';
  @override
  String get loveAppInvitation => 'Приглашение Love App';
  @override
  String get newCodeGenerated => 'Новый код сгенерирован';
  @override
  String get showQr => 'Показать QR';
  @override
  String get haveACode => 'Есть код?';
  @override
  String get connectPartnerBtn => 'Подключить партнёра';
  @override
  String get inviteMoreMembers => 'Пригласить участников';
  @override
  String membersOfMax(int current, int max) => '$current/$max участников';
  @override
  String shareGroupInviteText(String code, String link) =>
      'Присоединяйся к нашей группе в Love App! Используй код: $code\n\nИли нажми: $link';
  @override
  String get groupInvitation => 'Приглашение в группу Love App';
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
  String get joinAnotherGroup => 'Присоединиться к другой группе';
  @override
  String get enterCodeScanQr =>
      'Введите код, сканируйте QR или перейдите по ссылке';
  @override
  String get enterCode => 'Ввести код';
  @override
  String get invalidCodeTryAgain =>
      'Неверный код. Проверьте и попробуйте снова.';
  @override
  String get joinGroup => 'Присоединиться';
  @override
  String get cantInviteSelf => 'Вы не можете пригласить себя!';
  @override
  String get codeNotFound => 'Код не найден или уже использован';
  @override
  String get scanToConnect => 'Сканируйте для подключения';
  @override
  String get scanPartnersQr => 'Сканировать QR партнёра';
  @override
  String get addNewConnection => 'Новое подключение';
  @override
  String get chooseTypeForConnection => 'Выберите тип для нового подключения';
  @override
  String get yourCustomType => 'Ваш тип';
  @override
  String get newConnectionAdded => 'Новое подключение добавлено!';
  @override
  String get deleteConnection => 'Удалить подключение?';
  @override
  String get deleteConnectionDesc =>
      'Это удалит подключение навсегда. Если есть подключённый партнёр, он будет отключён.';
  @override
  String get connectionRemoved => 'Подключение удалено';
  @override
  String get disconnectQuestion => 'Отключиться?';
  @override
  String get disconnectDesc => 'Это сбросит ваш таймер и отключит партнёра.';
  @override
  String get renamePartner => 'Переименовать участника';
  @override
  String get renamePartnerHint =>
      'Имя видно только вам. Это не меняет имя партнёра у него.';
  @override
  String get resetNickname => 'Сбросить';
  @override
  String joinMeLinkText(String link) =>
      'Присоединяйся ко мне в Love App! $link';
  @override
  String get custom => 'Свой';
  @override
  String membersCountBracket(int count) => 'УЧАСТНИКИ ($count)';

  // ── Memory Lane ──
  @override
  String get memoryLane => 'Лента воспоминаний';
  @override
  String get addMemoryBtn => 'Добавить';
  @override
  String get pinned => '📌  Закреплено';

  // ── Timer Card ──
  @override
  String get timers => 'Таймеры';
  @override
  String get failedUploadBackground =>
      'Не удалось загрузить фон. Проверьте подключение.';

  // ── Mini Mood Calendar ──
  @override
  String get todayLabel => 'Сегодня';

  // ── Date helpers ──
  @override
  String get todayDate => 'Сегодня';
  @override
  String get yesterday => 'Вчера';
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
  String get iMissYou => 'Я скучаю';
  @override
  String get iMissYouSent => 'Отправлено! 💕';
  @override
  String missYouNotifTitle(String name) => '$name скучает по вам';
  @override
  String get missYouNotifBody => 'Думает о вас и вспоминает 💭';
  @override
  String missYouStreak(int count) => '🔥 $count';
  @override
  String get thinkingOfYou => 'Думаю о тебе';
  @override
  String get wantHug => 'Хочу обнять';
  @override
  String get vibeSent => 'Отправлено ✨';
  @override
  String get customVibe => 'Своё желание...';
  @override
  String get customVibeTitle => 'Своё сообщение';
  @override
  String get customVibeHint => 'Что ты хочешь сказать?';
  @override
  String thinkingOfYouNotifTitle(String name) => '$name думает о тебе 💭';
  @override
  String wantHugNotifTitle(String name) => '$name хочет обнять тебя 🤗';
  @override
  String customVibeNotifTitle(String name) => name;

  // ── Photo Card ──
  @override
  String get sharedAPicture => 'Поделился фото';
  @override
  String kmFromYou(String km) => '$km от вас';
  @override
  String get openInMaps => 'Открыть в картах';
  @override
  String get justNow => 'только что';
  @override
  String minutesAgo(int m) => '$m мин. назад';
  @override
  String hoursAgo(int h) => '$h ч. назад';
  @override
  String daysAgo(int d) => '$d д. назад';

  // ── Memory Lane Feed ──
  @override
  String get sharedAVideo => 'Поделился видео';
  @override
  String get sharedAVideoLink => 'Поделился видео по ссылке';
  @override
  String get sharedAThought => 'Поделился мыслями';
  @override
  String get sharedALocation => 'Отметил локацию';
  @override
  String get sharedMusic => 'Поделился музыкой';
  @override
  String get vibesTo => 'Вайбит под';
  @override
  String get setARoute => 'Маршрут';
  @override
  String get isListening => 'слушает';
  @override
  String get playTrack => 'Включить';
  @override
  String get note => 'Заметка';

  // ── Memory Lane (extended) ──
  @override
  String get noMemoriesYetDesc =>
      'Нажмите «Добавить», чтобы создать\nпервое общее воспоминание';
  @override
  String get unpinMemory => 'Открепить';
  @override
  String get pinMemory => 'Закрепить';
  @override
  String get saveToDevice => 'Сохранить';
  @override
  String get editMemory => 'Редактировать';
  @override
  String get deleteMemory => 'Удалить';
  @override
  String get deleteMemoryQuestion => 'Удалить воспоминание?';
  @override
  String get actionCannotBeUndone => 'Это действие нельзя отменить.';
  @override
  String get editMemoryTitle => 'Редактировать';
  @override
  String get titleOptional => 'Заголовок (необязательно)';
  @override
  String get description => 'Описание...';
  @override
  String get locationName => 'Название места...';
  @override
  String get changeLocationOnMap => 'Изменить место на карте';
  @override
  String get pickLocationOnMap => 'Выбрать место на карте';
  @override
  String get saveChanges => 'Сохранить изменения';
  @override
  String get addMemoryTitle => 'Добавить воспоминание';
  @override
  String get chooseWhatToShare => 'Выберите, чем поделиться';
  @override
  String newMemory(String type) => 'Новое: $type';
  @override
  String get memoryDetails => 'Детали';
  @override
  String get writeYourNote => 'Напишите заметку...';
  @override
  String get descriptionOptional => 'Описание (необязательно)';
  @override
  String get locationNameHint => 'Название места (напр. Парк Горького)';
  @override
  String get locationSet => 'Место выбрано ✓';
  @override
  String get useCurrent => 'Текущее';
  @override
  String get pickOnMap => 'На карте';
  @override
  String get songDetails => 'Детали трека';
  @override
  String get songName => 'Название песни';
  @override
  String get artistsCommaSeparated => 'Исполнители (через запятую)';
  @override
  String get egArtists => 'напр. Drake, The Weeknd';
  @override
  String get source => 'Источник';
  @override
  String get streamingLink => 'Ссылка на стриминг';
  @override
  String get fetched => 'Получено';
  @override
  String get pasteLinkFromService => 'Вставьте ссылку с любого сервиса...';
  @override
  String get autoFetchSongInfo => 'Авто-получение данных по ссылке';
  @override
  String get orDivider => 'ИЛИ';
  @override
  String get fileSelected => 'Файл выбран ✓';
  @override
  String get pickAudioFromDevice => 'Выбрать аудио с устройства';
  @override
  String get uploadingMemory => 'Загружаем воспоминание...';
  @override
  String get failedUploadPhotos =>
      'Не удалось загрузить фото. Убедитесь, что Firebase Storage включён.';
  @override
  String get failedUploadVideo =>
      'Не удалось загрузить видео. Убедитесь, что Firebase Storage включён.';
  @override
  String get memoryAddedSuccess => 'Воспоминание добавлено!';
  @override
  String failedAddMemory(String e) => 'Не удалось добавить: $e';
  @override
  String get noMediaUrl => 'Нет доступной ссылки на медиа';
  @override
  String get downloading => 'Скачиваем...';
  @override
  String get savedToGallery => 'Сохранено в галерею 🖼️';
  @override
  String savedToPath(String path) => 'Сохранено: $path';
  @override
  String downloadFailed(String e) => 'Ошибка скачивания: $e';
  @override
  String failedSelectPhotos(String e) => 'Не удалось выбрать фото: $e';
  @override
  String failedSelectVideo(String e) => 'Не удалось выбрать видео: $e';
  @override
  String get locationServicesDisabled => 'Геолокация отключена';
  @override
  String get locationPermissionDenied => 'Доступ к геолокации запрещён';
  @override
  String get failedGetLocation => 'Не удалось определить местоположение';
  @override
  String get tapToSelectPhotos => 'Нажмите, чтобы выбрать фото';
  @override
  String get tapToSelectVideo => 'Нажмите, чтобы выбрать видео';
  @override
  String get adultContent => 'Контент 18+';
  @override
  String get photoBlurred => 'Фото будет скрыто под блюром';
  @override
  String get fromGallery => 'Из галереи';
  @override
  String get byLink => 'По ссылке';
  @override
  String get videoLink => 'Ссылка на видео';
  @override
  String get fetchData => 'Получить данные';
  @override
  String get supportedPlatformsHint =>
      'Поддерживаются: YouTube, Vimeo, Dailymotion,\nTikTok, Instagram, VK и другие';
  @override
  String get supportedPlatforms => 'Поддерживаемые платформы';
  @override
  String get pasteLinkSupported =>
      'Вставьте ссылку с любой поддерживаемой платформы';
  @override
  String get gotIt => 'Понятно';
  @override
  String get supportedServices => 'Поддерживаемые сервисы';
  @override
  String get pasteLinkFromSupported =>
      'Вставьте ссылку с любого поддерживаемого сервиса';
  @override
  String get selectTextAndPress => 'Выдели текст и нажми';
  @override
  String get spoiler => 'Spoiler';
  @override
  String get deleteComment => 'Удалить комментарий?';
  @override
  String get deleteCommentQuestion => 'Удалить этот комментарий?';
  @override
  String get comments => 'Комментарии';
  @override
  String get writeAComment => 'Написать комментарий…';
  @override
  String get noCommentsYet => 'Нет комментариев — будьте первым!';
  @override
  String nPhotos(int count) => '$count фото';
  @override
  String get noPhotoAttached => 'Фото не прикреплено';
  @override
  String get unknownLocation => 'Неизвестная локация';
  @override
  String get openInGoogleMaps => 'Открыть в Google Картах';
  @override
  String get audioFile => 'Аудиофайл';
  @override
  String get unknownTrack => 'Неизвестный трек';
  @override
  String get noAudioUrl => 'Нет ссылки на аудио';
  @override
  String get cannotPlayAudio => 'Невозможно воспроизвести аудио';
  @override
  String openIn(String name) => 'Открыть в $name';
  @override
  String get tapToOpen => 'Нажмите, чтобы открыть';
  @override
  String get videoBadge => 'ВИДЕО';
  @override
  String get updateAvailableTitle => 'Доступно обновление';
  @override
  String get updateAvailableSubtitle => 'Новая версия приложения готова к установке';
  @override
  String get updateWhatsNew => 'Улучшения и исправления ошибок';
  @override
  String get updateButton => 'Обновить';
  @override
  String get updateLaterButton => 'Позже';
  @override
  String get updateRestartButton => 'Перезапустить и установить';
  @override
  String get noteBadge => 'ЗАМЕТКА';
  @override
  String get youtubeBadge => 'YouTube';
  @override
  String get photoNotUploaded => 'Фото ещё не загружено';
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
  String get noActiveConnection => 'Нет активного подключения';
  @override
  String get chooseAStatus => 'Выберите статус';
  @override
  String get customStatuses => 'Пользовательские статусы';
  @override
  String get currentStatus => 'Текущий статус';
  @override
  String get notSet => 'Не установлен';
  @override
  String get clearStatus => 'Очистить статус';
  @override
  String statusSetTo(String status) => 'Статус: $status';
  @override
  String failedSetStatus(String e) => 'Ошибка установки статуса: $e';
  @override
  String get statusCleared => 'Статус очищен';
  @override
  String failedClearStatus(String e) => 'Ошибка очистки статуса: $e';
  @override
  String get customStatusAdded => 'Статус добавлен';
  @override
  String failedAddStatus(String e) => 'Ошибка добавления статуса: $e';
  @override
  String get statusUpdated => 'Статус обновлён';
  @override
  String failedUpdateStatus(String e) => 'Ошибка обновления статуса: $e';
  @override
  String get deleteStatus => 'Удалить статус';
  @override
  String deleteStatusConfirm(String label) =>
      'Вы уверены, что хотите удалить «$label»?';
  @override
  String get statusDeleted => 'Статус удалён';
  @override
  String failedDeleteStatus(String e) => 'Ошибка удаления статуса: $e';
  @override
  String get editStatus => 'Редактировать статус';
  @override
  String get emojiLabel => 'Эмодзи';
  @override
  String get emojiHint => '💕';
  @override
  String get labelField => 'Название';
  @override
  String get egLivingTogether => 'напр., Живём вместе';
  @override
  String get update => 'Обновить';

  // ── Map Picker Screen ──
  @override
  String get selectLocationOnMap => 'Выберите место на карте';
  @override
  String get selectedLocation => 'Выбранная локация';
  @override
  String get selectLocation => 'Выбрать место';
  @override
  String get confirm => 'Подтвердить';
  @override
  String get gettingAddress => 'Определяем адрес...';
  @override
  String get tapOnMapToSelect => 'Нажмите на карту, чтобы выбрать другое место';
  @override
  String get failedGetCurrentLocation =>
      'Не удалось определить текущее местоположение';

  // ── Mood Calendar (extended) ──
  @override
  String get averageMood => 'Среднее настроение';
  @override
  String get great => 'Отлично';
  @override
  String get good => 'Хорошо';
  @override
  String get okay => 'Нормально';
  @override
  String get bad => 'Плохо';
  @override
  String get awful => 'Ужасно';
  @override
  String get notEnoughData => 'Недостаточно данных для графика';
  @override
  String moodRecorded(String label) => '$label записано!';
  @override
  String get noMoodRecorded => 'Настроение не отмечено';
  @override
  String get moodScorePrefix => 'Оценка';
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
  String get noTimers => 'Нет таймеров';
  @override
  String get createTimer => 'Создать таймер';
  @override
  String get editTimer => 'Редактировать таймер';
  @override
  String get timerNameLabel => 'НАЗВАНИЕ';
  @override
  String get egAnniversary => 'напр. Годовщина';
  @override
  String get targetDate => 'ЦЕЛЕВАЯ ДАТА';
  @override
  String get startDate => 'ДАТА НАЧАЛА';
  @override
  String get dateFormatHint => 'дд.мм.гггг';
  @override
  String get symbolLabel => 'СИМВОЛ';
  @override
  String get countdownMode => 'Режим отсчёта';
  @override
  String get setAsMain => 'Сделать основным';
  @override
  String get saveSettings => 'СОХРАНИТЬ';
  @override
  String get deleteTimerQuestion => 'Удалить таймер?';
  @override
  String timerDeleteConfirm(String name) => '«$name» будет удалён навсегда.';

  // ── Petal Timer Dial ──
  @override
  String get yearsLabel => 'Лет';
  @override
  String get monthsShortLabel => 'Мес';
  @override
  String get daysShortLabel => 'Дней';
  @override
  String get hoursLabel => 'Час';
  @override
  String get minLabel => 'Мин';
  @override
  String get secLabel => 'Сек';

  // ── Widget Screen (extended) ──
  @override
  String get homeScreenWidgets => 'Виджеты рабочего стола';
  @override
  String get addToHomeScreen => 'Добавить на рабочий стол';
  @override
  String get setAsPhotoOfDay => 'Установлено как фото дня';
  @override
  String get widgetAddedToHome => 'Виджет добавлен на рабочий стол';
  @override
  String failedAddWidget(String e) => 'Не удалось добавить виджет: $e';
  @override
  String get daysTogetherStat => 'Дней вместе';
  @override
  String get memoriesStat => 'Воспоминаний';
  @override
  String get drawingsStat => 'Рисунков';
  @override
  String get missYousStat => 'Скучаю';
  @override
  String get daysLeft => 'дней осталось';
  @override
  String get daysElapsed => 'дней прошло';
  @override
  String get noTimersWidget => 'Нет таймеров';
  @override
  String get photoOfDay => 'Фото дня';
  @override
  String get mine => 'Моё';
  @override
  String get onWidget => 'На виджете';
  @override
  String get randomSource => 'Случайное';
  @override
  String get ownPhoto => 'Своё фото';
  @override
  String get saveToMemoryLane => 'Добавить в ленту воспоминаний';
  @override
  String get regenerate => 'Повторная генерация';
  @override
  String get none => 'Нет';
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
  String get pairWidgetTitle => 'Парный виджет';
  @override
  String get pairWidgetSubtitle => 'Настроение, статус, сообщения и фото';
  @override
  String get daysCounterSubtitle => 'Системный счётчик дней отношений';
  @override
  String get timerWidgetTitle => 'Таймер';
  @override
  String get timerWidgetSubtitle => 'Выберите таймер для виджета';
  @override
  String get photoDayRandomSubtitle => 'Случайное фото из ленты';
  @override
  String get photoDayCustomSubtitle => 'Своё установленное фото';
  @override
  String get photoDayPartnerSubtitle => 'То, чем делится ваш партнёр';
  @override
  String get moodWidgetSubtitle => 'Горизонтальный виджет: моё и партнёра';
  @override
  String get relationshipStatsSubtitle =>
      'Важные цифры: дни, фото, рисунки и «скучаю»';
  @override
  String get daysCounterLabel => 'дней';
  @override
  String get addTimerHint => 'Добавьте таймер в разделе «Таймеры»';
  @override
  String get noTimersAddHint =>
      'Нет таймеров. Добавьте таймер в разделе «Таймеры».';
  @override
  String get soloTimerBannerTitle => 'Можно создать свой таймер';
  @override
  String get soloTimerBannerSubtitle =>
      'Одиночные таймеры и их виджеты доступны даже без добавления пары.';
  @override
  String get selectTimerForWidget => 'Выберите таймер для виджета:';
  @override
  String get daysShortLeft => 'дн. осталось';
  @override
  String get daysShortElapsed => 'дн. прошло';
  @override
  String get partnerPhotoWillAppear =>
      'Фото партнёра появится\nпосле его выбора';
  @override
  String get choosePhotoBelow => 'Выберите фото ниже';
  @override
  String get randomPhotoFromMemories => 'Случайное фото\nиз воспоминаний';
  @override
  String get photoSource => 'Источник фото:';
  @override
  String get fromMemories => 'из воспоминаний';
  @override
  String get fromGalleryLabel => 'из галереи';
  @override
  String get widgetModeMine => 'Мои фото';
  @override
  String get widgetModePartner => 'Фото партнёра';
  @override
  String get widgetInstances => 'Виджеты на рабочем столе';
  @override
  String get widgetNotAddedYet => 'Виджет ещё не добавлен';
  @override
  String widgetSlotTitle(int index) => 'Виджет ${index + 1}';
  @override
  String get addedWidgetsWillAppearHere =>
      'Добавленные фото-виджеты появятся здесь';
  @override
  String get addSeparateWidgetHint =>
      'Добавляйте несколько виджетов: у каждого будет своё фото и свой режим';
  @override
  String get widgetDisplaySource => 'Что показывать на виджете:';
  @override
  String get widgetDisplayPhoto => 'Фото для виджета';
  @override
  String get noPhotoSelected => 'Фото не выбрано';

  // ── Profile (extended) ──
  @override
  String get exportMemories => 'Экспорт воспоминаний';
  @override
  String get noActiveGroupForExport => 'Нет активной группы для экспорта';
  @override
  String get creatingArchive => 'Создаём архив...\nЭто займёт немного времени.';
  @override
  String exportError(String e) => 'Ошибка при экспорте: $e';
  @override
  String get relationshipStats => 'СТАТИСТИКА ОТНОШЕНИЙ';

  // ── Home Screen (extended) ──
  @override
  String get startWithBlankCanvas => 'Начать с чистого холста';
  @override
  String get openSavedDrawing => 'Открыть сохранённый рисунок';
  @override
  String get newPhoto => 'Новое фото';
  @override
  String get titleHint => 'Заголовок…';
  @override
  String get descriptionOptionalHint => 'Описание (необязательно)…';
  @override
  String get setAsWidgetPhoto => 'Фото дня на виджете';

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
  String get notifMissYou => '«Я скучаю»';
  @override
  String get notifMissYouSub => 'Когда партнёр нажимает кнопку «Я скучаю»';
  @override
  String get notifNewMemory => 'Новые воспоминания';
  @override
  String get notifNewMemorySub =>
      'Когда партнёр добавляет в ленту воспоминаний';
  @override
  String get notifMood => 'Настроение партнёра';
  @override
  String get notifMoodSub => 'Когда партнёр обновляет своё настроение';
  @override
  String get openSystemSettings => 'Системные настройки';
  @override
  String get notifSystemSettingsHint => 'Настройки хранятся на устройстве';
  @override
  String get lockScreenMood => 'Настроение на экране блокировки';
  @override
  String get lockScreenMoodSubtitle => 'Моё и партнёра — на экране блокировки';
  @override
  String get lockScreenMoodToggle => 'Показывать на экране блокировки';
  @override
  String get lockScreenMoodToggleSub =>
      'Настроение отображается при блокировке телефона';
  @override
  String get lockScreenMoodNoMood => 'Настроение не задано';
  @override
  String get lockScreenMoodSetHint =>
      'Установите настроение в календаре настроений';
  @override
  String get photoGridWidget => 'Сетка фото';
  @override
  String get photoGridWidgetSubtitle => 'Несколько фото из воспоминаний';
  @override
  String get photoGridCount => 'Количество фото';
  @override
  String get photoGridSelectPhotos => 'Выберите фото';
  @override
  String get photoGridAddPhoto => 'Добавить фото';
  @override
  String get photoGridCountLabel => 'фото на виджете';
  @override
  String get goToPin => 'К воспоминанию';
  @override
  String get openPhotoGallery => 'Галерея фото';
  @override
  String get allMediaGallery => 'Все фото и видео';
  @override
  String get loadMore => 'Загрузить ещё';
}

class _EnStrings extends AppStrings {
  const _EnStrings();

  // ── Common ──
  @override
  String get save => 'Save';
  @override
  String get cancel => 'Cancel';
  @override
  String get delete => 'Delete';
  @override
  String get edit => 'Edit';
  @override
  String get add => 'Add';
  @override
  String get done => 'Done';
  @override
  String get loading => 'Loading...';
  @override
  String get error => 'Error';
  @override
  String get ok => 'OK';
  @override
  String get yes => 'Yes';
  @override
  String get no => 'No';
  @override
  String get close => 'Close';
  @override
  String get back => 'Back';
  @override
  String get reset => 'Reset';
  @override
  String get clear => 'Clear';

  // ── Welcome ──
  @override
  String get welcomeTitle1 => 'This space is just\nfor the ';
  @override
  String get welcomeTitle2 => 'two of you';
  @override
  String get welcomeSubtitle => 'Moments, feelings, connection';
  @override
  String get welcomeFeatureMemories => 'Shared memories, photos, and notes';
  @override
  String get welcomeFeatureMood => 'Mood tracking, statuses, and daily rituals';
  @override
  String get welcomeFeatureWidgets => 'Timers, widgets, and your places map';
  @override
  String get welcomeStepCreateProfile => '1. Create your profile and sign in';
  @override
  String get welcomeStepConnectPartner =>
      '2. Connect your partner with a link, code, or QR';
  @override
  String get welcomeStepStartTogether =>
      '3. Add your first memory and personalize the space';
  @override
  String get createAccount => 'Create Account';
  @override
  String get alreadyHaveAccount => 'Already have an account';
  @override
  String get privateSecure => 'PRIVATE & SECURE';

  // ── Login ──
  @override
  String get welcomeBack => 'Welcome back!';
  @override
  String get loginToAccount => 'Sign in to your account';
  @override
  String get signInWithGoogle => 'Sign in with Google';
  @override
  String get or => 'or';
  @override
  String get email => 'Email';
  @override
  String get yourEmail => 'Your email';
  @override
  String get password => 'Password';
  @override
  String get yourPassword => 'Your password';
  @override
  String get login => 'Sign In';
  @override
  String get noAccount => 'No account? ';
  @override
  String get create => 'Create';
  @override
  String get invalidEmail => 'Enter a valid email';
  @override
  String get enterPassword => 'Enter your password';
  @override
  String get loginFailed => 'Login failed. Please try again.';
  @override
  String get profileNotFound => 'Profile not found. Please register again.';
  @override
  String get userNotFound => 'No user found with this email';
  @override
  String get wrongPassword => 'Wrong password';
  @override
  String get invalidEmailFormat => 'Invalid email format';
  @override
  String get tooManyAttempts => 'Too many attempts. Try again later';
  @override
  String get serverNotResponding =>
      'Server not responding. Check your internet.';
  @override
  String get googleNotResponding =>
      'Google not responding. Check your internet.';
  @override
  String loginError(String e) => 'Login error: $e';
  @override
  String googleLoginError(String e) => 'Google sign-in error: $e';

  // ── Setup ──
  @override
  String get whoAreYou => 'Who are you?';
  @override
  String get selectGenderForTheme => 'Select gender to customize theme';
  @override
  String get boy => 'Boy';
  @override
  String get girl => 'Girl';
  @override
  String get continueBtn => 'Continue';
  @override
  String get createProfile => 'Create your profile';
  @override
  String get signInGoogleOrManual => 'Sign in with Google or\nfill in manually';
  @override
  String get orManually => 'or manually';
  @override
  String get name => 'Name';
  @override
  String get yourName => 'Your name';
  @override
  String get minCharsPassword => 'At least 6 characters';
  @override
  String get start => 'Start';
  @override
  String get alreadyHaveAccountQuestion => 'Already have an account? ';
  @override
  String get enterYourName => 'Enter your name';
  @override
  String get enterValidEmail => 'Enter a valid email';
  @override
  String get selectGender => 'Select your gender';
  @override
  String get passwordMin6 => 'Password must be at least 6 characters';
  @override
  String get accountExists => 'Account exists';
  @override
  String get emailAlreadyRegistered =>
      'This email is already registered. Would you like to sign in?';
  @override
  String registrationError(String e) => 'Registration error: $e';
  @override
  String get agreeToTerms => 'I agree to the terms & conditions';
  @override
  String get forgotPassword => 'Forgot password?';
  @override
  String get showPassword => 'Show';
  @override
  String get hidePassword => 'Hide';
  @override
  String get min8Chars => 'Minimum 8 characters';
  @override
  String get oneUppercase => '1 uppercase';
  @override
  String get oneSpecialChar => 'At least 1 special character';
  @override
  String get fullName => 'Full Name';
  @override
  String get createAccountBtn => 'Create Account';
  @override
  String get continueWithGoogle => 'Continue with Google';
  @override
  String get continueWithApple => 'Continue with Apple';
  @override
  String get alreadyHaveAccountLogin => 'Already have an account?';
  @override
  String get passwordRequirements => 'Password requirements';

  // ── Home ──
  @override
  String get home => 'Home';
  @override
  String get widgets => 'Widgets';
  @override
  String get connect => 'Connect';
  @override
  String get profile => 'Profile';
  @override
  String get solo => 'Solo';
  @override
  String get waitingForConnection => 'WAITING FOR CONNECTION';
  @override
  String daysLabel(String suffix) => 'DAYS $suffix';
  @override
  String monthsLabel(String suffix) => 'MONTHS $suffix';
  @override
  String timeLabel(String suffix) => 'TIME $suffix';
  @override
  String get inLove => 'IN LOVE';
  @override
  String get together => 'TOGETHER';
  @override
  String get days => 'Days';
  @override
  String get months => 'Months';
  @override
  String get time => 'Time';
  @override
  String get inviteYourPartner => 'Invite Your Partner';
  @override
  String get shareLinkCodeQr => 'Share a link, code, or QR to connect';
  @override
  String get relationshipMemoryLane => 'Relationship Memory Lane';
  @override
  String get memoriesWillAppear => 'Memories will appear here';
  @override
  String get connectWithPartnerToStart => 'Connect with your partner to start';
  @override
  String partnerIsMood(String name, String mood) => '$name is $mood';
  @override
  String get answerSent => 'Answer sent!';
  @override
  String get dailyReflection => 'Daily Reflection';
  @override
  String get today => 'TODAY';
  @override
  String get answerPrompt => 'Answer Prompt';
  @override
  String get editAnswer => 'Edit Answer';
  @override
  String get clearMood => 'Clear Mood';
  @override
  String get removeMood => 'Remove Mood';
  @override
  String get howAreYouFeeling => 'How are you feeling?';
  @override
  String get partnerWillSeeMood => 'Your partner will see your mood';
  @override
  String moodDateLabel(String dateLabel) => 'Mood — $dateLabel';
  @override
  String get indicateMoodForDay => 'Indicate your mood for this day';
  @override
  String get relationshipStatus => 'Relationship Status';
  @override
  String get chooseHowToConnect => 'Choose how you want to connect';
  @override
  String get inLoveStatus => 'In Love';
  @override
  String get perfectForCouples => 'Perfect for romantic couples';
  @override
  String get married => 'Married';
  @override
  String get forMarriedPartners => 'For married partners';
  @override
  String get friends => 'Friends';
  @override
  String get connectWithBestFriend => 'Connect with your best friend';
  @override
  String get bestBuddies => 'Best Buddies';
  @override
  String get forInseparableCompanions => 'For inseparable companions';
  @override
  String get addCustomStatus => 'Add Custom Status';
  @override
  String get editCustomStatus => 'Edit Custom Status';
  @override
  String get addCaption => 'Add a caption';
  @override
  String get optionalDescribe => 'Optional — describe this moment';
  @override
  String get writeSmth => 'Write something...';
  @override
  String get skip => 'Skip';
  @override
  String get post => 'Post';
  @override
  String get posting => 'Posting...';
  @override
  String get failedUploadPhoto => 'Failed to upload photo';
  @override
  String get postedToMemoryLane => 'Posted to Memory Lane! 📸';
  @override
  String get moodCalendar => 'Mood Calendar';
  @override
  String get seeAll => 'See All';
  @override
  String get addMemory => 'Add';
  @override
  String get viewAll => 'View All';

  // ── Widget Screen ──
  @override
  String get widgetsTitle => 'Widgets';
  @override
  String get resetBtn => 'Reset';
  @override
  String get desktopPreview => 'Desktop preview';
  @override
  String get me => 'Me';
  @override
  String get partner => 'Partner';
  @override
  String get noStatus => 'No status';
  @override
  String get myWidget => 'My Widget';
  @override
  String get tapToEdit => 'Tap to edit';
  @override
  String get editBtn => 'Edit';
  @override
  String widgetOfPartner(String name) => '$name\'s Widget';
  @override
  String get emptyYet => 'Empty yet';
  @override
  String get updated => 'Updated';
  @override
  String get live => 'Live';
  @override
  String get mood => 'Mood';
  @override
  String get status => 'Status';
  @override
  String get message => 'Message';
  @override
  String get photo => 'Photo';
  @override
  String get photoUploaded => 'Photo uploaded';
  @override
  String get music => 'Music';
  @override
  String get addBtn => 'Add';
  @override
  String get widgetSettings => 'Widget Settings';
  @override
  String get photoToMemoryLane => 'Photo → Memory Lane';
  @override
  String get autoSavePhotoToMemories => 'Automatically save photos to memories';
  @override
  String get messagestoMemoryLane => 'Messages → Memory Lane';
  @override
  String get autoSaveMessages => 'Automatically save messages';
  @override
  String get musicToMemoryLane => 'Music → Memory Lane';
  @override
  String get autoSaveTracks => 'Automatically save tracks';
  @override
  String get moodToCalendar => 'Mood → Calendar';
  @override
  String get autoMarkMoodCalendar => 'Automatically mark in mood calendar';
  @override
  String get connectPartnerForWidgets =>
      'Connect a partner to start\nexchanging widgets';
  @override
  String get chooseMood => 'Choose mood';
  @override
  String get statusHint => 'What\'s new with you?';
  @override
  String get messageHint => 'Write something nice...';
  @override
  String get chooseSource => 'Choose source';
  @override
  String get camera => 'Camera';
  @override
  String get gallery => 'Gallery';
  @override
  String get musicTitle => 'Music';
  @override
  String get trackName => 'Track name';
  @override
  String get artist => 'Artist';
  @override
  String get linkOptional => 'Link (optional)';
  @override
  String get uploadingPhoto => 'Uploading photo...';
  @override
  String get resetWidget => 'Reset widget?';
  @override
  String get resetWidgetConfirm => 'All your widget data will be cleared.';
  @override
  String get notPairedWidgets => 'Widgets';
  @override
  String get notPairedWidgetsDesc =>
      'Connect a partner to start\nexchanging widgets';

  // ── Profile ──
  @override
  String get user => 'User';
  @override
  String get noEmail => 'No email';
  @override
  String get gender => 'Gender';
  @override
  String get male => 'Male';
  @override
  String get female => 'Female';
  @override
  String get information => 'INFORMATION';
  @override
  String get theme => 'Theme';
  @override
  String get relationships => 'RELATIONSHIPS';
  @override
  String get statusLabel => 'Status';
  @override
  String get partnerLabel => 'Partner';
  @override
  String get notSelected => 'Not selected';
  @override
  String daysTogetherLabel(String days) => '$days days';
  @override
  String get invitePartnerToCount =>
      'Invite a partner to start\ncounting days together ❤️';
  @override
  String get inLoveRelType => 'In Love';
  @override
  String get marriedRelType => 'Married';
  @override
  String get friendsRelType => 'Friends';
  @override
  String get bestFriendsRelType => 'Best Friends';
  @override
  String get customStatus => 'Custom Status';
  @override
  String get relationshipType => 'Relationship Type';
  @override
  String get selectPartner => 'Select Partner';
  @override
  String get noConnectedPartners => 'No connected partners';
  @override
  String get settings => 'SETTINGS';
  @override
  String get editProfile => 'Edit Profile';
  @override
  String get notifications => 'Notifications';
  @override
  String get privacy => 'Privacy';
  @override
  String get aboutApp => 'About App';
  @override
  String get supportAuthors => 'Support the Authors';
  @override
  String get logout => 'Sign Out';
  @override
  String get logoutQuestion => 'Sign Out?';
  @override
  String get logoutConfirm => 'Are you sure you want to sign out?';
  @override
  String get logoutBtn => 'Sign out';
  @override
  String get chooseColorTheme => 'Choose color theme';
  @override
  String get themeNamePink => 'Pink';
  @override
  String get themeNamePurple => 'Purple';
  @override
  String get themeNameBlue => 'Blue';
  @override
  String get themeNamePeach => 'Peach';
  @override
  String get themeNameSage => 'Sage';
  @override
  String get themeNameMidnight => 'Midnight';
  @override
  String get themeNameLavender => 'Lavender';
  @override
  String get themeNameCherry => 'Cherry';
  @override
  String get themeNameMint => 'Mint';
  @override
  String get themeNameSunset => 'Sunset';
  @override
  String get themeNameMonochrome => 'Monochrome';
  @override
  String get themeNameForest => 'Forest';
  @override
  String get themeNameOcean => 'Ocean';
  @override
  String premiumThemeLocked(int price) =>
      'Premium theme — $price coins, unlock it in the Coin shop';
  @override
  String get coinBalance => 'Coins';
  @override
  String get coinShopTitle => 'Coin Shop';
  @override
  String get coinShopSubtitle => 'Customization & treats';
  @override
  String get buyThemeTitle => 'Buy this theme?';
  @override
  String buyThemeDescription(String themeName, int price) =>
      'Unlock the "$themeName" theme for $price coins?';
  @override
  String get buyThemeConfirm => 'Buy';
  @override
  String get notEnoughCoins => 'Not enough coins';
  @override
  String get themePurchased => 'Theme unlocked';
  @override
  String get watchAdTitle => 'Watch an ad';
  @override
  String get watchAdSubtitle => 'Per view, up to 3 a day';
  @override
  String get adNotReady => 'Ad still loading — try again in a second';
  @override
  String get rewardPending => 'Crediting your reward…';
  @override
  String get coinPacksSectionTitle => 'Buy Coins';
  @override
  String coinPackTitle(int coins) => '$coins coins';
  @override
  String get coinPurchaseSuccess => 'Coins added!';
  @override
  String coinPurchaseSuccessAmount(int coins) => '+$coins coins credited';
  @override
  String get coinPurchasePending => 'Payment is being processed…';
  @override
  String get coinPurchaseCancelled => 'Purchase cancelled';
  @override
  String get coinPurchaseError => 'Purchase failed. Please try again';
  @override
  String get coinStoreUnavailable => 'Store unavailable';
  @override
  String get changesApplyImmediately => 'Changes apply immediately';
  @override
  String get dailyBonusTitle => 'Daily login';
  @override
  String get dailyBonusSubtitle => 'Every day on login';
  @override
  String coinEarned(int amount) => '+$amount coins earned!';
  @override
  String get memoryRewardTitle => 'Add a memory';
  @override
  String get memoryRewardSubtitle => 'Add a memory, once a day';
  @override
  String get partnerInviteRewardTitle => 'Invite your partner';
  @override
  String get partnerInviteRewardSubtitle => 'One-time on connection';
  @override
  String get moodStreakRewardTitle => 'Mood streak';
  @override
  String get moodStreakRewardSubtitle => 'Both filled mood 7 days in a row';
  @override
  String get earnCoinsSection => 'Earn for free';
  @override
  String get editProfileTitle => 'Edit Profile';
  @override
  String get uploading => 'Uploading...';
  @override
  String get userNotAuthorized => 'Error: user not authorized';
  @override
  String get failedUploadImage => 'Failed to upload image';
  @override
  String get avatarUpdated => 'Avatar updated';
  @override
  String get nameUpdated => 'Name updated';
  @override
  String uploadError(String e) => 'Upload error: $e';
  @override
  String get language => 'Language';
  @override
  String get selectLanguage => 'Select Language';
  @override
  String get blobAnimation => 'Blob Animation';

  // ── Mood Calendar ──
  @override
  String get moodCalendarTitle => 'Mood Calendar';
  @override
  String get zoomIn => 'Zoom In';
  @override
  String get zoomOut => 'Zoom Out';
  @override
  String get week => 'Week';
  @override
  String get month => 'Month';
  @override
  String get year => 'Year';
  @override
  String get myMood => 'My Mood';
  @override
  String partnerMood(String name) => '$name\'s Mood';
  @override
  String get moods => 'Moods';

  // ── Home (continued) ──
  @override
  String get emoji => 'Emoji';
  @override
  String get label => 'Label';
  @override
  String get egSoulmates => 'e.g., Soulmates';
  @override
  String get shareYourThoughts => 'Share your thoughts...';
  @override
  String get draw => 'Draw';
  @override
  String get calendar => 'Calendar';
  @override
  String get noMemoriesYet => 'No memories yet';

  // ── Draw Screen ──
  @override
  String get drawTogether => 'Draw Together';
  @override
  String get brush => 'Brush';
  @override
  String get eraser => 'Eraser';
  @override
  String get panTool => 'Hand';
  @override
  String get fillBg => 'Fill';
  @override
  String get rotateCanvas => 'Rotate Canvas';
  @override
  String get drawLine => 'Line';
  @override
  String get drawRect => 'Rectangle';
  @override
  String get drawCircle => 'Circle';
  @override
  String get drawTriangle => 'Triangle';
  @override
  String get fillShapes => 'Fill Shapes';
  @override
  String get insertPhoto => 'Insert Photo';
  @override
  String get photoRequiresPartner =>
      'Photo sharing is available only when drawing with a partner';
  @override
  String get photoFromGallery => 'From Gallery';
  @override
  String get photoFromCamera => 'Take Photo';
  @override
  String get undoAction => 'Undo';
  @override
  String get redoAction => 'Redo';
  @override
  String get clearCanvas => 'Clear';
  @override
  String get clearCanvasConfirm =>
      'Clear the entire canvas? This removes both users\' drawings.';
  @override
  String get deletePhoto => 'Delete photo';
  @override
  String get mascotBoyName => 'Pixel';
  @override
  String get mascotGirlName => 'Pixie';
  @override
  String get saveDrawing => 'Save';
  @override
  String get shareDrawing => 'Share';
  @override
  String drawingSavedTo(String path) => 'Drawing saved to: $path';
  @override
  String get failedToSaveDrawing => 'Failed to save drawing';
  @override
  String get failedToShareDrawing => 'Failed to share drawing';
  @override
  String get strokeThickness => 'Thickness';
  @override
  String get drawHint =>
      'Start drawing! Your partner will see your strokes in real time.';
  @override
  String partnerIsDrawing(String name) => '$name is drawing…';
  @override
  String get addFirstMemory => 'Add your first memory in Memory Lane';
  @override
  String get video => 'Video';
  @override
  String get videoLabel => 'Video';
  @override
  String get location => 'Location';
  @override
  String get audio => 'Audio';
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
  @override
  String get palmTool => 'Palm';
  @override
  String get drawingMode => 'Drawing Mode';
  @override
  String get newCanvas => 'New Canvas';
  @override
  String get myDrawings => 'My Drawings';
  @override
  String get untitledCanvas => 'Canvas';
  @override
  String get renameCanvas => 'Rename';
  @override
  String get deleteCanvas => 'Delete Canvas';
  @override
  String get deleteCanvasConfirm =>
      'Delete this canvas? This action cannot be undone.';
  @override
  String get canvasNameLabel => 'Canvas name';
  @override
  String get noDrawingsYet => 'No drawings yet';

  // ── Connect Partner ──
  @override
  String get newGroup => 'New';
  @override
  String get waiting => 'Waiting...';
  @override
  String get deleteGroupConfirm => 'Delete this group?';
  @override
  String get deleteGroupTitle => 'Delete Group';
  @override
  String get removeGroup => 'Remove';
  @override
  String get connected => 'Connected';
  @override
  String groupOf(int count) => 'Group of $count';
  @override
  String membersCount(int count) => 'MEMBERS · $count';
  @override
  String get member => 'Member';
  @override
  String get online => 'Online';
  @override
  String get offline => 'Offline';
  @override
  String get inviteMore => 'Invite More';
  @override
  String get scanQr => 'Scan QR';
  @override
  String get disconnect => 'Disconnect';
  @override
  String get connectYourPartner => 'Connect Your Partner';
  @override
  String get shareInviteCodeDesc =>
      'Share your invite code so your\npartner can join this space';
  @override
  String get yourInviteCode => 'YOUR INVITE CODE';
  @override
  String get copy => 'Copy';
  @override
  String get share => 'Share';
  @override
  String get codeCopied => 'Code copied!';
  @override
  String shareInviteText(String code, String link) =>
      'Join me on Love App! Use code: $code\n\nOr click: $link';
  @override
  String get loveAppInvitation => 'Love App Invitation';
  @override
  String get newCodeGenerated => 'New code generated';
  @override
  String get showQr => 'Show QR';
  @override
  String get haveACode => 'Have a code?';
  @override
  String get connectPartnerBtn => 'Connect Partner';
  @override
  String get inviteMoreMembers => 'Invite More Members';
  @override
  String membersOfMax(int current, int max) => '$current/$max members';
  @override
  String shareGroupInviteText(String code, String link) =>
      'Join our group on Love App! Use code: $code\n\nOr click: $link';
  @override
  String get groupInvitation => 'Love App Group Invitation';
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
  String get joinAnotherGroup => 'Join Another Group';
  @override
  String get enterCodeScanQr => 'Enter code, scan QR, or use a link';
  @override
  String get enterCode => 'Enter Code';
  @override
  String get invalidCodeTryAgain => 'Invalid code. Please check and try again.';
  @override
  String get joinGroup => 'Join Group';
  @override
  String get cantInviteSelf => "You can't invite yourself!";
  @override
  String get codeNotFound => 'Code not found or already used';
  @override
  String get scanToConnect => 'Scan to Connect';
  @override
  String get scanPartnersQr => "Scan Partner's QR Code";
  @override
  String get addNewConnection => 'Add New Connection';
  @override
  String get chooseTypeForConnection =>
      'Choose the type for your new connection';
  @override
  String get yourCustomType => 'Your custom type';
  @override
  String get newConnectionAdded => 'New connection added!';
  @override
  String get deleteConnection => 'Delete Connection?';
  @override
  String get deleteConnectionDesc =>
      'This will remove this connection permanently. If paired, it will disconnect your partner.';
  @override
  String get connectionRemoved => 'Connection removed';
  @override
  String get disconnectQuestion => 'Disconnect?';
  @override
  String get disconnectDesc =>
      'This will reset your timer and disconnect your partner.';
  @override
  String get renamePartner => 'Rename Member';
  @override
  String get renamePartnerHint =>
      'Only visible to you. This does not change the partner\'s name for them.';
  @override
  String get resetNickname => 'Reset';
  @override
  String joinMeLinkText(String link) => 'Join me on Love App! $link';
  @override
  String get custom => 'Custom';
  @override
  String membersCountBracket(int count) => 'MEMBERS ($count)';

  // ── Memory Lane ──
  @override
  String get memoryLane => 'Memory Lane';
  @override
  String get addMemoryBtn => 'Add Memory';
  @override
  String get pinned => '📌  Pinned';

  // ── Timer Card ──
  @override
  String get timers => 'Timers';
  @override
  String get failedUploadBackground =>
      'Failed to upload background. Check your connection.';

  // ── Mini Mood Calendar ──
  @override
  String get todayLabel => 'Today';

  // ── Date helpers ──
  @override
  String get todayDate => 'Today';
  @override
  String get yesterday => 'Yesterday';
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
  String get iMissYou => 'I miss you';
  @override
  String get iMissYouSent => 'Sent! 💕';
  @override
  String missYouNotifTitle(String name) => '$name misses you';
  @override
  String get missYouNotifBody => 'Thinking about you right now 💭';
  @override
  String missYouStreak(int count) => '🔥 $count';
  @override
  String get thinkingOfYou => 'Thinking of you';
  @override
  String get wantHug => 'Want a hug';
  @override
  String get vibeSent => 'Sent ✨';
  @override
  String get customVibe => 'Custom wish...';
  @override
  String get customVibeTitle => 'Custom message';
  @override
  String get customVibeHint => 'What do you want to say?';
  @override
  String thinkingOfYouNotifTitle(String name) => '$name is thinking of you 💭';
  @override
  String wantHugNotifTitle(String name) => '$name wants to hug you 🤗';
  @override
  String customVibeNotifTitle(String name) => name;

  // ── Photo Card ──
  @override
  String get sharedAPicture => 'Shared a picture';
  @override
  String kmFromYou(String km) => '$km from you';
  @override
  String get openInMaps => 'Open in maps';
  @override
  String get justNow => 'just now';
  @override
  String minutesAgo(int m) => '${m}m ago';
  @override
  String hoursAgo(int h) => '${h}h ago';
  @override
  String daysAgo(int d) => '${d}d ago';

  // ── Memory Lane Feed ──
  @override
  String get sharedAVideo => 'Shared a video';
  @override
  String get sharedAThought => 'Shared a thought';
  @override
  String get sharedALocation => 'Checked in';
  @override
  String get sharedMusic => 'Shared music';
  @override
  String get vibesTo => 'Vibes to';
  @override
  String get setARoute => 'Set a route';
  @override
  String get isListening => 'is listening';
  @override
  String get playTrack => 'Play';
  @override
  String get note => 'Note';
  @override
  String get sharedAVideoLink => 'Shared a video link';

  // ── Memory Lane (extended) ──
  @override
  String get noMemoriesYetDesc =>
      'Tap "Add Memory" to create your first\nshared memory together';
  @override
  String get unpinMemory => 'Unpin memory';
  @override
  String get pinMemory => 'Pin memory';
  @override
  String get saveToDevice => 'Save';
  @override
  String get editMemory => 'Edit memory';
  @override
  String get deleteMemory => 'Delete memory';
  @override
  String get deleteMemoryQuestion => 'Delete memory?';
  @override
  String get actionCannotBeUndone => 'This action cannot be undone.';
  @override
  String get editMemoryTitle => 'Edit Memory';
  @override
  String get titleOptional => 'Title (optional)';
  @override
  String get description => 'Description...';
  @override
  String get locationName => 'Location name...';
  @override
  String get changeLocationOnMap => 'Change Location on Map';
  @override
  String get pickLocationOnMap => 'Pick Location on Map';
  @override
  String get saveChanges => 'Save Changes';
  @override
  String get addMemoryTitle => 'Add Memory';
  @override
  String get chooseWhatToShare => 'Choose what you want to share';
  @override
  String newMemory(String type) => 'New $type';
  @override
  String get memoryDetails => 'Memory Details';
  @override
  String get writeYourNote => 'Write your note...';
  @override
  String get descriptionOptional => 'Description (optional)';
  @override
  String get locationNameHint => 'Location name (e.g. Central Park)';
  @override
  String get locationSet => 'Location set ✓';
  @override
  String get useCurrent => 'Use Current';
  @override
  String get pickOnMap => 'Pick on Map';
  @override
  String get songDetails => 'Song Details';
  @override
  String get songName => 'Song name';
  @override
  String get artistsCommaSeparated => 'Artists (comma separated)';
  @override
  String get egArtists => 'e.g. Drake, The Weeknd';
  @override
  String get source => 'Source';
  @override
  String get streamingLink => 'Streaming Link';
  @override
  String get fetched => 'Fetched';
  @override
  String get pasteLinkFromService => 'Paste link from any service...';
  @override
  String get autoFetchSongInfo => 'Auto-fetch song info from link';
  @override
  String get orDivider => 'OR';
  @override
  String get fileSelected => 'File selected ✓';
  @override
  String get pickAudioFromDevice => 'Pick audio from device';
  @override
  String get uploadingMemory => 'Uploading memory...';
  @override
  String get failedUploadPhotos =>
      'Failed to upload photos. Make sure Firebase Storage is enabled.';
  @override
  String get failedUploadVideo =>
      'Failed to upload video. Make sure Firebase Storage is enabled.';
  @override
  String get memoryAddedSuccess => 'Memory added successfully!';
  @override
  String failedAddMemory(String e) => 'Failed to add memory: $e';
  @override
  String get noMediaUrl => 'No media URL available';
  @override
  String get downloading => 'Downloading...';
  @override
  String get savedToGallery => 'Saved to gallery 🖼️';
  @override
  String savedToPath(String path) => 'Saved to $path';
  @override
  String downloadFailed(String e) => 'Download failed: $e';
  @override
  String failedSelectPhotos(String e) => 'Failed to select photos: $e';
  @override
  String failedSelectVideo(String e) => 'Failed to select video: $e';
  @override
  String get locationServicesDisabled => 'Location services are disabled';
  @override
  String get locationPermissionDenied => 'Location permission denied';
  @override
  String get failedGetLocation => 'Failed to get location';
  @override
  String get tapToSelectPhotos => 'Tap to select photos';
  @override
  String get tapToSelectVideo => 'Tap to select video';
  @override
  String get adultContent => '18+ Content';
  @override
  String get photoBlurred => 'Photo will be blurred';
  @override
  String get fromGallery => 'From gallery';
  @override
  String get byLink => 'By link';
  @override
  String get videoLink => 'Video link';
  @override
  String get fetchData => 'Fetch data';
  @override
  String get supportedPlatformsHint =>
      'Supported: YouTube, Vimeo, Dailymotion,\nTikTok, Instagram, VK and more';
  @override
  String get supportedPlatforms => 'Supported Platforms';
  @override
  String get pasteLinkSupported => 'Paste a link from any supported platform';
  @override
  String get gotIt => 'Got it';
  @override
  String get supportedServices => 'Supported Services';
  @override
  String get pasteLinkFromSupported =>
      'Paste a link from any supported service';
  @override
  String get selectTextAndPress => 'Select text and press';
  @override
  String get spoiler => 'Spoiler';
  @override
  String get deleteComment => 'Delete comment?';
  @override
  String get deleteCommentQuestion => 'Delete this comment?';
  @override
  String get comments => 'Comments';
  @override
  String get writeAComment => 'Write a comment…';
  @override
  String get noCommentsYet => 'No comments yet — be the first!';
  @override
  String nPhotos(int count) => '$count photos';
  @override
  String get noPhotoAttached => 'No photo attached';
  @override
  String get unknownLocation => 'Unknown location';
  @override
  String get openInGoogleMaps => 'Open in Google Maps';
  @override
  String get audioFile => 'Audio file';
  @override
  String get unknownTrack => 'Unknown Track';
  @override
  String get noAudioUrl => 'No audio URL';
  @override
  String get cannotPlayAudio => 'Cannot play this audio';
  @override
  String openIn(String name) => 'Open in $name';
  @override
  String get tapToOpen => 'Tap to open';
  @override
  String get videoBadge => 'VIDEO';
  @override
  String get updateAvailableTitle => 'Update available';
  @override
  String get updateAvailableSubtitle => 'A new version of the app is ready to install';
  @override
  String get updateWhatsNew => 'Improvements and bug fixes';
  @override
  String get updateButton => 'Update';
  @override
  String get updateLaterButton => 'Later';
  @override
  String get updateRestartButton => 'Restart and install';
  @override
  String get noteBadge => 'NOTE';
  @override
  String get youtubeBadge => 'YouTube';
  @override
  String get photoNotUploaded => 'Photo not uploaded yet';
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
  String get noActiveConnection => 'No active connection';
  @override
  String get chooseAStatus => 'Choose a Status';
  @override
  String get customStatuses => 'Custom Statuses';
  @override
  String get currentStatus => 'Current Status';
  @override
  String get notSet => 'Not Set';
  @override
  String get clearStatus => 'Clear Status';
  @override
  String statusSetTo(String status) => 'Status set to: $status';
  @override
  String failedSetStatus(String e) => 'Failed to set status: $e';
  @override
  String get statusCleared => 'Status cleared';
  @override
  String failedClearStatus(String e) => 'Failed to clear status: $e';
  @override
  String get customStatusAdded => 'Custom status added';
  @override
  String failedAddStatus(String e) => 'Failed to add status: $e';
  @override
  String get statusUpdated => 'Status updated';
  @override
  String failedUpdateStatus(String e) => 'Failed to update status: $e';
  @override
  String get deleteStatus => 'Delete Status';
  @override
  String deleteStatusConfirm(String label) =>
      'Are you sure you want to delete "$label"?';
  @override
  String get statusDeleted => 'Status deleted';
  @override
  String failedDeleteStatus(String e) => 'Failed to delete status: $e';
  @override
  String get editStatus => 'Edit Status';
  @override
  String get emojiLabel => 'Emoji';
  @override
  String get emojiHint => '💕';
  @override
  String get labelField => 'Label';
  @override
  String get egLivingTogether => 'e.g., Living Together';
  @override
  String get update => 'Update';

  // ── Map Picker Screen ──
  @override
  String get selectLocationOnMap => 'Select a location on the map';
  @override
  String get selectedLocation => 'Selected location';
  @override
  String get selectLocation => 'Select Location';
  @override
  String get confirm => 'Confirm';
  @override
  String get gettingAddress => 'Getting address...';
  @override
  String get tapOnMapToSelect =>
      'Tap on the map to select a different location';
  @override
  String get failedGetCurrentLocation => 'Failed to get current location';

  // ── Mood Calendar (extended) ──
  @override
  String get averageMood => 'Average Mood';
  @override
  String get great => 'Great';
  @override
  String get good => 'Good';
  @override
  String get okay => 'Okay';
  @override
  String get bad => 'Bad';
  @override
  String get awful => 'Awful';
  @override
  String get notEnoughData => 'Not enough data for chart';
  @override
  String moodRecorded(String label) => '$label recorded!';
  @override
  String get noMoodRecorded => 'No mood recorded';
  @override
  String get moodScorePrefix => 'Rating';
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
  String get noTimers => 'No timers';
  @override
  String get createTimer => 'Create Timer';
  @override
  String get editTimer => 'Edit Timer';
  @override
  String get timerNameLabel => 'NAME';
  @override
  String get egAnniversary => 'e.g. Anniversary';
  @override
  String get targetDate => 'TARGET DATE';
  @override
  String get startDate => 'START DATE';
  @override
  String get dateFormatHint => 'dd.mm.yyyy';
  @override
  String get symbolLabel => 'SYMBOL';
  @override
  String get countdownMode => 'Countdown Mode';
  @override
  String get setAsMain => 'Set as Main';
  @override
  String get saveSettings => 'SAVE SETTINGS';
  @override
  String get deleteTimerQuestion => 'Delete Timer?';
  @override
  String timerDeleteConfirm(String name) => '"$name" will be gone forever.';

  // ── Petal Timer Dial ──
  @override
  String get yearsLabel => 'Years';
  @override
  String get monthsShortLabel => 'Months';
  @override
  String get daysShortLabel => 'Days';
  @override
  String get hoursLabel => 'Hours';
  @override
  String get minLabel => 'Min';
  @override
  String get secLabel => 'Sec';

  // ── Widget Screen (extended) ──
  @override
  String get homeScreenWidgets => 'Home Screen Widgets';
  @override
  String get addToHomeScreen => 'Add to Home Screen';
  @override
  String get setAsPhotoOfDay => 'Set as Photo of the Day';
  @override
  String get widgetAddedToHome => 'Widget added to home screen';
  @override
  String failedAddWidget(String e) => 'Failed to add widget: $e';
  @override
  String get daysTogetherStat => 'Days Together';
  @override
  String get memoriesStat => 'Memories';
  @override
  String get drawingsStat => 'Drawings';
  @override
  String get missYousStat => 'Miss Yous';
  @override
  String get daysLeft => 'days left';
  @override
  String get daysElapsed => 'days elapsed';
  @override
  String get noTimersWidget => 'No timers';
  @override
  String get photoOfDay => 'Photo of the Day';
  @override
  String get mine => 'Mine';
  @override
  String get onWidget => 'On widget';
  @override
  String get randomSource => 'Random';
  @override
  String get ownPhoto => 'Own Photo';
  @override
  String get saveToMemoryLane => 'Save to Memory Lane';
  @override
  String get regenerate => 'Regenerate';
  @override
  String get none => 'None';
  @override
  String yearsAlready(int years) => '$years years already ❤️';
  @override
  String get pairWidgetTitle => 'Pair Widget';
  @override
  String get pairWidgetSubtitle => 'Mood, status, messages & photos';
  @override
  String get daysCounterSubtitle => 'Relationship day counter';
  @override
  String get timerWidgetTitle => 'Timer';
  @override
  String get timerWidgetSubtitle => 'Choose a timer for the widget';
  @override
  String get photoDayRandomSubtitle => 'Random photo from Memory Lane';
  @override
  String get photoDayCustomSubtitle => 'Custom set photo';
  @override
  String get photoDayPartnerSubtitle => 'What your partner shares';
  @override
  String get moodWidgetSubtitle => 'Horizontal widget: mine & partner\'s';
  @override
  String get relationshipStatsSubtitle =>
      'Important stats: days, photos, drawings & miss yous';
  @override
  String get daysCounterLabel => 'days';
  @override
  String get addTimerHint => 'Add a timer in the Timers section';
  @override
  String get noTimersAddHint => 'No timers. Add a timer in the Timers section.';
  @override
  String get soloTimerBannerTitle => 'You can create your own timer';
  @override
  String get soloTimerBannerSubtitle =>
      'Solo timers and their widgets are available even without adding a partner.';
  @override
  String get selectTimerForWidget => 'Select timer for widget:';
  @override
  String get daysShortLeft => 'd. left';
  @override
  String get daysShortElapsed => 'd. elapsed';
  @override
  String get partnerPhotoWillAppear =>
      'Partner\'s photo will appear\nafter they choose one';
  @override
  String get choosePhotoBelow => 'Choose a photo below';
  @override
  String get randomPhotoFromMemories => 'Random photo\nfrom memories';
  @override
  String get photoSource => 'Photo source:';
  @override
  String get fromMemories => 'from memories';
  @override
  String get fromGalleryLabel => 'from gallery';
  @override
  String get widgetModeMine => 'My photos';
  @override
  String get widgetModePartner => 'Partner photos';
  @override
  String get widgetInstances => 'Widgets on home screen';
  @override
  String get widgetNotAddedYet => 'Widget not added yet';
  @override
  String widgetSlotTitle(int index) => 'Widget ${index + 1}';
  @override
  String get addedWidgetsWillAppearHere =>
      'Added photo widgets will appear here';
  @override
  String get addSeparateWidgetHint =>
      'Add multiple widgets: each one will have its own photo and mode';
  @override
  String get widgetDisplaySource => 'What to show on widget:';
  @override
  String get widgetDisplayPhoto => 'Widget photo';
  @override
  String get noPhotoSelected => 'No photo selected';

  // ── Profile (extended) ──
  @override
  String get exportMemories => 'Export Memories';
  @override
  String get noActiveGroupForExport => 'No active group for export';
  @override
  String get creatingArchive => 'Creating archive...\nThis will take a moment.';
  @override
  String exportError(String e) => 'Error during export: $e';
  @override
  String get relationshipStats => 'RELATIONSHIP STATS';

  // ── Home Screen (extended) ──
  @override
  String get startWithBlankCanvas => 'Start with a blank canvas';
  @override
  String get openSavedDrawing => 'Open a saved drawing';
  @override
  String get newPhoto => 'New Photo';
  @override
  String get titleHint => 'Title…';
  @override
  String get descriptionOptionalHint => 'Description (optional)…';
  @override
  String get setAsWidgetPhoto => 'Set as widget photo';

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
  String get notifMissYou => '"Miss You"';
  @override
  String get notifMissYouSub => 'When your partner taps the Miss You button';
  @override
  String get notifNewMemory => 'New Memories';
  @override
  String get notifNewMemorySub => 'When your partner adds to the Memory Lane';
  @override
  String get notifMood => 'Partner Mood';
  @override
  String get notifMoodSub => 'When your partner updates their mood';
  @override
  String get openSystemSettings => 'System Settings';
  @override
  String get notifSystemSettingsHint => 'Settings are stored on this device';
  @override
  String get lockScreenMood => 'Lock Screen Mood';
  @override
  String get lockScreenMoodSubtitle => 'Mine & partner\'s on the lock screen';
  @override
  String get lockScreenMoodToggle => 'Show on lock screen';
  @override
  String get lockScreenMoodToggleSub =>
      'Mood is displayed when phone is locked';
  @override
  String get lockScreenMoodNoMood => 'No mood set';
  @override
  String get lockScreenMoodSetHint => 'Set mood in the mood calendar';
  @override
  String get photoGridWidget => 'Photo Grid';
  @override
  String get photoGridWidgetSubtitle => 'Multiple photos from memories';
  @override
  String get photoGridCount => 'Number of photos';
  @override
  String get photoGridSelectPhotos => 'Select photos';
  @override
  String get photoGridAddPhoto => 'Add photo';
  @override
  String get photoGridCountLabel => 'photos on widget';
  @override
  String get goToPin => 'Go to memory';
  @override
  String get openPhotoGallery => 'Photo gallery';
  @override
  String get allMediaGallery => 'All photos & videos';
  @override
  String get loadMore => 'Load more';
}
