#!/usr/bin/env bash
# Ночная сверка вынесенных коллекций: SQLite PocketBase -> Postgres.
# Старые сборки, попавшие мимо новых маршрутов, и любые ручные правки в PB
# доедут в Postgres, а не растворятся. Обычно доливает ноль строк.
set -a; . /opt/hotpath/env; set +a
for t in chat_messages mood_entries memories widget_data canvas_meta canvas_strokes; do
  echo "$(date -Is) $(/opt/hotpath/venv/bin/python /opt/hotpath/reconcile_table.py "$t" --commit 2>&1 | head -1)"
done

# Пары сверяются ИНАЧЕ. Источник правды по ним — Postgres, поэтому долив
# SQLite -> PG допустим только для строк, которых там нет вовсе (иначе
# откатятся свежие правки). Счётчики сверяются по значениям, а не по времени:
# их пишет прямой UPDATE, колонку updated он не двигает.
echo "$(date -Is) $(/opt/hotpath/venv/bin/python /opt/hotpath/verify_groups.py --only-missing --show 0 2>&1 | tail -2 | head -1)"

# Список пар человека открывает ему запись во все коллекции, оставшиеся в
# PocketBase: пустой список означает «не удалось сохранить» при живой паре.
echo "$(date -Is) $(/opt/hotpath/venv/bin/python /opt/hotpath/check_membership.py --fix 2>&1 | sed -n '2p')"

# Догон зеркала. Периодический проход идёт по отметке времени и берёт строки
# ПОСЛЕ неё: если пачка упала (SQLite был занят), а пара к тому времени больше
# не правилась, расхождение застывает — зеркало её уже не выберет. Раз в сутки
# доливаем все правки суток целиком, это секунды и несколько тысяч строк.
echo "$(date -Is) $(/opt/hotpath/venv/bin/python /opt/hotpath/rollback_groups.py --since "$(date -u -d '25 hours ago' '+%Y-%m-%d %H:%M:%S')" --commit 2>&1 | tail -1)"

# Счётчики приводим к фактическим записям — считать вернее, чем копировать.
echo "$(date -Is) $(/opt/hotpath/venv/bin/python /opt/hotpath/recount_group_counters.py --commit 2>&1 | head -2 | tr '\n' ' ')"
