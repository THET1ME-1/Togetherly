-- Отметки цикла, желания и категории желаний переезжают в Postgres, настройки
-- приложения получают копию для чтения (ночь на 19.10.2026). Форма повторяет
-- коллекции PocketBase, чтобы ответы hotpath не отличались от прежних.
-- Уникальных ключей, кроме id, у этих коллекций в SQLite нет.

CREATE TABLE IF NOT EXISTS cycle_entries (
  id        text PRIMARY KEY,
  group_id  text NOT NULL DEFAULT '',
  user_uid  text NOT NULL DEFAULT '',
  day       text NOT NULL DEFAULT '',
  kind      text NOT NULL DEFAULT '',
  flow      text NOT NULL DEFAULT '',
  shared    boolean NOT NULL DEFAULT false,
  created   text NOT NULL DEFAULT '',
  updated   text NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_cycle_entries_group_user_day ON cycle_entries (group_id, user_uid, day);
CREATE INDEX IF NOT EXISTS idx_cycle_entries_group_updated ON cycle_entries (group_id, updated);

CREATE TABLE IF NOT EXISTS wishes (
  id          text PRIMARY KEY,
  group_id    text NOT NULL DEFAULT '',
  author_uid  text NOT NULL DEFAULT '',
  title       text NOT NULL DEFAULT '',
  note        text NOT NULL DEFAULT '',
  category    text NOT NULL DEFAULT '',
  symbol      text NOT NULL DEFAULT '',
  done        boolean NOT NULL DEFAULT false,
  done_at     text NOT NULL DEFAULT '',
  done_by     text NOT NULL DEFAULT '',
  done_note   text NOT NULL DEFAULT '',
  kind        text NOT NULL DEFAULT '',
  price       double precision NOT NULL DEFAULT 0,
  currency    text NOT NULL DEFAULT '',
  url         text NOT NULL DEFAULT '',
  image       text NOT NULL DEFAULT '',
  shop        text NOT NULL DEFAULT '',
  created     text NOT NULL DEFAULT '',
  updated     text NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_wishes_group_created ON wishes (group_id, created);
CREATE INDEX IF NOT EXISTS idx_wishes_group_updated ON wishes (group_id, updated);

CREATE TABLE IF NOT EXISTS wish_categories (
  id          text PRIMARY KEY,
  group_id    text NOT NULL DEFAULT '',
  author_uid  text NOT NULL DEFAULT '',
  title       text NOT NULL DEFAULT '',
  symbol      text NOT NULL DEFAULT '',
  note        text NOT NULL DEFAULT '',
  created     text NOT NULL DEFAULT '',
  updated     text NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_wish_categories_group_created ON wish_categories (group_id, created);
CREATE INDEX IF NOT EXISTS idx_wish_categories_group_updated ON wish_categories (group_id, updated);

-- Копия, а не перенос: правда о настройках остаётся в SQLite (их правят
-- руками и читают хуки), сюда её кладёт _app_config_worker раз в 15 секунд.
CREATE TABLE IF NOT EXISTS app_config (
  id                   text PRIMARY KEY,
  min_build            double precision NOT NULL DEFAULT 0,
  updated_at           text NOT NULL DEFAULT '',
  gifts_enabled        boolean NOT NULL DEFAULT false,
  wishes_enabled       boolean NOT NULL DEFAULT false,
  widget_diag_enabled  boolean NOT NULL DEFAULT false,
  wallet               jsonb,
  chest_enabled        boolean NOT NULL DEFAULT false,
  room_native_ios      double precision NOT NULL DEFAULT 0
);
