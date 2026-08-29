#!/usr/bin/env python3
"""Тесты сверки чека App Store — того самого места, где 28–29 августа 2026
потерялись шесть оплат Togetherly+.

Что случилось. Приложение собрано на `in_app_purchase_storekit` 0.4.x, а это
StoreKit 2: в `serverVerificationData` приходит не base64-чек приложения, а
JWS-представление транзакции. Старый `verifyReceipt` такой формат не понимает
и отвечает `21002 malformed`, служба возвращала `valid:false`, а хук —
`403 purchase_not_verified`. Деньги списаны, доступа нет.

Проверять JWS надо самим: Apple подписывает транзакцию ключом, чей сертификат
лежит в заголовке (`x5c`), а цепочка ведёт к Apple Root CA — G3. Никаких
ключей и походов наружу для этого не нужно, поэтому тесты обходятся своей
цепочкой сертификатов и подменённым отпечатком корня.

Запуск: python3 tools/test_play_verify.py
"""
from __future__ import annotations

import base64
import datetime as dt
import json
import os
import sys
import unittest
from unittest import mock

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

import jwt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play_verify  # noqa: E402


# ── свои сертификаты вместо настоящих ────────────────────────────────────────

def _выпустить(subject: str, ключ, издатель_имя, издатель_ключ, *,
               ca: bool, дней: int = 30, начало_назад: int = 1):
    """Один сертификат цепочки. Самоподписанный, если издатель — он сам."""
    сейчас = dt.datetime.now(dt.timezone.utc)
    имя = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, subject)])
    builder = (
        x509.CertificateBuilder()
        .subject_name(имя)
        .issuer_name(издатель_имя)
        .public_key(ключ.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(сейчас - dt.timedelta(days=начало_назад))
        .not_valid_after(сейчас + dt.timedelta(days=дней))
        .add_extension(x509.BasicConstraints(ca=ca, path_length=None),
                       critical=True)
    )
    cert = builder.sign(издатель_ключ, hashes.SHA256())
    return cert, имя


def цепочка(дней_у_листа: int = 30):
    """Корень → промежуточный → лист. Возвращает сертификаты и ключ листа."""
    root_key = ec.generate_private_key(ec.SECP256R1())
    root, root_имя = _выпустить_самоподписанный("Тестовый корень", root_key)

    inter_key = ec.generate_private_key(ec.SECP256R1())
    inter, inter_имя = _выпустить("Тестовый промежуточный", inter_key,
                                  root_имя, root_key, ca=True)

    leaf_key = ec.generate_private_key(ec.SECP256R1())
    leaf, _ = _выпустить("Тестовый лист", leaf_key, inter_имя, inter_key,
                         ca=False, дней=дней_у_листа)
    return {"root": root, "inter": inter, "leaf": leaf, "leaf_key": leaf_key,
            "root_key": root_key, "inter_имя": inter_имя, "inter_key": inter_key}


def _выпустить_самоподписанный(subject: str, ключ):
    имя = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, subject)])
    сейчас = dt.datetime.now(dt.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(имя)
        .issuer_name(имя)
        .public_key(ключ.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(сейчас - dt.timedelta(days=1))
        .not_valid_after(сейчас + dt.timedelta(days=365))
        .add_extension(x509.BasicConstraints(ca=True, path_length=None),
                       critical=True)
        .sign(ключ, hashes.SHA256())
    )
    return cert, имя


def отпечаток(cert) -> str:
    return cert.fingerprint(hashes.SHA256()).hex()


def x5c(*certs) -> list[str]:
    return [base64.b64encode(c.public_bytes(serialization.Encoding.DER)).decode()
            for c in certs]


def собрать_jws(нагрузка: dict, ключ_подписи, сертификаты: list[str]) -> str:
    return jwt.encode(нагрузка, ключ_подписи, algorithm="ES256",
                      headers={"x5c": сертификаты})


ЧЕК = {
    "transactionId": "2000000900000001",
    "originalTransactionId": "2000000900000001",
    "bundleId": "com.togetherly.love",
    "productId": "togetherly_plus",
    "type": "Non-Consumable",
    "purchaseDate": 1788000000000,
    "environment": "Production",
}


class ПроверкаJWS(unittest.TestCase):
    def setUp(self):
        self.цепь = цепочка()
        патч = mock.patch.object(
            play_verify, "APPLE_ROOT_SHA256", {отпечаток(self.цепь["root"])})
        патч.start()
        self.addCleanup(патч.stop)

    def чек(self, **правки) -> str:
        нагрузка = dict(ЧЕК, **правки)
        return собрать_jws(нагрузка, self.цепь["leaf_key"],
                           x5c(self.цепь["leaf"], self.цепь["inter"],
                               self.цепь["root"]))

    # ── что должно проходить ────────────────────────────────────────────────

    def test_настоящая_покупка_принята(self):
        итог = play_verify.verify_apple("togetherly_plus", self.чек())
        self.assertEqual(итог, {"ok": True, "valid": True, "reason": "",
                                "environment": "Production",
                                "transactionId": "2000000900000001"})

    def test_песочница_принята(self):
        """TestFlight подписывает тем же корнем, но помечает окружение."""
        итог = play_verify.verify_apple("togetherly_plus",
                                        self.чек(environment="Sandbox"))
        self.assertTrue(итог["valid"])
        self.assertEqual(итог["environment"], "Sandbox")

    def test_подарок_расходуемый_принят(self):
        итог = play_verify.verify_apple(
            "togetherly_plus_gift",
            self.чек(productId="togetherly_plus_gift", type="Consumable"))
        self.assertTrue(итог["valid"])

    # ── что должно отвергаться ──────────────────────────────────────────────

    def test_чужой_корень_отвергнут(self):
        """Кто угодно может выпустить свою цепочку — доверяем только Apple."""
        чужая = цепочка()
        подделка = собрать_jws(ЧЕК, чужая["leaf_key"],
                               x5c(чужая["leaf"], чужая["inter"], чужая["root"]))
        итог = play_verify.verify_apple("togetherly_plus", подделка)
        self.assertFalse(итог["valid"])
        self.assertEqual(итог["reason"], "apple_untrusted_root")

    def test_подпись_чужим_ключом_отвергнута(self):
        """В x5c настоящая цепочка, а подписано другим ключом."""
        чужой_ключ = ec.generate_private_key(ec.SECP256R1())
        подделка = собрать_jws(ЧЕК, чужой_ключ,
                               x5c(self.цепь["leaf"], self.цепь["inter"],
                                   self.цепь["root"]))
        итог = play_verify.verify_apple("togetherly_plus", подделка)
        self.assertFalse(итог["valid"])
        self.assertEqual(итог["reason"], "apple_bad_signature")

    def test_разорванная_цепочка_отвергнута(self):
        """Лист выпущен не тем промежуточным, что лежит в заголовке."""
        другая = цепочка()
        подделка = собрать_jws(ЧЕК, self.цепь["leaf_key"],
                               x5c(self.цепь["leaf"], другая["inter"],
                                   self.цепь["root"]))
        итог = play_verify.verify_apple("togetherly_plus", подделка)
        self.assertFalse(итог["valid"])
        self.assertEqual(итог["reason"], "apple_broken_chain")

    def test_чужой_товар_отвергнут(self):
        """Чек за подарок не открывает Плюс: за что пришли, то и сверяем."""
        итог = play_verify.verify_apple("togetherly_plus",
                                        self.чек(productId="mood_pack.moti"))
        self.assertFalse(итог["valid"])
        self.assertEqual(итог["reason"], "product_not_in_receipt")

    def test_чужое_приложение_отвергнуто(self):
        итог = play_verify.verify_apple("togetherly_plus",
                                        self.чек(bundleId="com.example.other"))
        self.assertFalse(итог["valid"])
        self.assertEqual(итог["reason"], "bundle_mismatch")

    def test_возврат_денег_отвергнут(self):
        итог = play_verify.verify_apple(
            "togetherly_plus", self.чек(revocationDate=1788000100000))
        self.assertFalse(итог["valid"])
        self.assertEqual(итог["reason"], "cancelled")

    def test_просроченный_сертификат_отвергнут(self):
        просроченная = цепочка(дней_у_листа=-1)
        with mock.patch.object(play_verify, "APPLE_ROOT_SHA256",
                               {отпечаток(просроченная["root"])}):
            подделка = собрать_jws(
                ЧЕК, просроченная["leaf_key"],
                x5c(просроченная["leaf"], просроченная["inter"],
                    просроченная["root"]))
            итог = play_verify.verify_apple("togetherly_plus", подделка)
        self.assertFalse(итог["valid"])
        self.assertEqual(итог["reason"], "apple_cert_expired")

    def test_мусор_вместо_чека_отвергнут(self):
        """Три части есть, а заголовок не разбирается — наружу не ходим."""
        подделка = base64.urlsafe_b64encode(b'{"alg":"ES256","x5c":[]}').decode()
        итог = play_verify.verify_apple("togetherly_plus",
                                        f"{подделка}.aaaa.bbbb")
        self.assertFalse(итог["valid"])
        self.assertEqual(итог["reason"], "apple_short_chain")


class РазвилкаФорматов(unittest.TestCase):
    """Старые сборки на StoreKit 1 присылают base64-чек — их путь не тронут."""

    def test_старый_чек_идёт_к_verifyReceipt(self):
        чек = base64.b64encode(b"\x30\x82" + b"receipt" * 20).decode()
        with mock.patch.object(play_verify, "verify_apple_receipt",
                               return_value={"ok": True, "valid": True,
                                             "reason": ""}) as старый:
            итог = play_verify.verify_apple("togetherly_plus", чек)
        старый.assert_called_once()
        self.assertTrue(итог["valid"])

    def test_jws_не_ходит_к_verifyReceipt(self):
        цепь = цепочка()
        with mock.patch.object(play_verify, "APPLE_ROOT_SHA256",
                               {отпечаток(цепь["root"])}), \
             mock.patch.object(play_verify, "verify_apple_receipt") as старый:
            токен = собрать_jws(ЧЕК, цепь["leaf_key"],
                                x5c(цепь["leaf"], цепь["inter"], цепь["root"]))
            итог = play_verify.verify_apple("togetherly_plus", токен)
        старый.assert_not_called()
        self.assertTrue(итог["valid"])

    def test_опознание_jws(self):
        цепь = цепочка()
        токен = собрать_jws(ЧЕК, цепь["leaf_key"], x5c(цепь["leaf"]))
        self.assertTrue(play_verify.похоже_на_jws(токен))
        self.assertFalse(play_verify.похоже_на_jws(
            base64.b64encode(b"receipt" * 40).decode()))
        self.assertFalse(play_verify.похоже_на_jws(""))


if __name__ == "__main__":
    unittest.main(verbosity=2)
