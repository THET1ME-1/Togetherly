-- ============================================================
-- Togetherly — Этап 4 миграции: Supabase как ЕДИНСТВЕННОЕ хранилище
-- горячих данных (без dual-write в Firestore).
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
-- Идемпотентный (CREATE OR REPLACE) — можно запускать повторно.
--
-- Зачем RPC, а не update с клиента:
--  • member_moods / member_names / member_avatars / member_birthdays —
--    JSONB-карты «uid → значение». Оба партнёра пишут СВОИ ключи
--    одновременно; read-modify-write с клиента терял бы чужой ключ.
--    jsonb_set в одном UPDATE атомарен.
--  • memories_count / drawings_count — атомарный инкремент.
--  • memory_patch — частичная правка воспоминания: data || patch
--    (read-modify-write с клиента гонял бы весь JSONB и терял бы
--    параллельную правку партнёра).
-- ============================================================

-- ── Настроение участника на карточке (groups.member_moods) ──
CREATE OR REPLACE FUNCTION public.group_set_member_mood(
  p_group_id TEXT,
  p_uid      TEXT,
  p_mood     JSONB
) RETURNS VOID AS $$
  UPDATE public.groups
     SET member_moods = jsonb_set(
           COALESCE(member_moods, '{}'::jsonb), ARRAY[p_uid], p_mood)
   WHERE id = p_group_id;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION public.group_clear_member_mood(
  p_group_id TEXT,
  p_uid      TEXT
) RETURNS VOID AS $$
  UPDATE public.groups
     SET member_moods = COALESCE(member_moods, '{}'::jsonb) - p_uid
   WHERE id = p_group_id;
$$ LANGUAGE sql;

-- ── Имя/аватар участника (смена профиля должна доехать до партнёра) ──
CREATE OR REPLACE FUNCTION public.group_set_member_name(
  p_group_id TEXT,
  p_uid      TEXT,
  p_name     TEXT
) RETURNS VOID AS $$
  UPDATE public.groups
     SET member_names = jsonb_set(
           COALESCE(member_names, '{}'::jsonb), ARRAY[p_uid], to_jsonb(p_name))
   WHERE id = p_group_id;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION public.group_set_member_avatar(
  p_group_id TEXT,
  p_uid      TEXT,
  p_url      TEXT
) RETURNS VOID AS $$
  UPDATE public.groups
     SET member_avatars = jsonb_set(
           COALESCE(member_avatars, '{}'::jsonb), ARRAY[p_uid], to_jsonb(p_url))
   WHERE id = p_group_id;
$$ LANGUAGE sql;

-- ── День рождения участника (NULL = убрать дату) ──
CREATE OR REPLACE FUNCTION public.group_set_member_birthday(
  p_group_id TEXT,
  p_uid      TEXT,
  p_date     TIMESTAMPTZ
) RETURNS VOID AS $$
  UPDATE public.groups
     SET member_birthdays = CASE
           WHEN p_date IS NULL
             THEN COALESCE(member_birthdays, '{}'::jsonb) - p_uid
           ELSE jsonb_set(
             COALESCE(member_birthdays, '{}'::jsonb), ARRAY[p_uid], to_jsonb(p_date))
         END
   WHERE id = p_group_id;
$$ LANGUAGE sql;

-- ── Атомарные счётчики ленты/рисунков ──
CREATE OR REPLACE FUNCTION public.group_inc_counters(
  p_group_id TEXT,
  p_memories INT DEFAULT 0,
  p_drawings INT DEFAULT 0
) RETURNS VOID AS $$
  UPDATE public.groups
     SET memories_count = GREATEST(0, COALESCE(memories_count, 0) + p_memories),
         drawings_count = GREATEST(0, COALESCE(drawings_count, 0) + p_drawings)
   WHERE id = p_group_id;
$$ LANGUAGE sql;

-- ── Частичная правка воспоминания: data || patch + синк типизированных
--    колонок (edited_at / created_at / is_pinned), если они есть в патче ──
CREATE OR REPLACE FUNCTION public.memory_patch(
  p_id    TEXT,
  p_patch JSONB
) RETURNS VOID AS $$
  UPDATE public.memories
     SET data       = COALESCE(data, '{}'::jsonb) || p_patch,
         edited_at  = COALESCE(NULLIF(p_patch->>'editedAt',  '')::timestamptz, edited_at),
         created_at = COALESCE(NULLIF(p_patch->>'createdAt', '')::timestamptz, created_at),
         is_pinned  = COALESCE((p_patch->>'isPinned')::boolean, is_pinned)
   WHERE id = p_id;
$$ LANGUAGE sql;

-- ── Права (как у increment_miss_you) ──
GRANT EXECUTE ON FUNCTION
  public.group_set_member_mood(TEXT, TEXT, JSONB),
  public.group_clear_member_mood(TEXT, TEXT),
  public.group_set_member_name(TEXT, TEXT, TEXT),
  public.group_set_member_avatar(TEXT, TEXT, TEXT),
  public.group_set_member_birthday(TEXT, TEXT, TIMESTAMPTZ),
  public.group_inc_counters(TEXT, INT, INT),
  public.memory_patch(TEXT, JSONB)
TO anon, authenticated;
