#!/usr/bin/env python3
"""Раз в пять минут записывает, сколько людей на связи с Centrifugo.

Centrifugo знает только текущее число, истории у него нет: вечерний пик
18.10.2026 сравнить было не с чем. Строка журнала: время по Москве,
соединения, люди.

    */5 * * * * /usr/bin/python3 /opt/pocketbase/tools/online_log.py
    журнал: /var/log/togetherly_online.log
"""

import datetime
import json
import urllib.request

CONFIG = "/opt/centrifugo/config.json"
LOG = "/var/log/togetherly_online.log"
MSK = datetime.timezone(datetime.timedelta(hours=3))


def ключ():
    with open(CONFIG) as f:
        c = json.load(f)
    return c.get("api_key") or c.get("http_api", {}).get("key", "")


def main():
    req = urllib.request.Request("http://127.0.0.1:9000/api/info", data=b"{}",
                                 headers={"X-API-Key": ключ()})
    nodes = json.load(urllib.request.urlopen(req, timeout=10))["result"]["nodes"]
    соединений = sum(n["num_clients"] for n in nodes)
    людей = sum(n["num_users"] for n in nodes)
    with open(LOG, "a") as f:
        f.write(f"{datetime.datetime.now(MSK):%Y-%m-%d %H:%M} {соединений} {людей}\n")


if __name__ == "__main__":
    main()
