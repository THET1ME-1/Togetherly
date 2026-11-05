-- Часы в приложении для званий (05.11.2026, hotpath: /api/user/app-time).
-- Применять: docker exec -i supabase-db psql -U postgres -d postgres < app_time.sql
-- Повторный запуск ничего не ломает.

CREATE TABLE IF NOT EXISTS user_app_time (
  uid text PRIMARY KEY,
  seconds bigint NOT NULL DEFAULT 0,
  -- последнее звание, чей экран человек уже видел; только растёт
  rank_seen int NOT NULL DEFAULT -1
);

-- Когда телефон отчитался в последний раз: по нему сервер не засчитывает
-- больше реального времени. Телефонов на человека не больше пяти.
CREATE TABLE IF NOT EXISTS app_time_devices (
  uid text NOT NULL,
  device text NOT NULL,
  reported_at bigint NOT NULL,
  PRIMARY KEY (uid, device)
);
