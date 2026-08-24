"""Кладёт скриншот ревью для покупки в App Store Connect.

Без него покупка висит в MISSING_METADATA и на ревью не уходит. Загрузка
трёхшаговая: зарезервировать место (Apple вернёт адреса и заголовки), залить
байты по этим адресам, подтвердить контрольной суммой.

    python3 asc_upload_screenshot.py <iap_id> <файл.png>
"""

import hashlib
import json
import sys
import urllib.request
from pathlib import Path

import asc


def main():
    iap_id, path = sys.argv[1], Path(sys.argv[2])
    data = path.read_bytes()
    tok = asc.token()

    st, r = asc.call("/v1/inAppPurchaseAppStoreReviewScreenshots", "POST", {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "attributes": {"fileName": path.name, "fileSize": len(data)},
            "relationships": {
                "inAppPurchaseV2": {
                    "data": {"type": "inAppPurchases", "id": iap_id},
                },
            },
        },
    }, tok)
    if st not in (200, 201):
        print("резерв не удался:", st, asc.errors(r))
        sys.exit(1)

    shot_id = r["data"]["id"]
    for op in r["data"]["attributes"].get("uploadOperations", []):
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        with urllib.request.urlopen(req, timeout=120) as res:
            if res.status not in (200, 201, 204):
                print("кусок не залился:", res.status)
                sys.exit(1)

    st, r = asc.call(f"/v1/inAppPurchaseAppStoreReviewScreenshots/{shot_id}",
                     "PATCH", {
                         "data": {
                             "type": "inAppPurchaseAppStoreReviewScreenshots",
                             "id": shot_id,
                             "attributes": {
                                 "uploaded": True,
                                 "sourceFileChecksum": hashlib.md5(data).hexdigest(),
                             },
                         },
                     }, tok)
    print("подтверждение →", st, "" if st in (200, 201) else asc.errors(r))

    st, check = asc.call(f"/v2/inAppPurchases/{iap_id}", tok=tok)
    a = (check.get("data") or {}).get("attributes", {})
    print("состояние покупки:", a.get("productId"), "|", a.get("state"))


if __name__ == "__main__":
    main()
