-- Запись пары в Postgres. Копия схемы коллекции groups из PocketBase:
-- 47 колонок, типы по образцу уже переехавших таблиц (text NOT NULL DEFAULT '',
-- числа double precision, json — jsonb).
--
-- Таблица в SQLite НЕ удаляется и остаётся живым зеркалом: правила доступа
-- остальных коллекций ходят через relation users.group_ids -> groups, а отчёты
-- админки джойнят группы с users, которые остались в PocketBase.

CREATE TABLE IF NOT EXISTS groups (
    id                          text PRIMARY KEY,

    -- состав пары и денормализованные карты по участникам
    members                     jsonb,
    member_names                jsonb,
    member_avatars              jsonb,
    member_birthdays            jsonb,
    member_moods                jsonb,
    member_ailments             jsonb,
    max_members                 double precision NOT NULL DEFAULT 0,

    -- отношения
    relationship_type           text NOT NULL DEFAULT '',
    custom_relationship_label   text NOT NULL DEFAULT '',
    custom_relationship_emoji   text NOT NULL DEFAULT '',
    custom_relationship_types   jsonb,
    start_date                  text NOT NULL DEFAULT '',
    anniversary_date            text NOT NULL DEFAULT '',
    first_kiss_date             text NOT NULL DEFAULT '',

    -- статусы и счётчики
    current_status              jsonb,
    custom_statuses             jsonb,
    memories_count              double precision NOT NULL DEFAULT 0,
    drawings_count              double precision NOT NULL DEFAULT 0,
    messages_count              double precision NOT NULL DEFAULT 0,
    xp                          double precision NOT NULL DEFAULT 0,

    -- серия совместных заходов
    streak_days                 double precision NOT NULL DEFAULT 0,
    streak_last_opened_date     text NOT NULL DEFAULT '',
    streak_pending_date         text NOT NULL DEFAULT '',
    streak_pending_uid          text NOT NULL DEFAULT '',
    daily_tasks                 jsonb,

    -- маскот
    active_mascot_id            text NOT NULL DEFAULT '',
    mascot_position_x           double precision NOT NULL DEFAULT 0,
    mascot_position_y           double precision NOT NULL DEFAULT 0,
    mascot_scale                double precision NOT NULL DEFAULT 0,
    mascots                     jsonb,
    mascot_streaks              jsonb,

    -- прочее имущество пары
    timers                      jsonb,
    active_session              jsonb,
    owned_features              jsonb,

    -- пара с пустым местом («он в армии»)
    waiting_mode                boolean NOT NULL DEFAULT false,
    placeholder_name            text NOT NULL DEFAULT '',
    placeholder_avatar          text NOT NULL DEFAULT '',
    return_date                 text NOT NULL DEFAULT '',
    claim_token                 text NOT NULL DEFAULT '',
    claim_uid                   text NOT NULL DEFAULT '',
    claim_name                  text NOT NULL DEFAULT '',
    claim_at                    double precision NOT NULL DEFAULT 0,

    -- жизненный цикл
    disbanded                   boolean NOT NULL DEFAULT false,
    disbanded_at                text NOT NULL DEFAULT '',
    created_at                  text NOT NULL DEFAULT '',
    updated                     text NOT NULL DEFAULT ''
);

-- Членство: правило коллекции в PocketBase — members ?~ @request.auth.id,
-- то есть «состоит ли этот человек в паре». На jsonb это containment-запрос
-- members @> '"uid"', и он обязан идти по индексу, иначе каждая проверка
-- прав превращается в скан 22 тысяч строк.
CREATE INDEX IF NOT EXISTS idx_groups_members
    ON groups USING gin (members jsonb_path_ops);

-- Дельта и сверка идут по времени правки.
CREATE INDEX IF NOT EXISTS idx_groups_updated ON groups (updated);

-- Код второго места ищется при возвращении из армии; пустых значений большинство.
CREATE INDEX IF NOT EXISTS idx_groups_claim_token
    ON groups (claim_token) WHERE claim_token <> '';

-- Отчёты админки считают живые пары и медиану жизни распавшихся.
CREATE INDEX IF NOT EXISTS idx_groups_disbanded ON groups (disbanded);
