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
  // Фаза 1: тестовые аккаунты
  // ──────────────────────────────────────────────────────────────
  static const Set<String> _phase1Emails = {
    'badzoff@gmail.com',
    'ashatilov2008@gmail.com',
    'sasamatrosov87@gmail.com',
  };

  /// true — если этого пользователя читаем из Supabase (Фаза 1).
  static bool isPhase1User(String? email) =>
      email != null && _phase1Emails.contains(email.toLowerCase());

  /// true — Supabase credentials заполнены (не placeholder).
  static bool get isConfigured =>
      !supabaseUrl.contains('YOUR_PROJECT') &&
      !supabasePublishableKey.contains('YOUR_ANON');
}
