-- История импульсов «Скучаю» (28.09.2026, макет «Скучаю: история дня»,
-- вариант А). Запись miss_you держит только счётчик и ПОСЛЕДНИЙ импульс,
-- каждый новый затирал прежний: за день партнёр видел одно «Скучаю», хотя
-- утром было «Хочу обнять». Здесь каждый импульс — своя строка.
--
-- Частые тапы склеиваются в одну строку (count), если тот же человек шлёт
-- тот же импульс в пределах минуты: иначе зажатый палец дал бы сотню строк.
-- Живёт трое суток — экран показывает сегодня, в крайнем случае вчера.
--
-- Откат: DROP TABLE miss_you_events;
CREATE TABLE IF NOT EXISTS miss_you_events (
  id        text PRIMARY KEY,
  group_id  text NOT NULL,
  user_uid  text NOT NULL,
  vibe      text NOT NULL,
  text      text NOT NULL DEFAULT '',
  count     integer NOT NULL DEFAULT 1,
  reply_to  text,
  created   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS miss_you_events_group_created ON miss_you_events (group_id, created DESC);
