"""Настоящий токен сброса пароля для проверки цепочки.

PocketBase подписывает его HS256 ключом `users.tokenKey + secret коллекции`.
Тот же приём, что hotpath использует для проверки auth-токенов.
"""
import base64, hashlib, hmac, json, sqlite3, sys, time

DB = "/opt/pocketbase/pb_data/data.db"
uid = sys.argv[1]

db = sqlite3.connect(DB)
token_key = db.execute("SELECT tokenKey FROM users WHERE id = ?", (uid,)).fetchone()[0]
opts = json.loads(db.execute(
    "SELECT options FROM _collections WHERE name = 'users'").fetchone()[0])
col_id = db.execute("SELECT id FROM _collections WHERE name = 'users'").fetchone()[0]
secret = opts["passwordResetToken"]["secret"]
dur = int(opts["passwordResetToken"].get("duration") or 1800)

def b64(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

now = int(time.time())
head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
body = b64(json.dumps({
    "collectionId": col_id, "exp": now + dur, "id": uid,
    "type": "passwordReset", "email": db.execute(
        "SELECT email FROM users WHERE id = ?", (uid,)).fetchone()[0],
}, separators=(",", ":")).encode())
sig = b64(hmac.new((token_key + secret).encode(), f"{head}.{body}".encode(),
                   hashlib.sha256).digest())
print(f"{head}.{body}.{sig}")
