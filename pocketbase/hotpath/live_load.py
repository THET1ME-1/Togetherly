#!/usr/bin/env python3
"""Живой замер за 20 секунд на основном сервере. Только читает.

Сколько процессора съела каждая служба, сколько запросов пришло в
PocketBase (8090) и в hotpath (8120), во что обошёлся один запрос и сколько
запросов PocketBase ждёт соединения с базой. Запросы считает tcpdump по
первой строке HTTP, процессор — cgroup служб.

    python3 live_load.py

19.10.2026 в 01:14: сервер занят на 29% из 8 ядер, к базе PocketBase не ждёт
ни один запрос, PocketBase 30 запросов в секунду по 7,6 мс процессора,
hotpath 334 запроса по 2,4 мс.
"""

import collections
import re
import subprocess
import time
import urllib.request

ОКНО = 20


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


def весь_процессор():
    with open("/proc/stat") as f:
        vals = list(map(int, f.readline().split()[1:]))
    return sum(vals), vals[3] + vals[4]


def очередь():
    """Всего горутин PocketBase и сколько ждут соединения с базой.

    Ищется именно `(*DB).conn+`: у служебной `connectionOpener` то же
    начало имени, и она живёт всегда."""
    raw = urllib.request.urlopen(
        "http://127.0.0.1:6060/debug/pprof/goroutine?debug=1", timeout=10).read().decode()
    всего = int(re.search(r"total (\d+)", raw).group(1))
    ждут = 0
    for блок in raw.split("\n\n"):
        m = re.match(r"(\d+) @", блок)
        if m and "database/sql.(*DB).conn+" in блок:
            ждут += int(m.group(1))
    return всего, ждут


def ключ(метод, путь):
    части = путь.split("?")[0].strip("/").split("/")
    if len(части) >= 3 and части[:2] == ["api", "collections"]:
        return f"{метод} {части[2]}"
    return f"{метод} /" + "/".join(части[:3])


службы = {name: группа(name) for name in ("pocketbase", "hotpath", "caddy", "centrifugo", "nginx")}
службы["postgres"] = группа_докера("supabase-db")

всего_до, ждут_до = очередь()
до = {k: мкс(v) for k, v in службы.items()}
t_до, idle_до = весь_процессор()
начало = time.time()

методы = ("0x47455420", "0x504f5354", "0x50415443", "0x44454c45")  # GET POST PATC DELE
фильтр = ("tcp and (dst port 8090 or dst port 8120) and ("
          + " or ".join(f"tcp[((tcp[12:1] & 0xf0) >> 2):4] = {h}" for h in методы) + ")")
дамп = subprocess.run(["timeout", str(ОКНО), "tcpdump", "-i", "any", "-nn", "-l", "-A", "-s", "400", фильтр],
                      capture_output=True, text=True, errors="replace").stdout

прошло = time.time() - начало
после = {k: мкс(v) for k, v in службы.items()}
t_после, idle_после = весь_процессор()
всего_после, ждут_после = очередь()

порт = None
счёт = collections.Counter()
по_порту = collections.Counter()
for строка in дамп.splitlines():
    m = re.search(r"> [\d.]+\.(8090|8120): ", строка)
    if m:
        порт = m.group(1)
        continue
    m = re.search(r"(GET|POST|PATCH|DELETE) (/\S*) HTTP/1", строка)
    if m and порт:
        счёт[(порт, ключ(m.group(1), m.group(2)))] += 1
        по_порту[порт] += 1
        порт = None

занято = 1 - (idle_после - idle_до) / max(1, t_после - t_до)
print(f"окно {прошло:.1f} с, сервер занят {занято * 100:.0f}% от 8 ядер")
print(f"горутины PocketBase: {всего_до} → {всего_после}, из них ждут базу: {ждут_до} → {ждут_после}")
for name in службы:
    ядер = (после[name] - до[name]) / 1e6 / прошло
    print(f"  {name:11s} {ядер * 100:5.0f}% одного ядра")
for p, name in (("8090", "pocketbase"), ("8120", "hotpath")):
    n = по_порту[p]
    мс = (после[name] - до[name]) / 1000
    print(f"{name}: {n / прошло:.1f} запросов/с, {мс / max(n, 1):.2f} мс процессора на запрос")
    for (pp, k), c in счёт.most_common():
        if pp == p and c / прошло >= 0.3:
            print(f"    {c / прошло:6.1f}/с  {k}")
