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
REPEAT_BURST = 15       # письма с такой разницей шлёт машина, а не покупатель
REPEAT_GAP = 4 * 3600   # пауза между письмами, после которой рассылка считается оконченной


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


def buyer_of(body: str) -> str:
    """Почта покупателя: адрес перед словом «купил». В подвале письма стоит
    адрес поддержки lava, и поиск первой попавшейся почты цеплял бы его."""
    hit = re.search(r"([\w.+-]+@[\w-]+\.[\w.-]+)\s+купил", body)
    return hit.group(1).lower() if hit else ""


def без_повторов(rows: list[dict]) -> list[dict]:
    """Одна оплата — одна продажа, сколько бы писем о ней ни пришло.

    11 и 13 октября 2026 lava во время сбоя слала «успешную продажу» пачкой:
    несколько писем за первую минуту и дальше по одному в час, пока сбой не
    кончится (11.10 — восемь писем, 13.10 — больше тринадцати). Номера заказа
    в письме нет, поэтому серию узнаём по покупателю, товару и сумме, а её
    начало — по письмам, пришедшим с разницей в секунды: человек два раза за
    это время не заплатит. Дальше серия тянется, пока письма идут чаще, чем
    раз в REPEAT_GAP: потолка по длине нет, часовой хвост бывает и на сутки.

    Две оплаты с разницей в минуты НЕ склеиваем. Так платят по-настоящему,
    когда доступ не открылся сразу (21.08.2026 — 193 секунды между письмами),
    и вторые деньги тоже пришли.

    Без покупателя (донат) и без времени (запись старого кеша) не трогаем:
    узнать повтор не по чему.
    """
    out: list[dict] = []
    groups: dict[tuple, list[dict]] = {}
    for row in rows:
        if not row.get("ts") or not row.get("buyer"):
            out.append(row)
            continue
        key = (row["buyer"], row["product"], row["amount"], row["currency"], row["kind"])
        groups.setdefault(key, []).append(row)

    for letters in groups.values():
        letters.sort(key=lambda r: r["ts"])
        last = None  # время последнего письма идущей рассылки
        for i, row in enumerate(letters):
            if last is not None and row["ts"] - last <= REPEAT_GAP:
                last = row["ts"]
                continue
            out.append(row)
            follower = letters[i + 1] if i + 1 < len(letters) else None
            burst = follower is not None and follower["ts"] - row["ts"] <= REPEAT_BURST
            last = row["ts"] if burst else None
    return sorted(out, key=lambda r: r.get("ts") or 0)


def чистыми(rows: list[dict], lost: list[dict], в_период=None) -> dict:
    """Сумма за вычетом возвратов и доли площадки, по валютам.

    Возврат вычитается только из того периода, в который попал его день:
    21.10.2026 итог дня показал 8280 ₽ вместо 9936, потому что из него
    вычелся возврат 19.10. Без `в_период` считаются все дни и все возвраты.
    """
    acc: dict[str, float] = {}
    for r in rows:
        acc[r["currency"]] = acc.get(r["currency"], 0.0) + r["amount"]
    for r in lost:
        if r["currency"] in acc and (в_период is None or в_период(r["d"])):
            acc[r["currency"]] -= r["amount"]
    return {k: round(v * (1 - FEE), 2) for k, v in acc.items()}


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
        # Продажа и донат пишутся по-разному: «На ваш баланс поступила сумма
        # RUB 829» против «Вам пришёл донат RUB 50». Второй шаблон появился
        # после того, как донат на 50 ₽ прошёл мимо отчёта.
        money = (re.search(r"поступила сумма ([A-Z]{3}) ([0-9]+(?:[.,][0-9]+)?)", body)
                 or re.search(r"пришёл донат ([A-Z]{3}) ([0-9]+(?:[.,][0-9]+)?)", body))
        if not money:
            seen[mid] = None
            continue
        product = re.search(r"купил ваш продукт (.+?) На ваш баланс", body)
        seen[mid] = {
            "d": datetime.fromtimestamp(int(msg["internalDate"]) / 1000, timezone.utc).strftime("%Y-%m-%d"),
            "ts": int(msg["internalDate"]) // 1000,
            "buyer": buyer_of(body),
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

    sales = без_повторов([s for s in seen.values() if s])
    lost = refunds()

    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    month = today[:7]
    by_day: dict[str, dict[str, float]] = {}
    for s in sales:
        by_day.setdefault(s["d"], {})
        by_day[s["d"]][s["currency"]] = by_day[s["d"]].get(s["currency"], 0.0) + s["amount"] * (1 - FEE)

    def по_товарам(rows: list[dict]) -> list[dict]:
        acc: dict[str, dict] = {}
        for s in rows:
            key = s["product"] + "|" + s["currency"]
            row = acc.setdefault(key, {"name": s["product"], "currency": s["currency"],
                                       "count": 0, "amount": 0.0})
            row["count"] += 1
            row["amount"] = round(row["amount"] + s["amount"] * (1 - FEE), 2)
        return sorted(acc.values(), key=lambda r: -r["count"])

    by_product = по_товарам(sales)
    # Тот же разрез за текущий месяц: панель показывает покупки по магазинам
    # именно за месяц, и разбивка за всё время в этой таблице соврала бы —
    # рядом с ней стоят Google Play и App Store, а у них месяц.
    month_products = по_товарам([s for s in sales if s["d"][:7] == month])

    return {
        "ok": True, "title": "lava, все каналы", "source": "письма продавца",
        "fee": FEE, "new_mails": fresh, "count": len(sales),
        "total_net": чистыми(sales, lost),
        "month_net": чистыми([s for s in sales if s["d"][:7] == month], lost, lambda d: d[:7] == month),
        "today_net": чистыми([s for s in sales if s["d"] == today], lost, lambda d: d == today),
        "by_day": {k: {c: round(v, 2) for c, v in cur.items()} for k, cur in sorted(by_day.items())},
        "products": by_product,
        "month_products": month_products,
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
