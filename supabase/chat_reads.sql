-- ============================================================
-- Togetherly — Этап 5 миграции (срез 2): статусы прочтения чата.
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
-- Идемпотентный (IF NOT EXISTS) — можно запускать повторно.
-- ============================================================
-- Зеркало RTDB chats/{groupId}/reads/{uid} = lastReadTs (ms-epoch) →
-- public.chat_reads. Для галочек «прочитано». Сообщения чата уже читаются
-- из chat_messages; receipts были последним чтением чата из RTDB.
-- Низкочастотная запись (markRead троттлится по росту ts на клиенте).
-- RLS off (Фаза 1), keys = TEXT.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.chat_reads (
  group_id     TEXT        NOT NULL,
  user_uid     TEXT        NOT NULL,
  last_read_ts BIGINT      NOT NULL DEFAULT 0,  -- ms-since-epoch последнего прочитанного
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (group_id, user_uid)
);
ALTER TABLE public.chat_reads DISABLE ROW LEVEL SECURITY;

-- ── Realtime ──────────────────────────────────────────────────
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_reads; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
