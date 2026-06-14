/// Конфигурация миграции Firebase → Supabase.
///
/// Фаза 1: двое тестовых пользователей читают данные из Supabase,
///         остальные — по-прежнему из Firebase.
/// Фаза 2: двойная запись (Firebase + Supabase).
/// Фаза 3: все читают из Supabase.
/// Фаза 4: Firebase отключается.
abstract final class MigrationConfig {
  // ──────────────────────────────────────────────────────────────
  // Supabase credentials
  // Заполни после создания проекта на supabase.com:
  //   Project Settings → API → Project URL + anon public key
  // ──────────────────────────────────────────────────────────────
  static const String supabaseUrl = 'https://xxjlzzkhrvyiqaexvymx.supabase.co';
  // «publishable key» из Supabase → Project Settings → API Keys.
  // ВНИМАНИЕ: сюда идёт ТОЛЬКО publishable (sb_publishable_...),
  // НИКОГДА не secret (sb_secret_...) — секретный обходит RLS.
  static const String supabasePublishableKey =
      'sb_publishable_CjlP42zWZwPWGiUcbHC07w_qH9GZyuO';

  // ──────────────────────────────────────────────────────────────
  // ПУБЛИЧНЫЙ РЕЛИЗ: миграция ВЫКЛЮЧЕНА для всех (false).
  //
  // Почему НЕ true в проде: при поэтапном обновлении пары обновляются в
  // разное время. Обновлённый партнёр писал бы только в Supabase, а
  // отставший (старый билд) — только в Firebase → они не видят данные
  // друг друга, и записи отставшего безвозвратно теряются после выключения
  // Firebase. Плюс RLS выключен и publishable-ключ лежит в APK → без RLS
  // публичная база читается/пишется кем угодно. Поэтому для широкой
  // аудитории миграция остаётся за гейтом.
  //
  // Публичные юзеры (false + не в whitelist) работают на Firebase ровно как
  // раньше; 3 аккаунта ниже продолжают обкатку миграции на Supabase.
  //
  // ЧТОБЫ ВКЛЮЧИТЬ МИГРАЦИЮ ПУБЛИЧНО (true) — сперва закрыть два блокера:
  //   1) Смешанные пары: активировать Supabase для группы ТОЛЬКО когда ОБА
  //      партнёра на новом билде (маркер в group-doc), до этого — Firebase
  //      + Supabase-зеркало; ИЛИ форс-апдейт обоих.
  //   2) Безопасность: включить RLS + доступ по Firebase-JWT (или Edge
  //      Functions с проверкой ID-токена).
  // ──────────────────────────────────────────────────────────────
  static const bool enabledForEveryone = false;

  static const Set<String> _phase1Emails = {
    'badzoff@gmail.com',
    'ashatilov2008@gmail.com',
    'sasamatrosov87@gmail.com',
  };

  /// true — если этого пользователя читаем/пишем через Supabase.
  /// При [enabledForEveryone] — любой залогиненный юзер (есть email).
  static bool isPhase1User(String? email) {
    if (email == null) return false;
    if (enabledForEveryone) return true;
    return _phase1Emails.contains(email.toLowerCase());
  }

  /// true — Supabase credentials заполнены (не placeholder).
  static bool get isConfigured =>
      !supabaseUrl.contains('YOUR_PROJECT') &&
      !supabasePublishableKey.contains('YOUR_ANON');
}
