-- ============================================================
-- Togetherly — Этап 5 миграции (срез 1): маскоты + streak.
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
-- Идемпотентный (IF NOT EXISTS / CREATE OR REPLACE) — можно запускать повторно.
-- ============================================================
-- Зеркало Firestore:
--   groups/{g}/mascots/{mascotId}  → public.mascots (галерея маскотов пары)
--   group-doc floating/streak-поля → колонки public.groups:
--     activeMascotId            → active_mascot_id
--     mascotPositionX/Y, scale  → mascot_position_x / _y / mascot_scale
--     streakDays                → streak_days
--     streakLastOpenedDate      → streak_last_opened_date ('YYYY-MM-DD')
-- Колонка groups.mascots (JSONB) — рудимент старого подхода, НЕ используется
-- (реальные маскоты всегда жили в subcollection). Оставлена как есть.
-- realtime .stream() допускает один .eq(): маскоты фильтруются по group_id
-- напрямую (он уникален между группами), составной ключ не нужен.
-- RLS off (Фаза 1), keys = TEXT.
-- ============================================================

-- ── Галерея маскотов группы ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mascots (
  group_id      TEXT        NOT NULL,
  id            TEXT        NOT NULL,
  name          TEXT,
  image_url     TEXT,        -- URL рисованного маскота (Firebase/sb://); NULL у дефолтных
  default_asset TEXT,        -- asset-путь дефолтного маскота; NULL у рисованных
  created_by    TEXT,
  created_at    TIMESTAMPTZ,
  is_default    BOOLEAN     NOT NULL DEFAULT FALSE,
  record_streak INTEGER     NOT NULL DEFAULT 0,
  PRIMARY KEY (group_id, id)
);
ALTER TABLE public.mascots DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_mascots_group ON public.mascots(group_id);

-- ── Floating-маскот и streak в group-doc → колонки groups ─────
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS active_mascot_id        TEXT;
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS mascot_position_x       DOUBLE PRECISION;
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS mascot_position_y       DOUBLE PRECISION;
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS mascot_scale            DOUBLE PRECISION;
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS streak_days             INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS streak_last_opened_date TEXT;

-- ── Атомарный учёт ежедневной активности (streak) ────────────
-- Аналог FirebaseService.recordGroupActivity: оба партнёра могут открыть
-- приложение одновременно — read-modify-write с клиента терял бы инкремент.
-- FOR UPDATE + один UPDATE атомарны. Возвращает новый streak.
--   p_today = 'YYYY-MM-DD' (локальная дата клиента).
CREATE OR REPLACE FUNCTION public.group_record_activity(
  p_group_id TEXT,
  p_today    TEXT
) RETURNS INTEGER AS $$
DECLARE
  v_last   TEXT;
  v_cur    INTEGER;
  v_active TEXT;
  v_new    INTEGER;
BEGIN
  SELECT streak_last_opened_date, COALESCE(streak_days, 0), active_mascot_id
    INTO v_last, v_cur, v_active
    FROM public.groups
   WHERE id = p_group_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  IF v_last = p_today THEN
    RETURN v_cur;                       -- уже отметились сегодня
  END IF;
  IF v_last IS NOT NULL AND (p_today::date - v_last::date) = 1 THEN
    v_new := v_cur + 1;                 -- следующий подряд день
  ELSE
    v_new := 1;                         -- первый день или разрыв
  END IF;
  UPDATE public.groups
     SET streak_days = v_new, streak_last_opened_date = p_today
   WHERE id = p_group_id;
  -- Рекорд активного маскота
  IF v_active IS NOT NULL THEN
    UPDATE public.mascots
       SET record_streak = v_new
     WHERE group_id = p_group_id AND id = v_active AND record_streak < v_new;
  END IF;
  RETURN v_new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.group_record_activity(TEXT, TEXT)
  TO anon, authenticated;

-- ── Realtime ──────────────────────────────────────────────────
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.mascots; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
