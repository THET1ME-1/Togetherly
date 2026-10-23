"""Доступ к сайту по IPv6 из одной страны через Globalping (публичные узлы jsDelivr).

Зачем: запасной адрес edge.togetherly.day работает только по IPv6 (туннель
Hurricane Electric, см. раздел «Запасной путь для Украины» в CLAUDE.md). Скрипт
спрашивает узлы страны по IPv6, а если дописать последним доводом что угодно,
кроме only6, — следом те же узлы по IPv4: так видно, кого режут по обычному
адресу и пропускают по запасному.

Узлы Globalping читают только первые ~17 КБ ответа и рвут соединение сами:
для проверки больших файлов он не годится.

    python3 tools/globalping_ipv6.py edge.togetherly.day /api/health UA 14 only6
    python3 tools/globalping_ipv6.py games.togetherly.day /assets/games.css UA 12 both
"""
import json
import sys
import time
import urllib.request


def call(method, url, body=None):
    req = urllib.request.Request(
        url,
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Content-Type": "application/json", "User-Agent": "togetherly-check/1"},
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def measure(host, path, locations, ip_version):
    started = call("POST", "https://api.globalping.io/v1/measurements", {
        "type": "http",
        "target": host,
        "locations": locations,
        "measurementOptions": {
            "request": {"path": path, "method": "GET"},
            "protocol": "HTTPS",
            "ipVersion": ip_version,
        },
    })
    result = {}
    for _ in range(45):
        time.sleep(2)
        result = call("GET", f"https://api.globalping.io/v1/measurements/{started['id']}")
        if result.get("status") != "in-progress":
            break
    return started["id"], result


def show(title, result):
    answered = 0
    print(title)
    for row in result.get("results", []):
        probe, outcome = row["probe"], row["result"]
        code = outcome.get("statusCode")
        took = (outcome.get("timings") or {}).get("total")
        error = (outcome.get("rawOutput") or "")[:60].replace("\n", " ") if not code else ""
        answered += bool(code)
        print(f'  {probe.get("city", "?")[:12]:12} {probe.get("network", "?")[:26]:26} '
              f'AS{probe.get("asn")}  код={code} {took}мс {error}')
    print(f"  итого: ответили {answered} из {len(result.get('results', []))}")


def main():
    host, path, country, limit = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    only_ipv6 = len(sys.argv) > 5 and sys.argv[5] == "only6"
    measurement, by_ipv6 = measure(host, path, [{"country": country, "limit": limit}], 6)
    show(f"IPv6 {country}", by_ipv6)
    if only_ipv6:
        return
    # Те же узлы по IPv4: Globalping принимает номер прошлого замера как список узлов
    _, by_ipv4 = measure(host, path, measurement, 4)
    show(f"IPv4 {country}, те же узлы", by_ipv4)


if __name__ == "__main__":
    main()
