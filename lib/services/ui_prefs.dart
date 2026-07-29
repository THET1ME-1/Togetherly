import 'package:shared_preferences/shared_preferences.dart';

/// Лёгкие локальные UI-настройки (без сервера). Единый источник ключей, чтобы
/// главный экран и настройки читали/писали одно и то же.
class UiPrefs {
  UiPrefs._();

  /// Режим боковой кнопки навбара: true = стрелка → (открыть Ленту),
  /// false = плюс + (сразу создать пин). Дефолт — стрелка.
  static const String kHomeSideActionArrow = 'home_side_action_arrow';

  /// Показана ли одноразовая подсказка про удержание боковой кнопки.
  static const String kSideActionHintSeen = 'side_action_hint_seen';

  static Future<bool> sideActionIsArrow() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kHomeSideActionArrow) ?? true;
  }

  static Future<void> setSideActionIsArrow(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kHomeSideActionArrow, value);
  }

  static Future<bool> sideActionHintSeen() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kSideActionHintSeen) ?? false;
  }

  static Future<void> markSideActionHintSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kSideActionHintSeen, true);
  }

  /// Показан ли экран приглашения партнёра после регистрации. Флаг локальный
  /// намеренно: экран нужен один раз новичку, а не каждому, кто когда-то
  /// расстался и остался без пары.
  static const String kInviteScreenShown = 'invite_screen_shown';

  static Future<bool> inviteScreenShown() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kInviteScreenShown) ?? false;
  }

  static Future<void> markInviteScreenShown() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kInviteScreenShown, true);
  }

  /// Версия, на которой показывали рассказ про Togetherly+.
  ///
  /// Про платную часть надо рассказать один раз после обновления — и замолчать.
  /// Периодические напоминания «раз в N заходов» превращаются в долбёжку:
  /// человек открывает приложение по несколько раз в день, и такой экран
  /// вылезал бы каждые три-четыре дня. Дальше Плюс продаёт себя сам — по
  /// замкам, там, где человек в него упирается.
  static const String kPlusPitchVersion = 'plus_pitch_version';

  /// Показывали ли рассказ на этой версии.
  static Future<bool> plusPitchShownFor(String version) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kPlusPitchVersion) == version;
  }

  static Future<void> markPlusPitchShown(String version) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kPlusPitchVersion, version);
  }

  /// Первый запуск приложения после установки: рассказ про Плюс новичку не
  /// показываем — у него своя дорога, приглашение партнёра.
  static Future<bool> isFirstLaunchEver() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kPlusPitchVersion) == null &&
        !(p.getBool(kInviteScreenShown) ?? false);
  }

  /// Карточка первых действий закрыта крестиком.
  static const String kOnboardingDismissed = 'onboarding_card_dismissed';

  static Future<bool> onboardingDismissed() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kOnboardingDismissed) ?? false;
  }

  static Future<void> dismissOnboarding() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kOnboardingDismissed, true);
  }

  /// Виджет добавлен на рабочий стол. Считаем по факту успешного добавления:
  /// записи `widget_data` заводятся при любой синхронизации и о рабочем столе
  /// ничего не говорят.
  static const String kWidgetPinned = 'widget_pinned_once';

  static Future<bool> widgetPinned() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kWidgetPinned) ?? false;
  }

  static Future<void> markWidgetPinned() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kWidgetPinned, true);
  }

  /// Вид чата: `cozy` — наш (кривые углы, хвостики, лёгкий наклон, мордочки),
  /// `material` — обычные пузыри Material 3 без украшений. Хранится локально:
  /// это дело вкуса каждого, а не пары.
  static const String kChatLook = 'chat_look';

  static Future<bool> chatLookMaterial() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(kChatLook) ?? 'cozy') == 'material';
  }

  static Future<void> setChatLookMaterial(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kChatLook, value ? 'material' : 'cozy');
  }

  /// Узор фона чата (имя значения `ChatBackground`). По умолчанию «точки»:
  /// самый нейтральный из семи — работает с любой из двадцати палитр и не
  /// спорит с пузырями. Хранится локально, как и вид пузырей: это вкус
  /// каждого, а общий фон-картинка пары живёт отдельно в `groups`.
  static const String kChatBackground = 'chat_background_pattern';

  static Future<String> chatBackground() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kChatBackground) ?? 'dots';
  }

  static Future<void> setChatBackground(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kChatBackground, name);
  }

  /// Когда в последний раз отправляли «Скучаю» с карточки затихшего партнёра
  /// (epoch ms). Ограничивает подсказку одним разом в сутки.
  static const String kQuietNudgeAt = 'quiet_partner_nudge_at';

  static Future<int?> quietNudgeAt() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getInt(kQuietNudgeAt) ?? 0;
    return v > 0 ? v : null;
  }

  static Future<void> markQuietNudgeSent(int atMs) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(kQuietNudgeAt, atMs);
  }
}
