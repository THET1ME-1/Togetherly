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
  (`admob.readonly`). Не ответил с трёх попыток — крон оставляет прошлое
  полученное число (`admob` в `SAVED`), а «нет данных» пишется, только
  если за этот день числа ещё не было.

Связь сервера с Google рвётся на рукопожатии каждый десятый раз, поэтому
всё, что идёт в Google, ходит через `google_retry`, токены доступа (час
жизни) лежат в файлах, а цены прошлых сделок Play — в `PLAY_PRICES`.

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
import urllib.error
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

ON_SERVER = os.path.exists('/opt/pocketbase/pb_data/data.db')
SSH = ['ssh', '-i', os.path.expanduser('~/.ssh/togetherly_vps'), 'root@86.110.220.22']
KEY_PLAY = '/opt/play-service-account.json' if ON_SERVER else os.path.expanduser('~/keys/togetherly-play-access.json')
KEY_RSYA = '/opt/pocketbase/pb_data/.rsya_token' if ON_SERVER else os.path.expanduser('~/keys/yandex_partner_token')
KEY_ADMOB = '/opt/pocketbase/pb_data/.admob_oauth.json' if ON_SERVER else os.path.expanduser('~/keys/admob_oauth.json')
SAVED = '/opt/income/.sales_days.json'
ADMOB_ACCESS = '/opt/income/.admob_access.json'
PLAY_ACCESS = '/opt/income/.play_access.json'
PLAY_PRICES = '/opt/income/.play_prices.json'
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


def google_retry(what: str, call):
    """Три попытки с паузой: связь сервера с Google рвётся на рукопожатии
    каждый десятый раз, а подряд — по нескольку минут."""
    for attempt in range(3):
        try:
            return call()
        except Exception as e:                                  # noqa: BLE001
            # отказ по существу (нет такой покупки, нет прав) повтором не лечится
            refused = isinstance(e, urllib.error.HTTPError) and 400 <= e.code < 500 and e.code != 429
            if refused or attempt == 2:
                raise
            print(f'{what} не ответил (попытка {attempt + 1}): {e}', file=sys.stderr)
            time.sleep(5)


def cached_token(path: str, fetch) -> str:
    """Токен доступа Google живёт час: на сервере берётся из файла, пока не протух.
    fetch() отдаёт (токен, сколько секунд живёт)."""
    if ON_SERVER and os.path.exists(path):
        cached = json.load(open(path))
        if cached['until'] > time.time() + 60:
            return cached['token']
    token, lives = fetch()
    if ON_SERVER:
        json.dump({'token': token, 'until': time.time() + lives}, open(path, 'w'))
    return token


def play_auth() -> str:
    """Токен Google по ключу сервисного аккаунта: подпись JWT своими руками."""
    import jwt

    def fetch():
        k = json.load(open(KEY_PLAY))
        now = int(time.time())
        claim = {'iss': k['client_email'], 'scope': 'https://www.googleapis.com/auth/androidpublisher',
                 'aud': 'https://oauth2.googleapis.com/token', 'iat': now, 'exp': now + 3000}
        body = urllib.parse.urlencode({'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                                       'assertion': jwt.encode(claim, k['private_key'], algorithm='RS256')}).encode()
        with urllib.request.urlopen(urllib.request.Request('https://oauth2.googleapis.com/token', data=body), timeout=30) as r:
            got = json.load(r)
        return got['access_token'], got.get('expires_in', 3000)
    return google_retry('Вход в Google Play', lambda: cached_token(PLAY_ACCESS, fetch))


def play_price(product: str, token: str, auth: str):
    # Цена сделки не меняется: однажды узнанная берётся из файла,
    # и крон раз в пять минут не ходит в Google за каждой покупкой дня заново
    known = json.load(open(PLAY_PRICES)) if ON_SERVER and os.path.exists(PLAY_PRICES) else {}
    if token in known:
        return tuple(known[token])
    base = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}'

    def get(url):
        req = urllib.request.Request(url, headers={'Authorization': f'Bearer {auth}'})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    try:
        p = google_retry('Покупка Google Play', lambda: get(f'{base}/purchases/products/{product}/tokens/{urllib.parse.quote(token)}'))
        total = google_retry('Заказ Google Play', lambda: get(f'{base}/orders/{p["orderId"]}'))['total']
        price = int(total.get('units', 0)) + total.get('nanos', 0) / 1e9, total['currencyCode']
    except Exception:                                           # noqa: BLE001
        return None
    if ON_SERVER:
        known[token] = price
        tmp = PLAY_PRICES + '.tmp'
        json.dump(known, open(tmp, 'w'))
        os.replace(tmp, PLAY_PRICES)
    return price


def rates() -> dict:
    """Курс к доллару; файл живёт шесть часов, чтобы не дёргать сайт каждые 5 минут."""
    try:
        if time.time() - os.path.getmtime(RATES) < 6 * 3600:
            return json.load(open(RATES))
    except OSError:
        pass
    try:
        with urllib.request.urlopen('https://open.er-api.com/v6/latest/USD', timeout=30) as r:
            data = json.load(r)['rates']
    except Exception:                                           # noqa: BLE001
        # сайт курса не ответил — вчерашний курс лучше, чем упавший итог дня
        if os.path.exists(RATES):
            return json.load(open(RATES))
        raise
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


def admob_access(key: dict) -> str:
    """Токен доступа AdMob по refresh-токену."""
    def fetch():
        form = urllib.parse.urlencode({
            'client_id': key['client_id'],
            'client_secret': key['client_secret'],
            'refresh_token': key['refresh_token'],
            'grant_type': 'refresh_token',
        }).encode()
        with urllib.request.urlopen('https://oauth2.googleapis.com/token', form, timeout=30) as r:
            got = json.load(r)
        return got['access_token'], got.get('expires_in', 3600)
    return cached_token(ADMOB_ACCESS, fetch)


def admob(days: list[dt.date]) -> dict | None:
    """Доход AdMob в долларах по дням. None — AdMob не ответил."""
    key = json.load(open(KEY_ADMOB))
    date = lambda d: {'year': d.year, 'month': d.month, 'day': d.day}
    spec = {'reportSpec': {
        'dateRange': {'startDate': date(min(days)), 'endDate': date(max(days))},
        'dimensions': ['DATE'],
        'metrics': ['ESTIMATED_EARNINGS'],
        'localizationSettings': {'currencyCode': 'USD'},
    }}

    def report():
        req = urllib.request.Request(
            f"https://admob.googleapis.com/v1/accounts/{key['publisher_id']}/networkReport:generate",
            json.dumps(spec).encode(),
            {'Authorization': f'Bearer {admob_access(key)}', 'Content-Type': 'application/json'},
        )
        with urllib.request.urlopen(req, timeout=40) as r:
            return json.load(r)
    try:
        rows = google_retry('AdMob', report)
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
        # AdMob не ответил — оставить прошлое полученное число, а не «нет данных»:
        # сбой сети на пять минут не должен стирать уже известный доход
        # (дня в прошлом итоге нет, например сразу после полуночи — честное «нет данных»)
        if google is None:
            google = {k: v for k, v in (previous_admob() or {}).items() if k in map(str, days)}
            day_google = lambda d: google if str(d) in google else None
        else:
            day_google = lambda d: google
        out = {'at': time.time(), 'admob': google,
               'days': {str(d): answer(d, rate, ads, auth, day_google(d)) for d in days}}
        tmp = SAVED + '.tmp'
        json.dump(out, open(tmp, 'w'), ensure_ascii=False)
        os.replace(tmp, SAVED)
        return
    day = dt.date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else today
    google = admob([day])
    if google is None and str(day) in (previous_admob() or {}):
        google = previous_admob()
    print(answer(day, rate, rsya([day]), auth, google))


def previous_admob() -> dict | None:
    """Доход AdMob из прошлого сохранённого итога крона (только на сервере)."""
    if not ON_SERVER or not os.path.exists(SAVED):
        return None
    return json.load(open(SAVED)).get('admob')


if __name__ == '__main__':
    main()
