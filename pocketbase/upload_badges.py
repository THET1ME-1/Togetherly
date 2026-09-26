#!/usr/bin/env python3
"""Кладёт значки профиля и картинки подарков в серверный каталог Togetherly.

Подарок — такая же запись, только вида `gift` с id `gift_<ключ>` и
`gift.json` в папке вместо `badge.json`. Цена и действие подарка живут в
приложении и в `gifts.pb.js`; из каталога приходят только картинки, поэтому
перерисованный подарок доезжает до людей без обновления.

Каждый значок — запись `catalog_items` с `kind='badge'` и id `badge_<слаг>`.
В `files` три файла: анимация 192 px (`sm`), анимация 384 px (`lg`) и
неподвижный кадр (`still`); в `data` — ключ, редкость, названия и подписи на
семи языках и адреса файлов. Приложение читает каталог при старте, поэтому
новый значок появляется у людей БЕЗ обновления, а продаётся сразу: цену берёт
из этой же записи `/api/coins/purchase-icon`.

Ключ значка (`Paw`, `Perfect Match`) — это то, что лежит у людей в
`owned_icons`, `granted_badges` и `badge`. Менять его у существующего значка
нельзя: купленное перестанет узнаваться.

Запуск с VPS (наружу API суперюзера закрыт), папки готовит `export.py` из
~/Projects/togetherly-badges-hand:

    python3 upload_badges.py --dir /tmp/badges            все значки из папки
    python3 upload_badges.py --dir /tmp/badges --only fish
    python3 upload_badges.py --dir /tmp/badges --disable fish   снять с витрины

Папка значка:

    sm.webp  lg.webp  still.png
    badge.json  {"key": "Fish", "price": 0, "grantOnly": true, "rarity": "award",
                 "sort": 920, "name": {"ru": …, "en": …}, "desc": {"ru": …}}
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import re
import secrets
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

PB = "http://127.0.0.1:8090"
PB_DIR = "/opt/pocketbase"
PUBLIC = "https://togetherly.day"
FILES = ("sm.webp", "lg.webp", "still.png")


def slug(key: str) -> str:
    """Ключ → часть id записи. Тот же расчёт в coins.pb.js (`purchase-icon`)."""
    return re.sub(r"[^a-z0-9]+", "_", key.lower()).strip("_")


def superuser_token() -> tuple[str, str]:
    email = f"tmp-badges-{secrets.token_hex(3)}@x.local"
    password = secrets.token_urlsafe(12)
    subprocess.run([f"{PB_DIR}/pocketbase", "superuser", "create", email, password],
                   cwd=PB_DIR, check=True, capture_output=True)
    req = urllib.request.Request(
        f"{PB}/api/collections/_superusers/auth-with-password",
        data=json.dumps({"identity": email, "password": password}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as r:
        return email, json.load(r)["token"]


def drop_superuser(email: str) -> None:
    subprocess.run([f"{PB_DIR}/pocketbase", "superuser", "delete", email],
                   cwd=PB_DIR, check=False, capture_output=True)


def multipart(fields: dict[str, str], files: list[tuple[str, Path]]) -> tuple[bytes, str]:
    boundary = "----badges" + secrets.token_hex(8)
    body = b""
    for k, v in fields.items():
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n"
                 f"{v}\r\n").encode()
    for k, path in files:
        ctype = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"; "
                 f"filename=\"{path.name}\"\r\nContent-Type: {ctype}\r\n\r\n").encode()
        body += path.read_bytes() + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return body, f"multipart/form-data; boundary={boundary}"


def send(method: str, url: str, token: str, body: bytes, ctype: str) -> dict:
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={"Authorization": token, "Content-Type": ctype})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def exists(item_id: str, token: str) -> bool:
    req = urllib.request.Request(f"{PB}/api/collections/catalog_items/records/{item_id}",
                                 headers={"Authorization": token})
    try:
        urllib.request.urlopen(req)
        return True
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return False
        raise


def upload_gift(folder: Path, token: str) -> None:
    spec = json.loads((folder / "gift.json").read_text(encoding="utf-8"))
    key = spec["key"]
    # «art» — картинка интерфейса (монета TY), живёт так же, как подарок.
    kind = spec.get("kind", "gift")
    item_id = f"{kind}_" + slug(key)
    missing = [f for f in FILES if not (folder / f).exists()]
    if missing:
        sys.exit(f"{key}: нет файлов {', '.join(missing)}")
    fields = {"kind": kind, "name_ru": key, "name_en": key, "is_free": "false", "price": str(int(spec.get("price", 0))),
              "min_app": "", "sort": str(int(spec.get("sort", 500))), "enabled": "true", "data": "{}"}
    files = [("files", folder / f) for f in FILES]
    url = f"{PB}/api/collections/catalog_items/records/{item_id}"
    if exists(item_id, token):
        body, ctype = multipart({"files": ""}, [])
        send("PATCH", url, token, body, ctype)
        body, ctype = multipart(fields, files)
        rec = send("PATCH", url, token, body, ctype)
        action = "обновлён"
    else:
        fields["id"] = item_id
        body, ctype = multipart(fields, files)
        rec = send("POST", f"{PB}/api/collections/catalog_items/records", token, body, ctype)
        action = "заведён"
    stored = rec.get("files") or []
    if len(stored) != len(FILES):
        sys.exit(f"{key}: залилось {len(stored)} файлов из {len(FILES)}")
    urls = {name.split(".")[0]: f"{PUBLIC}/api/files/catalog_items/{rec['id']}/{stored_name}"
            for name, stored_name in zip(FILES, stored)}
    body, ctype = multipart({"data": json.dumps({"key": key, **urls}, ensure_ascii=False)}, [])
    send("PATCH", url, token, body, ctype)
    print(f"{'подарок' if kind == 'gift' else 'картинка'} {key}: {action} ({item_id})")


def upload(folder: Path, token: str) -> None:
    if (folder / "gift.json").exists():
        upload_gift(folder, token)
        return
    spec = json.loads((folder / "badge.json").read_text(encoding="utf-8"))
    key = spec["key"]
    item_id = "badge_" + slug(key)
    missing = [f for f in FILES if not (folder / f).exists()]
    if missing:
        sys.exit(f"{key}: нет файлов {', '.join(missing)}")
    names = spec.get("name") or {}
    fields = {
        "kind": "badge",
        "name_ru": names.get("ru", key),
        "name_en": names.get("en", key),
        "is_free": "false",
        "price": str(0 if spec.get("grantOnly") else int(spec.get("price", 0))),
        "min_app": "",
        "sort": str(int(spec.get("sort", 500))),
        "enabled": "true",
        "data": json.dumps({}, ensure_ascii=False),
    }
    files = [("files", folder / f) for f in FILES]
    url = f"{PB}/api/collections/catalog_items/records/{item_id}"
    if exists(item_id, token):
        # Старые файлы затираем целиком, иначе запись копит прошлые версии.
        body, ctype = multipart({"files": ""}, [])
        send("PATCH", url, token, body, ctype)
        body, ctype = multipart(fields, files)
        rec = send("PATCH", url, token, body, ctype)
        action = "обновлён"
    else:
        fields["id"] = item_id
        body, ctype = multipart(fields, files)
        rec = send("POST", f"{PB}/api/collections/catalog_items/records", token, body, ctype)
        action = "заведён"

    stored = rec.get("files") or []
    if len(stored) != len(FILES):
        sys.exit(f"{key}: залилось {len(stored)} файлов из {len(FILES)}")
    # PocketBase дописывает к имени случайный хвост, но порядок сохраняет.
    urls = {name.split(".")[0]: f"{PUBLIC}/api/files/catalog_items/{rec['id']}/{stored_name}"
            for name, stored_name in zip(FILES, stored)}
    manifest = {
        "key": key,
        "rarity": spec.get("rarity", "common"),
        "grantOnly": bool(spec.get("grantOnly")),
        "name": names,
        "desc": spec.get("desc") or {},
        **urls,
    }
    body, ctype = multipart({"data": json.dumps(manifest, ensure_ascii=False)}, [])
    send("PATCH", url, token, body, ctype)
    price = "награда" if spec.get("grantOnly") else f"{fields['price']} монет"
    print(f"{key}: {action} ({item_id}, {price})")


def disable(key_or_slug: str, token: str) -> None:
    item_id = key_or_slug if key_or_slug.startswith(("badge_", "gift_", "art_")) else "badge_" + slug(key_or_slug)
    body, ctype = multipart({"enabled": "false"}, [])
    send("PATCH", f"{PB}/api/collections/catalog_items/records/{item_id}", token, body, ctype)
    print(f"{item_id}: снят с витрины (у купивших остаётся)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", help="папка с подпапками значков (из export.py)")
    ap.add_argument("--only", nargs="*", default=[], help="слаги подпапок, которые залить")
    ap.add_argument("--disable", nargs="*", default=[], help="ключи или слаги, которые снять")
    args = ap.parse_args()

    email, token = superuser_token()
    try:
        for k in args.disable:
            disable(k, token)
        if args.dir:
            root = Path(args.dir)
            folders = sorted(p for p in root.iterdir() if (p / "badge.json").exists() or (p / "gift.json").exists())
            if args.only:
                folders = [p for p in folders if p.name in args.only]
            if not folders:
                sys.exit(f"в {root} нет папок значков")
            for folder in folders:
                upload(folder, token)
            print(f"проверить: {PUBLIC}/api/collections/catalog_items/records?filter=kind%3D'badge'")
    finally:
        drop_superuser(email)
        print("временный суперюзер удалён")


if __name__ == "__main__":
    main()
