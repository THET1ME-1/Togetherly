"""Заводит в Google Play товар-подарок `togetherly_plus_gift`.

Передать купленное на чужой аккаунт Play не умеет, поэтому подарок — это
ОТДЕЛЬНЫЙ товар: плательщик покупает его себе, а доступ по чеку открывает наш
сервер тому, кого выбрали в приложении. Товар обязан быть расходуемым — в Play
это не свойство карточки, а поведение приложения (`consumePurchase`), поэтому
здесь заводится обычный one-time product, а расходование делает клиент.

Цены и регионы копируются с боевого `togetherly_plus`: подарок стоит столько
же, скидку потом задают отдельным ценником в консоли.

Сухой прогон (ничего не меняет):
    python3 play_create_gift.py
Создание:
    python3 play_create_gift.py --commit
"""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request

from google.oauth2 import service_account
import google.auth.transport.requests as gt

KEY = "/home/alelx/keys/togetherly-play-access.json"
PKG = "com.togetherly.love"
SRC = "togetherly_plus"
DST = "togetherly_plus_gift"
BASE = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}"

TITLE = "Togetherly+ в подарок"
DESC = ("Подарок партнёру: полный доступ Togetherly+ откроется тому, кого вы "
        "выберете в приложении. Все платные темы, календарь цикла, виджеты.")


def token():
    cred = service_account.Credentials.from_service_account_file(
        KEY, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    cred.refresh(gt.Request())
    return cred.token


def call(path, method="GET", body=None, tok=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + tok)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            raw = res.read().decode()
            return res.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw[:600]}


def main():
    commit = "--commit" in sys.argv
    tok = token()

    st, src = call(f"/oneTimeProducts/{SRC}", tok=tok)
    if st != 200:
        print("не прочитать образец:", st, src)
        sys.exit(1)

    st, existing = call(f"/oneTimeProducts/{DST}", tok=tok)
    if st == 200:
        print(f"товар {DST} уже есть — ничего не делаю")
        return

    option = src["purchaseOptions"][0]
    body = {
        "packageName": PKG,
        "productId": DST,
        "listings": [{
            "languageCode": "en-US",
            "title": TITLE,
            "description": DESC,
        }],
        "taxAndComplianceSettings": src.get("taxAndComplianceSettings", {}),
        "regionsVersion": src.get("regionsVersion", {"version": "2025/03"}),
        "purchaseOptions": [{
            "purchaseOptionId": "gift",
            "state": "ACTIVE",
            # Тот же режим, что у боевого Плюса: товар виден и сборкам со
            # старой библиотекой оплаты.
            "buyOption": {"legacyCompatible": True},
            "regionalPricingAndAvailabilityConfigs":
                option["regionalPricingAndAvailabilityConfigs"],
            "newRegionsConfig": option.get("newRegionsConfig"),
            "taxAndComplianceSettings": option.get("taxAndComplianceSettings"),
        }],
    }
    body["purchaseOptions"][0] = {
        k: v for k, v in body["purchaseOptions"][0].items() if v is not None}

    regions = len(option["regionalPricingAndAvailabilityConfigs"])
    print(f"готов создать {DST}: {regions} регионов, цена как у {SRC}")
    if not commit:
        print("сухой прогон — запусти с --commit")
        return

    # Отдельного метода «создать товар» в API нет: и создание, и правка идут
    # через `oneTimeProducts:batchUpdate` с `allowMissing`. Обычный PATCH по
    # адресу товара отвечает 404 html-страницей — такого маршрута у них нет.
    st, res = call("/oneTimeProducts:batchUpdate", "POST", {
        "requests": [{
            "updateMask": "listings,taxAndComplianceSettings,purchaseOptions",
            "regionsVersion": body["regionsVersion"],
            "allowMissing": True,
            "oneTimeProduct": body,
        }],
    }, tok)
    if st != 200:
        print("отказ Play:", st, json.dumps(res, ensure_ascii=False)[:800])
        sys.exit(1)

    st, check = call(f"/oneTimeProducts/{DST}", tok=tok)
    opt = (check.get("purchaseOptions") or [{}])[0]
    ru = [c for c in opt.get("regionalPricingAndAvailabilityConfigs", [])
          if c["regionCode"] == "RU"]
    print("создан:", check.get("productId"),
          "| опция:", opt.get("purchaseOptionId"), opt.get("state"),
          "| регионов:", len(opt.get("regionalPricingAndAvailabilityConfigs", [])),
          "| RU:", ru[0]["price"] if ru else "нет")


if __name__ == "__main__":
    main()
