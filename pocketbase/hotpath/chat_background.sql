-- Общий фон чата пары (Togetherly+), ссылка pb://media/<id>/<файл>.
--
-- Поле жило в collections_schema.json, но колонки не было ни в Postgres, ни
-- в SQLite: hotpath выбрасывал его молча, и фон не сохранялся ни разу (жалоба
-- 14.09.2026). В SQLite колонку не заводим — зеркало её пропускает
-- (НЕ_ЗЕРКАЛИМ в hotpath.py).
--
-- Константное умолчание: ALTER не переписывает таблицу.
--
-- Откат:
--   ALTER TABLE groups DROP COLUMN chat_background;

ALTER TABLE groups
  ADD COLUMN IF NOT EXISTS chat_background text NOT NULL DEFAULT '';
