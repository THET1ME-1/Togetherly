#!/usr/bin/env python3
"""Проверка чека Google Play. Локальная служба на 127.0.0.1:8097.

Зачем отдельной службой. Проверять покупку должен сервер: клиент присылает
`purchaseToken`, и без сверки с Google этот токен можно выдумать — тогда Plus
или монеты достаются даром. Сверку хочется делать прямо в хуке PocketBase, но
JSVM не умеет подписывать RS256, а без подписи не получить токен доступа к
Play Developer API. Поэтому подпись и поход в Google живут здесь, а хук ходит
на localhost.

Протокол:
    POST /verify  {"productId": "...", "purchaseToken": "..."}
      → 200 {"ok": true, "valid": true,  "state": 0}         покупка настоящая
      → 200 {"ok": true, "valid": false, "reason": "..."}    Google не признал
      → 200 {"ok": false, "reason": "..."}                   сверить не вышло

Разница между `valid:false` и `ok:false` важна для хука: первое — отказ
(товар не покупали), второе — наша беда (Google не ответил), и на ней ломать
покупку живому человеку нельзя.

Ключ сервисного аккаунта: /opt/play-service-account.json (тот же
play-publisher@, что публикует сборки из CI). Права выданы в Play Console.
"""
from __future__ import annotations

import base64
import datetime as dt
import json
import logging
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa

KEY_PATH = os.environ.get("PLAY_KEY_PATH", "/opt/play-service-account.json")
PACKAGE = os.environ.get("PLAY_PACKAGE", "com.togetherly.love")
PORT = int(os.environ.get("PLAY_VERIFY_PORT", "8097"))
SCOPE = "https://www.googleapis.com/auth/androidpublisher"

log = logging.getLogger("play_verify")

# ── App Store ──────────────────────────────────────────────────────────────
# С iPhone приходит одно из двух, и различать их обязательно.
#
#   StoreKit 2 (сейчас): `serverVerificationData` — это JWS-представление
#   транзакции, три части через точку. Подписала его Apple, сертификат подписи
#   лежит в самом заголовке (`x5c`), цепочка ведёт к Apple Root CA — G3.
#   Проверяем сами: ни ключей, ни похода наружу для этого не нужно.
#
#   StoreKit 1 (сборки до 1.31): base64 app receipt, разбирает его сама Apple
#   на `verifyReceipt`. Путь оставлен ради тех, кто не обновился.
#
# ЗАЧЕМ РАЗВИЛКА. 28–29 августа 2026 шесть оплат Togetherly+ пропали именно
# здесь: JWS уходил на `verifyReceipt`, Apple отвечала `21002 malformed`, хук
# читал это как «покупки не было» и отдавал 403. Деньги списаны, доступа нет.
BUNDLE_ID = os.environ.get("APPLE_BUNDLE_ID", "com.togetherly.love")
APPLE_PROD = "https://buy.itunes.apple.com/verifyReceipt"
APPLE_SANDBOX = "https://sandbox.itunes.apple.com/verifyReceipt"

# Отпечаток SHA-256 корневого сертификата Apple Root CA — G3, к которому обязана
# сводиться цепочка из `x5c`. Держим списком: смена корня у Apple редка, но
# тогда какое-то время в ходу будут оба.
APPLE_ROOT_SHA256 = {
    "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179",
}

_token: str | None = None
_token_until: float = 0.0
_lock = threading.Lock()


def access_token() -> str:
    """Токен доступа к Play API. Держим до истечения: он живёт час, а покупки
    приходят редко — просить новый на каждую было бы расточительно."""
    global _token, _token_until
    with _lock:
        if _token and time.time() < _token_until - 60:
            return _token
        key = json.load(open(KEY_PATH))
        now = int(time.time())
        assertion = jwt.encode(
            {
                "iss": key["client_email"],
                "scope": SCOPE,
                "aud": "https://oauth2.googleapis.com/token",
                "iat": now,
                "exp": now + 3600,
            },
            key["private_key"],
            algorithm="RS256",
        )
        body = urllib.parse.urlencode({
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        }).encode()
        req = urllib.request.Request("https://oauth2.googleapis.com/token",
                                     data=body)
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read())
        _token = data["access_token"]
        _token_until = time.time() + int(data.get("expires_in", 3600))
        return _token


def verify(product_id: str, purchase_token: str) -> dict:
    """Спрашивает Google про конкретную покупку.

    purchaseState: 0 — куплено, 1 — отменено, 2 — ожидает оплаты. Засчитываем
    только ноль: у отменённой деньги вернули, у ожидающей их ещё не списали.
    """
    url = (f"https://androidpublisher.googleapis.com/androidpublisher/v3"
           f"/applications/{PACKAGE}/purchases/products/"
           f"{urllib.parse.quote(product_id)}/tokens/"
           f"{urllib.parse.quote(purchase_token)}")
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {access_token()}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read())
    except urllib.error.HTTPError as e:
        # 400 и 404 — Google не знает такой покупки: это отказ, а не наша беда.
        if e.code in (400, 404):
            return {"ok": True, "valid": False, "reason": f"google_{e.code}"}
        return {"ok": False, "reason": f"http_{e.code}"}
    except Exception as exc:
        return {"ok": False, "reason": type(exc).__name__}

    state = int(data.get("purchaseState", 1))
    return {
        "ok": True,
        "valid": state == 0,
        "state": state,
        "orderId": data.get("orderId", ""),
        "reason": "" if state == 0 else f"state_{state}",
    }


def apple_verdict(raw: dict, product_id: str) -> dict:
    """Разбирает ответ `verifyReceipt`.

    Коды Apple: 0 — чек разобран, 21007 — это чек песочницы (надо переспросить
    у sandbox-адреса), остальное — отказ. Товар ищем в самом чеке: там лежат
    ВСЕ покупки приложения, а засчитывать надо ровно ту, за которую пришли.
    """
    status = int(raw.get("status", -1))
    if status == 21007:
        return {"ok": True, "valid": False, "reason": "sandbox", "retry_sandbox": True}
    if status != 0:
        return {"ok": True, "valid": False, "reason": f"apple_{status}"}

    bundle = str((raw.get("receipt") or {}).get("bundle_id") or "")
    if bundle != BUNDLE_ID:
        return {"ok": True, "valid": False, "reason": "bundle_mismatch"}

    items = []
    for key in ("in_app", "latest_receipt_info"):
        part = raw.get(key) or (raw.get("receipt") or {}).get(key) or []
        if isinstance(part, list):
            items += part

    mine = [i for i in items if str(i.get("product_id") or "") == product_id]
    if not mine:
        return {"ok": True, "valid": False, "reason": "product_not_in_receipt"}
    # Возврат денег Apple помечает датой отмены — такую покупку не засчитываем.
    if all(i.get("cancellation_date_ms") for i in mine):
        return {"ok": True, "valid": False, "reason": "cancelled"}
    return {"ok": True, "valid": True, "reason": ""}


def похоже_на_jws(токен: str) -> bool:
    """Отличает транзакцию StoreKit 2 от старого чека приложения.

    Смотрим не на точки (в base64 их не бывает, но мусор бывает всякий), а на
    заголовок: у настоящего JWS он раскрывается в JSON с `alg` и цепочкой
    сертификатов `x5c`.
    """
    части = str(токен or "").split(".")
    if len(части) != 3:
        return False
    try:
        сырой = части[0]
        сырой += "=" * (-len(сырой) % 4)
        заголовок = json.loads(base64.urlsafe_b64decode(сырой))
    except Exception:
        return False
    return bool(заголовок.get("alg")) and isinstance(заголовок.get("x5c"), list)


def _срок(cert) -> tuple:
    """Границы годности сертификата с часовым поясом.

    На сервере стоит cryptography 3.4, где свойства отдают naive-время, а на
    рабочей машине 43, где старые имена ругаются в консоль. Поддерживаем оба.
    """
    try:
        return cert.not_valid_before_utc, cert.not_valid_after_utc
    except AttributeError:
        utc = dt.timezone.utc
        return (cert.not_valid_before.replace(tzinfo=utc),
                cert.not_valid_after.replace(tzinfo=utc))


def _подписал(cert, издатель) -> bool:
    """Проверяет, что `издатель` действительно выпустил `cert`."""
    ключ = издатель.public_key()
    try:
        if isinstance(ключ, ec.EllipticCurvePublicKey):
            ключ.verify(cert.signature, cert.tbs_certificate_bytes,
                        ec.ECDSA(cert.signature_hash_algorithm))
        elif isinstance(ключ, rsa.RSAPublicKey):
            ключ.verify(cert.signature, cert.tbs_certificate_bytes,
                        padding.PKCS1v15(), cert.signature_hash_algorithm)
        else:
            return False
    except Exception:
        return False
    return True


def verify_apple_jws(product_id: str, токен: str) -> dict:
    """Разбирает транзакцию StoreKit 2 и говорит, настоящая ли покупка.

    Порядок проверок важен: сперва корень цепочки, потом сроки, потом сама
    цепочка, и только затем подпись данных. Так в журнал попадает первая
    настоящая причина отказа, а не «подпись не сошлась» поверх чужого корня.
    """
    try:
        сырой = токен.split(".")[0]
        сырой += "=" * (-len(сырой) % 4)
        заголовок = json.loads(base64.urlsafe_b64decode(сырой))
        цепочка = [x509.load_der_x509_certificate(base64.b64decode(c))
                   for c in (заголовок.get("x5c") or [])]
    except Exception:
        return {"ok": True, "valid": False, "reason": "apple_bad_header"}

    if len(цепочка) < 2:
        return {"ok": True, "valid": False, "reason": "apple_short_chain"}

    if отпечаток_sha256(цепочка[-1]) not in APPLE_ROOT_SHA256:
        return {"ok": True, "valid": False, "reason": "apple_untrusted_root"}

    сейчас = dt.datetime.now(dt.timezone.utc)
    for cert in цепочка:
        начало, конец = _срок(cert)
        if not (начало <= сейчас <= конец):
            return {"ok": True, "valid": False, "reason": "apple_cert_expired"}

    for i in range(len(цепочка) - 1):
        if not _подписал(цепочка[i], цепочка[i + 1]):
            return {"ok": True, "valid": False, "reason": "apple_broken_chain"}

    try:
        данные = jwt.decode(
            токен, цепочка[0].public_key(), algorithms=["ES256"],
            options={"verify_aud": False, "verify_exp": False,
                     "verify_iat": False, "verify_nbf": False})
    except Exception:
        return {"ok": True, "valid": False, "reason": "apple_bad_signature"}

    if str(данные.get("bundleId") or "") != BUNDLE_ID:
        return {"ok": True, "valid": False, "reason": "bundle_mismatch"}
    if str(данные.get("productId") or "") != product_id:
        return {"ok": True, "valid": False, "reason": "product_not_in_receipt"}
    # Возврат денег Apple помечает датой отзыва — такую покупку не засчитываем.
    if данные.get("revocationDate"):
        return {"ok": True, "valid": False, "reason": "cancelled"}

    return {
        "ok": True,
        "valid": True,
        "reason": "",
        # Песочницу пропускаем: так покупку проверяют тестировщики из
        # TestFlight, и старый путь через `verifyReceipt` вёл себя так же.
        # Окружение уходит в вердикт, чтобы в журнале было видно, чей это чек.
        "environment": str(данные.get("environment") or ""),
        "transactionId": str(данные.get("transactionId") or ""),
    }


def отпечаток_sha256(cert) -> str:
    return cert.fingerprint(hashes.SHA256()).hex()


def verify_apple(product_id: str, receipt: str) -> dict:
    """Сверка чека App Store. Формат опознаём сами (см. развилку выше)."""
    if похоже_на_jws(receipt):
        return verify_apple_jws(product_id, receipt)
    return verify_apple_receipt(product_id, receipt)


def verify_apple_receipt(product_id: str, receipt: str) -> dict:
    """Спрашивает Apple про чек. Сперва прод, потом песочница (код 21007)."""
    body = json.dumps({"receipt-data": receipt}).encode()
    for url in (APPLE_PROD, APPLE_SANDBOX):
        req = urllib.request.Request(
            url, data=body, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = json.loads(r.read())
        except urllib.error.HTTPError as exc:
            return {"ok": False, "reason": f"http_{exc.code}"}
        except Exception as exc:
            return {"ok": False, "reason": type(exc).__name__}
        verdict = apple_verdict(raw, product_id)
        if not verdict.get("retry_sandbox"):
            return verdict
    return {"ok": True, "valid": False, "reason": "sandbox_failed"}


class Handler(BaseHTTPRequestHandler):
    def _send(self, payload: dict) -> None:
        raw = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self) -> None:  # noqa: N802 — имя задано базовым классом
        if self.path.rstrip("/") != "/verify":
            self._send({"ok": False, "reason": "no_such_path"})
            return
        try:
            size = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(size) or b"{}")
        except Exception:
            self._send({"ok": False, "reason": "bad_body"})
            return

        product = str(body.get("productId") or "").strip()
        token = str(body.get("purchaseToken") or "").strip()
        if not product or not token:
            self._send({"ok": False, "reason": "no_args"})
            return

        store = str(body.get("store") or "play").strip().lower()
        if store == "appstore":
            result = verify_apple(product, token)
        else:
            result = verify(product, token)
        log.info("%s [%s] → %s", product, store, result.get("reason") or "valid")
        self._send(result)

    def do_GET(self) -> None:  # noqa: N802
        self._send({"ok": True, "service": "play_verify"})

    def log_message(self, *args) -> None:
        """Свой журнал ведём сами: стандартный пишет строку на каждый запрос."""


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    log.info("проверка чеков Play слушает 127.0.0.1:%s", PORT)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
