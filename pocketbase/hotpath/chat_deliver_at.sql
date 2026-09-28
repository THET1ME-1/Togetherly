-- Сообщение «к утру» (28.09.2026): срок, до которого сообщение видит только
-- автор. 0 — обычное сообщение. Выпускает `_deliver_worker` в hotpath.
--
-- Константное умолчание — ALTER проходит мгновенно, таблицу не переписывает.
-- Частичный индекс держит только придержанные: их единицы, а воркер ходит
-- по нему раз в двадцать секунд.
--
-- Откат:
--   DROP INDEX IF EXISTS chat_messages_deliver_at;
--   ALTER TABLE chat_messages DROP COLUMN deliver_at;

ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS deliver_at double precision NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS chat_messages_deliver_at
  ON chat_messages (deliver_at) WHERE deliver_at > 0;
