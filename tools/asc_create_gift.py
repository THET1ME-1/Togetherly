"""Заводит в App Store Connect расходуемую покупку `togetherly_plus_gift`.

Передать купленное на чужой Apple ID StoreKit не умеет, поэтому подарок — это
отдельный CONSUMABLE: плательщик покупает его себе, а доступ по чеку открывает
наш сервер тому, кого выбрали в приложении. Расходуемый, а не разовый: иначе
второй подарок купить нельзя, и человек с Плюсом не смог бы подарить его
партнёру.

Цена берётся та же, что у боевого `togetherly_plus`: базовая территория США,
9,99 $ — Apple сама раскладывает её по остальным странам.

Сухой прогон:      python3 asc_create_gift.py
Создание:          python3 asc_create_gift.py --commit
"""

import json
import sys

import asc

APP_ID = asc.APP_ID
PRODUCT_ID = "togetherly_plus_gift"
NAME = "Togetherly+ Gift"
REVIEW_NOTE = (
    "Gift purchase. The buyer pays for Togetherly+ and picks which partner in "
    "their pair receives it; our server grants the access to the chosen "
    "account, not to the buyer. Consumable, so a person can gift it more than "
    "once and can gift it even if they already own Togetherly+. To test: sign "
    "in, connect a partner, open Profile - Togetherly+, tap Gift, choose the "
    "partner and confirm the purchase."
)
LOCALIZATIONS = [
    {"locale": "ru", "name": "Togetherly+ в подарок",
     "description": "Полный доступ в подарок партнёру."},
    {"locale": "en-US", "name": "Togetherly+ Gift",
     "description": "Gift full access to your partner."},
]
BASE_TERRITORY = "USA"
TARGET_PRICE = "9.99"


def existing():
    st, r = asc.call(f"/v1/apps/{APP_ID}/inAppPurchasesV2?limit=200")
    if st != 200:
        print("не прочитать список покупок:", st, asc.errors(r))
        sys.exit(1)
    for item in r.get("data", []):
        if item["attributes"]["productId"] == PRODUCT_ID:
            return item
    return None


def main():
    commit = "--commit" in sys.argv
    tok = asc.token()

    found = existing()
    if found:
        print(f"покупка {PRODUCT_ID} уже есть: id={found['id']} "
              f"состояние={found['attributes']['state']}")
        iap_id = found["id"]
    else:
        print(f"создаю CONSUMABLE {PRODUCT_ID}")
        if not commit:
            print("сухой прогон — запусти с --commit")
            return
        st, r = asc.call("/v2/inAppPurchases", "POST", {
            "data": {
                "type": "inAppPurchases",
                "attributes": {
                    "name": NAME,
                    "productId": PRODUCT_ID,
                    "inAppPurchaseType": "CONSUMABLE",
                    "reviewNote": REVIEW_NOTE,
                    "familySharable": False,
                },
                "relationships": {
                    "app": {"data": {"type": "apps", "id": APP_ID}},
                },
            },
        }, tok)
        if st not in (200, 201):
            print("отказ Apple:", st, asc.errors(r))
            sys.exit(1)
        iap_id = r["data"]["id"]
        print("создана:", iap_id)

    if not commit:
        print("сухой прогон — дальше не иду")
        return

    # Локализации: без них покупку не отправить на ревью.
    st, have = asc.call(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations", tok=tok)
    known = {d["attributes"]["locale"] for d in (have.get("data") or [])}
    for loc in LOCALIZATIONS:
        if loc["locale"] in known:
            print("локализация уже есть:", loc["locale"])
            continue
        st, r = asc.call("/v1/inAppPurchaseLocalizations", "POST", {
            "data": {
                "type": "inAppPurchaseLocalizations",
                "attributes": loc,
                "relationships": {
                    "inAppPurchaseV2": {
                        "data": {"type": "inAppPurchases", "id": iap_id},
                    },
                },
            },
        }, tok)
        print("локализация", loc["locale"], "→", st,
              "" if st in (200, 201) else asc.errors(r))

    # Цена. Точка цены привязана к конкретной покупке, поэтому список берём у
    # неё же и ищем ту, где покупатель платит столько же, сколько за Плюс.
    st, sched = asc.call(f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule", tok=tok)
    if st == 200 and (sched.get("data") or {}).get("id"):
        print("цена уже назначена")
        return

    st, points = asc.call(
        f"/v2/inAppPurchases/{iap_id}/pricePoints"
        f"?filter[territory]={BASE_TERRITORY}&limit=200", tok=tok)
    if st != 200:
        print("не прочитать точки цены:", st, asc.errors(points))
        sys.exit(1)
    point = None
    for p in points.get("data", []):
        if p["attributes"].get("customerPrice") == TARGET_PRICE:
            point = p["id"]
            break
    if not point:
        prices = sorted({p["attributes"].get("customerPrice")
                         for p in points.get("data", [])})
        print(f"нет точки цены {TARGET_PRICE}; доступны: {prices[:20]}")
        sys.exit(1)

    st, r = asc.call("/v1/inAppPurchasePriceSchedules", "POST", {
        "data": {
            "type": "inAppPurchasePriceSchedules",
            "relationships": {
                "inAppPurchase": {
                    "data": {"type": "inAppPurchases", "id": iap_id},
                },
                "baseTerritory": {
                    "data": {"type": "territories", "id": BASE_TERRITORY},
                },
                "manualPrices": {
                    "data": [{"type": "inAppPurchasePrices", "id": "${price1}"}],
                },
            },
        },
        "included": [{
            "type": "inAppPurchasePrices",
            "id": "${price1}",
            "attributes": {"startDate": None},
            "relationships": {
                "inAppPurchasePricePoint": {
                    "data": {"type": "inAppPurchasePricePoints", "id": point},
                },
            },
        }],
    }, tok)
    print("цена →", st, "" if st in (200, 201) else asc.errors(r))

    st, check = asc.call(f"/v2/inAppPurchases/{iap_id}", tok=tok)
    a = (check.get("data") or {}).get("attributes", {})
    print("итог:", a.get("productId"), "|", a.get("inAppPurchaseType"), "|",
          a.get("state"))


if __name__ == "__main__":
    main()
