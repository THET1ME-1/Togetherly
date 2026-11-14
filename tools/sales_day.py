#!/usr/bin/env python3
"""Продажи, РСЯ и AdMob за день — ответ на «сколько сегодня продаж».

Сутки — по времени Кишинёва (зимой UTC+2, летом UTC+3), РСЯ считает свои
сутки по Москве. Продажи из своей базы, а не из отчётов магазинов:

- App Store и Google Play — `iap_purchases` (PocketBase). Сделка считается в
  день, когда впервые появилась: приложение присылает старые чеки повторно.
  Цена App Store — из JWS чека (сумма покупателя с НДС), Google Play — из
  orders API по токену.
- lava — письма продавца из `/opt/income/.lava_mail_cache.json`, повторы
  писем снимает `lava_income.без_повторов`; сумма до удержания 8 %.
- РСЯ — API партнёрки, один день API не отдаёт, поэтому берётся два.
- AdMob — отчёт сети (`networkReport:generate`, доход в долларах); сутки
  аккаунта — по Кишинёву, как у продаж. Ключ — refresh-токен OAuth
  (`admob.readonly`). Не ответил — строка «нет данных», остальное считается.

Курс — open.er-api.com. Ответ — три строки: продажи, РСЯ, AdMob.

Работает и на сервере (там лежат база, ключ Play и токен РСЯ), и с
ноутбука (база через ssh, ключи из `~/keys`). На сервере крон раз в пять
минут кладёт готовый ответ за сегодня и вчера в `SAVED`, а команда
`продажи` на ноутбуке только читает файл — ответ мгновенный.

    python3 sales_day.py               сегодня, посчитать сейчас
    python3 sales_day.py 2026-11-08    этот день
    python3 sales_day.py --save        (крон) сегодня и вчера в файл
"""
import base64
import datetime as dt
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

ON_SERVER = os.path.exists('/opt/pocketbase/pb_data/data.db')
SSH = ['ssh', '-i', os.path.expanduser('~/.ssh/togetherly_vps'), 'root@86.110.220.22']
KEY_PLAY = '/opt/play-service-account.json' if ON_SERVER else os.path.expanduser('~/keys/togetherly-play-access.json')
KEY_RSYA = '/opt/pocketbase/pb_data/.rsya_token' if ON_SERVER else os.path.expanduser('~/keys/yandex_partner_token')
KEY_ADMOB = '/opt/pocketbase/pb_data/.admob_oauth.json' if ON_SERVER else os.path.expanduser('~/keys/admob_oauth.json')
SAVED = '/opt/income/.sales_days.json'
RATES = '/opt/income/.usd_rates.json' if ON_SERVER else os.path.expanduser('~/.cache/usd_rates.json')
PACKAGE = 'com.togetherly.love'
TZ = ZoneInfo('Europe/Chisinau')


def window(day: dt.date) -> tuple[dt.datetime, dt.datetime]:
    start = dt.datetime.combine(day, dt.time(), TZ).astimezone(dt.timezone.utc)
    return start, start + dt.timedelta(days=1)


def run_py(script: str) -> str:
    """Кусок кода рядом с базой: на сервере — здесь же, с ноутбука — по ssh."""
    cmd = ['python3', '-'] if ON_SERVER else SSH + ['python3', '-']
    return subprocess.run(cmd, input=script, capture_output=True, text=True, check=True).stdout


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
    return json.loads(run_py(script))


def lava_sales(start, end) -> list[dict]:
    script = f'''
import json, sys
sys.path.insert(0, "/opt/income")
from lava_income import без_повторов
d = json.load(open("/opt/income/.lava_mail_cache.json"))["sales"]
rows = [v for v in d.values() if v and v.get("kind") == "продажа" and v.get("amount") and {start.timestamp()} <= v["ts"] < {end.timestamp()}]
print(json.dumps(без_повторов(sorted(rows, key=lambda r: r["ts"]))))
'''
    return json.loads(run_py(script))


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


def play_auth() -> str:
    """Токен Google по ключу сервисного аккаунта: подпись JWT своими руками."""
    import jwt
    k = json.load(open(KEY_PLAY))
    now = int(time.time())
    claim = {'iss': k['client_email'], 'scope': 'https://www.googleapis.com/auth/androidpublisher',
             'aud': 'https://oauth2.googleapis.com/token', 'iat': now, 'exp': now + 3000}
    body = urllib.parse.urlencode({'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                                   'assertion': jwt.encode(claim, k['private_key'], algorithm='RS256')}).encode()
    with urllib.request.urlopen(urllib.request.Request('https://oauth2.googleapis.com/token', data=body), timeout=30) as r:
        return json.load(r)['access_token']


def play_price(product: str, token: str, auth: str):
    base = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}'

    def get(url):
        req = urllib.request.Request(url, headers={'Authorization': f'Bearer {auth}'})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    try:
        p = get(f'{base}/purchases/products/{product}/tokens/{urllib.parse.quote(token)}')
        total = get(f'{base}/orders/{p["orderId"]}')['total']
        return int(total.get('units', 0)) + total.get('nanos', 0) / 1e9, total['currencyCode']
    except Exception:                                           # noqa: BLE001
        return None


def rates() -> dict:
    """Курс к доллару; файл живёт шесть часов, чтобы не дёргать сайт каждые 5 минут."""
    try:
        if time.time() - os.path.getmtime(RATES) < 6 * 3600:
            return json.load(open(RATES))
    except OSError:
        pass
    with urllib.request.urlopen('https://open.er-api.com/v6/latest/USD', timeout=30) as r:
        data = json.load(r)['rates']
    os.makedirs(os.path.dirname(RATES), exist_ok=True)
    json.dump(data, open(RATES, 'w'))
    return data


def rsya(days: list[dt.date]) -> dict:
    """Доход РСЯ в долларах по дням (сутки РСЯ — московские)."""
    token = open(KEY_RSYA).read().strip()
    lo, hi = min(days), max(days)
    if lo == hi:
        lo = hi - dt.timedelta(days=1)
    url = ('https://partner.yandex.ru/api/statistics2/get.json?lang=ru&currency=USD'
           f'&period={lo}&period={hi}&field=partner_wo_nds&dimension_field=date%7Cday')
    req = urllib.request.Request(url, headers={'Authorization': f'OAuth {token}'})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = json.load(r)
    return {row['dimensions']['date'][0]: float(row['measures'][0]['partner_wo_nds']) for row in data['data']['points']}


def admob(days: list[dt.date]) -> dict | None:
    """Доход AdMob в долларах по дням. None — AdMob не ответил."""
    try:
        key = json.load(open(KEY_ADMOB))
        form = urllib.parse.urlencode({
            'client_id': key['client_id'],
            'client_secret': key['client_secret'],
            'refresh_token': key['refresh_token'],
            'grant_type': 'refresh_token',
        }).encode()
        with urllib.request.urlopen('https://oauth2.googleapis.com/token', form, timeout=30) as r:
            access = json.load(r)['access_token']
        date = lambda d: {'year': d.year, 'month': d.month, 'day': d.day}
        spec = {'reportSpec': {
            'dateRange': {'startDate': date(min(days)), 'endDate': date(max(days))},
            'dimensions': ['DATE'],
            'metrics': ['ESTIMATED_EARNINGS'],
            'localizationSettings': {'currencyCode': 'USD'},
        }}
        req = urllib.request.Request(
            f"https://admob.googleapis.com/v1/accounts/{key['publisher_id']}/networkReport:generate",
            json.dumps(spec).encode(),
            {'Authorization': f'Bearer {access}', 'Content-Type': 'application/json'},
        )
        with urllib.request.urlopen(req, timeout=60) as r:
            rows = json.load(r)
    except Exception as e:  # отчёт AdMob не должен ронять продажи и РСЯ
        print(f'AdMob не ответил: {e}', file=sys.stderr)
        return None
    out = {}
    for item in rows:
        row = item.get('row')
        if not row:
            continue
        day = row['dimensionValues']['DATE']['value']  # 20261114
        micros = int(row['metricValues']['ESTIMATED_EARNINGS'].get('microsValue', 0))
        out[f'{day[:4]}-{day[4:6]}-{day[6:]}'] = micros / 1e6
    return out


def money(v: float) -> str:
    return f'{v:.2f}'.replace('.', ',')


def answer(day: dt.date, rate: dict, ads: dict, auth_box: list, google: dict | None = None) -> str:
    """Две строки за день."""
    start, end = window(day)
    deals, lava = store_deals(start, end), lava_sales(start, end)
    total, unknown = 0.0, 0
    for d in deals:
        if d['tx']:
            price = apple_price(d['token'])
        else:
            if not auth_box:
                auth_box.append(play_auth())
            price = play_price(d['product'], d['token'], auth_box[0])
        if price:
            total += price[0] / rate[price[1]]
        else:
            unknown += 1
    for s in lava:
        total += s['amount'] / rate[s.get('currency') or 'RUB']
    tail = f', ещё {unknown} без цены' if unknown else ''
    earned = None if google is None else google.get(str(day), 0.0)
    # доли цента — не ноль: «0,00» читалось бы как поломка
    google_line = ('AdMob: нет данных' if earned is None
                   else 'AdMob: меньше 0,01 $' if 0 < earned < 0.005
                   else f'AdMob: {money(earned)} $')
    return (f'Всего продаж: {len(deals) + len(lava)} ({money(total)} ${tail})\n'
            f'РСЯ: {money(ads.get(str(day), 0.0))} $\n'
            f'{google_line}')


def main():
    today = dt.datetime.now(TZ).date()
    rate, auth = rates(), []
    if '--save' in sys.argv:
        days = [today, today - dt.timedelta(days=1)]
        ads, google = rsya(days), admob(days)
        out = {'at': time.time(), 'days': {str(d): answer(d, rate, ads, auth, google) for d in days}}
        tmp = SAVED + '.tmp'
        json.dump(out, open(tmp, 'w'), ensure_ascii=False)
        os.replace(tmp, SAVED)
        return
    day = dt.date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else today
    print(answer(day, rate, rsya([day]), auth, admob([day])))


if __name__ == '__main__':
    main()
