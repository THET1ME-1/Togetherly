"""Поднимает базовую цену товаров Google Play до 900 ₽ / 10 $ / 10 €.

Трогает ТОЛЬКО регионы, стоящие на прежнем базовом уровне (790 RUB, 9,99 USD,
9,99 EUR). Прочие уровни — 12 $ у Белоруссии, 10,99 € у части Европы — заданы
отдельно и к базовой цене отношения не имеют, поэтому остаются как есть.

Правка идёт тем же `oneTimeProducts:batchUpdate`, что и создание товара, и поле
запроса называется `oneTimeProduct`: на `product` приходит 400 «Unknown name».

Сухой прогон (ничего не меняет):
    python3 play_reprice.py
Применить:
    python3 play_reprice.py --commit
"""

import json
import sys

from play_create_gift import call, token

# «старая цена» → «новая», по валюте. Ключ — (валюта, целые, наноединицы).
OLD_NEW = {
    ("RUB", 790, 0): (900, 0),
    ("USD", 9, 990000000): (10, 0),
    ("EUR", 9, 990000000): (10, 0),
}
PRODUCTS = ("togetherly_plus_gift", "togetherly_plus")


def reprice(pid, tok, commit=False):
    st, prod = call(f"/oneTimeProducts/{pid}", tok=tok)
    if st != 200:
        print(f"{pid}: не прочитать товар — {st}")
        return False

    changed = []
    for opt in prod.get("purchaseOptions", []):
        for cfg in opt.get("regionalPricingAndAvailabilityConfigs", []):
            p = cfg.get("price") or {}
            key = (p.get("currencyCode"), int(p.get("units", 0)), p.get("nanos") or 0)
            if key not in OLD_NEW:
                continue
            units, nanos = OLD_NEW[key]
            changed.append((cfg["regionCode"], key, (units, nanos)))
            p["units"] = str(units)
            if nanos:
                p["nanos"] = nanos
            else:
                p.pop("nanos", None)

    print(f"{pid}: под правку {len(changed)} регионов")
    for rc, old, new in changed:
        print(f"   {rc}: {old[1]}.{str(old[2]).zfill(9)[:2]} {old[0]}"
              f" → {new[0]}.{str(new[1]).zfill(9)[:2]}")
    if not changed or not commit:
        return True

    st, res = call("/oneTimeProducts:batchUpdate", "POST", {
        "requests": [{
            "oneTimeProduct": prod,
            "updateMask": "purchaseOptions",
            "regionsVersion": prod.get("regionsVersion", {"version": "2025/03"}),
            "allowMissing": False,
        }],
    }, tok)
    if st != 200:
        print("   отказ Play:", st, json.dumps(res, ensure_ascii=False)[:400])
        return False
    print("   применено")
    return True


def main():
    commit = "--commit" in sys.argv
    tok = token()
    ok = all(reprice(pid, tok, commit) for pid in PRODUCTS)
    if not commit:
        print("\nсухой прогон — запусти с --commit")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
