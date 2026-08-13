#!/usr/bin/env python3
"""История дохода по месяцам и годам для вкладки «Доход».

Копить с сегодняшнего дня не пришлось: прошлое лежит у всех четырёх источников.
Яндекс и AdMob отдают помесячную разбивку за любой период, отчёты Play лежат
в бакете за все месяцы, продажи lava разобраны из писем и хранятся в кеше
`/opt/income/.lava_mail_cache.json`.

Валюты. Рубли и евро приводим к доллару по СЕГОДНЯШНЕМУ курсу — исторических
курсов бесплатные источники не дают, поэтому в файле рядом лежат и нативные
суммы, и курс, по которому считали. Для сравнения месяцев этого достаточно, для
бухгалтерии — нет, и в этом надо отдавать себе отчёт.

Запуск: раз в сутки по крону (прошлые месяцы не меняются, текущий обновляет
основная сводка) — `python3 /opt/income/income_history.py`.
"""
import base64
import csv
import io
import json
import os
import subprocess
import time
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime, timezone

OUT = "/opt/pocketbase/pb_data/.income_history.json"
RSYA_TOKEN = "/opt/pocketbase/pb_data/.rsya_token"
ADMOB_CFG = "/opt/pocketbase/pb_data/.admob_oauth.json"
PLAY_SA = "/opt/income/play-access.json"
PLAY_BUCKET = "/opt/pocketbase/pb_data/.play_bucket"
LAVA_CACHE = "/opt/income/.lava_mail_cache.json"
LAVA_FEE = 0.08
PLAY_FEE = 0.15
SINCE = "2025-01-01"


def rates() -> dict:
    """Сколько единиц валюты в долларе."""
    try:
        with urllib.request.urlopen("https://open.er-api.com/v6/latest/USD", timeout=30) as r:
            data = json.load(r).get("rates") or {}
        data["USD"] = 1.0
        return data
    except Exception:  # noqa: BLE001
        return {"USD": 1.0, "RUB": 82.0, "EUR": 0.92}


def rsya_months() -> dict:
    try:
        token = open(RSYA_TOKEN, encoding="utf-8").read().strip()
    except OSError:
        return {}
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    url = ("https://partner.yandex.ru/api/statistics2/get.json?lang=ru&currency=USD"
           f"&period={SINCE},{today}&dimension_field=date|month"
           "&field=partner_wo_nds&field=shows")
    req = urllib.request.Request(url, headers={"Authorization": "OAuth " + token, "User-Agent": "curl/8.0"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.load(r)["data"]
    except Exception:  # noqa: BLE001
        return {}
    out = {}
    for p in data.get("points", []):
        month = p["dimensions"]["date"][0][:7]
        out[month] = {"usd": round(float(p["measures"][0].get("partner_wo_nds") or 0), 2),
                      "shows": int(p["measures"][0].get("shows") or 0)}
    return out


def admob_months() -> dict:
    try:
        cfg = json.load(open(ADMOB_CFG, encoding="utf-8"))
    except OSError:
        return {}
    try:
        body = urllib.parse.urlencode({
            "client_id": cfg["client_id"], "client_secret": cfg["client_secret"],
            "refresh_token": cfg["refresh_token"], "grant_type": "refresh_token"}).encode()
        with urllib.request.urlopen(urllib.request.Request(
                "https://oauth2.googleapis.com/token", data=body), timeout=30) as r:
            token = json.load(r)["access_token"]
        start = datetime.strptime(SINCE, "%Y-%m-%d")
        now = datetime.now(timezone.utc)
        req = urllib.request.Request(
            f"https://admob.googleapis.com/v1/accounts/{cfg['publisher_id']}/networkReport:generate",
            data=json.dumps({"reportSpec": {
                "dateRange": {"startDate": {"year": start.year, "month": start.month, "day": start.day},
                              "endDate": {"year": now.year, "month": now.month, "day": now.day}},
                "dimensions": ["MONTH"], "metrics": ["ESTIMATED_EARNINGS", "IMPRESSIONS"],
                "localizationSettings": {"currencyCode": "USD"}}}).encode(),
            headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=90) as r:
            rows = json.load(r)
    except Exception:  # noqa: BLE001
        return {}
    out = {}
    for item in rows:
        row = item.get("row")
        if not row:
            continue
        ym = row["dimensionValues"]["MONTH"]["value"]
        earn = int(row["metricValues"].get("ESTIMATED_EARNINGS", {}).get("microsValue", 0)) / 1e6
        out[f"{ym[:4]}-{ym[4:6]}"] = {"usd": round(earn, 2)}
    return out


def play_months(cur: dict) -> dict:
    """Закрытые месяцы берём из отчёта о доходах, свежие — из продаж."""
    try:
        sa = json.load(open(PLAY_SA, encoding="utf-8"))
        bucket = open(PLAY_BUCKET, encoding="utf-8").read().strip().replace("gs://", "").strip("/")
    except OSError:
        return {}

    def b64(raw: bytes) -> str:
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    now = int(time.time())
    head = b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claim = b64(json.dumps({"iss": sa["client_email"],
                            "scope": "https://www.googleapis.com/auth/devstorage.read_only",
                            "aud": "https://oauth2.googleapis.com/token",
                            "iat": now, "exp": now + 3600}).encode())
    unsigned = f"{head}.{claim}"
    with open("/tmp/.play_hist.pem", "w", encoding="utf-8") as f:
        f.write(sa["private_key"])
    os.chmod("/tmp/.play_hist.pem", 0o600)
    sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", "/tmp/.play_hist.pem"],
                         input=unsigned.encode(), capture_output=True, check=True).stdout
    os.remove("/tmp/.play_hist.pem")
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": f"{unsigned}.{b64(sig)}"}).encode()
    with urllib.request.urlopen(urllib.request.Request(
            "https://oauth2.googleapis.com/token", data=body), timeout=30) as r:
        token = json.load(r)["access_token"]

    def api(url: str) -> bytes:
        req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token,
                                                   "User-Agent": "curl/8.0"})
        with urllib.request.urlopen(req, timeout=90) as resp:
            return resp.read()

    def listing(prefix: str) -> list:
        data = json.loads(api(f"https://storage.googleapis.com/storage/v1/b/{bucket}/o"
                              f"?prefix={urllib.parse.quote(prefix)}&fields=items(name)&maxResults=500"))
        return [o["name"] for o in data.get("items", [])]

    def download(name: str) -> bytes:
        return api(f"https://storage.googleapis.com/storage/v1/b/{bucket}/o/"
                   f"{urllib.parse.quote(name, safe='')}?alt=media")

    def rows_of(blob: bytes):
        with zipfile.ZipFile(io.BytesIO(blob)) as z:
            for name in z.namelist():
                if name.lower().endswith(".csv"):
                    text = z.read(name).decode("utf-8-sig", errors="replace")
                    for row in csv.DictReader(io.StringIO(text)):
                        yield row

    out: dict = {}
    for name in listing("earnings/"):
        ym = "".join(ch for ch in name if ch.isdigit())[:6]
        if len(ym) != 6:
            continue
        total = 0.0
        sales = 0
        for row in rows_of(download(name)):
            try:
                total += float((row.get("Amount (Merchant Currency)") or "0").replace(",", ""))
            except ValueError:
                continue
            if (row.get("Transaction Type") or "").strip() == "Charge":
                sales += 1
        out[f"{ym[:4]}-{ym[4:6]}"] = {"usd": round(total, 2), "sales": sales, "kind": "отчёт"}

    for name in listing("sales/"):
        ym = "".join(ch for ch in name if ch.isdigit())[:6]
        key = f"{ym[:4]}-{ym[4:6]}"
        if len(ym) != 6 or key in out:
            continue  # закрытый месяц уже посчитан точно
        total = 0.0
        sales = 0
        for row in rows_of(download(name)):
            if (row.get("Financial Status") or "").strip().lower() not in ("charged", ""):
                continue
            rate = cur.get((row.get("Currency of Sale") or "").strip())
            try:
                val = float((row.get("Item Price") or "0").replace(",", ""))
            except ValueError:
                continue
            if rate:
                total += val / rate * (1 - PLAY_FEE)
                sales += 1
        out[key] = {"usd": round(total, 2), "sales": sales, "kind": "оценка"}
    return out


def lava_months(cur: dict) -> dict:
    try:
        cache = json.load(open(LAVA_CACHE, encoding="utf-8")).get("sales", {})
    except OSError:
        return {}
    out: dict = {}
    for sale in cache.values():
        if not sale:
            continue
        month = sale["d"][:7]
        row = out.setdefault(month, {"usd": 0.0, "native": {}, "count": 0})
        net = sale["amount"] * (1 - LAVA_FEE)
        row["native"][sale["currency"]] = round(row["native"].get(sale["currency"], 0.0) + net, 2)
        rate = cur.get(sale["currency"]) or 1.0
        row["usd"] = round(row["usd"] + net / rate, 2)
        row["count"] += 1
    return out


def main() -> int:
    cur = rates()
    sources = {
        "rsya": rsya_months(),
        "lava": lava_months(cur),
        "admob": admob_months(),
        "play": play_months(cur),
    }

    months = sorted({m for src in sources.values() for m in src})
    rows = []
    for m in months:
        row = {"m": m, "total": 0.0}
        for key, data in sources.items():
            hit = data.get(m) or {}
            usd = float(hit.get("usd") or 0)
            row[key] = round(usd, 2)
            row["total"] = round(row["total"] + usd, 2)
            if key == "lava" and hit.get("native"):
                row["lava_native"] = hit["native"]
                row["lava_count"] = hit.get("count", 0)
            if key == "play" and hit.get("kind"):
                row["play_kind"] = hit["kind"]
            if key == "rsya" and hit.get("shows"):
                row["rsya_shows"] = hit["shows"]
        rows.append(row)

    years: dict = {}
    for row in rows:
        y = years.setdefault(row["m"][:4], {"y": row["m"][:4], "total": 0.0,
                                            "rsya": 0.0, "lava": 0.0, "admob": 0.0, "play": 0.0,
                                            "months": 0})
        for key in ("total", "rsya", "lava", "admob", "play"):
            y[key] = round(y[key] + row.get(key, 0), 2)
        y["months"] += 1

    result = {
        "updated": datetime.now(timezone.utc).isoformat(),
        "rates": {k: v for k, v in cur.items() if k in ("RUB", "EUR", "PLN", "KZT")},
        "rate_note": "рубли и евро пересчитаны по курсу на день сборки, не на дату платежа",
        "months": rows,
        "years": sorted(years.values(), key=lambda r: r["y"]),
    }
    tmp = OUT + ".tmp"
    # ensure_ascii обязателен: хук читает файл побайтово как latin-1.
    with open(tmp, "w", encoding="ascii") as f:
        json.dump(result, f, ensure_ascii=True)
    os.chmod(tmp, 0o600)
    os.replace(tmp, OUT)
    print(f"месяцев: {len(rows)}, лет: {len(result['years'])}, "
          f"итог за всё время: {round(sum(r['total'] for r in rows), 2)} $")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
