import 'services/locale_service.dart';

import 'l10n/dict/achievements.dart';
import 'l10n/dict/ailments.dart';
import 'l10n/dict/app_icons.dart';
import 'l10n/dict/chat.dart';
import 'l10n/dict/common.dart';
import 'l10n/dict/connect_partner.dart';
import 'l10n/dict/date_helpers.dart';
import 'l10n/dict/draw_gallery_canvas.dart';
import 'l10n/dict/draw_screen.dart';
import 'l10n/dict/home.dart';
import 'l10n/dict/home_screen.dart';
import 'l10n/dict/i_miss_you_vibes.dart';
import 'l10n/dict/live_location_map.dart';
import 'l10n/dict/love_test.dart';
import 'l10n/dict/login.dart';
import 'l10n/dict/map_picker_screen.dart';
import 'l10n/dict/mascot_draw_screen.dart';
import 'l10n/dict/mascot_gallery.dart';
import 'l10n/dict/memory_lane.dart';
import 'l10n/dict/memory_lane_feed.dart';
import 'l10n/dict/mini_mood_calendar.dart';
import 'l10n/dict/mood_calendar.dart';
import 'l10n/dict/notification_settings.dart';
import 'l10n/dict/petal_timer_dial.dart';
import 'l10n/dict/photo_card.dart';
import 'l10n/dict/photo_carousel_editor.dart';
import 'l10n/dict/custom_moods.dart';
import 'l10n/dict/custom_theme.dart';
import 'l10n/dict/pair_book.dart';
import 'l10n/dict/account_email.dart';
import 'l10n/dict/mascot_source.dart';
import 'l10n/dict/memory_sort.dart';
import 'l10n/dict/plus_promo.dart';
import 'l10n/dict/moods.dart';
import 'l10n/dict/postcard_templates.dart';
import 'l10n/dict/profile.dart';
import 'l10n/dict/profile_icons.dart';
import 'l10n/dict/profile_screen.dart';
import 'l10n/dict/ranks.dart';
import 'l10n/dict/relationship_status_screen.dart';
import 'l10n/dict/setup.dart';
import 'l10n/dict/timer_card.dart';
import 'l10n/dict/timer_expandable_timer_card.dart';
import 'l10n/dict/watch_voice.dart';
import 'l10n/dict/welcome.dart';
import 'l10n/dict/widget_screen.dart';

/// Словарь интерфейса: ключ → язык → строка.
///
/// Собран из разделов `l10n/dict/`, разбивка по экранам нужна, чтобы правка
/// одного экрана не требовала лезть в файл на полторы тысячи строк.
const Map<String, Map<String, String>> kStrings = {
  ...achievementsStrings,
  ...customMoodsStrings,
  ...customThemeStrings,
  ...pairBookStrings,
  ...accountEmailStrings,
  ...mascotSourceStrings,
  ...memorySortStrings,
  ...plusPromoStrings,
  ...ailmentsStrings,
  ...appIconsStrings,
  ...chatStrings,
  ...commonStrings,
  ...connectPartnerStrings,
  ...dateHelpersStrings,
  ...drawGalleryCanvasStrings,
  ...drawScreenStrings,
  ...homeStrings,
  ...homeScreenStrings,
  ...iMissYouVibesStrings,
  ...liveLocationMapStrings,
  ...loveTestStrings,
  ...loginStrings,
  ...mapPickerScreenStrings,
  ...mascotDrawScreenStrings,
  ...mascotGalleryStrings,
  ...memoryLaneStrings,
  ...memoryLaneFeedStrings,
  ...miniMoodCalendarStrings,
  ...moodCalendarStrings,
  ...notificationSettingsStrings,
  ...petalTimerDialStrings,
  ...photoCardStrings,
  ...photoCarouselEditorStrings,
  ...moodsStrings,
  ...postcardTemplatesStrings,
  ...profileStrings,
  ...profileIconsStrings,
  ...profileScreenStrings,
  ...ranksStrings,
  ...relationshipStatusScreenStrings,
  ...setupStrings,
  ...timerCardStrings,
  ...timerExpandableTimerCardStrings,
  ...welcomeStrings,
  ...watchVoiceStrings,
  ...widgetScreenStrings,
};

/// Перевод по ключу с откатом: выбранный язык → английский → русский → ключ.
///
/// Откат тут главное: пока пять языков не наполнены, немец видит английскую
/// надпись, а не пустое место и не имя ключа.
String trDict(String key, String code) {
  final entry = kStrings[key];
  if (entry == null) return key;
  return entry[code] ?? entry['en'] ?? entry['ru'] ?? key;
}

/// Перевод по ключу на текущий язык интерфейса.
///
/// Для каталогов, которые не проходят через `AppStrings`: достижения, уровни,
/// иконки, раскраски, категории желаний. Раньше они держали пары `titleRu` и
/// `titleEn` прямо в модели и выбирали язык через `isRussian ? ru : en` — с
/// семью языками это означало английский для всех, кроме русского. Голден
/// немецкого экрана достижений показал ровно это: заголовок переведён, а сами
/// достижения английские.
String trKey(String key) => trDict(key, LocaleService.instance.language.code);

/// Реализация простых строк через словарь.
///
/// Языковые классы наследуют её и добавляют только то, что словарём не
/// выражается: методы с подстановкой, числительные и списки дат.
abstract class DictStrings extends AppStrings {
  const DictStrings(this.langCode);

  /// Код языка этой реализации — по нему берётся колонка словаря.
  final String langCode;

  String _t(String key) => trDict(key, langCode);

  @override
  String get save => _t('save');
  @override
  String get watchVoiceCall => _t('watchVoiceCall');
  @override
  String get watchVoiceHangUp => _t('watchVoiceHangUp');
  @override
  String get watchVoiceConnecting => _t('watchVoiceConnecting');
  @override
  String get watchVoiceLive => _t('watchVoiceLive');
  @override
  String get watchVoiceFailed => _t('watchVoiceFailed');
  @override
  String get watchVoiceHint => _t('watchVoiceHint');
  @override
  String get watchVoiceMic => _t('watchVoiceMic');
  @override
  String get watchVoiceSpeaker => _t('watchVoiceSpeaker');
  @override
  String get cancel => _t('cancel');
  @override
  String get delete => _t('delete');
  @override
  String get edit => _t('edit');
  @override
  String get add => _t('add');
  @override
  String get done => _t('done');
  @override
  String get loading => _t('loading');
  @override
  String get error => _t('error');
  @override
  String get ok => _t('ok');
  @override
  String get yes => _t('yes');
  @override
  String get no => _t('no');
  @override
  String get close => _t('close');
  @override
  String get back => _t('back');
  @override
  String get reset => _t('reset');
  @override
  String get clear => _t('clear');
  @override
  String get welcomeTitle1 => _t('welcomeTitle1');
  @override
  String get welcomeTitle2 => _t('welcomeTitle2');
  @override
  String get welcomeSubtitle => _t('welcomeSubtitle');
  @override
  String get welcomeFeatureMemories => _t('welcomeFeatureMemories');
  @override
  String get welcomeFeatureMood => _t('welcomeFeatureMood');
  @override
  String get welcomeFeatureWidgets => _t('welcomeFeatureWidgets');
  @override
  String get welcomeStepCreateProfile => _t('welcomeStepCreateProfile');
  @override
  String get welcomeStepConnectPartner => _t('welcomeStepConnectPartner');
  @override
  String get welcomeStepStartTogether => _t('welcomeStepStartTogether');
  @override
  String get createAccount => _t('createAccount');
  @override
  String get alreadyHaveAccount => _t('alreadyHaveAccount');
  @override
  String get privateSecure => _t('privateSecure');
  @override
  String get snapHoldToRecord => _t('snapHoldToRecord');
  @override
  String get snapRecording => _t('snapRecording');
  @override
  String get snapSending => _t('snapSending');
  @override
  String get snapSent => _t('snapSent');
  @override
  String get snapFailed => _t('snapFailed');
  @override
  String get snapNew => _t('snapNew');
  @override
  String get snapSavedToFeed => _t('snapSavedToFeed');
  @override
  String get welcomeNext => _t('welcomeNext');
  @override
  String get welcomeBack => _t('welcomeBack');
  @override
  String get loginToAccount => _t('loginToAccount');
  @override
  String get signInWithGoogle => _t('signInWithGoogle');
  @override
  String get or => _t('or');
  @override
  String get email => _t('email');
  @override
  String get yourEmail => _t('yourEmail');
  @override
  String get password => _t('password');
  @override
  String get yourPassword => _t('yourPassword');
  @override
  String get login => _t('login');
  @override
  String get noAccount => _t('noAccount');
  @override
  String get create => _t('create');
  @override
  String get invalidEmail => _t('invalidEmail');
  @override
  String get enterPassword => _t('enterPassword');
  @override
  String get loginFailed => _t('loginFailed');
  @override
  String get profileNotFound => _t('profileNotFound');
  @override
  String get userNotFound => _t('userNotFound');
  @override
  String get wrongPassword => _t('wrongPassword');
  @override
  String get invalidEmailFormat => _t('invalidEmailFormat');
  @override
  String get tooManyAttempts => _t('tooManyAttempts');
  @override
  String get serverNotResponding => _t('serverNotResponding');
  @override
  String get connectionBlocked => _t('connectionBlocked');
  @override
  String get providerUnreachable => _t('providerUnreachable');
  String get providerPageFailed => _t('providerPageFailed');

  @override
  String get retry => _t('retry');
  @override
  String get googleNotResponding => _t('googleNotResponding');
  @override
  String get whoAreYou => _t('whoAreYou');
  @override
  String get selectGenderForTheme => _t('selectGenderForTheme');
  @override
  String get boy => _t('boy');
  @override
  String get girl => _t('girl');
  @override
  String get continueBtn => _t('continueBtn');
  @override
  String get createProfile => _t('createProfile');
  @override
  String get signInGoogleOrManual => _t('signInGoogleOrManual');
  @override
  String get orManually => _t('orManually');
  @override
  String get name => _t('name');
  @override
  String get yourName => _t('yourName');
  @override
  String get minCharsPassword => _t('minCharsPassword');
  @override
  String get start => _t('start');
  @override
  String get alreadyHaveAccountQuestion => _t('alreadyHaveAccountQuestion');
  @override
  String get enterYourName => _t('enterYourName');
  @override
  String get enterValidEmail => _t('enterValidEmail');
  @override
  String get selectGender => _t('selectGender');
  @override
  String get passwordMin6 => _t('passwordMin6');
  @override
  String get accountExists => _t('accountExists');
  @override
  String get emailAlreadyRegistered => _t('emailAlreadyRegistered');
  @override
  String get agreeToTermsPrefix => _t('agreeToTermsPrefix');
  @override
  String get termsOfUse => _t('termsOfUse');
  @override
  String get agreeToTermsAnd => _t('agreeToTermsAnd');
  @override
  String get privacyPolicyLink => _t('privacyPolicyLink');
  @override
  String get forgotPassword => _t('forgotPassword');
  @override
  String get passwordResetError => _t('passwordResetError');
  @override
  String get showPassword => _t('showPassword');
  @override
  String get hidePassword => _t('hidePassword');
  @override
  String get min8Chars => _t('min8Chars');
  @override
  String get oneUppercase => _t('oneUppercase');
  @override
  String get oneSpecialChar => _t('oneSpecialChar');
  @override
  String get fullName => _t('fullName');
  @override
  String get createAccountBtn => _t('createAccountBtn');
  @override
  String get continueWithGoogle => _t('continueWithGoogle');
  @override
  String get continueWithApple => _t('continueWithApple');
  @override
  String get signInWith => _t('signInWith');
  @override
  String get signUpWith => _t('signUpWith');
  @override
  String get rememberMe => _t('rememberMe');
  @override
  String get alreadyHaveAccountLogin => _t('alreadyHaveAccountLogin');
  @override
  String get passwordRequirements => _t('passwordRequirements');
  @override
  String get home => _t('home');
  @override
  String get widgets => _t('widgets');
  @override
  String get connect => _t('connect');
  @override
  String get profile => _t('profile');
  @override
  String get solo => _t('solo');
  @override
  String get waitingForConnection => _t('waitingForConnection');
  @override
  String get inLove => _t('inLove');
  @override
  String get together => _t('together');
  @override
  String get days => _t('days');
  @override
  String get months => _t('months');
  @override
  String get time => _t('time');
  @override
  String get inviteYourPartner => _t('inviteYourPartner');
  @override
  String get shareLinkCodeQr => _t('shareLinkCodeQr');
  @override
  String get relationshipMemoryLane => _t('relationshipMemoryLane');
  @override
  String get memoriesWillAppear => _t('memoriesWillAppear');
  @override
  String get connectWithPartnerToStart => _t('connectWithPartnerToStart');
  @override
  String get answerSent => _t('answerSent');
  @override
  String get dailyReflection => _t('dailyReflection');
  @override
  String get today => _t('today');
  @override
  String get answerPrompt => _t('answerPrompt');
  @override
  String get editAnswer => _t('editAnswer');
  @override
  String get clearMood => _t('clearMood');
  @override
  String get removeMood => _t('removeMood');
  @override
  String get howAreYouFeeling => _t('howAreYouFeeling');
  @override
  String get partnerWillSeeMood => _t('partnerWillSeeMood');
  @override
  String get moodBandBright => _t('moodBandBright');
  @override
  String get moodBandEven => _t('moodBandEven');
  @override
  String get moodBandSad => _t('moodBandSad');
  @override
  String get moodBandHeavy => _t('moodBandHeavy');
  @override
  String get bookTitle => _t('bookTitle');
  @override
  String get bookLead => _t('bookLead');
  @override
  String get bookPeriodAll => _t('bookPeriodAll');
  @override
  String get bookPeriodYear => _t('bookPeriodYear');
  @override
  String get bookPeriodMonth => _t('bookPeriodMonth');
  @override
  String get bookPeriodCustom => _t('bookPeriodCustom');
  @override
  String get bookPickDates => _t('bookPickDates');
  @override
  String get bookBuild => _t('bookBuild');
  @override
  String get bookBuilding => _t('bookBuilding');
  @override
  String get bookShare => _t('bookShare');
  @override
  String get bookEmpty => _t('bookEmpty');
  @override
  String get bookTooMany => _t('bookTooMany');
  @override
  String get bookReady => _t('bookReady');
  @override
  String get bookFailed => _t('bookFailed');
  @override
  String get bookSecretHint => _t('bookSecretHint');
  @override
  String get customThemeTitle => _t('customThemeTitle');
  @override
  String get customThemeFromPhoto => _t('customThemeFromPhoto');
  @override
  String get customThemeFromPicker => _t('customThemeFromPicker');
  @override
  String get customThemePickPhoto => _t('customThemePickPhoto');
  @override
  String get customThemeAnotherPhoto => _t('customThemeAnotherPhoto');
  @override
  String get customThemePhotoHint => _t('customThemePhotoHint');
  @override
  String get customThemeNoColors => _t('customThemeNoColors');
  @override
  String get customThemeNameLabel => _t('customThemeNameLabel');
  @override
  String get customThemeNameHint => _t('customThemeNameHint');
  @override
  String get customThemeUnnamed => _t('customThemeUnnamed');
  @override
  String get customThemeFull => _t('customThemeFull');
  @override
  String get customThemeDelete => _t('customThemeDelete');
  @override
  String get customThemeEdit => _t('customThemeEdit');
  @override
  String get customThemePreview => _t('customThemePreview');
  @override
  String get plusCustomThemeTitle => _t('plusCustomThemeTitle');
  @override
  String get plusCustomThemeBody => _t('plusCustomThemeBody');
  @override
  String get plusBookTitle => _t('plusBookTitle');
  @override
  String get plusBookBody => _t('plusBookBody');

  @override
  String get customMoodBand => _t('customMoodBand');
  @override
  String get customMoodNewTile => _t('customMoodNewTile');
  @override
  String get customMoodTitle => _t('customMoodTitle');
  @override
  String get customMoodSubtitle => _t('customMoodSubtitle');
  @override
  String get customMoodSourceEmoji => _t('customMoodSourceEmoji');
  @override
  String get customMoodSourcePhoto => _t('customMoodSourcePhoto');
  @override
  String get customMoodSourceDraw => _t('customMoodSourceDraw');
  @override
  String get customMoodEmojiHint => _t('customMoodEmojiHint');
  @override
  String get customMoodLabelHint => _t('customMoodLabelHint');
  @override
  String get customMoodScoreTitle => _t('customMoodScoreTitle');
  @override
  String get customMoodScore1 => _t('customMoodScore1');
  @override
  String get customMoodScore2 => _t('customMoodScore2');
  @override
  String get customMoodScore3 => _t('customMoodScore3');
  @override
  String get customMoodScore4 => _t('customMoodScore4');
  @override
  String get customMoodScore5 => _t('customMoodScore5');
  @override
  String get customMoodSave => _t('customMoodSave');
  @override
  String get customMoodDelete => _t('customMoodDelete');
  @override
  String get customMoodDeleteHint => _t('customMoodDeleteHint');
  @override
  String get customMoodDrawTitle => _t('customMoodDrawTitle');
  @override
  String get customMoodDrawDone => _t('customMoodDrawDone');
  @override
  String get customMoodEraser => _t('customMoodEraser');
  @override
  String get customMoodUndo => _t('customMoodUndo');
  @override
  String get customMoodNeedPicture => _t('customMoodNeedPicture');
  @override
  String get customMoodNeedLabel => _t('customMoodNeedLabel');
  @override
  String get customMoodFailed => _t('customMoodFailed');
  @override
  String get customMoodLimitReached => _t('customMoodLimitReached');
  @override
  String get customMoodPlusLock => _t('customMoodPlusLock');
  @override
  String get plusPromoTitle => _t('plusPromoTitle');
  @override
  String get plusPromoBody => _t('plusPromoBody');
  @override
  String get plusPromoPerkMoods => _t('plusPromoPerkMoods');
  @override
  String get plusPromoPerkCycle => _t('plusPromoPerkCycle');
  @override
  String get plusPromoPerkStats => _t('plusPromoPerkStats');
  @override
  String get plusPromoPerkWidgets => _t('plusPromoPerkWidgets');
  @override
  String get plusPromoPerkNoAds => _t('plusPromoPerkNoAds');
  @override
  String get plusPromoOpen => _t('plusPromoOpen');
  @override
  String get plusPromoLater => _t('plusPromoLater');
  @override
  String get memorySortTitle => _t('memorySortTitle');
  @override
  String get memorySortByEvent => _t('memorySortByEvent');
  @override
  String get memorySortByEventHint => _t('memorySortByEventHint');
  @override
  String get memorySortByAdded => _t('memorySortByAdded');
  @override
  String get memorySortByAddedHint => _t('memorySortByAddedHint');
  @override
  String get mascotSourceTitle => _t('mascotSourceTitle');
  @override
  String get mascotSourceGallery => _t('mascotSourceGallery');
  @override
  String get mascotSourceGalleryHint => _t('mascotSourceGalleryHint');
  @override
  String get mascotSourceFile => _t('mascotSourceFile');
  @override
  String get mascotSourceFileHint => _t('mascotSourceFileHint');
  @override
  String get settingsAccountEmailHint => _t('settingsAccountEmailHint');
  @override
  String get accountEmailCopied => _t('accountEmailCopied');
  @override
  String get moodTabLabel => _t('moodTabLabel');
  @override
  String get ailmentTabLabel => _t('ailmentTabLabel');
  @override
  String get ailmentPickerSubtitle => _t('ailmentPickerSubtitle');
  @override
  String get clearAilment => _t('clearAilment');
  @override
  String get indicateMoodForDay => _t('indicateMoodForDay');
  @override
  String get relationshipStatus => _t('relationshipStatus');
  @override
  String get chooseHowToConnect => _t('chooseHowToConnect');
  @override
  String get inLoveStatus => _t('inLoveStatus');
  @override
  String get perfectForCouples => _t('perfectForCouples');
  @override
  String get married => _t('married');
  @override
  String get forMarriedPartners => _t('forMarriedPartners');
  @override
  String get friends => _t('friends');
  @override
  String get connectWithBestFriend => _t('connectWithBestFriend');
  @override
  String get bestBuddies => _t('bestBuddies');
  @override
  String get forInseparableCompanions => _t('forInseparableCompanions');
  @override
  String get addCustomStatus => _t('addCustomStatus');
  @override
  String get editCustomStatus => _t('editCustomStatus');
  @override
  String get addCaption => _t('addCaption');
  @override
  String get optionalDescribe => _t('optionalDescribe');
  @override
  String get writeSmth => _t('writeSmth');
  @override
  String get skip => _t('skip');
  @override
  String get post => _t('post');
  @override
  String get posting => _t('posting');
  @override
  String get failedUploadPhoto => _t('failedUploadPhoto');
  @override
  String get memoryNotSaved => _t('memoryNotSaved');
  @override
  String get achievementUnlocked => _t('achievementUnlocked');
  @override
  String get achMetricDays => _t('achMetricDays');
  @override
  String get achMetricMemories => _t('achMetricMemories');
  @override
  String get achMetricMessages => _t('achMetricMessages');
  @override
  String get achMetricDrawings => _t('achMetricDrawings');
  @override
  String get achMetricStreak => _t('achMetricStreak');
  @override
  String get achFilterAll => _t('achFilterAll');
  @override
  String get achFilterUnlocked => _t('achFilterUnlocked');
  @override
  String get achFilterInProgress => _t('achFilterInProgress');
  @override
  String get achNothingHere => _t('achNothingHere');
  @override
  String get achievementsTitle => _t('achievementsTitle');
  @override
  String get achievementsShort => _t('achievementsShort');
  @override
  String get achievementDone => _t('achievementDone');
  @override
  String get markSecret => _t('markSecret');
  @override
  String get unmarkSecret => _t('unmarkSecret');
  @override
  String get markedSecret => _t('markedSecret');
  @override
  String get unmarkedSecret => _t('unmarkedSecret');
  @override
  String get secretMemories => _t('secretMemories');
  @override
  String get enterPinTitle => _t('enterPinTitle');
  @override
  String get setPinTitle => _t('setPinTitle');
  @override
  String get setPinHint => _t('setPinHint');
  @override
  String get pinConfirmHint => _t('pinConfirmHint');
  @override
  String get pinMismatch => _t('pinMismatch');
  @override
  String get pinForgot => _t('pinForgot');
  @override
  String get pinResetTitle => _t('pinResetTitle');
  @override
  String get pinResetBody => _t('pinResetBody');
  @override
  String get wrongPin => _t('wrongPin');
  @override
  String get pinTooShort => _t('pinTooShort');
  @override
  String get pinDone => _t('pinDone');
  @override
  String get timeCapsule => _t('timeCapsule');
  @override
  String get capsuleIntro => _t('capsuleIntro');
  @override
  String get capsuleLetterHint => _t('capsuleLetterHint');
  @override
  String get capsuleAttachPhoto => _t('capsuleAttachPhoto');
  @override
  String get capsuleOpenDate => _t('capsuleOpenDate');
  @override
  String get change => _t('change');
  @override
  String get capsulePreset1m => _t('capsulePreset1m');
  @override
  String get capsulePreset6m => _t('capsulePreset6m');
  @override
  String get capsulePreset1y => _t('capsulePreset1y');
  @override
  String get capsuleSeal => _t('capsuleSeal');
  @override
  String get capsuleNeedsContent => _t('capsuleNeedsContent');
  @override
  String get capsuleNeedsFutureDate => _t('capsuleNeedsFutureDate');
  @override
  String get capsuleAddSub => _t('capsuleAddSub');
  @override
  String get capsuleCreated => _t('capsuleCreated');
  @override
  String get capsuleOpenedTitle => _t('capsuleOpenedTitle');
  @override
  String get capsuleOpenedBody => _t('capsuleOpenedBody');
  @override
  String get postedToMemoryLane => _t('postedToMemoryLane');
  @override
  String get moodCalendar => _t('moodCalendar');
  @override
  String get seeAll => _t('seeAll');
  @override
  String get addMemory => _t('addMemory');
  @override
  String get viewAll => _t('viewAll');
  @override
  String get widgetsTitle => _t('widgetsTitle');
  @override
  String get resetBtn => _t('resetBtn');
  @override
  String get desktopPreview => _t('desktopPreview');
  @override
  String get me => _t('me');
  @override
  String get partner => _t('partner');
  @override
  String get noStatus => _t('noStatus');
  @override
  String get myWidget => _t('myWidget');
  @override
  String get tapToEdit => _t('tapToEdit');
  @override
  String get editBtn => _t('editBtn');
  @override
  String get emptyYet => _t('emptyYet');
  @override
  String get updated => _t('updated');
  @override
  String get live => _t('live');
  @override
  String get mood => _t('mood');
  @override
  String get status => _t('status');
  @override
  String get message => _t('message');
  @override
  String get photo => _t('photo');
  @override
  String get photoUploaded => _t('photoUploaded');
  @override
  String get widgetPhotoOwnerOnlyHint => _t('widgetPhotoOwnerOnlyHint');
  @override
  String get music => _t('music');
  @override
  String get addBtn => _t('addBtn');
  @override
  String get widgetSettings => _t('widgetSettings');
  @override
  String get photoToMemoryLane => _t('photoToMemoryLane');
  @override
  String get autoSavePhotoToMemories => _t('autoSavePhotoToMemories');
  @override
  String get messagestoMemoryLane => _t('messagestoMemoryLane');
  @override
  String get autoSaveMessages => _t('autoSaveMessages');
  @override
  String get musicToMemoryLane => _t('musicToMemoryLane');
  @override
  String get autoSaveTracks => _t('autoSaveTracks');
  @override
  String get moodToCalendar => _t('moodToCalendar');
  @override
  String get autoMarkMoodCalendar => _t('autoMarkMoodCalendar');
  @override
  String get connectPartnerForWidgets => _t('connectPartnerForWidgets');
  @override
  String get chooseMood => _t('chooseMood');
  @override
  String get statusHint => _t('statusHint');
  @override
  String get messageHint => _t('messageHint');
  @override
  String get chooseSource => _t('chooseSource');
  @override
  String get camera => _t('camera');
  @override
  String get gallery => _t('gallery');
  @override
  String get musicTitle => _t('musicTitle');
  @override
  String get trackName => _t('trackName');
  @override
  String get artist => _t('artist');
  @override
  String get linkOptional => _t('linkOptional');
  @override
  String get uploadingPhoto => _t('uploadingPhoto');
  @override
  String get resetWidget => _t('resetWidget');
  @override
  String get resetWidgetConfirm => _t('resetWidgetConfirm');
  @override
  String get notPairedWidgets => _t('notPairedWidgets');
  @override
  String get notPairedWidgetsDesc => _t('notPairedWidgetsDesc');
  @override
  String get user => _t('user');
  @override
  String get noEmail => _t('noEmail');
  @override
  String get gender => _t('gender');
  @override
  String get male => _t('male');
  @override
  String get female => _t('female');
  @override
  String get genderPreferNotSay => _t('genderPreferNotSay');
  @override
  String get genderCustom => _t('genderCustom');
  @override
  String get genderCustomHint => _t('genderCustomHint');
  @override
  String get genderNotSet => _t('genderNotSet');
  @override
  String get information => _t('information');
  @override
  String get theme => _t('theme');
  @override
  String get relationships => _t('relationships');
  @override
  String get statusLabel => _t('statusLabel');
  @override
  String get partnerLabel => _t('partnerLabel');
  @override
  String get notSelected => _t('notSelected');
  @override
  String get invitePartnerToCount => _t('invitePartnerToCount');
  @override
  String get anniversaryDate => _t('anniversaryDate');
  @override
  String get anniversaryWheelHint => _t('anniversaryWheelHint');
  @override
  String get firstKissDate => _t('firstKissDate');
  @override
  String get myBirthday => _t('myBirthday');
  @override
  String get partnerBirthday => _t('partnerBirthday');
  @override
  String get notifCelebrations => _t('notifCelebrations');
  @override
  String get notifCelebrationsHint => _t('notifCelebrationsHint');
  @override
  String get anniversaryTodayTitle => _t('anniversaryTodayTitle');
  @override
  String get anniversaryTodayBody => _t('anniversaryTodayBody');
  @override
  String get birthdayTodayTitle => _t('birthdayTodayTitle');
  @override
  String get birthdayTodayBody => _t('birthdayTodayBody');
  @override
  String get anniversaryTomorrowTitle => _t('anniversaryTomorrowTitle');
  @override
  String get anniversaryTomorrowBody => _t('anniversaryTomorrowBody');
  @override
  String get birthdayTomorrowTitle => _t('birthdayTomorrowTitle');
  @override
  String get birthdayTomorrowBody => _t('birthdayTomorrowBody');
  @override
  String get celebrationBannerAnniversary => _t('celebrationBannerAnniversary');
  @override
  String get celebrationBannerBirthday => _t('celebrationBannerBirthday');
  @override
  String get daysUntilAnniversary => _t('daysUntilAnniversary');
  @override
  String get daysUntilBirthday => _t('daysUntilBirthday');
  @override
  String get inLoveRelType => _t('inLoveRelType');
  @override
  String get marriedRelType => _t('marriedRelType');
  @override
  String get friendsRelType => _t('friendsRelType');
  @override
  String get bestFriendsRelType => _t('bestFriendsRelType');
  @override
  String get customStatus => _t('customStatus');
  @override
  String get relationshipType => _t('relationshipType');
  @override
  String get selectPartner => _t('selectPartner');
  @override
  String get noConnectedPartners => _t('noConnectedPartners');
  @override
  String get settings => _t('settings');
  @override
  String get editProfile => _t('editProfile');
  @override
  String get notifications => _t('notifications');
  @override
  String get privacy => _t('privacy');
  @override
  String get aboutApp => _t('aboutApp');
  @override
  String get supportAuthors => _t('supportAuthors');
  @override
  String get supportIntro => _t('supportIntro');
  @override
  String get logout => _t('logout');
  @override
  String get logoutQuestion => _t('logoutQuestion');
  @override
  String get logoutConfirm => _t('logoutConfirm');
  @override
  String get logoutBtn => _t('logoutBtn');
  @override
  String get deleteAccount => _t('deleteAccount');
  @override
  String get deleteAccountQuestion => _t('deleteAccountQuestion');
  @override
  String get deleteAccountConfirm => _t('deleteAccountConfirm');
  @override
  String get deleteAccountBtn => _t('deleteAccountBtn');
  @override
  String get deleteAccountReauth => _t('deleteAccountReauth');
  @override
  String get deleteAccountError => _t('deleteAccountError');
  @override
  String get chooseColorTheme => _t('chooseColorTheme');
  @override
  String get appearanceTitle => _t('appearanceTitle');
  @override
  String get paletteLabel => _t('paletteLabel');
  @override
  String get themeModeLabel => _t('themeModeLabel');
  @override
  String get themeStyleLabel => _t('themeStyleLabel');
  @override
  String get themeModeLight => _t('themeModeLight');
  @override
  String get themeModeDark => _t('themeModeDark');
  @override
  String get themeModeSystem => _t('themeModeSystem');
  @override
  String get themeFlavorSoft => _t('themeFlavorSoft');
  @override
  String get themeFlavorJuicy => _t('themeFlavorJuicy');
  @override
  String get themeFlavorExact => _t('themeFlavorExact');
  @override
  String get amoledLabel => _t('amoledLabel');
  @override
  String get levelTasksGroup => _t('levelTasksGroup');
  @override
  String get themeNamePink => _t('themeNamePink');
  @override
  String get themeNamePurple => _t('themeNamePurple');
  @override
  String get themeNameBlue => _t('themeNameBlue');
  @override
  String get themeNamePeach => _t('themeNamePeach');
  @override
  String get themeNameSage => _t('themeNameSage');
  @override
  String get themeNameMidnight => _t('themeNameMidnight');
  @override
  String get themeNameLavender => _t('themeNameLavender');
  @override
  String get themeNameCherry => _t('themeNameCherry');
  @override
  String get themeNameMint => _t('themeNameMint');
  @override
  String get themeNameSunset => _t('themeNameSunset');
  @override
  String get themeNameMonochrome => _t('themeNameMonochrome');
  @override
  String get themeNameForest => _t('themeNameForest');
  @override
  String get themeNameOcean => _t('themeNameOcean');
  @override
  String get themeNameHoney => _t('themeNameHoney');
  @override
  String get themeNameLemon => _t('themeNameLemon');
  @override
  String get themeNameSand => _t('themeNameSand');
  @override
  String get themeNameAurora => _t('themeNameAurora');
  @override
  String get themeNameBordeaux => _t('themeNameBordeaux');
  @override
  String get themeNameTeal => _t('themeNameTeal');
  @override
  String get themeNameNord => _t('themeNameNord');
  @override
  String get themeNameCharcoalTeal => _t('themeNameCharcoalTeal');
  @override
  String get themeNameCoffee => _t('themeNameCoffee');
  @override
  String get themeNameForestDark => _t('themeNameForestDark');
  @override
  String get themeNameGarnet => _t('themeNameGarnet');
  @override
  String get themeNameDarkHoney => _t('themeNameDarkHoney');
  @override
  String get coinBalance => _t('coinBalance');
  @override
  String get coinShopTitle => _t('coinShopTitle');
  @override
  String get coinShopSubtitle => _t('coinShopSubtitle');
  @override
  String get coinEarnTitle => _t('coinEarnTitle');
  @override
  String get coinEarnSubtitle => _t('coinEarnSubtitle');
  @override
  String get buyThemeTitle => _t('buyThemeTitle');
  @override
  String get buyThemeConfirm => _t('buyThemeConfirm');
  @override
  String get notEnoughCoins => _t('notEnoughCoins');
  @override
  String get themePurchased => _t('themePurchased');
  @override
  String get iconShopTitle => _t('iconShopTitle');
  @override
  String get iconShopSubtitle => _t('iconShopSubtitle');
  @override
  String get noIconOption => _t('noIconOption');
  @override
  String get iconRewardOnly => _t('iconRewardOnly');
  @override
  String get iconRewardHint => _t('iconRewardHint');
  @override
  String get iconPurchased => _t('iconPurchased');
  @override
  String get watchAdTitle => _t('watchAdTitle');
  @override
  String get watchAdSubtitle => _t('watchAdSubtitle');
  @override
  String get adNotReady => _t('adNotReady');
  @override
  String get adRewardLimitReached => _t('adRewardLimitReached');
  @override
  String get rewardPending => _t('rewardPending');
  @override
  String get coinPacksSectionTitle => _t('coinPacksSectionTitle');
  @override
  String get coinPurchaseSuccess => _t('coinPurchaseSuccess');
  @override
  String get coinPurchasePending => _t('coinPurchasePending');
  @override
  String get coinPurchaseCancelled => _t('coinPurchaseCancelled');
  @override
  String get coinPurchaseError => _t('coinPurchaseError');
  @override
  String get coinStoreUnavailable => _t('coinStoreUnavailable');
  @override
  String get restorePurchasesTitle => _t('restorePurchasesTitle');
  @override
  String get restorePurchasesSuccess => _t('restorePurchasesSuccess');
  @override
  String get restorePurchasesError => _t('restorePurchasesError');
  @override
  String get changesApplyImmediately => _t('changesApplyImmediately');
  @override
  String get dailyBonusTitle => _t('dailyBonusTitle');
  @override
  String get dailyBonusSubtitle => _t('dailyBonusSubtitle');
  @override
  String get memoryRewardTitle => _t('memoryRewardTitle');
  @override
  String get memoryRewardSubtitle => _t('memoryRewardSubtitle');
  @override
  String get partnerInviteRewardTitle => _t('partnerInviteRewardTitle');
  @override
  String get partnerInviteRewardSubtitle => _t('partnerInviteRewardSubtitle');
  @override
  String get moodStreakRewardTitle => _t('moodStreakRewardTitle');
  @override
  String get moodStreakRewardSubtitle => _t('moodStreakRewardSubtitle');
  @override
  String get earnCoinsSection => _t('earnCoinsSection');
  @override
  String get editProfileTitle => _t('editProfileTitle');
  @override
  String get uploading => _t('uploading');
  @override
  String get userNotAuthorized => _t('userNotAuthorized');
  @override
  String get failedUploadImage => _t('failedUploadImage');
  @override
  String get avatarUpdated => _t('avatarUpdated');
  @override
  String get nameUpdated => _t('nameUpdated');
  @override
  String get language => _t('language');
  @override
  String get selectLanguage => _t('selectLanguage');
  @override
  String get blobAnimation => _t('blobAnimation');
  @override
  String get moodCalendarTitle => _t('moodCalendarTitle');
  @override
  String get moodSettings => _t('moodSettings');
  @override
  String get moodMultiplePerDay => _t('moodMultiplePerDay');
  @override
  String get moodMultiplePerDaySubtitle => _t('moodMultiplePerDaySubtitle');
  @override
  String get zoomIn => _t('zoomIn');
  @override
  String get zoomOut => _t('zoomOut');
  @override
  String get week => _t('week');
  @override
  String get month => _t('month');
  @override
  String get year => _t('year');
  @override
  String get myMood => _t('myMood');
  @override
  String get moods => _t('moods');
  @override
  String get emoji => _t('emoji');
  @override
  String get label => _t('label');
  @override
  String get egSoulmates => _t('egSoulmates');
  @override
  String get shareYourThoughts => _t('shareYourThoughts');
  @override
  String get draw => _t('draw');
  @override
  String get calendar => _t('calendar');
  @override
  String get noMemoriesYet => _t('noMemoriesYet');
  @override
  String get drawTogether => _t('drawTogether');
  @override
  String get brush => _t('brush');
  @override
  String get eraser => _t('eraser');
  @override
  String get panTool => _t('panTool');
  @override
  String get fillBg => _t('fillBg');
  @override
  String get rotateCanvas => _t('rotateCanvas');
  @override
  String get drawLine => _t('drawLine');
  @override
  String get drawRect => _t('drawRect');
  @override
  String get drawCircle => _t('drawCircle');
  @override
  String get drawTriangle => _t('drawTriangle');
  @override
  String get fillShapes => _t('fillShapes');
  @override
  String get insertPhoto => _t('insertPhoto');
  @override
  String get photoRequiresPartner => _t('photoRequiresPartner');
  @override
  String get photoFromGallery => _t('photoFromGallery');
  @override
  String get photoFromCamera => _t('photoFromCamera');
  @override
  String get undoAction => _t('undoAction');
  @override
  String get redoAction => _t('redoAction');
  @override
  String get clearCanvas => _t('clearCanvas');
  @override
  String get clearCanvasConfirm => _t('clearCanvasConfirm');
  @override
  String get deletePhoto => _t('deletePhoto');
  @override
  String get mascotBoyName => _t('mascotBoyName');
  @override
  String get mascotGirlName => _t('mascotGirlName');
  @override
  String get mascotSpikyName => _t('mascotSpikyName');
  @override
  String get mascotLuluName => _t('mascotLuluName');
  @override
  String get mascotIskrikName => _t('mascotIskrikName');
  @override
  String get mascotZhuzhaName => _t('mascotZhuzhaName');
  @override
  String get saveDrawing => _t('saveDrawing');
  @override
  String get shareDrawing => _t('shareDrawing');
  @override
  String get failedToSaveDrawing => _t('failedToSaveDrawing');
  @override
  String get failedToShareDrawing => _t('failedToShareDrawing');
  @override
  String get strokeThickness => _t('strokeThickness');
  @override
  String get drawHint => _t('drawHint');
  @override
  String get addFirstMemory => _t('addFirstMemory');
  @override
  String get video => _t('video');
  @override
  String get videoLabel => _t('videoLabel');
  @override
  String get location => _t('location');
  @override
  String get audio => _t('audio');
  @override
  String get palmTool => _t('palmTool');
  @override
  String get drawingMode => _t('drawingMode');
  @override
  String get newCanvas => _t('newCanvas');
  @override
  String get myDrawings => _t('myDrawings');
  @override
  String get untitledCanvas => _t('untitledCanvas');
  @override
  String get renameCanvas => _t('renameCanvas');
  @override
  String get deleteCanvas => _t('deleteCanvas');
  @override
  String get deleteCanvasConfirm => _t('deleteCanvasConfirm');
  @override
  String get canvasNameLabel => _t('canvasNameLabel');
  @override
  String get noDrawingsYet => _t('noDrawingsYet');
  @override
  String get newGroup => _t('newGroup');
  @override
  String get waiting => _t('waiting');
  @override
  String get deleteGroupConfirm => _t('deleteGroupConfirm');
  @override
  String get deleteGroupTitle => _t('deleteGroupTitle');
  @override
  String get removeGroup => _t('removeGroup');
  @override
  String get connected => _t('connected');
  @override
  String get member => _t('member');
  @override
  String get online => _t('online');
  @override
  String get offline => _t('offline');
  @override
  String get chatOnline => _t('chatOnline');
  @override
  String get chatTypingShort => _t('chatTypingShort');
  @override
  String get inviteMore => _t('inviteMore');
  @override
  String get scanQr => _t('scanQr');
  @override
  String get disconnect => _t('disconnect');
  @override
  String get connectYourPartner => _t('connectYourPartner');
  @override
  String get shareInviteCodeDesc => _t('shareInviteCodeDesc');
  @override
  String get yourInviteCode => _t('yourInviteCode');
  @override
  String get copy => _t('copy');
  @override
  String get share => _t('share');
  @override
  String get codeCopied => _t('codeCopied');
  @override
  String get loveAppInvitation => _t('loveAppInvitation');
  @override
  String get newCodeGenerated => _t('newCodeGenerated');
  @override
  String get showQr => _t('showQr');
  @override
  String get haveACode => _t('haveACode');
  @override
  String get inviteHeroTitle => _t('inviteHeroTitle');
  @override
  String get inviteHeroBody => _t('inviteHeroBody');
  @override
  String get sendInvitation => _t('sendInvitation');
  @override
  String get haveCode => _t('haveCode');
  @override
  String get staySolo => _t('staySolo');
  @override
  String get later => _t('later');
  @override
  String get tapToCopy => _t('tapToCopy');
  @override
  String get inviteCodeLoading => _t('inviteCodeLoading');
  @override
  String get inviteQrTitle => _t('inviteQrTitle');
  @override
  String get inviteQrHint => _t('inviteQrHint');
  @override
  String get enterPartnerCode => _t('enterPartnerCode');
  @override
  String get inviteCodeNotFound => _t('inviteCodeNotFound');
  @override
  String get onboardingTitle => _t('onboardingTitle');
  @override
  String get onboardingDone => _t('onboardingDone');
  @override
  String get onboardingStepPhoto => _t('onboardingStepPhoto');
  @override
  String get onboardingStepMood => _t('onboardingStepMood');
  @override
  String get onboardingStepWidget => _t('onboardingStepWidget');
  @override
  String get onboardingSkip => _t('onboardingSkip');
  @override
  String get chatEmptyTitle => _t('chatEmptyTitle');
  @override
  String get chatEmptyBody => _t('chatEmptyBody');
  @override
  String get chatEmptyGhostTheirs => _t('chatEmptyGhostTheirs');
  @override
  String get chatEmptyGhostMine => _t('chatEmptyGhostMine');
  @override
  String get chatPinTooltip => _t('chatPinTooltip');
  @override
  String get chatStyleTooltip => _t('chatStyleTooltip');
  @override
  String get chatLookMaterial => _t('chatLookMaterial');
  @override
  String get chatLookCozy => _t('chatLookCozy');
  @override
  String get chatLookMaterialOn => _t('chatLookMaterialOn');
  @override
  String get chatLookCozyOn => _t('chatLookCozyOn');
  @override
  String get titleFieldHint => _t('titleFieldHint');
  @override
  String get symbolPickerTitle => _t('symbolPickerTitle');
  @override
  String get symbolPickerAll => _t('symbolPickerAll');
  @override
  String get countdownModeHint => _t('countdownModeHint');
  @override
  String get setAsMainHint => _t('setAsMainHint');
  @override
  String get symbolSearchHint => _t('symbolSearchHint');
  @override
  String get symbolSearchEmpty => _t('symbolSearchEmpty');
  @override
  String get symbolSetHint => _t('symbolSetHint');
  @override
  String get symbolSetLove => _t('symbolSetLove');
  @override
  String get symbolSetHolidays => _t('symbolSetHolidays');
  @override
  String get symbolSetHome => _t('symbolSetHome');
  @override
  String get symbolSetRoad => _t('symbolSetRoad');
  @override
  String get symbolSetWork => _t('symbolSetWork');
  @override
  String get chatBgPlain => _t('chatBgPlain');
  @override
  String get chatBgDawn => _t('chatBgDawn');
  @override
  String get chatBgHearts => _t('chatBgHearts');
  @override
  String get chatBgWeave => _t('chatBgWeave');
  @override
  String get chatBgDots => _t('chatBgDots');
  @override
  String get chatBgBubbles => _t('chatBgBubbles');
  @override
  String get chatBgNight => _t('chatBgNight');
  @override
  String get needsPartnerHint => _t('needsPartnerHint');
  @override
  String get inviteReminderTitle => _t('inviteReminderTitle');
  @override
  String get inviteReminderBody => _t('inviteReminderBody');
  @override
  String get invitePromptTitle => _t('invitePromptTitle');
  @override
  String get invitePromptBody => _t('invitePromptBody');
  @override
  String get invitePromptAction => _t('invitePromptAction');
  @override
  String get quietPartnerBody => _t('quietPartnerBody');
  @override
  String get quietPartnerAction => _t('quietPartnerAction');
  @override
  String get quietPartnerSent => _t('quietPartnerSent');
  @override
  String get connectPartnerBtn => _t('connectPartnerBtn');
  @override
  String get inviteMoreMembers => _t('inviteMoreMembers');
  @override
  String get groupInvitation => _t('groupInvitation');
  @override
  String get joinAnotherGroup => _t('joinAnotherGroup');
  @override
  String get enterCodeScanQr => _t('enterCodeScanQr');
  @override
  String get enterCode => _t('enterCode');
  @override
  String get invalidCodeTryAgain => _t('invalidCodeTryAgain');
  @override
  String get joinGroup => _t('joinGroup');
  @override
  String get cantInviteSelf => _t('cantInviteSelf');
  @override
  String get codeNotFound => _t('codeNotFound');
  @override
  String get scanToConnect => _t('scanToConnect');
  @override
  String get scanPartnersQr => _t('scanPartnersQr');
  @override
  String get qrPointAtCode => _t('qrPointAtCode');
  @override
  String get qrScannerUnavailable => _t('qrScannerUnavailable');
  @override
  String get qrScannerUnavailableHint => _t('qrScannerUnavailableHint');
  @override
  String get qrEnterCodeManually => _t('qrEnterCodeManually');
  @override
  String get addNewConnection => _t('addNewConnection');
  @override
  String get chooseTypeForConnection => _t('chooseTypeForConnection');
  @override
  String get yourCustomType => _t('yourCustomType');
  @override
  String get newConnectionAdded => _t('newConnectionAdded');
  @override
  String get deleteConnection => _t('deleteConnection');
  @override
  String get deleteConnectionAction => _t('deleteConnectionAction');
  @override
  String get deleteConnectionWith => _t('deleteConnectionWith');
  @override
  String get deleteConnectionDesc => _t('deleteConnectionDesc');
  @override
  String get connectionRemoved => _t('connectionRemoved');
  @override
  String get disconnectQuestion => _t('disconnectQuestion');
  @override
  String get disconnectDesc => _t('disconnectDesc');
  @override
  String get renamePartner => _t('renamePartner');
  @override
  String get renamePartnerHint => _t('renamePartnerHint');
  @override
  String get resetNickname => _t('resetNickname');
  @override
  String get custom => _t('custom');
  @override
  String get memoryLane => _t('memoryLane');
  @override
  String get addMemoryBtn => _t('addMemoryBtn');
  @override
  String get addMemoryToFeed => _t('addMemoryToFeed');
  @override
  String get pinned => _t('pinned');
  @override
  String get timers => _t('timers');
  @override
  String get failedUploadBackground => _t('failedUploadBackground');
  @override
  String get todayLabel => _t('todayLabel');

  @override
  String get moodYearNoMark => _t('moodYearNoMark');
  @override
  String get moodYearWorse => _t('moodYearWorse');
  @override
  String get moodYearBetter => _t('moodYearBetter');
  @override
  String get moodYearEmpty => _t('moodYearEmpty');
  @override
  String moodYearAverage(String avg) =>
      _t('moodYearAverage').replaceAll('{avg}', avg);
  @override
  String moodYearMissing(int days) =>
      _t('moodYearMissing').replaceAll('{days}', tgDaysMilestone(days));
  @override
  String get todayDate => _t('todayDate');
  @override
  String get yesterday => _t('yesterday');
  @override
  String get iMissYou => _t('iMissYou');
  @override
  String get iMissYouSent => _t('iMissYouSent');
  @override
  String get missYouNotifBody => _t('missYouNotifBody');
  @override
  String get thinkingOfYou => _t('thinkingOfYou');
  @override
  String get wantHug => _t('wantHug');
  @override
  String get vibeSent => _t('vibeSent');
  @override
  String get customVibe => _t('customVibe');
  @override
  String get customVibeTitle => _t('customVibeTitle');
  @override
  String get customVibeHint => _t('customVibeHint');
  @override
  String get missYouTitle => _t('missYouTitle');
  @override
  String get missYouSendHint => _t('missYouSendHint');
  @override
  String get missYouYou => _t('missYouYou');
  @override
  String get missYouPartner => _t('missYouPartner');
  @override
  String get missYouMore => _t('missYouMore');
  @override
  String get missYouLatest => _t('missYouLatest');
  @override
  String get missYouReplyBack => _t('missYouReplyBack');
  @override
  String get missYouWeekTitle => _t('missYouWeekTitle');
  @override
  String get missYouWeekEmpty => _t('missYouWeekEmpty');
  @override
  String get missYouWishRemoved => _t('missYouWishRemoved');
  @override
  String get sharedAPicture => _t('sharedAPicture');
  @override
  String get openInMaps => _t('openInMaps');
  @override
  String get justNow => _t('justNow');
  @override
  String get sharedAVideo => _t('sharedAVideo');
  @override
  String get sharedAVideoLink => _t('sharedAVideoLink');
  @override
  String get sharedAThought => _t('sharedAThought');
  @override
  String get sharedALocation => _t('sharedALocation');
  @override
  String get sharedMusic => _t('sharedMusic');
  @override
  String get vibesTo => _t('vibesTo');
  @override
  String get setARoute => _t('setARoute');
  @override
  String get isListening => _t('isListening');
  @override
  String get playTrack => _t('playTrack');
  @override
  String get note => _t('note');
  @override
  String get noMemoriesYetDesc => _t('noMemoriesYetDesc');
  @override
  String get unpinMemory => _t('unpinMemory');
  @override
  String get pinMemory => _t('pinMemory');
  @override
  String get saveToDevice => _t('saveToDevice');
  @override
  String get editMemory => _t('editMemory');
  @override
  String get deleteMemory => _t('deleteMemory');
  @override
  String get deleteMemoryQuestion => _t('deleteMemoryQuestion');
  @override
  String get actionCannotBeUndone => _t('actionCannotBeUndone');
  @override
  String get editMemoryTitle => _t('editMemoryTitle');
  @override
  String get titleOptional => _t('titleOptional');
  @override
  String get description => _t('description');
  @override
  String get locationName => _t('locationName');
  @override
  String get changeLocationOnMap => _t('changeLocationOnMap');
  @override
  String get pickLocationOnMap => _t('pickLocationOnMap');
  @override
  String get saveChanges => _t('saveChanges');
  @override
  String get addMemoryTitle => _t('addMemoryTitle');
  @override
  String get chooseWhatToShare => _t('chooseWhatToShare');
  @override
  String get memoryDetails => _t('memoryDetails');
  @override
  String get writeYourNote => _t('writeYourNote');
  @override
  String get descriptionOptional => _t('descriptionOptional');
  @override
  String get locationNameHint => _t('locationNameHint');
  @override
  String get locationSet => _t('locationSet');
  @override
  String get useCurrent => _t('useCurrent');
  @override
  String get pickOnMap => _t('pickOnMap');
  @override
  String get songDetails => _t('songDetails');
  @override
  String get songName => _t('songName');
  @override
  String get artistsCommaSeparated => _t('artistsCommaSeparated');
  @override
  String get egArtists => _t('egArtists');
  @override
  String get source => _t('source');
  @override
  String get streamingLink => _t('streamingLink');
  @override
  String get fetched => _t('fetched');
  @override
  String get pasteLinkFromService => _t('pasteLinkFromService');
  @override
  String get autoFetchSongInfo => _t('autoFetchSongInfo');
  @override
  String get musicMetaNotFound => _t('musicMetaNotFound');
  @override
  String get orDivider => _t('orDivider');
  @override
  String get fileSelected => _t('fileSelected');
  @override
  String get pickAudioFromDevice => _t('pickAudioFromDevice');
  @override
  String get uploadingMemory => _t('uploadingMemory');
  @override
  String get failedUploadPhotos => _t('failedUploadPhotos');
  @override
  String get failedUploadVideo => _t('failedUploadVideo');
  @override
  String get memoryAddedSuccess => _t('memoryAddedSuccess');
  @override
  String get noMediaUrl => _t('noMediaUrl');
  @override
  String get downloading => _t('downloading');
  @override
  String get savedToGallery => _t('savedToGallery');
  @override
  String get locationServicesDisabled => _t('locationServicesDisabled');
  @override
  String get locationPermissionDenied => _t('locationPermissionDenied');
  @override
  String get cameraPermissionDenied => _t('cameraPermissionDenied');
  @override
  String get failedGetLocation => _t('failedGetLocation');
  @override
  String get tapToSelectPhotos => _t('tapToSelectPhotos');
  @override
  String get tapToSelectVideo => _t('tapToSelectVideo');
  @override
  String get adultContent => _t('adultContent');
  @override
  String get photoBlurred => _t('photoBlurred');
  @override
  String get fromGallery => _t('fromGallery');
  @override
  String get byLink => _t('byLink');
  @override
  String get videoLink => _t('videoLink');
  @override
  String get books => _t('books');
  @override
  String get bookSearchHint => _t('bookSearchHint');
  @override
  String get searchBooksPrompt => _t('searchBooksPrompt');
  @override
  String get noBooksFound => _t('noBooksFound');
  @override
  String get bookSearchFailed => _t('bookSearchFailed');
  @override
  String get bookSearchFailedHint => _t('bookSearchFailedHint');
  @override
  String get bookEnterManually => _t('bookEnterManually');
  @override
  String get bookManualEntryHint => _t('bookManualEntryHint');
  @override
  String get sharedABook => _t('sharedABook');
  @override
  String get bookAuthorLabel => _t('bookAuthorLabel');
  @override
  String get bookAuthorHint => _t('bookAuthorHint');
  @override
  String get bookTitleHint => _t('bookTitleHint');
  @override
  String get bookDetails => _t('bookDetails');
  @override
  String get bookReadMore => _t('bookReadMore');
  @override
  String get bookSearchAgain => _t('bookSearchAgain');
  @override
  String get movies => _t('movies');
  @override
  String get movieSearchHint => _t('movieSearchHint');
  @override
  String get searchMoviesPrompt => _t('searchMoviesPrompt');
  @override
  String get noMoviesFound => _t('noMoviesFound');
  @override
  String get movieSearchFailed => _t('movieSearchFailed');
  @override
  String get movieSearchFailedHint => _t('movieSearchFailedHint');
  @override
  String get movieEnterManually => _t('movieEnterManually');
  @override
  String get movieManualEntryHint => _t('movieManualEntryHint');
  @override
  String get movieNoToken => _t('movieNoToken');
  @override
  String get sharedAMovie => _t('sharedAMovie');
  @override
  String get movieTitleHint => _t('movieTitleHint');
  @override
  String get movieOriginalTitleHint => _t('movieOriginalTitleHint');
  @override
  String get movieDetails => _t('movieDetails');
  @override
  String get movieReadMore => _t('movieReadMore');
  @override
  String get movieSearchAgain => _t('movieSearchAgain');
  @override
  String get yourRating => _t('yourRating');
  @override
  String get ratingNotRated => _t('ratingNotRated');
  @override
  String get ratingHint => _t('ratingHint');
  @override
  String get ratingMasterpiece => _t('ratingMasterpiece');
  @override
  String get ratingExcellent => _t('ratingExcellent');
  @override
  String get ratingGood => _t('ratingGood');
  @override
  String get ratingMixed => _t('ratingMixed');
  @override
  String get ratingBad => _t('ratingBad');
  @override
  String get ratingAwful => _t('ratingAwful');
  @override
  String get yourReview => _t('yourReview');
  @override
  String get reviewHint => _t('reviewHint');
  @override
  String get memoryDateLabel => _t('memoryDateLabel');
  @override
  String get memoryDateNow => _t('memoryDateNow');
  @override
  String get dateNowLabel => _t('dateNowLabel');
  @override
  String get memoryDatePickDate => _t('memoryDatePickDate');
  @override
  String get memoryDatePickTime => _t('memoryDatePickTime');
  @override
  String get memoryDateClear => _t('memoryDateClear');
  @override
  String get fetchData => _t('fetchData');
  @override
  String get supportedPlatformsHint => _t('supportedPlatformsHint');
  @override
  String get supportedPlatforms => _t('supportedPlatforms');
  @override
  String get pasteLinkSupported => _t('pasteLinkSupported');
  @override
  String get gotIt => _t('gotIt');
  @override
  String get sideActionTitle => _t('sideActionTitle');
  @override
  String get sideActionOpenFeed => _t('sideActionOpenFeed');
  @override
  String get sideActionCreatePin => _t('sideActionCreatePin');
  @override
  String get sideActionHint => _t('sideActionHint');

  @override
  String get snapHoldHint => _t('snapHoldHint');

  @override
  String get missScreenHint => _t('missScreenHint');
  @override
  String get supportedServices => _t('supportedServices');
  @override
  String get pasteLinkFromSupported => _t('pasteLinkFromSupported');
  @override
  String get selectTextAndPress => _t('selectTextAndPress');
  @override
  String get spoiler => _t('spoiler');
  @override
  String get deleteComment => _t('deleteComment');
  @override
  String get deleteCommentQuestion => _t('deleteCommentQuestion');
  @override
  String get comments => _t('comments');
  @override
  String get writeAComment => _t('writeAComment');
  @override
  String get noCommentsYet => _t('noCommentsYet');
  @override
  String get noPhotoAttached => _t('noPhotoAttached');
  @override
  String get unknownLocation => _t('unknownLocation');
  @override
  String get openInGoogleMaps => _t('openInGoogleMaps');
  @override
  String get audioFile => _t('audioFile');
  @override
  String get unknownTrack => _t('unknownTrack');
  @override
  String get noAudioUrl => _t('noAudioUrl');
  @override
  String get cannotPlayAudio => _t('cannotPlayAudio');
  @override
  String get tapToOpen => _t('tapToOpen');
  @override
  String get videoBadge => _t('videoBadge');
  @override
  String get updateAvailableTitle => _t('updateAvailableTitle');
  @override
  String get updateAvailableSubtitle => _t('updateAvailableSubtitle');
  @override
  String get updateButton => _t('updateButton');
  @override
  String get updateLaterButton => _t('updateLaterButton');
  @override
  String get updateRestartButton => _t('updateRestartButton');
  @override
  String get forceUpdateTitle => _t('forceUpdateTitle');
  @override
  String get forceUpdateBody => _t('forceUpdateBody');
  @override
  String get forceUpdateButton => _t('forceUpdateButton');
  @override
  String get noteBadge => _t('noteBadge');
  @override
  String get youtubeBadge => _t('youtubeBadge');
  @override
  String get photoNotUploaded => _t('photoNotUploaded');
  @override
  String get noActiveConnection => _t('noActiveConnection');
  @override
  String get chooseAStatus => _t('chooseAStatus');
  @override
  String get customStatuses => _t('customStatuses');
  @override
  String get currentStatus => _t('currentStatus');
  @override
  String get notSet => _t('notSet');
  @override
  String get clearStatus => _t('clearStatus');
  @override
  String get statusCleared => _t('statusCleared');
  @override
  String get customStatusAdded => _t('customStatusAdded');
  @override
  String get statusUpdated => _t('statusUpdated');
  @override
  String get deleteStatus => _t('deleteStatus');
  @override
  String get statusDeleted => _t('statusDeleted');
  @override
  String get editStatus => _t('editStatus');
  @override
  String get emojiLabel => _t('emojiLabel');
  @override
  String get emojiHint => _t('emojiHint');
  @override
  String get labelField => _t('labelField');
  @override
  String get egLivingTogether => _t('egLivingTogether');
  @override
  String get update => _t('update');
  @override
  String get selectLocationOnMap => _t('selectLocationOnMap');
  @override
  String get selectedLocation => _t('selectedLocation');
  @override
  String get selectLocation => _t('selectLocation');
  @override
  String get confirm => _t('confirm');
  @override
  String get gettingAddress => _t('gettingAddress');
  @override
  String get tapOnMapToSelect => _t('tapOnMapToSelect');
  @override
  String get failedGetCurrentLocation => _t('failedGetCurrentLocation');
  @override
  String get averageMood => _t('averageMood');
  @override
  String get great => _t('great');
  @override
  String get good => _t('good');
  @override
  String get okay => _t('okay');
  @override
  String get bad => _t('bad');
  @override
  String get awful => _t('awful');
  @override
  String get notEnoughData => _t('notEnoughData');
  @override
  String get noMoodRecorded => _t('noMoodRecorded');
  @override
  String get moodScorePrefix => _t('moodScorePrefix');
  @override
  String get noTimers => _t('noTimers');
  @override
  String get createTimer => _t('createTimer');
  @override
  String get editTimer => _t('editTimer');
  @override
  String get timerNameLabel => _t('timerNameLabel');
  @override
  String get egAnniversary => _t('egAnniversary');
  @override
  String get targetDate => _t('targetDate');
  @override
  String get startDate => _t('startDate');
  @override
  String get dateFormatHint => _t('dateFormatHint');
  @override
  String get symbolLabel => _t('symbolLabel');
  @override
  String get countdownMode => _t('countdownMode');
  @override
  String get countdownPastDateWarning => _t('countdownPastDateWarning');
  @override
  String get setAsMain => _t('setAsMain');
  @override
  String get saveSettings => _t('saveSettings');
  @override
  String get deleteTimerQuestion => _t('deleteTimerQuestion');
  @override
  String get yearsLabel => _t('yearsLabel');
  @override
  String get monthsShortLabel => _t('monthsShortLabel');
  @override
  String get daysShortLabel => _t('daysShortLabel');
  @override
  String get hoursLabel => _t('hoursLabel');
  @override
  String get minLabel => _t('minLabel');
  @override
  String get secLabel => _t('secLabel');
  @override
  String get homeScreenWidgets => _t('homeScreenWidgets');
  @override
  String get addToHomeScreen => _t('addToHomeScreen');
  @override
  String get addWidgetFromHomeHint => _t('addWidgetFromHomeHint');
  @override
  String get iosWidgetsNeedIos17 => _t('iosWidgetsNeedIos17');
  @override
  String get setAsPhotoOfDay => _t('setAsPhotoOfDay');
  @override
  String get widgetAddedToHome => _t('widgetAddedToHome');
  @override
  String get daysTogetherStat => _t('daysTogetherStat');
  @override
  String get memoriesStat => _t('memoriesStat');
  @override
  String get drawingsStat => _t('drawingsStat');
  @override
  String get missYousStat => _t('missYousStat');
  @override
  String get daysLeft => _t('daysLeft');
  @override
  String get daysElapsed => _t('daysElapsed');
  @override
  String get noTimersWidget => _t('noTimersWidget');
  @override
  String get photoOfDay => _t('photoOfDay');
  @override
  String get mine => _t('mine');
  @override
  String get onWidget => _t('onWidget');
  @override
  String get randomSource => _t('randomSource');
  @override
  String get ownPhoto => _t('ownPhoto');
  @override
  String get saveToMemoryLane => _t('saveToMemoryLane');
  @override
  String get regenerate => _t('regenerate');
  @override
  String get none => _t('none');
  @override
  String get pairWidgetTitle => _t('pairWidgetTitle');
  @override
  String get pairWidgetSubtitle => _t('pairWidgetSubtitle');
  @override
  String get daysCounterSubtitle => _t('daysCounterSubtitle');
  @override
  String get timerWidgetTitle => _t('timerWidgetTitle');
  @override
  String get timerWidgetSubtitle => _t('timerWidgetSubtitle');
  @override
  String get photoDayRandomSubtitle => _t('photoDayRandomSubtitle');
  @override
  String get photoDayCustomSubtitle => _t('photoDayCustomSubtitle');
  @override
  String get photoDayPartnerSubtitle => _t('photoDayPartnerSubtitle');
  @override
  String get moodWidgetSubtitle => _t('moodWidgetSubtitle');
  @override
  String get relationshipStatsSubtitle => _t('relationshipStatsSubtitle');
  @override
  String get daysCounterLabel => _t('daysCounterLabel');
  @override
  String get addTimerHint => _t('addTimerHint');
  @override
  String get noTimersAddHint => _t('noTimersAddHint');
  @override
  String get soloTimerBannerTitle => _t('soloTimerBannerTitle');
  @override
  String get soloTimerBannerSubtitle => _t('soloTimerBannerSubtitle');
  @override
  String get selectTimerForWidget => _t('selectTimerForWidget');
  @override
  String get daysShortLeft => _t('daysShortLeft');
  @override
  String get daysShortElapsed => _t('daysShortElapsed');
  @override
  String get partnerPhotoWillAppear => _t('partnerPhotoWillAppear');
  @override
  String get choosePhotoBelow => _t('choosePhotoBelow');
  @override
  String get randomPhotoFromMemories => _t('randomPhotoFromMemories');
  @override
  String get photoSource => _t('photoSource');
  @override
  String get fromMemories => _t('fromMemories');
  @override
  String get fromGalleryLabel => _t('fromGalleryLabel');
  @override
  String get widgetModeMine => _t('widgetModeMine');
  @override
  String get widgetModePartner => _t('widgetModePartner');
  @override
  String get widgetInstances => _t('widgetInstances');
  @override
  String get widgetNotAddedYet => _t('widgetNotAddedYet');
  @override
  String get addedWidgetsWillAppearHere => _t('addedWidgetsWillAppearHere');
  @override
  String get addSeparateWidgetHint => _t('addSeparateWidgetHint');
  @override
  String get widgetDisplaySource => _t('widgetDisplaySource');
  @override
  String get widgetDisplayPhoto => _t('widgetDisplayPhoto');
  @override
  String get noPhotoSelected => _t('noPhotoSelected');
  @override
  String get cycleConsentTitle => _t('cycleConsentTitle');
  @override
  String get resetMissYouCount => _t('resetMissYouCount');
  @override
  String get resetMissYouConfirmTitle => _t('resetMissYouConfirmTitle');
  @override
  String get resetMissYouConfirmBody => _t('resetMissYouConfirmBody');
  @override
  String get noActiveGroupForExport => _t('noActiveGroupForExport');
  @override
  String get creatingArchive => _t('creatingArchive');
  @override
  String get relationshipStats => _t('relationshipStats');
  @override
  String get startWithBlankCanvas => _t('startWithBlankCanvas');
  @override
  String get openSavedDrawing => _t('openSavedDrawing');
  @override
  String get newPhoto => _t('newPhoto');
  @override
  String get titleHint => _t('titleHint');
  @override
  String get descriptionOptionalHint => _t('descriptionOptionalHint');
  @override
  String get setAsWidgetPhoto => _t('setAsWidgetPhoto');
  @override
  String get notifMissYou => _t('notifMissYou');
  @override
  String get notifMissYouSub => _t('notifMissYouSub');
  @override
  String get notifNewMemory => _t('notifNewMemory');
  @override
  String get notifNewMemorySub => _t('notifNewMemorySub');
  @override
  String get notifMood => _t('notifMood');
  @override
  String get notifMoodSub => _t('notifMoodSub');
  @override
  String get notifChat => _t('notifChat');
  @override
  String get notifChatSub => _t('notifChatSub');
  @override
  String get notifDrawInvite => _t('notifDrawInvite');
  @override
  String get notifComments => _t('notifComments');
  @override
  String get notifCommentsSub => _t('notifCommentsSub');
  @override
  String get notifDrawInviteSub => _t('notifDrawInviteSub');
  @override
  String get notifDaysTogether => _t('notifDaysTogether');
  @override
  String get notifDaysTogetherSub => _t('notifDaysTogetherSub');
  @override
  String get notifDaysTogetherSubIos => _t('notifDaysTogetherSubIos');
  @override
  String get adLabel => _t('adLabel');
  @override
  String get daysTogetherNotifTagline => _t('daysTogetherNotifTagline');
  @override
  String get openSystemSettings => _t('openSystemSettings');
  @override
  String get notifSystemSettingsHint => _t('notifSystemSettingsHint');
  @override
  String get chatTitle => _t('chatTitle');
  @override
  String get chatHint => _t('chatHint');
  @override
  String get voiceSlideHints => _t('voiceSlideHints');
  @override
  String get voiceReleaseToCancel => _t('voiceReleaseToCancel');
  @override
  String get voiceReleaseToLock => _t('voiceReleaseToLock');
  @override
  String get voiceMessage => _t('voiceMessage');
  @override
  String get voiceTooShort => _t('voiceTooShort');
  @override
  String get voiceNoPermission => _t('voiceNoPermission');
  @override
  String get voiceFailed => _t('voiceFailed');
  @override
  String get voiceLimitReached => _t('voiceLimitReached');
  @override
  String get voiceHeard => _t('voiceHeard');
  @override
  String get waitingSetupTitle => _t('waitingSetupTitle');
  @override
  String get waitingEditTitle => _t('waitingEditTitle');
  @override
  String get waitingSetupHint => _t('waitingSetupHint');
  @override
  String get waitingNameLabel => _t('waitingNameLabel');
  @override
  String get waitingReturnDate => _t('waitingReturnDate');
  @override
  String get waitingCreateAction => _t('waitingCreateAction');
  @override
  String get waitingCreateFailed => _t('waitingCreateFailed');
  @override
  String get waitingBadge => _t('waitingBadge');
  @override
  String get waitingCodeTitle => _t('waitingCodeTitle');
  @override
  String get waitingCodeHint => _t('waitingCodeHint');
  @override
  String get waitingCodeCopied => _t('waitingCodeCopied');
  @override
  String get waitingResetCode => _t('waitingResetCode');
  @override
  String get waitingResetCodeHint => _t('waitingResetCodeHint');
  @override
  String get waitingCancelAction => _t('waitingCancelAction');
  @override
  String get waitingCancelTitle => _t('waitingCancelTitle');
  @override
  String get waitingCancelHint => _t('waitingCancelHint');
  @override
  String get waitingCancelDone => _t('waitingCancelDone');
  @override
  String get waitingClaimTitle => _t('waitingClaimTitle');
  @override
  String get waitingClaimAsk => _t('waitingClaimAsk');
  @override
  String get waitingClaimYes => _t('waitingClaimYes');
  @override
  String get waitingClaimNo => _t('waitingClaimNo');
  @override
  String get waitingPendingTitle => _t('waitingPendingTitle');
  @override
  String get waitingPendingHint => _t('waitingPendingHint');
  @override
  String get waitingRejected => _t('waitingRejected');
  @override
  String get waitingApproved => _t('waitingApproved');
  @override
  String get waitingUntilReturn => _t('waitingUntilReturn');
  @override
  String get waitingHomeToday => _t('waitingHomeToday');
  @override
  String get waitingWhoLabel => _t('waitingWhoLabel');
  @override
  String get waitingKnowWho => _t('waitingKnowWho');
  @override
  String get waitingDontKnowWho => _t('waitingDontKnowWho');
  @override
  String get waitingUnknownName => _t('waitingUnknownName');
  @override
  String get waitingUnknownHint => _t('waitingUnknownHint');
  @override
  String get waitingSoloTitle => _t('waitingSoloTitle');
  @override
  String get waitingSoloBody => _t('waitingSoloBody');
  @override
  String get waitingSoloAction => _t('waitingSoloAction');
  @override
  String get chatEmpty => _t('chatEmpty');
  @override
  String get chatEditMessage => _t('chatEditMessage');
  @override
  String get chatDeleteMessage => _t('chatDeleteMessage');
  @override
  String get chatReply => _t('chatReply');
  @override
  String get chatEdited => _t('chatEdited');
  @override
  String get chatDeletedPlaceholder => _t('chatDeletedPlaceholder');
  @override
  String get chatSendFailed => _t('chatSendFailed');
  @override
  String get chatWaitsForPartner => _t('chatWaitsForPartner');
  @override
  String get chatAttachPin => _t('chatAttachPin');
  @override
  String get chatSave => _t('chatSave');
  @override
  String get chatNewMessages => _t('chatNewMessages');
  @override
  String get pixelCanvasTitle => _t('pixelCanvasTitle');
  @override
  String get pixelCanvasHint => _t('pixelCanvasHint');
  @override
  String get pixelWidth => _t('pixelWidth');
  @override
  String get pixelHeight => _t('pixelHeight');
  @override
  String get plainCanvas => _t('plainCanvas');
  @override
  String get pixelCanvasCreate => _t('pixelCanvasCreate');
  @override
  String get pixelGridShow => _t('pixelGridShow');
  @override
  String get pixelGridHide => _t('pixelGridHide');
  @override
  String get canvasesTitle => _t('canvasesTitle');
  @override
  String get pixelScreenTitle => _t('pixelScreenTitle');
  @override
  String get pixelCanvasCreateAction => _t('pixelCanvasCreateAction');
  @override
  String get plainCanvasSubtitle => _t('plainCanvasSubtitle');
  @override
  String get pixelCanvasSubtitle => _t('pixelCanvasSubtitle');
  @override
  String get widgetsCurrentSection => _t('widgetsCurrentSection');
  @override
  String get widgetsCurrentSubtitle => _t('widgetsCurrentSubtitle');
  @override
  String get widgetsNewSection => _t('widgetsNewSection');
  @override
  String get widgetsNewSubtitle => _t('widgetsNewSubtitle');
  @override
  String get tgTogetherTitle => _t('tgTogetherTitle');
  @override
  String get tgTogetherSubtitle => _t('tgTogetherSubtitle');
  @override
  String get tgNoteTitle => _t('tgNoteTitle');
  @override
  String get tgNoteSubtitle => _t('tgNoteSubtitle');
  @override
  String get tgNotePaperTitle => _t('tgNotePaperTitle');
  @override
  String get tgNotePaperSubtitle => _t('tgNotePaperSubtitle');
  @override
  String get tgMissTitle => _t('tgMissTitle');
  @override
  String get tgMissSubtitle => _t('tgMissSubtitle');
  @override
  String get tgSizeHintCompact => _t('tgSizeHintCompact');
  @override
  String get tgSizeHintWide => _t('tgSizeHintWide');
  @override
  String get tgSizeHintLarge => _t('tgSizeHintLarge');
  @override
  String get tgSizeHintStrip => _t('tgSizeHintStrip');
  @override
  String get tgNextSection => _t('tgNextSection');
  @override
  String get tgMissSend => _t('tgMissSend');
  @override
  String get tgMissStripHint => _t('tgMissStripHint');
  @override
  String get tgMoodTitle => _t('tgMoodTitle');
  @override
  String get tgMoodSubtitle => _t('tgMoodSubtitle');
  @override
  String get tgMoodToday => _t('tgMoodToday');
  @override
  String get tgMoodMe => _t('tgMoodMe');
  @override
  String get tgMoodPartner => _t('tgMoodPartner');
  @override
  String get tgMoodNotSet => _t('tgMoodNotSet');
  @override
  String get tgMoodWeekTitle => _t('tgMoodWeekTitle');
  @override
  String get tgCountdownTitle => _t('tgCountdownTitle');
  @override
  String get tgCountdownSubtitle => _t('tgCountdownSubtitle');
  @override
  String get tgCountdownEmpty => _t('tgCountdownEmpty');
  @override
  String get tgCountdownDays => _t('tgCountdownDays');
  @override
  String get tgCountdownHours => _t('tgCountdownHours');
  @override
  String get tgCountdownMinutes => _t('tgCountdownMinutes');
  @override
  String get tgRingTitle => _t('tgRingTitle');
  @override
  String get tgRingSubtitle => _t('tgRingSubtitle');
  @override
  String get tgGridTitle => _t('tgGridTitle');
  @override
  String get tgGridSubtitle => _t('tgGridSubtitle');
  @override
  String get tgYearNoStartDate => _t('tgYearNoStartDate');
  @override
  String get tgYearMonthsLabel => _t('tgYearMonthsLabel');
  @override
  String get tgYearMemoriesLabel => _t('tgYearMemoriesLabel');
  @override
  String get tgSizeHintToday => _t('tgSizeHintToday');
  @override
  String get tgSizeHintWeek => _t('tgSizeHintWeek');
  @override
  String get settingsTitle => _t('settingsTitle');
  @override
  String get settingsOpen => _t('settingsOpen');
  @override
  String get settingsOpenHint => _t('settingsOpenHint');
  @override
  String get settingsAppearanceHint => _t('settingsAppearanceHint');
  @override
  String get settingsNotificationsHint => _t('settingsNotificationsHint');
  @override
  String get settingsLockMoodHint => _t('settingsLockMoodHint');
  @override
  String get settingsDataSection => _t('settingsDataSection');
  @override
  String get settingsExportHint => _t('settingsExportHint');
  @override
  String get settingsResetMissHint => _t('settingsResetMissHint');
  @override
  String get settingsPrivacyHint => _t('settingsPrivacyHint');
  @override
  String get settingsCoinsHint => _t('settingsCoinsHint');
  @override
  String get settingsSupportHint => _t('settingsSupportHint');
  @override
  String get telegramChannelTitle => _t('telegramChannelTitle');
  @override
  String get telegramChannelHint => _t('telegramChannelHint');
  @override
  String get bugBotTitle => _t('bugBotTitle');
  @override
  String get bugBotHint => _t('bugBotHint');
  @override
  String get settingsAccountSection => _t('settingsAccountSection');
  @override
  String get settingsDeleteHint => _t('settingsDeleteHint');
  @override
  String get mascotSleepTitle => _t('mascotSleepTitle');
  @override
  String get mascotSleepHint => _t('mascotSleepHint');
  @override
  String get mascotSleepEmpty => _t('mascotSleepEmpty');
  @override
  String get mascotSleepFrom => _t('mascotSleepFrom');
  @override
  String get mascotSleepTo => _t('mascotSleepTo');
  @override
  String get mascotSleepOff => _t('mascotSleepOff');
  @override
  String get mascotNightAwake => _t('mascotNightAwake');
  @override
  String get cycleTitle => _t('cycleTitle');
  @override
  String get cycleSettingsHint => _t('cycleSettingsHint');
  @override
  String get cycleShareWithPartner => _t('cycleShareWithPartner');
  @override
  String get cycleShareHint => _t('cycleShareHint');
  @override
  String get cycleWipe => _t('cycleWipe');
  @override
  String get cycleWipeHint => _t('cycleWipeHint');
  @override
  String get cycleWipeConfirm => _t('cycleWipeConfirm');
  @override
  String get cycleNoDataTitle => _t('cycleNoDataTitle');
  @override
  String get cycleNoDataHint => _t('cycleNoDataHint');
  @override
  String get cycleExpectedToday => _t('cycleExpectedToday');
  @override
  String get cycleOverdueHint => _t('cycleOverdueHint');
  @override
  String get cycleIrregularWarning => _t('cycleIrregularWarning');
  @override
  String get cycleMarkPeriod => _t('cycleMarkPeriod');
  @override
  String get cycleMarkPeriodHint => _t('cycleMarkPeriodHint');
  @override
  String get cycleMarkIntimacy => _t('cycleMarkIntimacy');
  @override
  String get cycleMarkIntimacyHint => _t('cycleMarkIntimacyHint');
  @override
  String get cycleAnalyticsTitle => _t('cycleAnalyticsTitle');
  @override
  String get cycleAverageLength => _t('cycleAverageLength');
  @override
  String get cycleAveragePeriod => _t('cycleAveragePeriod');
  @override
  String get cycleNextPeriod => _t('cycleNextPeriod');
  @override
  String get cycleFertileWindow => _t('cycleFertileWindow');
  @override
  String get cycleDaysUnit => _t('cycleDaysUnit');
  @override
  String get cycleAverageShort => _t('cycleAverageShort');
  @override
  String get cycleRangeShort => _t('cycleRangeShort');
  @override
  String get cycleRegularity => _t('cycleRegularity');
  @override
  String get cycleRegularityOk => _t('cycleRegularityOk');
  @override
  String get cycleRegularityLow => _t('cycleRegularityLow');
  @override
  String get cycleChartLengths => _t('cycleChartLengths');
  @override
  String get cycleChartDurations => _t('cycleChartDurations');
  @override
  String get cycleLegendPeriod => _t('cycleLegendPeriod');
  @override
  String get cycleLegendPredicted => _t('cycleLegendPredicted');
  @override
  String get cycleLegendOvulation => _t('cycleLegendOvulation');
  @override
  String get cycleLegendFertile => _t('cycleLegendFertile');
  @override
  String get cycleLegendIntimacy => _t('cycleLegendIntimacy');
  @override
  String get cycleTipsTitle => _t('cycleTipsTitle');
  @override
  String get cycleTipWarmTitle => _t('cycleTipWarmTitle');
  @override
  String get cycleTipWarmBody => _t('cycleTipWarmBody');
  @override
  String get cycleTipFeetTitle => _t('cycleTipFeetTitle');
  @override
  String get cycleTipFeetBody => _t('cycleTipFeetBody');
  @override
  String get cycleTipPainTitle => _t('cycleTipPainTitle');
  @override
  String get cycleTipPainBody => _t('cycleTipPainBody');
  @override
  String get cycleTipShowerTitle => _t('cycleTipShowerTitle');
  @override
  String get cycleTipShowerBody => _t('cycleTipShowerBody');
  @override
  String get cycleTipChangeTitle => _t('cycleTipChangeTitle');
  @override
  String get cycleTipChangeBody => _t('cycleTipChangeBody');
  @override
  String get cycleTipIronTitle => _t('cycleTipIronTitle');
  @override
  String get cycleTipIronBody => _t('cycleTipIronBody');
  @override
  String get cycleTipRestTitle => _t('cycleTipRestTitle');
  @override
  String get cycleTipRestBody => _t('cycleTipRestBody');
  @override
  String get dayLogWhat => _t('dayLogWhat');
  @override
  String get dayLogNotMarked => _t('dayLogNotMarked');
  @override
  String get dayLogTodayOnly => _t('dayLogTodayOnly');
  @override
  String get cycleSheetHint => _t('cycleSheetHint');
  @override
  String get cycleSexMarked => _t('cycleSexMarked');
  @override
  String get drawLayers => _t('drawLayers');
  @override
  String get drawLayerAdd => _t('drawLayerAdd');
  @override
  String get drawLayerHide => _t('drawLayerHide');
  @override
  String get drawLayerShow => _t('drawLayerShow');
  @override
  String get drawLayerDelete => _t('drawLayerDelete');
  @override
  String get drawLayerDeleteConfirm => _t('drawLayerDeleteConfirm');
  @override
  String get drawBackgrounds => _t('drawBackgrounds');
  @override
  String get plusTitle => _t('plusTitle');
  @override
  String get plusHeroTitle => _t('plusHeroTitle');
  @override
  String get plusHeroBody => _t('plusHeroBody');
  @override
  String get plusActiveTitle => _t('plusActiveTitle');
  @override
  String get plusActiveBody => _t('plusActiveBody');
  @override
  String get plusNoAdsTitle => _t('plusNoAdsTitle');
  @override
  String get plusNoAdsBody => _t('plusNoAdsBody');
  @override
  String get plusWishesTitle => _t('plusWishesTitle');
  @override
  String get plusWishesBody => _t('plusWishesBody');
  @override
  String get plusColoringTitle => _t('plusColoringTitle');
  @override
  String get plusColoringBody => _t('plusColoringBody');
  @override
  String get plusThemesTitle => _t('plusThemesTitle');
  @override
  String get plusThemesBody => _t('plusThemesBody');
  @override
  String get plusCycleTitle => _t('plusCycleTitle');
  @override
  String get plusCycleBody => _t('plusCycleBody');
  @override
  String get plusWidgetsTitle => _t('plusWidgetsTitle');
  @override
  String get plusWidgetsBody => _t('plusWidgetsBody');
  @override
  String get plusTipsTitle => _t('plusTipsTitle');
  @override
  String get plusTipsBody => _t('plusTipsBody');
  @override
  String get plusVideoTitle => _t('plusVideoTitle');
  @override
  String get plusVideoBody => _t('plusVideoBody');
  @override
  String get plusBuy => _t('plusBuy');
  @override
  String get plusHaveCode => _t('plusHaveCode');
  @override
  String get plusHowItWorks => _t('plusHowItWorks');
  @override
  String get plusPortableNote => _t('plusPortableNote');
  @override
  String get plusUnavailableHere => _t('plusUnavailableHere');
  @override
  String get plusStoreUnavailable => _t('plusStoreUnavailable');
  @override
  String get statsTitle => _t('statsTitle');
  @override
  String get pickerDateTab => _t('pickerDateTab');
  @override
  String get pcTicketRoute => _t('pcTicketRoute');
  @override
  String get pcNameTicket => _t('pcNameTicket');
  @override
  String get pcNameReceipt => _t('pcNameReceipt');
  @override
  String get pcNameTelegram => _t('pcNameTelegram');
  @override
  String get pcNameParcel => _t('pcNameParcel');
  @override
  String get pcMsgTicket => _t('pcMsgTicket');
  @override
  String get pcReceiptTotal => _t('pcReceiptTotal');
  @override
  String get pcLabelReceiptItems => _t('pcLabelReceiptItems');
  @override
  String get pcMsgReceipt => _t('pcMsgReceipt');
  @override
  String get pcTelegramTitle => _t('pcTelegramTitle');
  @override
  String get pcMsgTelegram => _t('pcMsgTelegram');
  @override
  String get pcParcelCare => _t('pcParcelCare');
  @override
  String get pcParcelTo => _t('pcParcelTo');
  @override
  String get redeemCodeAlphabet => _t('redeemCodeAlphabet');
  @override
  String get pickerTimeTab => _t('pickerTimeTab');
  @override
  String get statsDaysTogether => _t('statsDaysTogether');
  @override
  String get statsMemories => _t('statsMemories');
  @override
  String get statsDrawings => _t('statsDrawings');
  @override
  String get statsStreak => _t('statsStreak');
  @override
  String get statsXp => _t('statsXp');
  @override
  String get statsMoodMonth => _t('statsMoodMonth');
  @override
  String get statsMoodMine => _t('statsMoodMine');
  @override
  String get statsMoodPartner => _t('statsMoodPartner');
  @override
  String get statsTipsTitle => _t('statsTipsTitle');
  @override
  String get statsEntryTitle => _t('statsEntryTitle');
  @override
  String get statsEntrySubtitle => _t('statsEntrySubtitle');
  @override
  String get statsFullLink => _t('statsFullLink');
  @override
  String get statsFullLinkHint => _t('statsFullLinkHint');
  @override
  String get plusPurchased => _t('plusPurchased');
  @override
  String get plusPurchasePending => _t('plusPurchasePending');
  @override
  String get plusPurchaseFailed => _t('plusPurchaseFailed');
  @override
  String get plusCodeHint => _t('plusCodeHint');
  @override
  String get plusCodeApply => _t('plusCodeApply');
  @override
  String get plusCodeOk => _t('plusCodeOk');
  @override
  String get plusCodeFailed => _t('plusCodeFailed');
  @override
  String get plusLockedTipsTitle => _t('plusLockedTipsTitle');
  @override
  String get plusLockedTipsBody => _t('plusLockedTipsBody');
  @override
  String get plusUnlock => _t('plusUnlock');
  @override
  String get chatBgSharedHint => _t('chatBgSharedHint');
  @override
  String get chatBgUploading => _t('chatBgUploading');
  @override
  String get chatBgSharedDone => _t('chatBgSharedDone');
  @override
  String get exportTakesTime => _t('exportTakesTime');
  @override
  String get selectAll => _t('selectAll');
  @override
  String get chatStyleFace => _t('chatStyleFace');
  @override
  String get chatStyleBackground => _t('chatStyleBackground');
  @override
  String get chatStyleTextColor => _t('chatStyleTextColor');
  @override
  String get chatStyleAuto => _t('chatStyleAuto');
  @override
  String get chatStyleTheme => _t('chatStyleTheme');
  @override
  String get chatBgTitle => _t('chatBgTitle');
  @override
  String get chatBgSet => _t('chatBgSet');
  @override
  String get chatBgChange => _t('chatBgChange');
  @override
  String get chatBgRemove => _t('chatBgRemove');
  @override
  String get chatBgCharged => _t('chatBgCharged');
  @override
  String get lockScreenMood => _t('lockScreenMood');
  @override
  String get lockScreenMoodSubtitle => _t('lockScreenMoodSubtitle');
  @override
  String get lockScreenMoodToggle => _t('lockScreenMoodToggle');
  @override
  String get lockScreenMoodToggleSub => _t('lockScreenMoodToggleSub');
  @override
  String get lockScreenMoodNoMood => _t('lockScreenMoodNoMood');
  @override
  String get lockScreenMoodSetHint => _t('lockScreenMoodSetHint');
  @override
  String get photoGridWidget => _t('photoGridWidget');
  @override
  String get photoGridWidgetSubtitle => _t('photoGridWidgetSubtitle');
  @override
  String get photoGridCount => _t('photoGridCount');
  @override
  String get photoGridSelectPhotos => _t('photoGridSelectPhotos');
  @override
  String get photoGridAddPhoto => _t('photoGridAddPhoto');
  @override
  String get photoGridCountLabel => _t('photoGridCountLabel');
  @override
  String get goToPin => _t('goToPin');
  @override
  String get openPhotoGallery => _t('openPhotoGallery');
  @override
  String get allMediaGallery => _t('allMediaGallery');
  @override
  String get loadMore => _t('loadMore');
  @override
  String get previewLabel => _t('previewLabel');
  @override
  String get photoSent => _t('photoSent');
  @override
  String get partnerFallback => _t('partnerFallback');
  @override
  String get captionDestMemories => _t('captionDestMemories');
  @override
  String get captionDestMemoriesSub => _t('captionDestMemoriesSub');
  @override
  String get captionDestPairWidget => _t('captionDestPairWidget');
  @override
  String get captionDestPartnerWidget => _t('captionDestPartnerWidget');
  @override
  String get groupMascot => _t('groupMascot');
  @override
  String get tapForGallery => _t('tapForGallery');
  @override
  String get selectMascot => _t('selectMascot');
  @override
  String get showLabel => _t('showLabel');
  @override
  String get widgetStreakTitle => _t('widgetStreakTitle');
  @override
  String get widgetStreakSubtitle => _t('widgetStreakSubtitle');
  @override
  String get widgetPetalTimerTitle => _t('widgetPetalTimerTitle');
  @override
  String get widgetPetalTimerSubtitle => _t('widgetPetalTimerSubtitle');
  @override
  String get widgetPhotoTitle => _t('widgetPhotoTitle');
  @override
  String get widgetPhotoSubtitle => _t('widgetPhotoSubtitle');
  @override
  String get streakTogetherCaps => _t('streakTogetherCaps');
  @override
  String get daysInARow => _t('daysInARow');
  @override
  String get keepItUp => _t('keepItUp');
  @override
  String get ourPhotosInsteadOfDrawing => _t('ourPhotosInsteadOfDrawing');
  @override
  String get daysPhotosDescription => _t('daysPhotosDescription');
  @override
  String get showOurPhotos => _t('showOurPhotos');
  @override
  String get partnerNoProfilePhoto => _t('partnerNoProfilePhoto');
  @override
  String get addYourProfilePhoto => _t('addYourProfilePhoto');
  @override
  String get daysPhotosDone => _t('daysPhotosDone');
  @override
  String get purchaseFailedTryLater => _t('purchaseFailedTryLater');
  @override
  String get personalPhotosHelpShort => _t('personalPhotosHelpShort');
  @override
  String get uploadedPhotosToMemoryLane => _t('uploadedPhotosToMemoryLane');
  @override
  String get selectPhotosForPartner => _t('selectPhotosForPartner');
  @override
  String get stopSharingPhotos => _t('stopSharingPhotos');
  @override
  String get photosForPartnerRemoved => _t('photosForPartnerRemoved');
  @override
  String get noPhotosFromPartner => _t('noPhotosFromPartner');
  @override
  String get noPhotosAdded => _t('noPhotosAdded');
  @override
  String get onePhotoNoCarousel => _t('onePhotoNoCarousel');
  @override
  String get partnerPhotoTitle => _t('partnerPhotoTitle');
  @override
  String get partnerSharedOnePhoto => _t('partnerSharedOnePhoto');
  @override
  String get partnerNotSharedYet => _t('partnerNotSharedYet');
  @override
  String get changePhotosLabel => _t('changePhotosLabel');
  @override
  String get onUnlockOption => _t('onUnlockOption');
  @override
  String get byTimeOption => _t('byTimeOption');
  @override
  String get every15Minutes => _t('every15Minutes');
  @override
  String get every30Minutes => _t('every30Minutes');
  @override
  String get everyHourOption => _t('everyHourOption');
  @override
  String get every3HoursOption => _t('every3HoursOption');
  @override
  String get createPostcardTitle => _t('createPostcardTitle');
  @override
  String get createPostcardSubtitle => _t('createPostcardSubtitle');
  @override
  String get whereToSendPhoto => _t('whereToSendPhoto');
  @override
  String get sendLabel => _t('sendLabel');
  @override
  String get widgetPhotoCaption => _t('widgetPhotoCaption');
  @override
  String get mascotSaveFailed => _t('mascotSaveFailed');
  @override
  String get mascotLoadFailed => _t('mascotLoadFailed');
  @override
  String get transparentBgTitle => _t('transparentBgTitle');
  @override
  String get transparentBgBody => _t('transparentBgBody');
  @override
  String get mascotNameTitle => _t('mascotNameTitle');
  @override
  String get enterNameHint => _t('enterNameHint');
  @override
  String get mascotLimitReached => _t('mascotLimitReached');
  @override
  String get rename => _t('rename');
  @override
  String get deleteMascotTitle => _t('deleteMascotTitle');
  @override
  String get deactivateLabel => _t('deactivateLabel');
  @override
  String get makeActiveLabel => _t('makeActiveLabel');
  @override
  String get editLabel => _t('editLabel');
  @override
  String get exportPng => _t('exportPng');
  @override
  String get groupMascots => _t('groupMascots');
  @override
  String get limitLabel => _t('limitLabel');
  @override
  String get mascotsLoadFailedMultiline => _t('mascotsLoadFailedMultiline');
  @override
  String get artistCredit => _t('artistCredit');
  @override
  String get uploadPhotoTooltip => _t('uploadPhotoTooltip');
  @override
  String get drawLabel => _t('drawLabel');
  @override
  String get streakBroken => _t('streakBroken');
  @override
  String get streakKeepHint => _t('streakKeepHint');
  @override
  String get streakStartHint => _t('streakStartHint');
  @override
  String get fromUs => _t('fromUs');
  @override
  String get drawSomethingFirst => _t('drawSomethingFirst');
  @override
  String get drawMascotTitle => _t('drawMascotTitle');
  @override
  String get toolBrush => _t('toolBrush');
  @override
  String get toolPencil => _t('toolPencil');
  @override
  String get toolMarker => _t('toolMarker');
  @override
  String get toolEraser => _t('toolEraser');
  @override
  String get toolFill => _t('toolFill');
  @override
  String get toolLine => _t('toolLine');
  @override
  String get toolRect => _t('toolRect');
  @override
  String get toolCircle => _t('toolCircle');
  @override
  String get toolTriangle => _t('toolTriangle');
  @override
  String get fillAction => _t('fillAction');
  @override
  String get resetSize => _t('resetSize');
  @override
  String get undoLabel => _t('undoLabel');
  @override
  String get redoLabel => _t('redoLabel');
  @override
  String get underlayLabel => _t('underlayLabel');
  @override
  String get drawHintEdit => _t('drawHintEdit');
  @override
  String get drawHintDraw => _t('drawHintDraw');
  @override
  String get colorLabel => _t('colorLabel');
  @override
  String get coloringOwnAdd => _t('coloringOwnAdd');
  @override
  String get coloringOwnProcessing => _t('coloringOwnProcessing');
  @override
  String get coloringOwnDefaultName => _t('coloringOwnDefaultName');
  @override
  String get coloringTitle => _t('coloringTitle');
  @override
  String get coloringSubtitle => _t('coloringSubtitle');
  @override
  String get coloringModeSurprise => _t('coloringModeSurprise');
  @override
  String get coloringModeTogether => _t('coloringModeTogether');
  @override
  String get coloringModeSurpriseHint => _t('coloringModeSurpriseHint');
  @override
  String get coloringModeTogetherHint => _t('coloringModeTogetherHint');
  @override
  String get coloringOtherHalf => _t('coloringOtherHalf');
  @override
  String get coloringMyHalf => _t('coloringMyHalf');
  @override
  String get coloringSwapSides => _t('coloringSwapSides');
  @override
  String get coloringPartnerHalfHidden => _t('coloringPartnerHalfHidden');
  @override
  String get coloringDoneBtn => _t('coloringDoneBtn');
  @override
  String get coloringNotDoneBtn => _t('coloringNotDoneBtn');
  @override
  String get coloringWaitingTitle => _t('coloringWaitingTitle');
  @override
  String get coloringRevealTitle => _t('coloringRevealTitle');
  @override
  String get coloringShare => _t('coloringShare');
  @override
  String get coloringSave => _t('coloringSave');
  @override
  String get coloringToMemories => _t('coloringToMemories');
  @override
  String get coloringSaved => _t('coloringSaved');
  @override
  String get coloringNew => _t('coloringNew');
  @override
  String get eyedropper => _t('eyedropper');
  @override
  String get eyedropperHint => _t('eyedropperHint');
  @override
  String get recentColors => _t('recentColors');
  @override
  String get customColor => _t('customColor');
  @override
  String get hueLabel => _t('hueLabel');
  @override
  String get saturationLabel => _t('saturationLabel');
  @override
  String get brightnessLabel => _t('brightnessLabel');
  @override
  String get selectAction => _t('selectAction');
  @override
  String get pcNamesFallback => _t('pcNamesFallback');
  @override
  String get pcLabelNames => _t('pcLabelNames');
  @override
  String get pcLabelDaysCaption => _t('pcLabelDaysCaption');
  @override
  String get pcLabelMessage => _t('pcLabelMessage');
  @override
  String get pcLabelCaption => _t('pcLabelCaption');
  @override
  String get pcLabelPolaroidCaption => _t('pcLabelPolaroidCaption');
  @override
  String get pcLabelMessageAlt => _t('pcLabelMessageAlt');
  @override
  String get pcDaysTogether => _t('pcDaysTogether');
  @override
  String get pcMsgTogether => _t('pcMsgTogether');
  @override
  String get pcDaysOfLove => _t('pcDaysOfLove');
  @override
  String get pcMsgPolaroid => _t('pcMsgPolaroid');
  @override
  String get pcDaysNearby => _t('pcDaysNearby');
  @override
  String get pcMsgBloom => _t('pcMsgBloom');
  @override
  String get pcNightsUnderSky => _t('pcNightsUnderSky');
  @override
  String get pcMsgNightSky => _t('pcMsgNightSky');
  @override
  String get addOneToTenPhotos => _t('addOneToTenPhotos');
  @override
  String get addMorePhotosCarouselHint => _t('addMorePhotosCarouselHint');
  @override
  String get dragToReorder => _t('dragToReorder');
  @override
  String get mainPhoto => _t('mainPhoto');
  @override
  String get addMore => _t('addMore');
  @override
  String get fromDevice => _t('fromDevice');
  @override
  String get fromFeed => _t('fromFeed');
  @override
  String get cropAvatarTitle => _t('cropAvatarTitle');
  @override
  String get avatarTitle => _t('avatarTitle');
  @override
  String get appIconTitle => _t('appIconTitle');
  @override
  String get appIconUpdateHint => _t('appIconUpdateHint');
  @override
  String get appIconChangeFailed => _t('appIconChangeFailed');
  @override
  String get viewAction => _t('viewAction');
  @override
  String get enterDateFormat => _t('enterDateFormat');
  @override
  String get enterTimeFormat => _t('enterTimeFormat');
  @override
  String get dateHintFormat => _t('dateHintFormat');
  @override
  String get timeHintFormat => _t('timeHintFormat');
  @override
  String get openCalendar => _t('openCalendar');
  @override
  String get refreshTooltip => _t('refreshTooltip');
  @override
  String get memoriesMapTooltip => _t('memoriesMapTooltip');
  @override
  String get editLocation => _t('editLocation');
  @override
  String get addLocation => _t('addLocation');
  @override
  String get photoVideoNote => _t('photoVideoNote');
  @override
  String get appNotInstalled => _t('appNotInstalled');
  @override
  String get watchTogether => _t('watchTogether');
  @override
  String get watchRoomOpensForBoth => _t('watchRoomOpensForBoth');
  @override
  String get watchAfterShortAd => _t('watchAfterShortAd');
  @override
  String get watchOpenOnSite => _t('watchOpenOnSite');
  @override
  String get watchOnSiteHint => _t('watchOnSiteHint');
  @override
  String get watchPartnerInBrowser => _t('watchPartnerInBrowser');
  @override
  String get watchCodeRetry => _t('watchCodeRetry');
  @override
  String get watchRecent => _t('watchRecent');
  @override
  String get watchOurVideos => _t('watchOurVideos');
  @override
  String get watchVideoUploading => _t('watchVideoUploading');
  @override
  String get watchVideoFormatUnsupported => _t('watchVideoFormatUnsupported');
  @override
  String get watchPickFileAgain => _t('watchPickFileAgain');
  @override
  String get watchVideoRemoveTitle => _t('watchVideoRemoveTitle');
  @override
  String get watchVideoRemoveBody => _t('watchVideoRemoveBody');
  @override
  String get watchVideoRemoved => _t('watchVideoRemoved');
  @override
  String get watchHeroTitle => _t('watchHeroTitle');
  @override
  String get watchHeroText => _t('watchHeroText');
  @override
  String get linkCopied => _t('linkCopied');
  @override
  String get copyLink => _t('copyLink');
  @override
  String get watchTogetherAdPrompt => _t('watchTogetherAdPrompt');
  @override
  String get watchAction => _t('watchAction');
  @override
  String get youtubeLinkHint => _t('youtubeLinkHint');
  @override
  String get startAction => _t('startAction');
  @override
  String get youtubeLinkInvalid => _t('youtubeLinkInvalid');
  @override
  String get joinAction => _t('joinAction');
  @override
  String get partnerEndedWatchTogether => _t('partnerEndedWatchTogether');
  @override
  String get videoCannotWatchTogether => _t('videoCannotWatchTogether');
  @override
  String get videoEmbedBlockedHint => _t('videoEmbedBlockedHint');
  @override
  String get chooseAnother => _t('chooseAnother');
  @override
  String get openOnYoutube => _t('openOnYoutube');
  @override
  String get watchingTogether => _t('watchingTogether');
  @override
  String get partnerJoined => _t('partnerJoined');
  @override
  String get waitingForPartner => _t('waitingForPartner');
  @override
  String get syncedPlaying => _t('syncedPlaying');
  @override
  String get syncedPaused => _t('syncedPaused');
  @override
  String get writeFirstMessage => _t('writeFirstMessage');
  @override
  String get messageInputHint => _t('messageInputHint');
  @override
  String get selectOnePhoto => _t('selectOnePhoto');
  @override
  String get maxSelected => _t('maxSelected');
  @override
  String get selectPhotosPrompt => _t('selectPhotosPrompt');
  @override
  String get failedToLoadMemories => _t('failedToLoadMemories');
  @override
  String get noPhotosInMemoryLane => _t('noPhotosInMemoryLane');
  @override
  String get inWidget => _t('inWidget');
  @override
  String get postcardTitle => _t('postcardTitle');
  @override
  String get changePhoto => _t('changePhoto');
  @override
  String get addPhotoFromGallery => _t('addPhotoFromGallery');
  @override
  String get tapAnyTextToEdit => _t('tapAnyTextToEdit');
  @override
  String get creating => _t('creating');
  @override
  String get sharePostcard => _t('sharePostcard');
  @override
  String get noGeoMemories => _t('noGeoMemories');
  @override
  String get addLocationHint => _t('addLocationHint');
  @override
  String get placeFallback => _t('placeFallback');
  @override
  String get welcomeSlide1Title => _t('welcomeSlide1Title');
  @override
  String get welcomeSlide2Title => _t('welcomeSlide2Title');
  @override
  String get welcomeSlide3Title => _t('welcomeSlide3Title');
  @override
  String get newEntry => _t('newEntry');
  @override
  String get photoVideo => _t('photoVideo');
  @override
  String get cropPhotoAction => _t('cropPhotoAction');
  @override
  String get cropPhotoHint => _t('cropPhotoHint');
  @override
  String get optionalTapToSelect => _t('optionalTapToSelect');
  @override
  String get dragHint => _t('dragHint');
  @override
  String get addPhoto => _t('addPhoto');
  @override
  String get groupMascotBanner => _t('groupMascotBanner');
  @override
  String get goToGallery => _t('goToGallery');
  @override
  String get hide => _t('hide');
  @override
  String get placeOrCoordsHint => _t('placeOrCoordsHint');
  @override
  String get goToCoordinates => _t('goToCoordinates');
  @override
  String get chatBgSaveFailed => _t('chatBgSaveFailed');
  @override
  String get timeFormatHint => _t('timeFormatHint');
  @override
  String get bookTitleLanguageHint => _t('bookTitleLanguageHint');
  @override
  String get liveMapTitle => _t('liveMapTitle');
  @override
  String get liveMapEnableCta => _t('liveMapEnableCta');
  @override
  String get liveMapEnableHint => _t('liveMapEnableHint');
  @override
  String get liveMapPermissionDenied => _t('liveMapPermissionDenied');
  @override
  String get liveMapUpdated => _t('liveMapUpdated');
  String get liveMapWaitingPartner => _t('liveMapWaitingPartner');
  @override
  String get liveMapYou => _t('liveMapYou');
  @override
  String get liveMapCenterMe => _t('liveMapCenterMe');
  @override
  String get liveMapShowBoth => _t('liveMapShowBoth');
  @override
  String get liveMapOpenFull => _t('liveMapOpenFull');
  @override
  String get liveMapNotPaired => _t('liveMapNotPaired');
  @override
  String get liveMapStopCta => _t('liveMapStopCta');
  @override
  String get liveMapStopped => _t('liveMapStopped');
  @override
  String get liveLocationServiceTitle => _t('liveLocationServiceTitle');
  @override
  String get liveLocationServiceText => _t('liveLocationServiceText');
  @override
  String get liveLocationJustNow => _t('liveLocationJustNow');
  @override
  String get unitCm => _t('unitCm');
  @override
  String get unitM => _t('unitM');
  @override
  String get unitKm => _t('unitKm');
  @override
  String get unitMinShort => _t('unitMinShort');
  @override
  String get unitHourShort => _t('unitHourShort');
  @override
  String get unitDayShort => _t('unitDayShort');
  @override
  String get giftAccepted => _t('giftAccepted');
  @override
  String get giftIncomingTitle => _t('giftIncomingTitle');
  @override
  String get giftNoteHint => _t('giftNoteHint');
  @override
  String get giftNoteSkip => _t('giftNoteSkip');
  @override
  String get giftNoteSend => _t('giftNoteSend');
  @override
  String get giftWishHint => _t('giftWishHint');
  @override
  String get giftWishSend => _t('giftWishSend');
  @override
  String get giftWishEmpty => _t('giftWishEmpty');
  @override
  String get supportTitle => _t('supportTitle');
  @override
  String get redeemCodeTitle => _t('redeemCodeTitle');
  @override
  String get redeemCodeSubtitle => _t('redeemCodeSubtitle');
  @override
  String get redeemCodeHint => _t('redeemCodeHint');
  @override
  String get redeemCodeApply => _t('redeemCodeApply');
  @override
  String get redeemCodeAlready => _t('redeemCodeAlready');
  @override
  String get redeemCodeFailed => _t('redeemCodeFailed');
  @override
  String get giftAccept => _t('giftAccept');
  @override
  String get giftDecline => _t('giftDecline');
  @override
  String get giftFlipCoin => _t('giftFlipCoin');
  @override
  String get giftFlipYou => _t('giftFlipYou');
  @override
  String get giftFlipPartner => _t('giftFlipPartner');
  @override
  String get partnerGiftsTitle => _t('partnerGiftsTitle');
  @override
  String get partnerGiftsEmpty => _t('partnerGiftsEmpty');
  @override
  String get partnerMissTitle => _t('partnerMissTitle');
  @override
  String get partnerMissEmpty => _t('partnerMissEmpty');
  @override
  String get selfGiftsTitle => _t('selfGiftsTitle');
  @override
  String get selfMissTitle => _t('selfMissTitle');
  @override
  String get openPartnerProfile => _t('openPartnerProfile');
  @override
  String get giftShopTitle => _t('giftShopTitle');
  @override
  String get giftSent => _t('giftSent');
  @override
  String get giftNotEnoughCoins => _t('giftNotEnoughCoins');
  @override
  String get giftNoConnection => _t('giftNoConnection');
  @override
  String get giftFailed => _t('giftFailed');
}
