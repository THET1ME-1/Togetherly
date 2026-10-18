#!/usr/bin/env python3
"""Одинаковые запросы в PocketBase и в hotpath: сколько процессора стоит каждый.

Берёт живую пару, выписывает участнику токен тем же ключом, что PocketBase
(ничего не пишет), и шлёт пачку одинаковых запросов сперва в PocketBase
(127.0.0.1:8090), потом в hotpath (127.0.0.1:8120). Процессор меряется по
cgroup службы, у hotpath вместе с Postgres. Фон за окна до и после пачки
вычитается. Колонка «PB во время hp» ловит запросы, которые hotpath отдал
самому PocketBase.

    set -a; . /opt/hotpath/env; set +a
    /opt/hotpath/venv/bin/python bench_pb_vs_hp.py [часть названия ...]

Замер 19.10.2026 в 01:20 (мс на запрос, PocketBase / hotpath+Postgres):
профиль 0,99 / 1,20, подарки 3,82 / 5,06, настройки 0,80 / 1,46, пропуск в
канал 0,98 / 1,36, «Умение любить» 11,49 / 1,35, карточка 1,38 / 0,79, токен
подключения 0,14 / 1,01, каталог 15,56 / 27,56, после кэша готового ответа
17,21 / 0,61.
"""

import base64
import collections
import hashlib
import hmac
import json
import sqlite3
import subprocess
import sys
import threading
import time

import httpx

PB = "http://127.0.0.1:8090"
HP = "http://127.0.0.1:8120"
DB = "/opt/pocketbase/pb_data/data.db"
N = 1000
ПОТОКОВ = 6
ФОН = 3.0


def группа(unit):
    cg = subprocess.run(["systemctl", "show", "-p", "ControlGroup", "--value", unit],
                        capture_output=True, text=True).stdout.strip()
    return f"/sys/fs/cgroup{cg}"


def группа_докера(name):
    cid = subprocess.run(["docker", "inspect", "-f", "{{.Id}}", name],
                         capture_output=True, text=True).stdout.strip()
    return f"/sys/fs/cgroup/system.slice/docker-{cid}.scope"


def мкс(path):
    with open(f"{path}/cpu.stat") as f:
        for line in f:
            k, v = line.split()
            if k == "usage_usec":
                return int(v)
    return 0


def b64u(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def токен(uid, token_key, secret):
    head = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = b64u(json.dumps({"collectionId": "_pb_users_auth_", "id": uid, "type": "auth",
                            "refreshable": False, "exp": int(time.time()) + 900}).encode())
    sig = b64u(hmac.new((token_key + secret).encode(), f"{head}.{body}".encode(),
                        hashlib.sha256).digest())
    return f"{head}.{body}.{sig}"


ГРУППЫ = {"pb": [группа("pocketbase")], "hp": [группа("hotpath"), группа_докера("supabase-db")]}


def снимок():
    return time.time(), {k: sum(мкс(c) for c in v) for k, v in ГРУППЫ.items()}


def пачка(base, метод, путь, params, body, h):
    коды = collections.Counter()
    замок = threading.Lock()

    def работник(k):
        with httpx.Client(timeout=30) as client:
            for i in range(k, N, ПОТОКОВ):
                hh = dict(h)
                # Свой адрес на запрос: лимиты PocketBase не примут пачку за
                # одного клиента и не тронут соседей с 127.0.0.1.
                hh["X-Forwarded-For"] = f"10.255.{i // 250}.{i % 250 + 1}"
                r = client.request(метод, base + путь, params=params, json=body, headers=hh)
                with замок:
                    коды[r.status_code] += 1

    нити = [threading.Thread(target=работник, args=(k,)) for k in range(ПОТОКОВ)]
    for t in нити:
        t.start()
    for t in нити:
        t.join()
    return коды


lite = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=30)
secret = json.loads(lite.execute(
    "SELECT options FROM _collections WHERE name='users'").fetchone()[0])["authToken"]["secret"]
gid, members = lite.execute("""
    SELECT g.id, g.members FROM groups g
    JOIN (SELECT group_id, count(*) n FROM gifts GROUP BY group_id) c ON c.group_id = g.id
    WHERE NOT coalesce(g.disbanded, 0) AND json_array_length(g.members) = 2
      AND c.n BETWEEN 15 AND 60
    ORDER BY g.updated DESC LIMIT 1""").fetchone()
a, b = json.loads(members)
key_a = lite.execute("SELECT tokenKey FROM users WHERE id = ?", (a,)).fetchone()[0]
h = {"Authorization": токен(a, key_a, secret)}


def по_паре(col, per):
    cols = {r[1] for r in lite.execute(f"PRAGMA table_info({col})")}
    p = {"filter": f'group_id = "{gid}"', "perPage": per}
    if "updated" in cols:
        p["sort"] = "-updated"
    return p


запросы = [
    ("свой профиль", "GET", f"/api/collections/users/records/{a}", None, None),
    ("подарки пары", "GET", "/api/collections/gifts/records", по_паре("gifts", 100), None),
    ("настройки приложения", "GET", "/api/collections/app_config/records", {"perPage": 1}, None),
    ("пропуск в канал", "POST", "/api/centrifugo/subscription-token", None, {"channel": f"pair:{gid}"}),
    ("тест любви", "GET", "/api/collections/love_tests/records", по_паре("love_tests", 50), None),
    ("карточка партнёра", "GET", "/api/user/card", {"uid": b}, None),
    ("токен подключения", "POST", "/api/centrifugo/connection-token", None, {}),
    ("каталог целиком", "GET", "/api/collections/catalog_items/records", {"perPage": 500}, None),
]
if sys.argv[1:]:
    запросы = [z for z in запросы if any(s in z[0] for s in sys.argv[1:])]

print(f"пачка {N} запросов, {ПОТОКОВ} потоков; мс процессора на один запрос")
print(f"{'запрос':22s} {'PocketBase':>11s} {'hotpath+PG':>11s} {'PB во время hp':>15s}  коды")
with httpx.Client(timeout=30) as c:
    for имя, метод, путь, params, body in запросы:
        коды = [c.request(метод, base + путь, params=params, json=body, headers=h).status_code
                for base in (PB, HP)]
        if коды != [200, 200]:
            print(f"{имя:22s} пропускаю, проба ответила {коды}")
            continue

        t0, c0 = снимок()
        time.sleep(ФОН)
        t1, c1 = снимок()
        коды_pb = пачка(PB, метод, путь, params, body, h)
        t2, c2 = снимок()
        time.sleep(ФОН)
        t3, c3 = снимок()
        коды_hp = пачка(HP, метод, путь, params, body, h)
        t4, c4 = снимок()
        time.sleep(ФОН)
        t5, c5 = снимок()

        фон_pb = ((c1["pb"] - c0["pb"]) + (c3["pb"] - c2["pb"])) / ((t1 - t0) + (t3 - t2))
        фон_hp = ((c3["hp"] - c2["hp"]) + (c5["hp"] - c4["hp"])) / ((t3 - t2) + (t5 - t4))
        pb_мс = ((c2["pb"] - c1["pb"]) - фон_pb * (t2 - t1)) / 1000 / N
        hp_мс = ((c4["hp"] - c3["hp"]) - фон_hp * (t4 - t3)) / 1000 / N
        pb_в_hp = ((c4["pb"] - c3["pb"]) - фон_pb * (t4 - t3)) / 1000 / N
        print(f"{имя:22s} {pb_мс:11.2f} {hp_мс:11.2f} {pb_в_hp:15.2f}  "
              f"{dict(коды_pb)} {dict(коды_hp)}")
