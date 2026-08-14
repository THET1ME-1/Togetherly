-- Таблица «Скучаю» в Postgres. Форма повторяет коллекцию PocketBase, чтобы
-- ответы hotpath не отличались от прежних. Уникальный индекс по паре
-- (group_id, user_uid) нужен для атомарного INSERT … ON CONFLICT: именно он
-- заменяет прежний read-modify-write в транзакции SQLite.
CREATE TABLE IF NOT EXISTS miss_you (
  id             text PRIMARY KEY,
  group_id       text NOT NULL DEFAULT '',
  user_uid       text NOT NULL DEFAULT '',
  count          double precision NOT NULL DEFAULT 0,
  updated_at     text NOT NULL DEFAULT '',
  last_vibe      text NOT NULL DEFAULT '',
  last_vibe_text text NOT NULL DEFAULT '',
  by_weekday     jsonb,
  by_vibe        jsonb,
  updated        text NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_missyou_group_user ON miss_you (group_id, user_uid);
CREATE INDEX IF NOT EXISTS idx_missyou_group_updated ON miss_you (group_id, updated);
