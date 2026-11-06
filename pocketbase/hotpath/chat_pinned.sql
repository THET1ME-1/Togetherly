-- Закреплённые сообщения чата (06.11.2026): когда закрепили (epoch-ms, 0 —
-- нет) и кто. Закрепляет любой из пары, страж пускает эти поля и не автору.
--
-- Колонки с константным умолчанием — ALTER мгновенный, таблицу не переписывает.
-- Индекс — отдельным файлом `chat_pinned_index.sql`: в таблице 3,3 млн строк,
-- и обычный CREATE INDEX на время стройки остановил бы запись в чат.
--
-- Откат:
--   DROP INDEX IF EXISTS idx_chat_messages_pinned;
--   ALTER TABLE chat_messages DROP COLUMN pinned_by, DROP COLUMN pinned_at;

ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS pinned_at double precision NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS pinned_by text NOT NULL DEFAULT '';
