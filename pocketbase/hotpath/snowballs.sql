-- Снежки темы «Новый год» (27.11.2026). Каждая строка — брошенный снежок:
-- кто бросил и в какую пару. Партнёр в приложении получает его сразу (канал
-- пары), не в приложении — пуш и попадание при следующем открытии: для этого
-- seen_at (показан ли партнёру) и pushed (ушёл ли пуш; пуш не чаще раза в
-- 10 минут на пару). Живёт сутки — старые строки чистит маршрут.
--
-- Откат: DROP TABLE snowballs;
CREATE TABLE IF NOT EXISTS snowballs (
  id        text PRIMARY KEY,
  group_id  text NOT NULL,
  from_uid  text NOT NULL,
  pushed    boolean NOT NULL DEFAULT false,
  seen_at   timestamptz,
  created   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS snowballs_group_created ON snowballs (group_id, created);
CREATE INDEX IF NOT EXISTS snowballs_from_created ON snowballs (from_uid, created);
