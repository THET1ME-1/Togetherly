-- ============================================================
-- Togetherly — МОРДОЧКА СООБЩЕНИЯ (выражение, выбранное отправителем).
-- Имя варианта (_FaceExpr: happy/love/wink/playful/sad/calm) или NULL — без лица.
-- Зеркалит RTDB chats/{groupId}/messages/{id}/face → public.chat_messages.face.
-- Run in: Supabase Dashboard → SQL Editor. Идемпотентно.
-- ============================================================

ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS face TEXT;
