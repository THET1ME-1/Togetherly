-- Тест «Умение любить» и маскоты пары переезжают в Postgres (ночь на 19.10.2026).
-- Форма повторяет коллекции PocketBase, чтобы ответы hotpath не отличались от
-- прежних. Уникальные индексы те же, что в SQLite: на отказе по ним приложение
-- строит «найди или создай» (_upsertByFilter, _upsertById).

CREATE TABLE IF NOT EXISTS love_tests (
  id        text PRIMARY KEY,
  group_id  text NOT NULL DEFAULT '',
  user_uid  text NOT NULL DEFAULT '',
  data      jsonb,
  total     double precision NOT NULL DEFAULT 0,
  updated   text NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_love_tests_group_user ON love_tests (group_id, user_uid);
CREATE INDEX IF NOT EXISTS idx_love_tests_group_updated ON love_tests (group_id, updated);

CREATE TABLE IF NOT EXISTS mascots (
  id             text PRIMARY KEY,
  group_id       text NOT NULL DEFAULT '',
  mascot_id      text NOT NULL DEFAULT '',
  name           text NOT NULL DEFAULT '',
  image_url      text NOT NULL DEFAULT '',
  default_asset  text NOT NULL DEFAULT '',
  created_by     text NOT NULL DEFAULT '',
  created_at     text NOT NULL DEFAULT '',
  is_default     boolean NOT NULL DEFAULT false,
  record_streak  double precision NOT NULL DEFAULT 0,
  updated        text NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_mascots_group_mascot ON mascots (group_id, mascot_id);
CREATE INDEX IF NOT EXISTS idx_mascots_group_updated ON mascots (group_id, updated);
