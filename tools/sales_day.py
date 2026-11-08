#!/usr/bin/env python3
"""Продажи и РСЯ за день — ответ на «сколько сегодня продаж».

Сутки — по времени Кишинёва (зимой UTC+2, летом UTC+3), РСЯ считает свои
сутки по Москве. Продажи из своей базы, а не из отчётов магазинов:

- App Store и Google Play — `iap_purchases` (PocketBase). Сделка считается в
  день, когда впервые появилась: приложение присылает старые чеки повторно.
  Цена App Store — из JWS чека (сумма покупателя с НДС), Google Play — из
  orders API по токену (`~/keys/togetherly-play-access.json`).
- lava — письма продавца из `/opt/income/.lava_mail_cache.json`, повторы
  писем снимает `lava_income.без_повторов`; сумма до удержания 8 %.
- РСЯ — API партнёрки (`~/keys/yandex_partner_token`), один день API не
  отдаёт, поэтому берётся два и строка нужного.

Курс — open.er-api.com. Ответ — ровно две строки, как просит владелец:

    python3 tools/sales_day.py            сегодня
    python3 tools/sales_day.py 2026-11-08 этот день
"""
import base64
import datetime as dt
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

SSH = ['ssh', '-i', os.path.expanduser('~/.ssh/togetherly_vps'), 'root@86.110.220.22']
KEY_PLAY = os.path.expanduser('~/keys/togetherly-play-access.json')
KEY_RSYA = os.path.expanduser('~/keys/yandex_partner_token')
PACKAGE = 'com.togetherly.love'


def window(day: dt.date) -> tuple[dt.datetime, dt.datetime]:
    tz = ZoneInfo('Europe/Chisinau')
    start = dt.datetime.combine(day, dt.time(), tz).astimezone(dt.timezone.utc)
    return start, start + dt.timedelta(days=1)


def remote(script: str) -> str:
    return subprocess.run(SSH + ['python3', '-'], input=script, capture_output=True, text=True, check=True).stdout


def store_deals(start, end) -> list[dict]:
    """Сделки магазинов, впервые появившиеся за сутки."""
    script = f'''
import json, sqlite3
db = sqlite3.connect("file:/opt/pocketbase/pb_data/data.db?mode=ro", uri=True, timeout=8)
rows = db.execute("""
  select deal, min(at), product_id, token, transaction_id from (
    select case when transaction_id <> '' then transaction_id else id end deal, at, product_id, token, transaction_id
    from iap_purchases) group by deal having min(at) >= ? and min(at) < ?""",
  ("{start:%Y-%m-%d %H:%M:%S}", "{end:%Y-%m-%d %H:%M:%S}")).fetchall()
print(json.dumps([dict(zip(("deal","at","product","token","tx"), r)) for r in rows]))
'''
    return json.loads(remote(script))


def lava_sales(start, end) -> list[dict]:
    script = f'''
import json, sys
sys.path.insert(0, "/opt/income")
from lava_income import без_повторов
d = json.load(open("/opt/income/.lava_mail_cache.json"))["sales"]
rows = [v for v in d.values() if v and v.get("kind") == "продажа" and v.get("amount") and {start.timestamp()} <= v["ts"] < {end.timestamp()}]
print(json.dumps(без_повторов(sorted(rows, key=lambda r: r["ts"]))))
'''
    return json.loads(remote(script))


def apple_price(token: str):
    """Цена покупателя из JWS чека App Store: (сумма, валюта)."""
    try:
        part = token.split('.')[1]
        data = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
        if data.get('environment') != 'Production':
            return None
        return data['price'] / 1000, data['currency']
    except Exception:                                           # noqa: BLE001
        return None


def play_token() -> str:
    from google.oauth2 import service_account
    from google.auth.transport.requests import Request
    cred = service_account.Credentials.from_service_account_file(
        KEY_PLAY, scopes=['https://www.googleapis.com/auth/androidpublisher'])
    cred.refresh(Request())
    return cred.token


def play_price(product: str, token: str, auth: str):
    base = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}'

    def get(url):
        req = urllib.request.Request(url, headers={'Authorization': f'Bearer {auth}'})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    try:
        p = get(f'{base}/purchases/products/{product}/tokens/{urllib.parse.quote(token)}')
        order = get(f'{base}/orders/{p["orderId"]}')
        total = order['total']
        return int(total.get('units', 0)) + total.get('nanos', 0) / 1e9, total['currencyCode']
    except Exception:                                           # noqa: BLE001
        return None


def rates() -> dict:
    with urllib.request.urlopen('https://open.er-api.com/v6/latest/USD', timeout=30) as r:
        return json.load(r)['rates']


def rsya(day: dt.date) -> float:
    token = open(KEY_RSYA).read().strip()
    prev = day - dt.timedelta(days=1)
    url = ('https://partner.yandex.ru/api/statistics2/get.json?lang=ru&currency=USD'
           f'&period={prev}&period={day}&field=partner_wo_nds&dimension_field=date%7Cday')
    req = urllib.request.Request(url, headers={'Authorization': f'OAuth {token}'})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = json.load(r)
    for row in data['data']['points']:
        if row['dimensions']['date'][0] == str(day):
            return float(row['measures'][0]['partner_wo_nds'])
    return 0.0


def main():
    day = dt.date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else dt.datetime.now(ZoneInfo('Europe/Chisinau')).date()
    start, end = window(day)
    rate = rates()
    usd = lambda amount, cur: amount / rate[cur]
    deals = store_deals(start, end)
    lava = lava_sales(start, end)
    total, unknown = 0.0, 0
    auth = None
    for d in deals:
        price = apple_price(d['token']) if d['tx'] else None
        if not d['tx']:
            auth = auth or play_token()
            price = play_price(d['product'], d['token'], auth)
        if price:
            total += usd(*price)
        else:
            unknown += 1
    for s in lava:
        total += usd(s['amount'], s.get('currency') or 'RUB')
    count = len(deals) + len(lava)
    money = f'{total:.2f}'.replace('.', ',')
    tail = f', ещё {unknown} без цены' if unknown else ''
    print(f'Всего продаж: {count} ({money} ${tail})')
    print(f'РСЯ: {rsya(day):.2f} $'.replace('.', ','))


if __name__ == '__main__':
    main()
