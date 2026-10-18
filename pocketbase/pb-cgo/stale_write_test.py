"""Проверка: правка профиля, ждавшая очереди на запись, не стирает чужое.

Сценарий 18.10.2026: запрос PATCH читает запись users, ждёт свободного
писателя, а за это время сервер выдаёт приз (Плюс, рамку). Старая сборка
клала строку целиком и приз стирала.

Запуск: python3 stale_write_test.py <путь к бинарю pocketbase>
Поднимает свою копию PocketBase во временной папке, ничего снаружи не трогает.
"""
import json
import os
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

ADMIN = ("admin@stale.test", "AdminPass123!")
USER_PASS = "UserPass123!"


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Api:
    def __init__(self, base):
        self.base = base
        self.token = ""

    def call(self, method, path, body=None, token=None):
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self.base + path, data=data, method=method)
        request.add_header("Content-Type", "application/json")
        # token="-" — запрос без входа (вход пользователя паролем)
        auth = self.token if token is None else token
        if auth and auth != "-":
            request.add_header("Authorization", auth)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.status, json.loads(response.read() or b"{}")
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read() or b"{}")


def main():
    binary = os.path.abspath(sys.argv[1])
    failures = []

    def check(name, ok, detail=""):
        print(("ПРОШЛО  " if ok else "ПРОВАЛ  ") + name + (f" — {detail}" if detail and not ok else ""))
        if not ok:
            failures.append(name)

    with tempfile.TemporaryDirectory() as root:
        data_dir = os.path.join(root, "pb_data")
        subprocess.run([binary, "superuser", "upsert", *ADMIN, "--dir", data_dir],
                       check=True, capture_output=True)
        port = free_port()
        log = open(os.path.join(root, "pb.log"), "w")
        server = subprocess.Popen([binary, "serve", "--http", f"127.0.0.1:{port}", "--dir", data_dir],
                                  cwd=root, stdout=log, stderr=subprocess.STDOUT)
        try:
            api = Api(f"http://127.0.0.1:{port}")
            for _ in range(150):
                try:
                    if api.call("GET", "/api/health")[0] == 200:
                        break
                except OSError:
                    pass
                time.sleep(0.2)

            status, auth = api.call("POST", "/api/collections/_superusers/auth-with-password",
                                    {"identity": ADMIN[0], "password": ADMIN[1]})
            assert status == 200, auth
            api.token = auth["token"]

            status, users = api.call("GET", "/api/collections/users")
            fields = users["fields"] + [
                {"name": "plus", "type": "bool"},
                {"name": "note", "type": "text"},
                {"name": "owned", "type": "json"},
                {"name": "updated_at", "type": "text"},
                {"name": "notif_synced_at", "type": "number"},
                {"name": "theme_id", "type": "number"},
            ]
            status, body = api.call("PATCH", "/api/collections/users", {"fields": fields})
            assert status == 200, body

            status, user = api.call("POST", "/api/collections/users/records", {
                "email": "user@stale.test", "password": USER_PASS, "passwordConfirm": USER_PASS,
                "note": "a", "owned": [],
            })
            assert status == 200, user
            uid = user["id"]
            db_path = os.path.join(data_dir, "data.db")

            def race(server_sql, client_body):
                """Пока база занята «сервером», приходит правка профиля."""
                locked = threading.Event()

                def holder():
                    con = sqlite3.connect(db_path, timeout=30, isolation_level=None)
                    con.execute("BEGIN IMMEDIATE")
                    locked.set()
                    time.sleep(2.0)
                    con.execute(server_sql, (uid,))
                    con.execute("COMMIT")
                    con.close()

                thread = threading.Thread(target=holder)
                thread.start()
                locked.wait(5)
                time.sleep(0.2)
                result = api.call("PATCH", f"/api/collections/users/records/{uid}", client_body)
                thread.join()
                return result

            status, _ = race("UPDATE users SET plus = 1 WHERE id = ?", {"note": "b"})
            check("правка профиля под очередью отвечает 200", status == 200, str(status))
            _, record = api.call("GET", f"/api/collections/users/records/{uid}")
            check("Плюс, выданный во время ожидания, уцелел", record.get("plus") is True, str(record.get("plus")))
            check("сама правка записалась", record.get("note") == "b", str(record.get("note")))

            race("UPDATE users SET owned = '[\"frame:frame_cat\"]' WHERE id = ?", {"note": "c"})
            _, record = api.call("GET", f"/api/collections/users/records/{uid}")
            check("рамка, выданная во время ожидания, уцелела",
                  record.get("owned") == ["frame:frame_cat"], str(record.get("owned")))

            status, _ = api.call("PATCH", f"/api/collections/users/records/{uid}", {"plus": False})
            _, record = api.call("GET", f"/api/collections/users/records/{uid}")
            check("намеренное снятие Плюса записывается", record.get("plus") is False, str(record.get("plus")))

            new_pass = "NewUserPass456!"
            status, _ = api.call("PATCH", f"/api/collections/users/records/{uid}",
                                 {"password": new_pass, "passwordConfirm": new_pass})
            status_new, _ = api.call("POST", "/api/collections/users/auth-with-password",
                                     {"identity": "user@stale.test", "password": new_pass}, token="-")
            status_old, _ = api.call("POST", "/api/collections/users/auth-with-password",
                                     {"identity": "user@stale.test", "password": USER_PASS}, token="-")
            check("вход с новым паролем", status_new == 200, str(status_new))
            check("старый пароль больше не подходит", status_old == 400, str(status_old))

            _, before = api.call("GET", f"/api/collections/users/records/{uid}")
            time.sleep(1.1)
            api.call("PATCH", f"/api/collections/users/records/{uid}", {"note": "d"})
            _, after = api.call("GET", f"/api/collections/users/records/{uid}")
            check("время изменения сдвигается", after.get("updated") != before.get("updated"),
                  f"{before.get('updated')} -> {after.get('updated')}")

            # Пустая правка (те же значения плюс отметка updated_at) не ждёт
            # писателя и не пишет: база занята, а ответ приходит сразу.
            _, before = api.call("GET", f"/api/collections/users/records/{uid}")
            locked = threading.Event()
            release = threading.Event()

            def hold_lock():
                con = sqlite3.connect(db_path, timeout=30, isolation_level=None)
                con.execute("BEGIN IMMEDIATE")
                locked.set()
                release.wait(5)
                con.execute("ROLLBACK")
                con.close()

            holder = threading.Thread(target=hold_lock)
            holder.start()
            locked.wait(5)
            started = time.time()
            status, body = api.call("PATCH", f"/api/collections/users/records/{uid}",
                                    {"note": "d", "updated_at": "2026-10-19T00:00:00Z"})
            elapsed = time.time() - started
            release.set()
            holder.join()
            _, after = api.call("GET", f"/api/collections/users/records/{uid}")
            check("пустая правка отвечает 200 и записью", status == 200 and body.get("id") == uid, str(status))
            check("пустая правка не ждёт занятую базу", elapsed < 1.0, f"{elapsed:.2f} с")
            check("пустая правка не сдвигает время изменения", after.get("updated") == before.get("updated"),
                  f"{before.get('updated')} -> {after.get('updated')}")

            api.call("PATCH", f"/api/collections/users/records/{uid}", {"notif_synced_at": 111})
            _, record = api.call("GET", f"/api/collections/users/records/{uid}")
            check("первая отметка синхронизации уведомлений пишется", record.get("notif_synced_at") == 111,
                  str(record.get("notif_synced_at")))
            api.call("PATCH", f"/api/collections/users/records/{uid}", {"notif_synced_at": 222})
            _, record = api.call("GET", f"/api/collections/users/records/{uid}")
            check("повторная отметка без других правок не пишется", record.get("notif_synced_at") == 111,
                  str(record.get("notif_synced_at")))
            api.call("PATCH", f"/api/collections/users/records/{uid}", {"theme_id": 2, "notif_synced_at": 333})
            _, record = api.call("GET", f"/api/collections/users/records/{uid}")
            check("настоящая правка вместе с отметкой пишется",
                  record.get("theme_id") == 2 and record.get("notif_synced_at") == 333,
                  f"{record.get('theme_id')} {record.get('notif_synced_at')}")
        finally:
            server.terminate()
            server.wait(10)
            log.close()

    print("ИТОГ:", "всё прошло" if not failures else f"провалов {len(failures)}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
