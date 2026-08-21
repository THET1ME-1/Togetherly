-- Поля фигурок (видеосообщений в форме) в горячей таблице чата.
--
-- Колонки добавляются с константным умолчанием, поэтому ALTER проходит
-- мгновенно и таблицу не переписывает: на миллионах строк это важно.
--
-- Типы и NOT NULL повторяют соседей (voice_*): hotpath кладёт в text-поля
-- пустую строку, а в num — ноль, и различать «не задано» от нуля клиент умеет
-- сам (ChatMsg.fromPb коэрсит 0 и '' в null).
--
-- Откат:
--   ALTER TABLE chat_messages
--     DROP COLUMN note_url, DROP COLUMN note_ms, DROP COLUMN note_shape,
--     DROP COLUMN note_thumb, DROP COLUMN note_seen_at, DROP COLUMN note_hearts;

ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS note_url     text             NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS note_ms      double precision NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS note_shape   text             NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS note_thumb   text             NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS note_seen_at double precision NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS note_hearts  text             NOT NULL DEFAULT '';
