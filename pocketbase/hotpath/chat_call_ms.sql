-- История звонков: запись «Звонок · 4:12» в чате пары несёт длительность.
--
-- Колонка с константным умолчанием — ALTER мгновенный, таблицу не переписывает.
-- Ноль значит «не звонок» (ChatMsg.fromPb коэрсит 0 в null).
--
-- Откат: ALTER TABLE chat_messages DROP COLUMN call_ms;

ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS call_ms double precision NOT NULL DEFAULT 0;
