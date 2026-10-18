"""Вернуть призы сундука, которые затёрла устаревшая запись пользователя.

Под перегрузкой запрос на правку users читает запись, минутами ждёт очереди
на запись и кладёт её целиком: выданный за это время приз пропадает.
Скрипт сверяет chest_opens за последние двое суток с записью человека: Плюс
навсегда, Плюс на неделю, рамки (кроме подаренных партнёру) и значки.

Без --commit только считает. С --commit дописывает недостающее одной
транзакцией, прежние значения кладёт в копию /root/chest-prizes-restore-bak-*.json.
"""
import json
import sqlite3
import sys
import time

DB = "/opt/pocketbase/pb_data/data.db"
SINCE = sys.argv[sys.argv.index("--since") + 1] if "--since" in sys.argv else None
COMMIT = "--commit" in sys.argv
WEEK_MS = 7 * 86400 * 1000

db = sqlite3.connect(DB, timeout=30)
db.execute("PRAGMA busy_timeout = 30000")
if SINCE is None:
    SINCE = db.execute("select strftime('%Y-%m-%d %H:%M:%S', 'now', '-2 days')").fetchone()[0]

lost_plus = db.execute(
    """select o.id, o.user_uid from chest_opens o join users u on u.id = o.user_uid
       where o.prize = 'plus' and o.created >= ? and coalesce(u.plus, 0) = 0""", (SINCE,)).fetchall()

# Срок недели считается от самого позднего выигрыша человека.
lost_week = db.execute(
    """select o.user_uid, max((strftime('%s', o.created) + 7 * 86400) * 1000) until_ms
       from chest_opens o join users u on u.id = o.user_uid
       where o.prize = 'plus7' and o.created >= ? and coalesce(u.plus, 0) = 0
       group by o.user_uid
       having max(coalesce(u.plus_trial_until, 0)) < max((strftime('%s', o.created) + 6 * 86400) * 1000)""",
    (SINCE,)).fetchall()


def as_list(raw):
    try:
        value = json.loads(raw or "[]")
        return value if isinstance(value, list) else []
    except ValueError:
        return []


lost_frames = db.execute(
    """select o.id, o.user_uid, o.prize, o.created from chest_opens o
       join users u on u.id = o.user_uid
       where o.prize like 'frame_%' and o.created >= ?
         and instr(coalesce(u.owned_features, ''), '"frame:' || o.prize || '"') = 0
         and not exists (select 1 from gifts g where g.sender_uid = o.user_uid and g.gift_key = o.prize)
       order by o.created""", (SINCE,)).fetchall()

lost_badges = db.execute(
    """select o.id, o.user_uid, o.prize, json_extract(c.data, '$.key'), o.created from chest_opens o
       join users u on u.id = o.user_uid
       join catalog_items c on c.id = o.prize
       where o.prize like 'badge_%' and o.created >= ?
         and json_extract(c.data, '$.key') is not null
         and instr(coalesce(u.owned_icons, ''), '"' || json_extract(c.data, '$.key') || '"') = 0
       order by o.created""", (SINCE,)).fetchall()

stamp = time.strftime("%Y-%m-%d %H:%M:%S")
total = len(lost_plus) + len(lost_week) + len(lost_frames) + len(lost_badges)
print(f"{stamp} с {SINCE}: Плюс навсегда {len(lost_plus)}, Плюс на неделю {len(lost_week)}, "
      f"рамок {len(lost_frames)}, значков {len(lost_badges)}")

if not COMMIT or total == 0:
    for row in (lost_plus + lost_week)[:5]:
        print("  Плюс", row)
    for row in lost_frames[:5]:
        print("  рамка", row)
    for row in lost_badges[:5]:
        print("  значок", row)
    sys.exit(0)

backup = {}
db.execute("BEGIN IMMEDIATE")
try:
    for _, uid in lost_plus:
        plus, platform = db.execute("select plus, plus_platform from users where id = ?", (uid,)).fetchone()
        backup.setdefault(uid, {})["plus"] = [plus, platform]
        db.execute("update users set plus = 1, plus_platform = 'chest' where id = ? and coalesce(plus, 0) = 0", (uid,))
    for uid, until_ms in lost_week:
        current = db.execute("select plus_trial_until from users where id = ?", (uid,)).fetchone()[0]
        backup.setdefault(uid, {})["plus_trial_until"] = current
        db.execute("update users set plus_trial_until = ? where id = ? and coalesce(plus_trial_until, 0) < ?",
                   (until_ms, uid, until_ms))
    for _, uid, prize, _ in lost_frames:
        features, icons = db.execute("select owned_features, owned_icons from users where id = ?", (uid,)).fetchone()
        backup.setdefault(uid, {}).setdefault("owned_features", features)
        items = as_list(features)
        key = "frame:" + prize
        if key not in items:
            items.append(key)
            db.execute("update users set owned_features = ? where id = ?", (json.dumps(items), uid))
    for _, uid, _, key, _ in lost_badges:
        features, icons = db.execute("select owned_features, owned_icons from users where id = ?", (uid,)).fetchone()
        backup.setdefault(uid, {}).setdefault("owned_icons", icons)
        items = as_list(icons)
        if key not in items:
            items.append(key)
            db.execute("update users set owned_icons = ? where id = ?", (json.dumps(items), uid))
    db.execute("COMMIT")
except Exception:
    db.execute("ROLLBACK")
    raise

path = f"/root/chest-prizes-restore-bak-{time.strftime('%Y%m%d-%H%M')}.json"
with open(path, "w", encoding="utf-8") as f:
    json.dump(backup, f, ensure_ascii=False)
print(f"{stamp} вернул: Плюс навсегда {len(lost_plus)}, Плюс на неделю {len(lost_week)}, "
      f"рамок {len(lost_frames)}, значков {len(lost_badges)}; копия прежних значений {path}")
