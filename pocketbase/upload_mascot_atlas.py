#!/usr/bin/env python3
"""Кладёт анимированных маскотов в каталог Togetherly.

Атлас (PNG со всеми кадрами) уходит в поле `image` записи `catalog_items`,
манифест — в `data`. Клиент читает каталог при старте, поэтому новый персонаж
появляется у людей БЕЗ обновления приложения.

Запуск с самого VPS (наружу API суперюзера закрыт):
    python3 upload_mascot_atlas.py --dir atlas --min-app 1.22.0
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import secrets
import subprocess
import sys
import urllib.request
from pathlib import Path

PB = "http://127.0.0.1:8090"
PB_DIR = "/opt/pocketbase"


def superuser_token() -> tuple[str, str]:
    """Заводит временного суперюзера и возвращает (email, token)."""
    email = f"tmp-mascots-{secrets.token_hex(3)}@x.local"
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


def multipart(fields: dict[str, str], files: dict[str, Path]) -> tuple[bytes, str]:
    boundary = "----mascot" + secrets.token_hex(8)
    body = b""
    for k, v in fields.items():
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n"
                 f"{v}\r\n").encode()
    for k, path in files.items():
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
    ap.add_argument("--dir", default="atlas", help="каталог с png и index.json")
    ap.add_argument("--min-app", default="1.22.0",
                    help="сборка, с которой маскоты показываются")
    ap.add_argument("--sort-from", type=int, default=100)
    args = ap.parse_args()

    src = Path(args.dir)
    index = json.loads((src / "index.json").read_text(encoding="utf-8"))

    email, token = superuser_token()
    try:
        for i, item in enumerate(index):
            png = src / item["sheet"]
            manifest = dict(item["manifest"])
            manifest["story_ru"] = item.get("story_ru", "")

            fields = {
                "kind": "mascot_anim",
                "name_ru": item["name_ru"],
                "name_en": item["name_en"],
                "is_free": "true",
                "min_app": args.min_app,
                "sort": str(args.sort_from + i),
                "enabled": "true",
                "data": json.dumps(manifest, ensure_ascii=False),
            }
            if not exists(item["id"], token):
                fields["id"] = item["id"]
                body, ctype = multipart(fields, {"image": png})
                rec = send("POST", f"{PB}/api/collections/catalog_items/records",
                           token, body, ctype)
                action = "заведён"
            else:
                body, ctype = multipart(fields, {"image": png})
                rec = send("PATCH",
                           f"{PB}/api/collections/catalog_items/records/{item['id']}",
                           token, body, ctype)
                action = "обновлён"

            # Ссылку на атлас дописываем в data вторым проходом: имя файла
            # известно только после загрузки.
            url = f"https://togetherly.duckdns.org/api/files/catalog_items/{rec['id']}/{rec['image']}"
            manifest["sheet"] = url
            body, ctype = multipart({"data": json.dumps(manifest, ensure_ascii=False)}, {})
            send("PATCH", f"{PB}/api/collections/catalog_items/records/{rec['id']}",
                 token, body, ctype)
            print(f"{item['name_ru']}: {action}, {url}")
    finally:
        drop_superuser(email)
        print("временный суперюзер удалён")


if __name__ == "__main__":
    main()
