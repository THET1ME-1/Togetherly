"""Какие ошибки присылал человек или версия — даже если сами события удалены.

Bugsink хранит ограниченное число событий и прореживает их, но счётчики
меток (`release`, `user.id`) остаются навсегда. По ним видно, что приходило.

Запуск на сервере:
    docker exec -i bugsink python - --user <uid> < bugsink_who.py
    docker exec -i bugsink python - --release 1.37.1 < bugsink_who.py
"""
import argparse
import sqlite3

parser = argparse.ArgumentParser()
parser.add_argument("--user", default="")
parser.add_argument("--release", default="")
args = parser.parse_args()

if args.user:
    key, value = "user.id", args.user
elif args.release:
    key, value = "release", "%" + args.release + "%"
else:
    raise SystemExit("Нужен --user или --release")

db = sqlite3.connect("/data/db.sqlite3")

# Счётчики по группам ошибок
rows = db.execute(
    """select it.count, i.calculated_type, i.calculated_value, i.last_seen, i.id
       from tags_issuetag it
       join tags_tagkey k on k.id = it.key_id
       join tags_tagvalue v on v.id = it.value_id
       join issues_issue i on i.id = it.issue_id
       where k.key = ? and v.value like ?
       order by i.last_seen desc""",
    (key, value),
).fetchall()

if not rows:
    print("Ничего не приходило")
for count, kind, text, last_seen, issue_id in rows:
    # Сколько событий этой группы с этой меткой ещё лежит целиком
    stored = db.execute(
        """select count(*) from tags_eventtag et
           join tags_tagvalue v on v.id = et.value_id
           join tags_tagkey k on k.id = v.key_id
           where k.key = ? and v.value like ? and et.issue_id = ?""",
        (key, value, issue_id),
    ).fetchone()[0]
    title = (kind + ": " + text)[:110]
    print(f"{last_seen[:16]}  пришло {count:>4}  лежит {stored:>3}  {title}")
