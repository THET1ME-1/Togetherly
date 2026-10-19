#!/usr/bin/env python3
"""Доход App Store: сколько купили на iPhone и сколько за это заплатили.

Устроено так же, как сбор Google Play: скрипт ходит в чужой кабинет по крону и
кладёт готовый файл, а хук PocketBase его только читает. Причина та же —
подпись запросов требует криптографии, которой в JSVM нет.

Деньги берутся из ежедневного отчёта о продажах (`salesReports`, DAILY SALES
SUMMARY). В строке есть `Developer Proceeds` — доля разработчика за штуку, то
есть цена уже без комиссии Apple, в валюте региона. Отчёт за день Apple
выкладывает назавтра и больше не меняет, поэтому скачанные дни лежат в кэше
рядом со сбором, и каждый час качается только то, чего в нём ещё нет. Из того
же кэша складываются месяцы для архива (`income_history.py`).

В отчёте вместе с покупками лежат скачивания, повторные загрузки и обновления
приложения — сотни строк в день с нулевой долей. Покупка — только строка с
ненулевой долей; возврат приходит отрицательными штуками и вычитается.
Аккаунт разработчика общий для всех приложений, как у Google Play и lava,
поэтому в отчёте есть и подписка Fern Pro.

    python3 apple_income.py            собрать и записать
    python3 apple_income.py --show     показать, ничего не записывая

Номер поставщика (`vendorNumber`) API не отдаёт ни одним эндпоинтом — его
видно только в App Store Connect, на странице «Отчёты о продажах и трендах»
рядом с именем разработчика. Он, issuer и путь к ключу лежат в
`/opt/income/.asc_income.json`, рядом со сбором: репозиторий публичный, а это
сведения об аккаунте.
"""

import csv
import gzip
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta, timezone

# Доступ лежит рядом со сбором, а не в коде: репозиторий публичный, а issuer и
# номер поставщика — сведения об аккаунте, которым там не место.
#
#     /opt/income/.asc_income.json
#     {"issuer": "…", "key_id": "…", "key_path": "…", "vendor": "…"}
ДОСТУП_ПУТЬ = os.environ.get("ASC_CONFIG", "/opt/income/.asc_income.json")
OUT_PATH = os.environ.get("ASC_OUT", "/opt/pocketbase/pb_data/.appstore_income.json")
КЭШ_ПУТЬ = os.environ.get("ASC_CACHE", "/opt/income/.asc_days_cache.json")
BASE = "https://api.appstoreconnect.apple.com"

# Первые продажи на iPhone — август 2026, раньше отчёты пустые.
НАЧАЛО = date(2026, 8, 1)
# Дней в подневном ряду: по нему панель считает доход за любой период.
ГЛУБИНА = 62
# Отчёт за день выходит назавтра. Нет его и через трое суток — значит, в тот
# день не было ни продаж, ни скачиваний, и спрашивать его больше незачем.
ЖДАТЬ_ОТЧЁТ = 3


def доступ() -> dict:
    """Issuer, ключ и номер поставщика: из файла рядом со сбором или из среды."""
    из_файла = {}
    try:
        with open(ДОСТУП_ПУТЬ, encoding="utf-8") as f:
            из_файла = json.load(f)
    except (OSError, json.JSONDecodeError):
        pass
    ключ_id = os.environ.get("ASC_KEY_ID") or из_файла.get("key_id", "")
    return {
        "issuer": os.environ.get("ASC_ISSUER") or из_файла.get("issuer", ""),
        "key_id": ключ_id,
        "key_path": (os.environ.get("ASC_KEY_PATH") or из_файла.get("key_path")
                     or f"/opt/income/AuthKey_{ключ_id}.p8"),
        "vendor": os.environ.get("ASC_VENDOR") or str(из_файла.get("vendor", "")),
    }


def токен(доступ_: dict) -> str:
    """JWT для App Store Connect: ES256, живёт не дольше двадцати минут.

    Подписываем сами, без pyjwt: на сервере из криптографии стоит только
    `cryptography`, а тянуть ради одного заголовка ещё пакет незачем.
    """
    from cryptography.hazmat.primitives import hashes, serialization        # noqa: PLC0415
    from cryptography.hazmat.primitives.asymmetric import ec, utils         # noqa: PLC0415

    def b64(raw: bytes) -> str:
        import base64                                                       # noqa: PLC0415
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    сейчас = int(time.time())
    шапка = {"alg": "ES256", "kid": доступ_["key_id"], "typ": "JWT"}
    тело = {"iss": доступ_["issuer"], "iat": сейчас, "exp": сейчас + 900,
            "aud": "appstoreconnect-v1"}
    основа = (b64(json.dumps(шапка, separators=(",", ":")).encode()) + "." +
              b64(json.dumps(тело, separators=(",", ":")).encode()))

    with open(доступ_["key_path"], "rb") as f:
        ключ = serialization.load_pem_private_key(f.read(), password=None)
    der = ключ.sign(основа.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der)
    подпись = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return основа + "." + b64(подпись)


def отчёт(параметры: dict, доступ_: dict) -> bytes:
    """Отчёт Apple: gzip внутри, а при отсутствии данных — честный 404.

    404 приходит и на день, отчёт за который ещё не вышел, и на день вовсе без
    продаж и скачиваний. Сбоем это не считается.
    """
    строка = "&".join(f"filter[{k}]={v}" for k, v in параметры.items())
    req = urllib.request.Request(f"{BASE}/v1/salesReports?{строка}")
    req.add_header("Authorization", "Bearer " + токен(доступ_))
    req.add_header("Accept", "application/a-gzip")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return gzip.decompress(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return b""
        raise


def строки(сырое: bytes):
    if not сырое:
        return
    текст = сырое.decode("utf-8", errors="replace")
    for ряд in csv.DictReader(io.StringIO(текст), delimiter="\t"):
        yield ряд


def покупки_дня(сырое: bytes) -> list:
    """Строки отчёта, где есть деньги: [товар, штук, доля за штуку, валюта].

    Скачивания, повторные загрузки и обновления идут с нулевой долей и
    покупками не считаются. Возврат приходит отрицательными штуками.
    """
    покупки = []
    for ряд in строки(сырое):
        try:
            штук = int((ряд.get("Units") or "0").strip() or 0)
            доля = float((ряд.get("Developer Proceeds") or "0").strip() or 0)
        except ValueError:
            continue
        if not штук or not доля:
            continue
        товар = (ряд.get("SKU") or ряд.get("Apple Identifier") or "—").strip()
        валюта = (ряд.get("Currency of Proceeds") or "").strip()
        покупки.append([товар, штук, доля, валюта])
    return покупки


def курсы() -> dict:
    """Сколько единиц валюты в долларе (USD = 1).

    Без курсов сбор падает целиком: молча выброшенные рубли и лиры занизили бы
    месяц вдвое, а прошлая сводка в панели честнее.
    """
    with urllib.request.urlopen("https://open.er-api.com/v6/latest/USD", timeout=30) as r:
        ставки = json.loads(r.read()).get("rates", {})
    ставки["USD"] = 1.0
    return ставки


def в_доллары(покупки: list, ставки: dict) -> tuple:
    """Сумма в долларах и покупки по товарам."""
    всего, товары = 0.0, {}
    for товар, штук, доля, валюта in покупки:
        курс = ставки.get(валюта)
        if not курс:
            continue
        деньги = доля * штук / курс
        строка = товары.setdefault(товар, {"name": товар, "count": 0, "usd": 0.0})
        строка["count"] += штук
        строка["usd"] = round(строка["usd"] + деньги, 2)
        всего += деньги
    return всего, товары


def дни(доступ_: dict, сегодня: date, кэш_путь: str) -> tuple:
    """Покупки по дням с НАЧАЛО по вчера и причина сбоя, если Apple не ответила.

    Скачанное берётся из кэша, недостающее — у Apple. Сбой посреди прохода не
    теряет уже скачанные дни: остальные досчитаются в следующий час.
    """
    try:
        with open(кэш_путь, encoding="utf-8") as f:
            кэш = json.load(f)
    except (OSError, ValueError):
        кэш = {}

    сбой = ""
    день = НАЧАЛО
    while день < сегодня:
        ключ = день.isoformat()
        if ключ not in кэш:
            try:
                сырое = отчёт({"frequency": "DAILY", "reportDate": ключ, "reportSubType": "SUMMARY",
                               "reportType": "SALES", "vendorNumber": доступ_["vendor"]}, доступ_)
            except (OSError, ValueError) as e:
                сбой = f"{ключ}: {e}"[:160]
                print(f"App Store: отчёт за {сбой}", file=sys.stderr)
                break
            if сырое:
                кэш[ключ] = покупки_дня(сырое)
            elif (сегодня - день).days > ЖДАТЬ_ОТЧЁТ:
                кэш[ключ] = []
        день += timedelta(days=1)

    with open(кэш_путь + ".tmp", "w", encoding="utf-8") as f:
        json.dump(кэш, f)
    os.replace(кэш_путь + ".tmp", кэш_путь)
    return кэш, сбой


def собрать(сегодня: date | None = None, кэш_путь: str = КЭШ_ПУТЬ) -> dict:
    доступ_ = доступ()
    if not доступ_["vendor"] or not доступ_["issuer"] or not доступ_["key_id"]:
        return {"ok": False, "title": "App Store",
                "reason": f"не настроен доступ: заполните {ДОСТУП_ПУТЬ} "
                          "(issuer, key_id, vendor)"}

    сегодня = сегодня or datetime.now(timezone.utc).date()
    ставки = курсы()
    кэш, сбой = дни(доступ_, сегодня, кэш_путь)

    месяц = сегодня.strftime("%Y-%m")
    прошлый = (сегодня.replace(day=1) - timedelta(days=1)).strftime("%Y-%m")
    вчера = (сегодня - timedelta(days=1)).isoformat()
    начало_ряда = (сегодня - timedelta(days=ГЛУБИНА)).isoformat()

    # Блок сложения: дни в ряд для панели, месяцы для архива, товары за месяц
    по_дням, месяцы, товары = [], {}, {}
    for день, покупки in sorted(кэш.items()):
        usd, по_товарам = в_доллары(покупки, ставки)
        запись = месяцы.setdefault(день[:7], {"usd": 0.0, "count": 0})
        запись["usd"] = round(запись["usd"] + usd, 2)
        запись["count"] += sum(товар["count"] for товар in по_товарам.values())
        if покупки and день >= начало_ряда:
            по_дням.append({"d": день, "v": round(usd, 4)})
        if день[:7] == месяц:
            for имя, товар in по_товарам.items():
                строка = товары.setdefault(имя, {"name": имя, "count": 0, "usd": 0.0})
                строка["count"] += товар["count"]
                строка["usd"] = round(строка["usd"] + товар["usd"], 2)

    заметка = ("деньги считаются по доле разработчика в ежедневных отчётах, "
               "то есть уже без комиссии Apple; отчёт за день Apple выкладывает назавтра")
    if сбой:
        заметка += f"; последний отчёт не скачан ({сбой})"

    return {
        "ok": True, "title": "App Store", "currency": "USD",
        # Сегодняшнего дня у Apple не бывает: отчёт выходит назавтра. Ноль тут
        # честнее пропуска — иначе панель показала бы вчерашние деньги как
        # сегодняшние.
        "today": 0.0,
        "yesterday": round(sum(запись["v"] for запись in по_дням if запись["d"] == вчера), 2),
        "month": месяцы.get(месяц, {}).get("usd", 0.0),
        "prev_month": месяцы.get(прошлый, {}).get("usd", 0.0),
        "month_label": месяц,
        "prev_month_label": прошлый,
        "purchases": sorted(товары.values(), key=lambda r: -r["count"]),
        "month_sales": sum(товар["count"] for товар in товары.values()),
        "days": по_дням,
        # Месяцы целиком с первой продажи: их забирает архив дохода.
        "months": {m: v for m, v in sorted(месяцы.items()) if v["usd"] or v["count"]},
        "note": заметка,
        "updated": datetime.now(timezone.utc).isoformat(),
    }


def записать(итог: dict) -> None:
    # ensure_ascii обязателен: хук читает файл побайтово как latin-1.
    with open(OUT_PATH, "w", encoding="ascii") as f:
        json.dump(итог, f, ensure_ascii=True)
    os.chmod(OUT_PATH, 0o600)


def main() -> int:
    try:
        итог = собрать()
    except Exception as e:                         # noqa: BLE001 — причина уезжает в журнал крона
        print(f"App Store: сбор не удался ({e})", file=sys.stderr)
        # Сбой Apple или курсов не стирает прошлую сводку: панель покажет её,
        # а причина останется в журнале крона.
        if os.path.exists(OUT_PATH):
            return 1
        итог = {"ok": False, "title": "App Store", "reason": str(e)[:200]}
    if "--show" not in sys.argv:
        записать(итог)
    print(json.dumps(итог, ensure_ascii=False)[:600])
    return 0 if итог.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
