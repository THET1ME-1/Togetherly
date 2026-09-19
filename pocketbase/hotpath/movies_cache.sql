-- Кэш поиска фильмов (19.09.2026, movies.py).
-- wd_cache — ужатые записи Викиданных: фильмы и страны. Полная запись весит
-- сотни килобайт, здесь от силы полтора, и повторный поиск того же фильма
-- в Викиданные за ней не ходит.
-- movie_query_cache — готовые ответы по запросу и языку.
CREATE TABLE IF NOT EXISTS wd_cache (
    qid     text   PRIMARY KEY,
    data    jsonb  NOT NULL,
    updated bigint NOT NULL
);
CREATE TABLE IF NOT EXISTS movie_query_cache (
    key     text   PRIMARY KEY,
    docs    jsonb  NOT NULL,
    source  text   NOT NULL,
    updated bigint NOT NULL
);
