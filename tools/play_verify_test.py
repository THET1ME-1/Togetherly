"""Разбор ответа App Store при сверке чека.

Сверка нужна ровно за тем же, зачем она у Google: 26 июля выдуманный токен
открывал Togetherly+ даром, потому что сервер верил клиенту на слово. На iPhone
чек — это base64 app receipt, и Apple проверяет его сама на `verifyReceipt`.
Общий секрет там нужен только авто-возобновляемым подпискам, а Togetherly+ —
разовая покупка, поэтому сверка возможна без отдельного ключа.

Запуск: python3 -m unittest tools.play_verify_test -v
"""
import unittest

from play_verify import BUNDLE_ID, apple_verdict


class AppleVerdict(unittest.TestCase):
    def чек(self, product="togetherly_plus", bundle=BUNDLE_ID, status=0):
        return {
            "status": status,
            "receipt": {"bundle_id": bundle},
            "latest_receipt_info": [],
            "receipt_in_app": [],
            "in_app": [{"product_id": product, "quantity": "1"}],
        }

    def test_свой_товар_подтверждён(self):
        v = apple_verdict(self.чек(), "togetherly_plus")
        self.assertTrue(v["ok"])
        self.assertTrue(v["valid"])

    def test_чужой_товар_не_подтверждён(self):
        # В чеке лежат ВСЕ покупки приложения; засчитываем только нужную.
        v = apple_verdict(self.чек(product="coins_10"), "togetherly_plus")
        self.assertTrue(v["ok"])
        self.assertFalse(v["valid"])
        self.assertEqual(v["reason"], "product_not_in_receipt")

    def test_чужое_приложение_не_подтверждается(self):
        # Чек чужого приложения — попытка выдать чужую покупку за свою.
        v = apple_verdict(self.чек(bundle="com.example.other"), "togetherly_plus")
        self.assertFalse(v["valid"])
        self.assertEqual(v["reason"], "bundle_mismatch")

    def test_битый_чек_отклоняется(self):
        # 21002 — «receipt-data не разобрался»: подделка или мусор.
        v = apple_verdict({"status": 21002}, "togetherly_plus")
        self.assertTrue(v["ok"])
        self.assertFalse(v["valid"])
        self.assertEqual(v["reason"], "apple_21002")

    def test_песочница_видна_отдельно(self):
        # 21007 — чек из песочницы прислали в прод: это не отказ, а повод
        # переспросить у sandbox-адреса.
        v = apple_verdict({"status": 21007}, "togetherly_plus")
        self.assertEqual(v["reason"], "sandbox")
        self.assertFalse(v["valid"])
        self.assertTrue(v["retry_sandbox"])

    def test_покупки_ищутся_и_в_latest_receipt_info(self):
        # У старых чеков список лежит в другом поле.
        raw = {
            "status": 0,
            "receipt": {"bundle_id": BUNDLE_ID},
            "latest_receipt_info": [{"product_id": "togetherly_plus"}],
        }
        self.assertTrue(apple_verdict(raw, "togetherly_plus")["valid"])

    def test_отменённая_покупка_не_считается(self):
        raw = {
            "status": 0,
            "receipt": {"bundle_id": BUNDLE_ID},
            "in_app": [
                {"product_id": "togetherly_plus", "cancellation_date_ms": "1787000000000"}
            ],
        }
        v = apple_verdict(raw, "togetherly_plus")
        self.assertFalse(v["valid"])
        self.assertEqual(v["reason"], "cancelled")


if __name__ == "__main__":
    unittest.main()
