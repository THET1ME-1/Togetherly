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
  String get logout;
  String get logoutQuestion;
  String get logoutConfirm;
  String get logoutBtn;
  String get chooseColorTheme;
  String get changesApplyImmediately;
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

  // ── I Miss You ──
  String get iMissYou;
  String get iMissYouSent;
  String missYouNotifTitle(String name);
  String get missYouNotifBody;
  String missYouStreak(int count);

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
  String get sharedAThought;
  String get sharedALocation;
  String get sharedMusic;
  String get vibesTo;
  String get setARoute;
  String get isListening;
  String get playTrack;
  String get note;
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
  String get changesApplyImmediately => 'Изменения применяются сразу';
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
  String get video => 'ВИДЕО';
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

  // ── I Miss You ──
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
  String get changesApplyImmediately => 'Changes apply immediately';
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
  String get video => 'VIDEO';
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

  // ── I Miss You ──
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
}
