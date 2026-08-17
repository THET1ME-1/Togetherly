#!/usr/bin/env python3
"""Кладёт пак настроений в каталог Togetherly.

Картинки эмоций уходят в многофайловое поле `files` записи `catalog_items`
(`kind='mood_pack'`), манифест с их адресами — в `data`. Клиент читает каталог
при старте, поэтому новый пак появляется у людей БЕЗ обновления приложения, а
платный ещё и продаётся сразу: цену берёт из этой же записи серверный роут
`/api/coins/purchase-feature`.

Запуск с самого VPS (наружу API суперюзера закрыт):

    python3 upload_mood_pack.py --dir packs/kawaii --min-app 1.22.0
    python3 upload_mood_pack.py --dir packs/kawaii --price 120 --plus

Что лежит в каталоге пака:

    pack.json          описание (см. ниже)
    happy.webp         имя файла = id настроения
    sad.webp
    ...

    pack.json:
    {
      "id": "kawaii",
      "name_ru": "Каваи",
      "name_en": "Kawaii",
      "author": "noia_aa",
      "tileGradient": ["#FFD9E8", "#FFF1F6"],
      "moods": {
        "happy": {"labelRu": "Счастье", "labelEn": "Happy", "color": "#F5C542", "score": 5},
        "sad":   {"labelRu": "Грустно", "labelEn": "Sad",   "color": "#6B9BD2", "score": 2}
      }
    }

Для известных приложению id (`happy`, `sad`, …) метку, цвет и score можно не
писать вовсе: клиент возьмёт их из своей сборки. Заполнять обязательно только
для НОВЫХ эмоций, которых в приложении ещё нет.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import secrets
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

PB = "http://127.0.0.1:8090"
PB_DIR = "/opt/pocketbase"
PUBLIC = "https://togetherly.day"
IMAGE_SUFFIXES = (".webp", ".png", ".gif", ".jpg", ".jpeg")


def superuser_token() -> tuple[str, str]:
    """Заводит временного суперюзера и возвращает (email, token)."""
    email = f"tmp-moodpack-{secrets.token_hex(3)}@x.local"
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
    boundary = "----moodpack" + secrets.token_hex(8)
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


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="каталог пака с pack.json и картинками")
    ap.add_argument("--min-app", default="1.22.0",
                    help="сборка, с которой пак показывается")
    ap.add_argument("--price", type=int, default=0,
                    help="цена в монетах; 0 — бесплатный пак")
    ap.add_argument("--plus", action="store_true",
                    help="открыт владельцам Togetherly+ (иначе Плюс его НЕ даёт)")
    ap.add_argument("--sort", type=int, default=200)
    ap.add_argument("--disabled", action="store_true", help="завести выключенным")
    args = ap.parse_args()

    src = Path(args.dir)
    spec = json.loads((src / "pack.json").read_text(encoding="utf-8"))
    pack_id = spec["id"]
    moods_spec: dict = spec.get("moods", {})

    images = sorted(p for p in src.iterdir() if p.suffix.lower() in IMAGE_SUFFIXES)
    if not images:
        sys.exit(f"в {src} нет картинок настроений")

    # Порядок эмоций в паке = порядок в pack.json, если он там задан. Иначе по
    # именам файлов: пикер показывает их в этом же порядке.
    order = list(moods_spec) or [p.stem for p in images]
    by_id = {p.stem: p for p in images}
    missing = [m for m in order if m not in by_id]
    if missing:
        sys.exit(f"нет картинок для настроений: {', '.join(missing)}")

    email, token = superuser_token()
    try:
        fields = {
            "kind": "mood_pack",
            "name_ru": spec.get("name_ru", pack_id),
            "name_en": spec.get("name_en", pack_id),
            "is_free": "false" if args.price > 0 else "true",
            "price": str(max(0, args.price)),
            "min_app": args.min_app,
            "sort": str(args.sort),
            "enabled": "false" if args.disabled else "true",
            # data пишем вторым проходом: адреса файлов известны только после
            # загрузки, как и у атласов маскотов
            "data": json.dumps({}, ensure_ascii=False),
        }
        upload = [("files", by_id[m]) for m in order]

        if exists(pack_id, token):
            # Старые файлы затираем целиком: иначе повторная заливка копит
            # хвосты прошлых версий картинок в той же записи.
            body, ctype = multipart({"files": ""}, [])
            send("PATCH", f"{PB}/api/collections/catalog_items/records/{pack_id}",
                 token, body, ctype)
            body, ctype = multipart(fields, upload)
            rec = send("PATCH", f"{PB}/api/collections/catalog_items/records/{pack_id}",
                       token, body, ctype)
            action = "обновлён"
        else:
            fields["id"] = pack_id
            body, ctype = multipart(fields, upload)
            rec = send("POST", f"{PB}/api/collections/catalog_items/records",
                       token, body, ctype)
            action = "заведён"

        stored = rec.get("files") or []
        if len(stored) != len(order):
            sys.exit(f"залилось {len(stored)} файлов из {len(order)}")

        manifest: dict = {"moods": []}
        if spec.get("tileGradient"):
            manifest["tileGradient"] = spec["tileGradient"]
        # Имя художника подписывает пак в листе выбора настроения. Ссылок сюда
        # не кладём: это подпись под работой, а не реклама площадки.
        if spec.get("author"):
            manifest["author"] = spec["author"]
        if args.price > 0:
            manifest["unlock"] = {"type": "premium", "price": args.price, "plus": args.plus}

        for mood_id, filename in zip(order, stored):
            entry = {
                "id": mood_id,
                "url": f"{PUBLIC}/api/files/catalog_items/{rec['id']}/{filename}",
            }
            entry.update({k: v for k, v in (moods_spec.get(mood_id) or {}).items()})
            manifest["moods"].append(entry)

        body, ctype = multipart(
            {"data": json.dumps(manifest, ensure_ascii=False)}, [])
        send("PATCH", f"{PB}/api/collections/catalog_items/records/{rec['id']}",
             token, body, ctype)

        money = f"{args.price} монет" + (", открыт Плюсом" if args.plus else "")
        print(f"{fields['name_ru']}: {action}, настроений {len(order)}, "
              f"{money if args.price else 'бесплатный'}")
        print(f"проверить: {PUBLIC}/api/collections/catalog_items/records/{rec['id']}")
    finally:
        drop_superuser(email)
        print("временный суперюзер удалён")


if __name__ == "__main__":
    main()
