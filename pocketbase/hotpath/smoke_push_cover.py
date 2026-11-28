"""Обложки «А» по боевой базе: собирает каждый вид и проверяет, что ссылки
на картинки открываются (200). Только чтение.

На VPS:  /opt/hotpath/venv/bin/python /opt/hotpath/smoke_push_cover.py
"""
import json
import os
import sqlite3
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import push_cover  # noqa: E402

DB = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
lite = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)


# Тот же запрос, что `_каталог_для_обложки` в hotpath.
def look(item_id):
    row = lite.execute("SELECT files, data FROM catalog_items WHERE id = ? AND enabled = 1",
                       (item_id,)).fetchone()
    if row is None:
        return None
    return json.loads(row[0] or "[]"), json.loads(row[1] or "{}")


# Живой человек с аватаром и рамкой — для чата.
avatar, frame = lite.execute(
    "SELECT avatar_url, frame FROM users WHERE frame <> '' AND avatar_url LIKE 'pb://%' "
    "ORDER BY updated DESC LIMIT 1").fetchone()

ВИДЫ = [
    ("miss", {"from_name": "Алина", "body": "Хочу обнять"}),
    ("mood", {"from_name": "Алина", "mood_id": "love", "label": "Влюблённость"}),
    ("mood", {"from_name": "Алина", "mood_id": "kiss", "label": "Поцелуй"}),
    ("chat", {"from_name": "Алина", "body": "Ты дома?", "avatar": avatar, "frame": frame,
              "message_id": "m1", "group_id": "g1", "from_uid": "u1"}),
    ("date", {"from_name": "Алина", "title": "Концерт", "symbol": "theater_comedy"}),
    ("snowball", {"from_name": "Алина"}),
    ("date_remind", {"title": "Годовщина", "body": "Завтра", "symbol": "cake"}),
    ("evening", {"title": "Как прошёл день?", "body": "Отметь настроение"}),
    ("chest", {"title": "Сундук полный", "body": "Загляни"}),
    ("gift", {"from_name": "Алина", "gift_key": "heart", "title": "Сердце"}),
    ("gift", {"from_name": "Алина", "gift_key": "au_bouquet", "title": "Букет"}),
    ("gift", {"from_name": "Алина", "gift_key": "frame_au_bow", "title": "Рамка"}),
    ("comment", {"from_name": "Алина", "body": "Хочу туда"}),
    ("draw", {"from_name": "Алина", "title": "Порисуем?"}),
    ("plusgift", {"from_name": "Алина", "title": "Плюс"}),
    ("pair_reset", {"title": "Пароль меняют"}),
    ("reels", {"from_name": "Алина", "title": "Алина зовёт смотреть TikTok", "feed": "tiktok",
               "group_id": "g1", "from_uid": "u1"}),
    ("badge", {"title": "Вам вручён значок", "body": "Спасибо"}),
    ("mascot_miss", {"title": "Ту скучает"}),
    ("invite", {"title": "Позови партнёра"}),
    ("mood_lock", {"mood_id": "love", "choices": [{"id": "love", "label": "Люблю"},
                                                  {"id": "sad", "label": "Грущу"}]}),
]


def ссылки(c):
    for ключ in ("art", "art_big"):
        a = c.get(ключ) or {}
        if a.get("url") and not a.get("auth"):
            yield ключ, a["url"]
    чат = c.get("chat") or {}
    for ключ in ("avatar", "frame"):
        if чат.get(ключ):
            yield "chat." + ключ, чат[ключ]


def код(url):
    req = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception as e:  # noqa: BLE001
        return str(e)


плохо = 0
for вид, ctx in ВИДЫ:
    c = push_cover.cover(вид, "ru", ctx, look)
    if c is None:
        print(f"✗ {вид}: обложки нет")
        плохо += 1
        continue
    размер = len(json.dumps(c, ensure_ascii=False).encode())
    art = c.get("art")
    print(f"  {вид}: art={json.dumps(art, ensure_ascii=False)[:70]} · {размер} байт")
    if вид in ("miss", "mood", "snowball", "gift", "draw", "reels", "mood_lock") and art == {"app": True} \
            and ctx.get("mood_id") != "kiss":
        print(f"✗ {вид}: ждал картинку, а стоит иконка")
        плохо += 1
    if вид in ("mascot_miss", "invite") and not (c.get("art_big") or {}).get("url"):
        print(f"✗ {вид}: ждал картинку события в развёрнутом виде")
        плохо += 1
    for котик in c.get("moods") or []:
        ответ = код(котик["url"])
        if ответ != 200:
            print(f"✗ {вид} котик {котик['id']}: {ответ}")
            плохо += 1
    for ключ, url in ссылки(c):
        ответ = код(url)
        if ответ != 200:
            print(f"✗ {вид} {ключ}: {ответ} {url}")
            плохо += 1
print("ИТОГ:", "всё открывается" if плохо == 0 else f"провалов {плохо}")
sys.exit(1 if плохо else 0)
