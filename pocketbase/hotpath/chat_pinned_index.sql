-- Частичный индекс закреплённых (06.11.2026): их единицы, полоска над лентой
-- и экран «Все закреплённые» выбирают их по паре. CONCURRENTLY — запись в
-- чат во время стройки не встаёт; поэтому одна команда в файле, без
-- транзакции вокруг.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chat_messages_pinned
  ON chat_messages (group_id, ts) WHERE pinned_at > 0;
