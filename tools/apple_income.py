#!/usr/bin/env python3
"""Доход App Store: сколько купили Плюса на iPhone и сколько за это заплатили.

Устроено так же, как сбор Google Play: скрипт ходит в чужой кабинет по крону и
кладёт готовый файл, а хук PocketBase его только читает. Причина та же —
подпись запросов требует криптографии, которой в JSVM нет.

Apple отдаёт два вида отчётов, и оба нужны:

* **Продажи** (`salesReports`) — по дню, назавтра после самого дня. В строке
  есть `Developer Proceeds` — доля разработчика за одну покупку, то есть цена
  уже за вычетом комиссии Apple. Это и есть деньги, только в валюте региона.
* **Финансовый отчёт** (`financeReports`) — раз в месяц, с задержкой; в нём
  фактические суммы к выплате. Он точнее: там учтены возвраты и налоги.

Пока финансовый отчёт за месяц не вышел, месяц считается по продажам. Ровно
так же ведёт себя сбор Google Play, и по той же причине.

    python3 apple_income.py            собрать и записать
    python3 apple_income.py --show     показать, ничего не записывая

Номер поставщика (`vendorNumber`) API не отдаёт ни одним эндпоинтом — его
видно только в App Store Connect, в разделе «Платежи и финансовые отчёты».
Он, issuer и путь к ключу лежат в `/opt/income/.asc_income.json`, рядом со
сбором: репозиторий публичный, а это сведения об аккаунте.
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
from datetime import datetime, timedelta, timezone

# Доступ лежит рядом со сбором, а не в коде: репозиторий публичный, а issuer и
# номер поставщика — сведения об аккаунте, которым там не место.
#
#     /opt/income/.asc_income.json
#     {"issuer": "…", "key_id": "…", "key_path": "…", "vendor": "…"}
ДОСТУП_ПУТЬ = os.environ.get("ASC_CONFIG", "/opt/income/.asc_income.json")
OUT_PATH = os.environ.get("ASC_OUT", "/opt/pocketbase/pb_data/.appstore_income.json")
BASE = "https://api.appstoreconnect.apple.com"

# Дней назад, за которые тянем ежедневные отчёты. Больше месяца незачем: панель
# показывает текущий и прошлый месяц, а история живёт своим архивом.
ГЛУБИНА = 62


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

    Пустой день — обычное дело: за выходные покупок может не быть вовсе.
    Такой день пропускаем, а не считаем сбоем.
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


def курсы() -> dict:
    """Сколько единиц валюты в долларе (USD = 1)."""
    try:
        with urllib.request.urlopen("https://open.er-api.com/v6/latest/USD", timeout=30) as r:
            ставки = json.loads(r.read()).get("rates", {})
        ставки["USD"] = 1.0
        return ставки
    except Exception:                              # noqa: BLE001 — без курсов считаем только доллары
        return {"USD": 1.0}


def день(дата: str, доступ_: dict, ставки: dict) -> dict:
    """Один день продаж: деньги в долларах и покупки по товарам.

    Считаем по `Developer Proceeds` — это доля разработчика за одну покупку,
    то есть цена уже без комиссии Apple. Цена покупателя (`Customer Price`)
    для дохода не годится: из неё Apple забирает свои пятнадцать или тридцать
    процентов, и по ней месяц завышался бы на треть.
    """
    сырое = отчёт({"frequency": "DAILY", "reportDate": дата, "reportSubType": "SUMMARY",
                   "reportType": "SALES", "vendorNumber": доступ_["vendor"]}, доступ_)
    всего, товары = 0.0, {}
    for ряд in строки(сырое):
        try:
            штук = int((ряд.get("Units") or "0").strip() or 0)
            доля = float((ряд.get("Developer Proceeds") or "0").strip() or 0)
        except ValueError:
            continue
        валюта = (ряд.get("Currency of Proceeds") or "").strip()
        курс = ставки.get(валюта)
        if not курс or штук <= 0:
            continue
        # Возвраты приходят отрицательными единицами — их не выбрасываем, иначе
        # месяц окажется больше того, что придёт на счёт.
        деньги = доля * штук / курс
        имя = (ряд.get("SKU") or ряд.get("Apple Identifier") or "—").strip()
        товар = товары.setdefault(имя, {"name": имя, "count": 0, "usd": 0.0})
        товар["count"] += штук
        товар["usd"] = round(товар["usd"] + деньги, 2)
        всего += деньги
    return {"usd": round(всего, 4), "purchases": товары}


def собрать() -> dict:
    д = доступ()
    if not д["vendor"] or not д["issuer"] or not д["key_id"]:
        return {"ok": False, "title": "App Store",
                "reason": f"не настроен доступ: заполните {ДОСТУП_ПУТЬ} "
                          "(issuer, key_id, vendor)"}

    ставки = курсы()
    сегодня = datetime.now(timezone.utc).date()
    дни, товары = {}, {}
    # Отчёт за сам день Apple выкладывает на следующие сутки, поэтому идём с
    # вчерашнего: запрос за сегодня всегда вернул бы пустоту.
    for сдвиг in range(1, ГЛУБИНА + 1):
        дата = (сегодня - timedelta(days=сдвиг)).isoformat()
        сутки = день(дата, д, ставки)
        if сутки["usd"] or сутки["purchases"]:
            дни[дата] = сутки["usd"]
            if дата[:7] == сегодня.strftime("%Y-%m"):
                for имя, т in сутки["purchases"].items():
                    строка = товары.setdefault(имя, {"name": имя, "count": 0, "usd": 0.0})
                    строка["count"] += т["count"]
                    строка["usd"] = round(строка["usd"] + т["usd"], 2)

    месяц = сегодня.strftime("%Y-%m")
    прошлый = (сегодня.replace(day=1) - timedelta(days=1)).strftime("%Y-%m")
    за_месяц = round(sum(v for d, v in дни.items() if d[:7] == месяц), 2)
    за_прошлый = round(sum(v for d, v in дни.items() if d[:7] == прошлый), 2)
    вчера = (сегодня - timedelta(days=1)).isoformat()

    return {
        "ok": True, "title": "App Store", "currency": "USD",
        # Сегодняшнего дня у Apple не бывает: отчёт выходит назавтра. Ноль тут
        # честнее пропуска — иначе панель показала бы вчерашние деньги как
        # сегодняшние.
        "today": 0.0,
        "yesterday": round(дни.get(вчера, 0.0), 2),
        "month": за_месяц,
        "prev_month": за_прошлый,
        "month_label": месяц,
        "prev_month_label": прошлый,
        "purchases": sorted(товары.values(), key=lambda r: -r["count"]),
        "month_sales": sum(т["count"] for т in товары.values()),
        "days": [{"d": d, "v": v} for d, v in sorted(дни.items())],
        "note": "деньги считаются по доле разработчика в ежедневных отчётах, "
                "то есть уже без комиссии Apple; отчёт за сегодня выходит завтра",
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
    except Exception as e:                         # noqa: BLE001 — причина уезжает во вкладку
        итог = {"ok": False, "title": "App Store", "reason": str(e)[:200]}
    if "--show" not in sys.argv:
        записать(итог)
    print(json.dumps(итог, ensure_ascii=False)[:600])
    return 0 if итог.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
