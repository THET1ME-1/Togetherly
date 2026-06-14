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
  // МИГРАЦИЯ ВКЛЮЧЕНА ДЛЯ ВСЕХ (true) — Stage 2.
  //
  // Каждый, кто обновится, участвует в миграции: ДВОЙНАЯ запись (Firebase —
  // источник + зеркало в Supabase), ЧТЕНИЕ из Firebase (см. _readSb=false в
  // сервисах). Это безопасно для смешанных пар: и старая, и новая версия
  // читают/пишут общий источник Firebase, никто не теряет данные; Supabase
  // тем временем наполняется для будущего переключения чтения (Stage 3).
  //
  // ⚠️ ПЕРЕД ПУБЛИКАЦИЕЙ (тег релиза) ОБЯЗАТЕЛЬНО закрыть безопасность Supabase:
  //   выполнить supabase/security.sql (RLS) + включить Third-Party Auth Firebase
  //   в панели Supabase (см. supabase/SECURITY_RUNBOOK.md). Без этого открытая
  //   база читается/пишется кем угодно (publishable-ключ лежит в APK).
  // ──────────────────────────────────────────────────────────────
  static const bool enabledForEveryone = true;

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
