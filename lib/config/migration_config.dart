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

  // ──────────────────────────────────────────────────────────────
  // STAGE 3 — ЧТЕНИЕ группы/чата/виджета из Supabase (экономия на Firebase-
  // чтениях). Включается ПОВЕРХ безопасных per-group гейтов (см.
  // FirebaseService._readSb): группа читается из Supabase ТОЛЬКО когда
  //   (1) оба партнёра на новой сборке (детектор sbMig),
  //   (2) бэкфилл данных+медиа группы завершён, и
  //   (3) это было подтверждено в ПРОШЛОЙ сессии (флаг из prefs) — источник
  //       чтения не меняется в середине сессии, без ребинда листенеров.
  // Firebase продолжает дуал-райтиться (полный фолбэк), поэтому флип обратим
  // БЕЗ потери данных: false здесь = мгновенный откат всех чтений на Firebase.
  //
  // ⚠️ Перед включением для реальных пар: убедиться, что Stage 1 (RLS +
  //    Firebase-токен, supabase/security.sql) применён и проверен на устройстве —
  //    иначе Supabase отдаёт пусто залогиненному участнику (данные не теряются,
  //    лежат в Firebase, но пара временно видит пусто до отката этого флага).
  // ──────────────────────────────────────────────────────────────
  static const bool stage3ReadFromSupabase = true;

  // ──────────────────────────────────────────────────────────────
  // STAGE 4 — убрать ИЗБЫТОЧНУЮ запись данных в Firebase для полностью
  // мигрированных групп (тех, что читаются из Supabase — см.
  // FirebaseService._writeFb). Срезает расходы на Firestore-ЗАПИСЬ.
  //
  // Под Stage 4 для такой группы данные (память/чат/комментарии/настроения/
  // холст/виджет/групповые поля) пишутся ТОЛЬКО в Supabase. НАМЕРЕННО остаются
  // в Firebase даже для мигрированных групп (их читают пуш-функции/Auth):
  //   • членство группы — members/memberNames/memberAvatars (роутинг пушей);
  //   • документы-события missYouEvents/widgetDataEvents/chatEvents (триггеры FCM);
  //   • users-doc (fcmTokens/профиль) и RTDB presence/missYou/push-токены;
  //   • Firebase Auth.
  //
  // ⚠️ ЭТО УБИРАЕТ СТРАХОВОЧНУЮ СЕТКУ: пока true, у мигрированной группы НЕТ
  //    свежей Firebase-копии данных → откат Stage 3 (stage3ReadFromSupabase=false)
  //    перестаёт быть безопасным для НОВЫХ записей (старые данные целы в Supabase
  //    и в Firebase-бэкфилле). ВКЛЮЧЕНО после проверки Stage 3 на 2 реальных
  //    устройствах: полностью мигрированная пара пишет данные И медиа только в
  //    Supabase (медиа роутится тем же гейтом — uploadFile/_uploadGroupMediaToSupabase).
  //    Откат всё ещё возможен: stage3ReadFromSupabase=false вернёт чтения на
  //    Firebase, но записи, сделанные под Stage 4, в Firebase не попадут.
  // ──────────────────────────────────────────────────────────────
  static const bool stage4DropFirebaseWrites = true;

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
