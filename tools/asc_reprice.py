"""Ставит цену покупок App Store: 10,00 $ базовой, 10,00 € и 900 ₽ вручную.

Базовая территория — США: от неё Apple считает остальные 172. Германия и
Россия заданы отдельными ручными ценами, потому что автоматический пересчёт
от 10 $ даёт там свои значения, а нужны ровно 10 € и 900 ₽.
"""
import sys
sys.path.insert(0, str(__import__("pathlib").Path(__file__).parent))
import asc

WANT = {"USA": 10.0, "DEU": 10.0, "RUS": 900.0}
IAPS = {"togetherly_plus_gift": "6804702550", "togetherly_plus": "6803018520"}


def point_for(iid, terr, price, tok):
    url = f"/v2/inAppPurchases/{iid}/pricePoints?filter[territory]={terr}&limit=200"
    while url:
        st, r = asc.call(url, tok=tok)
        if st != 200:
            return None
        for d in r.get("data", []):
            cp = d["attributes"].get("customerPrice")
            if cp and abs(float(cp) - price) < 0.001:
                return d["id"]
        nxt = (r.get("links") or {}).get("next")
        url = nxt.replace("https://api.appstoreconnect.apple.com", "") if nxt else None
    return None


def reprice(pid, iid, tok, dry=True):
    points = {}
    for terr, price in WANT.items():
        p = point_for(iid, terr, price, tok)
        if not p:
            print(f"{pid}: нет точки {price} для {terr} — прерываю")
            return False
        points[terr] = p
    print(f"{pid}: точки найдены — " + ", ".join(f"{t} {WANT[t]}" for t in WANT))
    if dry:
        return True

    ids = {t: f"${{price{i+1}}}" for i, t in enumerate(WANT)}
    body = {
        "data": {
            "type": "inAppPurchasePriceSchedules",
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [
                    {"type": "inAppPurchasePrices", "id": ids[t]} for t in WANT]},
            },
        },
        "included": [{
            "type": "inAppPurchasePrices",
            "id": ids[t],
            "attributes": {"startDate": None},
            "relationships": {
                "inAppPurchasePricePoint": {
                    "data": {"type": "inAppPurchasePricePoints", "id": points[t]}},
            },
        } for t in WANT],
    }
    st, r = asc.call("/v1/inAppPurchasePriceSchedules", "POST", body, tok=tok)
    print(f"   расписание → {st}", "" if st in (200, 201) else asc.errors(r))
    return st in (200, 201)


if __name__ == "__main__":
    dry = "--commit" not in sys.argv
    tok = asc.token()
    for pid, iid in IAPS.items():
        reprice(pid, iid, tok, dry=dry)
    if dry:
        print("\n(сухой прогон — добавь --commit)")
