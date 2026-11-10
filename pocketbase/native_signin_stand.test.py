#!/usr/bin/env python3
"""Стенд: вход через Google и Apple не оставляет чужой пароль в аккаунте.

Нативный вход (`google_native.pb.js`, `apple_native.pb.js`) находит аккаунт по
почте из токена. Аккаунт с этой почтой мог завести кто угодно: почту при
регистрации по паролю никто не подтверждает. До 10.11.2026 хозяин почты входил
через Google в такую заготовку, а пароль того, кто её завёл, оставался
рабочим — он заходил следом и читал всё. Штатный вход PocketBase страницей в
этом случае ставит неподтверждённому аккаунту случайный пароль; нативный этого
не делал.

Живым сервером это не проверить (нужен настоящий токен Google), поэтому тест
поднимает свой PocketBase на пустой базе и подставной релей на 127.0.0.1:8096,
который «подтверждает» любой токен:

    python3 pocketbase/native_signin_stand.test.py

Сборка PocketBase — `pocketbase/pb-cgo/pocketbase-cgo-new` (та же, что на
проде) или путь в PB_BIN.
"""
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PB_BIN = os.environ.get("PB_BIN", os.path.join(HERE, "pb-cgo", "pocketbase-cgo-new"))
PORT = int(os.environ.get("STAND_PORT", "18097"))
BASE = f"http://127.0.0.1:{PORT}"
RELAY_PORT = 8096  # адрес релея вписан в хуки
HOOKS = ("google_native.pb.js", "apple_native.pb.js", "login_methods.pb.js", "partner_reset.js")
ADMIN = ("stand@x.local", "standpass12345")
T0 = time.time()
OK, FAIL = [], []


def log(*a):
    print(f"[{time.time() - T0:6.2f}s]", *a, flush=True)


def check(name, cond, detail=""):
    (OK if cond else FAIL).append(name)
    log(("  ✓ " if cond else "  ✗ ") + name + (f" — {detail}" if detail else ""))


def api(path, data=None, token=None, method=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(BASE + path, data=body,
                                 method=method or ("POST" if body is not None else "GET"))
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


class Relay(http.server.BaseHTTPRequestHandler):
    """Подставной `apns_relay.py`: токен — это json с готовыми полями."""

    def do_POST(self):  # noqa: N802 — имя задано базовым классом
        size = int(self.headers.get("Content-Length") or 0)
        try:
            claims = json.loads(json.loads(self.rfile.read(size))["token"])
            confirmed = str(claims.get("email_verified", "")).lower() == "true"
            if self.path == "/google/verify" and not confirmed:
                # Настоящий релей токен Google с неподтверждённой почтой не
                # принимает вовсе (`verify_google_identity`).
                out = {"ok": False, "reason": "ValueError: почта не подтверждена"}
            else:
                # У Apple признак едет в ответе булевым, как в настоящем релее.
                out = dict(claims, ok=True, email_verified=confirmed)
        except Exception:
            out = {"ok": False, "reason": "плохой токен"}
        raw = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, *args):
        pass


def signup(email, password):
    st, r = api("/api/collections/users/records", {
        "email": email, "password": password, "passwordConfirm": password,
        "name": "Заготовка"})
    assert st in (200, 201), f"регистрация {email}: {st} {r}"
    return r["id"]


def login(email, password):
    st, r = api("/api/collections/users/auth-with-password",
                {"identity": email, "password": password})
    return r.get("token") if st == 200 else None


def alive(token):
    st, _ = api("/api/collections/users/auth-refresh", {}, token)
    return st == 200


def google(sub, email, verified="true"):
    return api("/api/google/native", {"idToken": json.dumps(
        {"sub": sub, "email": email, "email_verified": verified, "name": "Хозяин Почты"})})


def apple(sub, email):
    return api("/api/apple/native", {"identityToken": json.dumps(
        {"sub": sub, "email": email, "email_verified": "true"})})


def scenarios(admin):
    log("=== 1. чужая заготовка: хозяин почты входит через Google ===")
    uid = signup("victim@example.com", "AttackerPass1!")
    theirs = login("victim@example.com", "AttackerPass1!")
    check("тот, кто завёл заготовку, вошёл по своему паролю", bool(theirs))
    st, r = google("g-victim", "victim@example.com")
    mine = r.get("token", "")
    check("хозяин почты вошёл в аккаунт с этой почтой",
          st == 200 and (r.get("record") or {}).get("id") == uid, f"{st} {str(r)[:160]}")
    check("пароль заготовки больше не подходит",
          login("victim@example.com", "AttackerPass1!") is None)
    check("прежний вход того, кто её завёл, сорван", not alive(theirs))
    check("вход хозяина почты жив", alive(mine))
    check("почта помечена подтверждённой", (r.get("record") or {}).get("verified") is True)
    st, m = api("/api/auth/methods", None, mine)
    check("экран «Способы входа»: пароля нет, Google привязан",
          st == 200 and m.get("password") is False and m.get("providers") == ["google"],
          f"{st} {m}")
    st, r = api("/api/auth/set-password", {"password": "OwnerPass123!"}, mine)
    check("хозяин задаёт свой пароль без старого", st == 200 and bool(r.get("token")),
          f"{st} {str(r)[:120]}")
    check("его новый пароль работает", bool(login("victim@example.com", "OwnerPass123!")))

    log("=== 2. второй вход через Google ничего не сбрасывает ===")
    st, r = google("g-victim", "victim@example.com")
    check("вошёл в тот же аккаунт", st == 200 and (r.get("record") or {}).get("id") == uid, f"{st}")
    check("пароль хозяина цел", bool(login("victim@example.com", "OwnerPass123!")))

    log("=== 3. подтверждённый аккаунт: пароль не трогаем ===")
    uid2 = signup("known@example.com", "KnownPass123!")
    st, _ = api(f"/api/collections/users/records/{uid2}", {"verified": True}, admin,
                method="PATCH")
    check("почта подтверждена (стенд)", st == 200, f"{st}")
    was = login("known@example.com", "KnownPass123!")
    st, r = google("g-known", "known@example.com")
    check("вошёл через Google в свой аккаунт",
          st == 200 and (r.get("record") or {}).get("id") == uid2, f"{st}")
    check("пароль прежний", bool(login("known@example.com", "KnownPass123!")))
    check("прежний вход жив", alive(was))

    log("=== 3а. Google привязан в «Способах входа»: работают оба способа ===")
    # Человек вошёл по паролю и привязал Google на экране «Способы входа»
    # (привязку делает PocketBase страницей, здесь она заведена записью).
    # Почта при этом так и не подтверждена. Вход через Google находит такого
    # человека по привязке, а не по почте, и пароль не трогает.
    uid_l = signup("linked@example.com", "LinkedPass123!")
    was = login("linked@example.com", "LinkedPass123!")
    st, r = api("/api/collections/_externalAuths/records", {
        "collectionRef": "_pb_users_auth_", "recordRef": uid_l,
        "provider": "google", "providerId": "g-linked"}, admin)
    check("привязка Google заведена (стенд)", st == 200, f"{st} {str(r)[:120]}")
    st, r = google("g-linked", "linked@example.com")
    check("вошёл через Google в свой аккаунт",
          st == 200 and (r.get("record") or {}).get("id") == uid_l, f"{st}")
    check("пароль по-прежнему работает", bool(login("linked@example.com", "LinkedPass123!")))
    check("вход на другом телефоне не сорван", alive(was))
    st, m = api("/api/auth/methods", None, r.get("token", ""))
    check("«Способы входа»: и пароль, и Google",
          st == 200 and m.get("password") is True and m.get("providers") == ["google"],
          f"{st} {m}")

    log("=== 4. новой почты нет — заводится аккаунт ===")
    st, r = google("g-new", "newcomer@example.com")
    check("аккаунт заведён и подтверждён",
          st == 200 and (r.get("record") or {}).get("verified") is True
          and (r.get("meta") or {}).get("created") is True, f"{st} {str(r)[:160]}")

    log("=== 5. Google не подтвердил почту — по ней не цепляемся ===")
    signup("shaky@example.com", "ShakyPass123!")
    st, r = google("g-shaky", "shaky@example.com", verified="false")
    check("вход отклонён, чужой аккаунт не открыт", st != 200, f"{st} {str(r)[:120]}")
    check("пароль аккаунта цел", bool(login("shaky@example.com", "ShakyPass123!")))

    log("=== 6. то же через Apple ===")
    uid3 = signup("apple-victim@example.com", "AttackerPass2!")
    theirs = login("apple-victim@example.com", "AttackerPass2!")
    st, r = apple("a-victim", "apple-victim@example.com")
    check("хозяин почты вошёл через Apple",
          st == 200 and (r.get("record") or {}).get("id") == uid3, f"{st} {str(r)[:160]}")
    check("пароль заготовки больше не подходит",
          login("apple-victim@example.com", "AttackerPass2!") is None)
    check("прежний вход того, кто её завёл, сорван", not alive(theirs))
    check("вход хозяина почты жив", alive(r.get("token", "")))


def main():
    if not os.path.exists(PB_BIN):
        sys.exit(f"нет сборки PocketBase: {PB_BIN} (путь можно дать в PB_BIN)")
    try:
        relay = http.server.ThreadingHTTPServer(("127.0.0.1", RELAY_PORT), Relay)
    except OSError as e:
        sys.exit(f"порт {RELAY_PORT} занят (здесь запущен настоящий релей?): {e}")
    threading.Thread(target=relay.serve_forever, daemon=True).start()

    root = tempfile.mkdtemp(prefix="pb-stand-")
    data, hooks = os.path.join(root, "pb_data"), os.path.join(root, "pb_hooks")
    os.makedirs(hooks)
    for name in HOOKS:
        shutil.copy(os.path.join(HERE, "pb_hooks", name), hooks)
    subprocess.run([PB_BIN, "superuser", "upsert", *ADMIN, "--dir", data],
                   check=True, capture_output=True)
    # Папку хуков сборка берёт сама: `pb_hooks` рядом с папкой данных.
    server = subprocess.Popen(
        [PB_BIN, "serve", f"--http=127.0.0.1:{PORT}", "--dir", data],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(60):
            try:
                if api("/api/health")[0] == 200:
                    break
            except OSError:
                pass
            time.sleep(0.25)
        else:
            sys.exit("стенд не поднялся")
        st, r = api("/api/collections/_superusers/auth-with-password",
                    {"identity": ADMIN[0], "password": ADMIN[1]})
        admin = r["token"]
        # Поля прода, которые читают хуки.
        st, col = api("/api/collections/users", None, admin)
        fields = col["fields"] + [
            {"name": "display_name", "type": "text"},
            {"name": "platform", "type": "text"},
            {"name": "gender", "type": "text"},
            {"name": "password_set", "type": "number"},
        ]
        st, r = api("/api/collections/users", {"fields": fields}, admin, method="PATCH")
        assert st == 200, f"поля стенда: {st} {r}"
        scenarios(admin)
    finally:
        server.terminate()
        try:
            server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill()
        relay.shutdown()
        shutil.rmtree(root, ignore_errors=True)

    log(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    if FAIL:
        for f in FAIL:
            log("  ✗", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
