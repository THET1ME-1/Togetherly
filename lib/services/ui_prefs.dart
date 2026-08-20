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

  /// Настройки кисти холста: сглаживание, ровные фигуры, симметрия. Живут
  /// на устройстве — это привычка руки, а не общее имущество пары.
  static const String kBrushSmoothing = 'draw_brush_smoothing';

  /// Состав и порядок панели быстрого доступа холста.
  static const String kDrawQuickTools = 'draw_quick_tools';

  /// Каким видом открывать экран настроений: сеткой или сосудом.
  static const String kMoodVesselView = 'mood_vessel_view';
  static const String kBrushQuickShapes = 'draw_brush_quick_shapes';
  static const String kBrushSymmetry = 'draw_brush_symmetry';
  static const String kBrushSymmetrySectors = 'draw_brush_symmetry_sectors';

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

  /// Одноразовые подсказки о новых функциях.
  ///
  /// Ключ у каждой свой (`snap_hold`, `miss_screen`, `side_action`), очередь
  /// показа держит [HintQueue]. Отметка ставится в момент показа, а не по
  /// кнопке «Понятно»: закрытый тапом мимо пузырь возвращаться не должен.
  /// У подсказки про боковую кнопку ключ старше самой очереди, и менять его
  /// нельзя: те, кто её уже видел, получили бы её заново.
  static String hintKey(String name) =>
      name == 'side_action' ? kSideActionHintSeen : 'hint_${name}_seen';

  static Future<bool> hintSeen(String name) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(hintKey(name)) ?? false;
  }

  static Future<void> markHintSeen(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(hintKey(name), true);
  }

  /// Свёрнутые секции экранов — ключи вида `profile:pair`, `settings:about`.
  ///
  /// Храним именно СВЁРНУТЫЕ, а не развёрнутые: раскрытая секция — состояние по
  /// умолчанию, и человек, который ничего не сворачивал, не должен получить
  /// схлопнутый экран из-за пустого списка.
  ///
  /// Решение переживает выход с экрана: свернувший «Отношения» один раз хочет
  /// видеть их свёрнутыми и завтра, а не сворачивать заново на каждый заход.
  static const String kCollapsedSections = 'collapsed_sections';

  static Future<Set<String>> collapsedSections() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(kCollapsedSections) ?? const <String>[]).toSet();
  }

  static Future<void> setSectionCollapsed(String key, bool collapsed) async {
    final p = await SharedPreferences.getInstance();
    final saved = (p.getStringList(kCollapsedSections) ?? const <String>[])
        .toSet();
    if (collapsed) {
      saved.add(key);
    } else {
      saved.remove(key);
    }
    await p.setStringList(kCollapsedSections, saved.toList());
  }

  // ── Плашка Togetherly+ ──
  /// Когда показывали в прошлый раз (epoch-ms).
  static const String kPlusPromoAt = 'plus_promo_at';

  /// Когда приложение впервые запустилось на этом телефоне (epoch-ms).
  /// В первые сутки витрину не показываем: человек ещё не понял, за что платить.
  static const String kFirstRunAt = 'first_run_at';

  static Future<int> plusPromoAt() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(kPlusPromoAt) ?? 0;
  }

  // ── «Умение любить»: карточка на главной ──────────────────────────────────

  static const _loveDismissedKey = 'love_test_prompt_dismissed';

  /// Карточку показываем один раз: прошли или закрыли — она больше не
  /// появится. Флаг локальный, у каждого свой: тест проходят по отдельности.
  static Future<bool> loveTestPromptDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loveDismissedKey) ?? false;
  }

  static Future<void> dismissLoveTestPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loveDismissedKey, true);
  }

  static const _loveAdAtKey = 'love_test_ad_at';

  /// Когда перед результатом теста последний раз крутили ролик (epoch-ms).
  /// Ноль — ни разу. Пауза между показами живёт в `models/love_test_ad.dart`.
  static Future<int> loveTestAdAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_loveAdAtKey) ?? 0;
  }

  static Future<void> setLoveTestAdAt(int nowMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_loveAdAtKey, nowMs);
  }

  static Future<void> setPlusPromoShown(int nowMs) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(kPlusPromoAt, nowMs);
  }

  /// Отметка первого запуска. Ставится один раз и дальше только читается.
  static Future<int> firstRunAt(int nowMs) async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getInt(kFirstRunAt) ?? 0;
    if (saved > 0) return saved;
    await p.setInt(kFirstRunAt, nowMs);
    return nowMs;
  }

  // ── Лента воспоминаний ──
  /// Чем упорядочена лента: `eventDate` (когда это случилось) или `addedAt`
  /// (когда занесли). Выбор человека, а не состояние экрана.
  static const String kMemorySort = 'memory_sort';

  static Future<String?> memorySort() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kMemorySort);
  }

  static Future<void> setMemorySort(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kMemorySort, value);
  }
}
