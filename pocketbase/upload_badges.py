#!/usr/bin/env python3
"""Кладёт значки профиля, рамки аватарки и картинки подарков в серверный каталог Togetherly.

Рамка аватарки — запись вида `frame` с id `frame_<ключ>` и `frame.json` в
папке. Всё про рамку живёт в этой записи: редкость, названия и подписи на
семи языках, анимация и неподвижный кадр. За монеты рамки не продаются, их
разыгрывает сундук (`chest.pb.js`): он читает рамки из каталога при каждом
открытии, поэтому новая рамка сразу встаёт в розыгрыш и в магазин, без сборки
приложения и без правки хука. Доля в сундуке зависит от редкости.

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
    python3 upload_badges.py --dir /tmp/frames              рамки (папки с frame.json)
    python3 upload_badges.py --disable frame_cat            снять рамку с витрины

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
    # Только буквы и цифры: пароль с дефисом впереди командная строка
    # PocketBase принимает за флаг и суперюзера не заводит (05.10.2026).
    password = secrets.token_hex(16)
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
    # Подарок сезонного набора назван в gift.json: в коде приложения его нет,
    # название оно берёт из каталога.
    title = spec.get("name") or {}
    fields = {"kind": kind, "name_ru": title.get("ru", key), "name_en": title.get("en", key), "is_free": "false",
              "price": str(int(spec.get("price", 0))),
              "min_app": "", "sort": str(int(spec.get("sort", 500))), "enabled": "true", "data": "{}"}
    # xl.webp — крупная анимация, есть не у всех (монета TY для листа).
    names = list(FILES) + (["xl.webp"] if (folder / "xl.webp").exists() else [])
    files = [("files", folder / f) for f in names]
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
    if len(stored) != len(names):
        sys.exit(f"{key}: залилось {len(stored)} файлов из {len(names)}")
    urls = {name.split(".")[0]: f"{PUBLIC}/api/files/catalog_items/{rec['id']}/{stored_name}"
            for name, stored_name in zip(names, stored)}
    # Подарок сезонного сундука несёт набор и редкость: по ним его разыгрывает
    # chest.pb.js (обычный сундук вещи набора не выдаёт).
    extra = {k: spec[k] for k in ("set", "rarity") if spec.get(k)}
    body, ctype = multipart({"data": json.dumps({"key": key, **extra, **urls}, ensure_ascii=False)}, [])
    send("PATCH", url, token, body, ctype)
    print(f"{'подарок' if kind == 'gift' else 'картинка'} {key}: {action} ({item_id}{', набор ' + spec['set'] if spec.get('set') else ''})")


def upload_frame(folder: Path, token: str) -> None:
    spec = json.loads((folder / "frame.json").read_text(encoding="utf-8"))
    key = spec["key"]
    item_id = "frame_" + slug(key)
    missing = [f for f in FILES if not (folder / f).exists()]
    if missing:
        sys.exit(f"{key}: нет файлов {', '.join(missing)}")
    names = spec.get("name") or {}
    if spec.get("rarity") not in ("common", "rare", "legendary"):
        sys.exit(f"{key}: редкость должна быть common, rare или legendary")
    fields = {
        "kind": "frame",
        "name_ru": names.get("ru", key),
        "name_en": names.get("en", key),
        "is_free": "false",
        "price": "0",
        "min_app": "",
        "sort": str(int(spec.get("sort", 500))),
        "enabled": "true",
        "data": "{}",
    }
    files = [("files", folder / f) for f in FILES]
    url = f"{PB}/api/collections/catalog_items/records/{item_id}"
    if exists(item_id, token):
        body, ctype = multipart({"files": ""}, [])
        send("PATCH", url, token, body, ctype)
        body, ctype = multipart(fields, files)
        rec = send("PATCH", url, token, body, ctype)
        action = "обновлена"
    else:
        fields["id"] = item_id
        body, ctype = multipart(fields, files)
        rec = send("POST", f"{PB}/api/collections/catalog_items/records", token, body, ctype)
        action = "заведена"
    stored = rec.get("files") or []
    if len(stored) != len(FILES):
        sys.exit(f"{key}: залилось {len(stored)} файлов из {len(FILES)}")
    urls = {name.split(".")[0]: f"{PUBLIC}/api/files/catalog_items/{rec['id']}/{stored_name}"
            for name, stored_name in zip(FILES, stored)}
    manifest = {
        "key": key,
        "rarity": spec.get("rarity", "common"),
        "name": names,
        "desc": spec.get("desc") or {},
        # Радиус фото под рамкой, единицы холста 0..100 (31 — фото целиком).
        "hole": float(spec.get("hole", 31)),
        # Набор сезонного сундука («13» — Хэллоуин): из обычного не выпадает.
        **({"set": spec["set"]} if spec.get("set") else {}),
        **urls,
    }
    body, ctype = multipart({"data": json.dumps(manifest, ensure_ascii=False)}, [])
    send("PATCH", url, token, body, ctype)
    print(f"рамка {key}: {action} ({item_id}, {spec['rarity']}, в сундуке)")


def upload_chest(folder: Path, token: str) -> None:
    """Сезонный сундук: запись вида `chest`, id `chest_<ключ>`. Файлы — всё,
    что лежит в папке рядом с chest.json (анимации, занавесы, музыка); в
    `data` к описанию добавляются их адреса по имени без расширения."""
    spec = json.loads((folder / "chest.json").read_text(encoding="utf-8"))
    key = spec["key"]
    item_id = "chest_" + slug(key)
    names = sorted(p.name for p in folder.iterdir() if p.is_file() and p.name != "chest.json")
    title = spec.get("name") or {}
    fields = {"kind": "chest", "name_ru": title.get("ru", key), "name_en": title.get("en", key), "is_free": "false",
              "price": "0", "min_app": "", "sort": str(int(spec.get("sort", 500))), "enabled": "true", "data": "{}"}
    files = [("files", folder / n) for n in names]
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
    if len(stored) != len(names):
        sys.exit(f"{key}: залилось {len(stored)} файлов из {len(names)}")
    urls = {n.rsplit(".", 1)[0]: f"{PUBLIC}/api/files/catalog_items/{rec['id']}/{s}" for n, s in zip(names, stored)}
    body, ctype = multipart({"data": json.dumps({**spec, "files": urls}, ensure_ascii=False)}, [])
    send("PATCH", url, token, body, ctype)
    print(f"сундук {key}: {action} ({item_id}, {spec.get('from')} — {spec.get('until')}, {len(names)} файлов)")


def upload(folder: Path, token: str) -> None:
    if (folder / "chest.json").exists():
        upload_chest(folder, token)
        return
    if (folder / "frame.json").exists():
        upload_frame(folder, token)
        return
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
        # Значок из сундука: не продаётся, его разыгрывает chest.pb.js.
        "chest": bool(spec.get("chest")),
        **({"set": spec["set"]} if spec.get("set") else {}),
        "name": names,
        "desc": spec.get("desc") or {},
        **urls,
    }
    body, ctype = multipart({"data": json.dumps(manifest, ensure_ascii=False)}, [])
    send("PATCH", url, token, body, ctype)
    price = ("из сундука, " + spec.get("rarity", "common")) if spec.get("chest") else \
        ("награда" if spec.get("grantOnly") else f"{fields['price']} монет")
    print(f"{key}: {action} ({item_id}, {price})")


def disable(key_or_slug: str, token: str) -> None:
    item_id = key_or_slug if key_or_slug.startswith(("badge_", "gift_", "art_", "frame_", "chest_")) else "badge_" + slug(key_or_slug)
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
            folders = sorted(p for p in root.iterdir()
                             if any((p / f).exists() for f in ("badge.json", "gift.json", "frame.json", "chest.json")))
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
