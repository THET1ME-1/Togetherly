-- Контур своей раскраски (23.09.2026). Приложение пишет ссылку на контур в
-- canvas_meta.coloring_outline, а колонки в Postgres не было: hotpath молча
-- выбрасывал поле, и партнёр получал пустой лист без контура.
ALTER TABLE canvas_meta ADD COLUMN IF NOT EXISTS coloring_outline text NOT NULL DEFAULT '';
