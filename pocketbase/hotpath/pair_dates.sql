-- Наши даты (TOG-61, 28.11.2026): памятные даты пары и будильники напоминаний.
-- Коллекция живёт только в Postgres, в SQLite PocketBase её нет. Форма записи
-- та же, что у остальных коллекций hotpath: created/updated текстом в формате
-- PocketBase, json-поля — jsonb.

CREATE TABLE IF NOT EXISTS pair_dates (
  id          text PRIMARY KEY,
  group_id    text NOT NULL DEFAULT '',
  author_uid  text NOT NULL DEFAULT '',
  title       text NOT NULL DEFAULT '',
  symbol      text NOT NULL DEFAULT '',
  note        text NOT NULL DEFAULT '',
  day         text NOT NULL DEFAULT '',
  start_time  text NOT NULL DEFAULT '',
  tz          text NOT NULL DEFAULT '',
  rrule       text NOT NULL DEFAULT '',
  exdates     jsonb,
  reminders   jsonb,
  created     text NOT NULL DEFAULT '',
  updated     text NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_pair_dates_group_updated ON pair_dates (group_id, updated);
CREATE INDEX IF NOT EXISTS idx_pair_dates_group_day ON pair_dates (group_id, day);

-- Будильники: одна строка на (что, запись, человек, за сколько минут) —
-- ближайшее срабатывание. Сработала — строка забирается и ставится следующая.
-- kind: 'pair_date'; потом сюда же лягут ежедневные напоминания (TOG-113).
CREATE TABLE IF NOT EXISTS date_alarms (
  id        bigserial PRIMARY KEY,
  kind      text NOT NULL,
  ref_id    text NOT NULL,
  group_id  text NOT NULL DEFAULT '',
  uid       text NOT NULL,
  minutes   integer NOT NULL DEFAULT 0,
  occ       text NOT NULL DEFAULT '',
  fire_at   timestamptz NOT NULL,
  UNIQUE (kind, ref_id, uid, minutes)
);
CREATE INDEX IF NOT EXISTS idx_date_alarms_fire_at ON date_alarms (fire_at);
CREATE INDEX IF NOT EXISTS idx_date_alarms_ref ON date_alarms (kind, ref_id);
