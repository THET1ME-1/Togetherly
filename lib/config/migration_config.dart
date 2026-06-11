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
  // Фаза 2: миграция включена для ВСЕХ пользователей этой сборки
  // (не только тест-аккаунтов). Любой залогиненный юзер dual-write'ит
  // и читает из Supabase. Это dev-сборка — у прод-юзеров (Play Store /
  // main) Supabase-кода нет вовсе, так что флаг затрагивает только тех,
  // кто реально запускает эту ветку. Список ниже оставлен для отката.
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
