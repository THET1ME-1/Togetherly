#!/usr/bin/env python3
"""Доход lava.top для вкладки «Доход» — по письмам продавца.

Почему не по API. Отчёты lava (`/api/v1/sales/`, `/api/v1/invoices`) видят
только счета, заведённые нашим API-ключом. Покупку по прямой ссылке с витрины
они не показывают вовсе, а таких большинство: 4 счёта против 26 писем о
продажах. Единственный полный след — письмо продавцу «успешная продажа», где
есть и почта покупателя, и сумма. По ним же выдаётся Плюс (`lava_mail_watch.py`),
так что источник уже проверен временем.

Что считаем. В письме сумма ДО удержания площадки («На ваш баланс поступила
сумма RUB 829»), поэтому чистое считаем сами: минус комиссия 8%. Проверено на
долларовой покупке: 10,00 $ в письме → 9,20 $ в кабинете.

Возвраты письмами не приходят — их видно только в кабинете. Число возвратов
кладётся руками в /opt/pocketbase/pb_data/.lava_refunds (по строке на возврат:
`ГГГГ-ММ-ДД СУММА ВАЛЮТА`), скрипт их вычитает.

Запуск: раз в 15 минут по крону, ключи Gmail — из /etc/gmail-relay.env.
"""
import base64
import json
import os
import re
import urllib.parse
import urllib.request
from datetime import datetime, timezone

CACHE = "/opt/income/.lava_mail_cache.json"
OUT = "/opt/pocketbase/pb_data/.lava_income.json"
REFUNDS = "/opt/pocketbase/pb_data/.lava_refunds"
FEE = 0.08  # удержание lava.top
QUERY = "from:lava.top newer_than:400d"


def gmail_token() -> str:
    data = urllib.parse.urlencode({
        "client_id": os.environ["GMAIL_CLIENT_ID"],
        "client_secret": os.environ["GMAIL_CLIENT_SECRET"],
        "refresh_token": os.environ.get("GMAIL_READ_REFRESH_TOKEN") or os.environ["GMAIL_REFRESH_TOKEN"],
        "grant_type": "refresh_token",
    }).encode()
    with urllib.request.urlopen("https://oauth2.googleapis.com/token", data=data, timeout=30) as r:
        return json.load(r)["access_token"]


def gmail(path: str, token: str) -> dict:
    req = urllib.request.Request("https://gmail.googleapis.com/gmail/v1/users/me/" + path,
                                 headers={"Authorization": "Bearer " + token, "User-Agent": "curl/8.0"})
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.load(r)


def plain_text(msg: dict) -> str:
    def walk(part: dict) -> str:
        out = ""
        if part.get("body", {}).get("data"):
            out += base64.urlsafe_b64decode(part["body"]["data"] + "==").decode("utf-8", "replace")
        for sub in part.get("parts") or []:
            out += walk(sub)
        return out
    raw = re.sub(r"(?is)<(style|script|head)[^>]*>.*?</\1>", " ", walk(msg["payload"]))
    raw = re.sub(r"<[^>]+>", " ", raw).replace("&nbsp;", " ").replace("&mdash;", "—")
    return re.sub(r"\s+", " ", raw).strip()


def load_cache() -> dict:
    try:
        with open(CACHE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def refunds() -> list[dict]:
    out = []
    try:
        for line in open(REFUNDS, encoding="utf-8"):
            parts = line.split()
            if len(parts) >= 3:
                out.append({"d": parts[0], "amount": float(parts[1].replace(",", ".")), "currency": parts[2].upper()})
    except OSError:
        pass
    return out


def collect() -> dict:
    token = gmail_token()
    cache = load_cache()
    seen = cache.get("sales", {})

    # Список писем берём метаданными — сто штук за запрос; тело тянем только у
    # незнакомых, иначе каждые пятнадцать минут перечитывали бы всю переписку.
    ids, page = [], None
    while True:
        q = ("messages?q=" + urllib.parse.quote(QUERY) + "&maxResults=100" +
             ("&pageToken=" + page if page else ""))
        chunk = gmail(q, token)
        ids += [m["id"] for m in chunk.get("messages", [])]
        page = chunk.get("nextPageToken")
        if not page:
            break

    fresh = 0
    for mid in ids:
        if mid in seen:
            continue
        msg = gmail("messages/" + mid + "?format=full", token)
        subject = " ".join(h["value"] for h in msg["payload"]["headers"] if h["name"].lower() == "subject")
        if "продажа" not in subject and "донат" not in subject:
            seen[mid] = None          # письмо не про деньги, помним, чтобы не качать снова
            continue
        body = plain_text(msg)
        money = re.search(r"поступила сумма ([A-Z]{3}) ([0-9]+(?:[.,][0-9]+)?)", body)
        if not money:
            seen[mid] = None
            continue
        product = re.search(r"купил ваш продукт (.+?) На ваш баланс", body)
        seen[mid] = {
            "d": datetime.fromtimestamp(int(msg["internalDate"]) / 1000, timezone.utc).strftime("%Y-%m-%d"),
            "currency": money.group(1),
            "amount": float(money.group(2).replace(",", ".")),
            "product": (product.group(1).strip() if product else "донат"),
            "kind": "донат" if "донат" in subject else "продажа",
        }
        fresh += 1

    cache["sales"] = seen
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, "w", encoding="utf-8") as f:
        json.dump(cache, f, ensure_ascii=False)

    sales = [s for s in seen.values() if s]
    lost = refunds()

    def net(rows: list[dict]) -> dict:
        acc: dict[str, float] = {}
        for r in rows:
            acc[r["currency"]] = acc.get(r["currency"], 0.0) + r["amount"]
        for r in lost:
            if r["currency"] in acc:
                acc[r["currency"]] -= r["amount"]
        return {k: round(v * (1 - FEE), 2) for k, v in acc.items()}

    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    month = today[:7]
    by_day: dict[str, dict[str, float]] = {}
    for s in sales:
        by_day.setdefault(s["d"], {})
        by_day[s["d"]][s["currency"]] = by_day[s["d"]].get(s["currency"], 0.0) + s["amount"] * (1 - FEE)

    by_product: dict[str, dict] = {}
    for s in sales:
        key = s["product"] + "|" + s["currency"]
        row = by_product.setdefault(key, {"name": s["product"], "currency": s["currency"], "count": 0, "amount": 0.0})
        row["count"] += 1
        row["amount"] = round(row["amount"] + s["amount"] * (1 - FEE), 2)

    return {
        "ok": True, "title": "lava, все каналы", "source": "письма продавца",
        "fee": FEE, "new_mails": fresh, "count": len(sales),
        "total_net": net(sales),
        "month_net": net([s for s in sales if s["d"][:7] == month]),
        "today_net": net([s for s in sales if s["d"] == today]),
        "by_day": {k: {c: round(v, 2) for c, v in cur.items()} for k, cur in sorted(by_day.items())},
        "products": sorted(by_product.values(), key=lambda r: -r["count"]),
        "refunds": lost,
        "updated": datetime.now(timezone.utc).isoformat(),
    }


def main() -> int:
    try:
        result = collect()
    except Exception as e:  # noqa: BLE001 — причина уезжает во вкладку как есть
        result = {"ok": False, "reason": str(e)[:200]}
    # ensure_ascii обязателен: хук читает файл побайтово как latin-1.
    with open(OUT, "w", encoding="ascii") as f:
        json.dump(result, f, ensure_ascii=True)
    os.chmod(OUT, 0o600)
    print(json.dumps(result, ensure_ascii=False)[:500])
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
