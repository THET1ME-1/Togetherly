#!/usr/bin/env python3
"""Проверки релея FCM: тело запроса и разбор отказов.

Запуск: python3 pocketbase/fcm/test_fcm_relay.py
Ключ и сеть не нужны — проверяем чистые функции.
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fcm_relay  # noqa: E402


class BuildMessage(unittest.TestCase):
    def test_обычный_пуш_несёт_заголовок_и_канал(self):
        m = fcm_relay.build_message(
            {"title": "Аня", "body": "Написала сообщение"}, "TOKEN")

        self.assertEqual(m["token"], "TOKEN")
        self.assertEqual(m["notification"]["title"], "Аня")
        self.assertEqual(
            m["android"]["notification"]["channel_id"], "partner_notifications")
        self.assertEqual(m["android"]["priority"], "high")

    def test_значения_data_приводятся_к_строкам(self):
        # Число в data FCM отбивает как INVALID_ARGUMENT, и пуш не уходит.
        m = fcm_relay.build_message(
            {"title": "т", "data": {"kind": "chat", "count": 3, "ok": True}}, "T")

        self.assertEqual(m["data"]["kind"], "chat")
        self.assertEqual(m["data"]["count"], "3")
        self.assertEqual(m["data"]["ok"], "true")

    def test_тихий_пуш_без_баннера(self):
        m = fcm_relay.build_message({"silent": True, "data": {"kind": "widget"}}, "T")

        self.assertNotIn("notification", m)
        self.assertEqual(m["data"]["kind"], "widget")
        self.assertEqual(m["android"]["priority"], "high")

    def test_метка_схлопывает_уведомления_одной_пары(self):
        m = fcm_relay.build_message({"title": "т", "tag": "pair42"}, "T")
        self.assertEqual(m["android"]["notification"]["tag"], "pair42")

    def test_без_заголовка_подписываемся_приложением(self):
        m = fcm_relay.build_message({}, "T")
        self.assertEqual(m["notification"]["title"], "Togetherly")


class ErrorCode(unittest.TestCase):
    def test_мёртвый_токен_виден_по_details(self):
        raw = json.dumps({"error": {
            "code": 404, "status": "NOT_FOUND", "message": "Requested entity was not found.",
            "details": [{
                "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
                "errorCode": "UNREGISTERED",
            }],
        }})

        reason = fcm_relay.error_code(raw)
        self.assertEqual(reason, "UNREGISTERED")
        self.assertTrue(fcm_relay.token_is_gone(reason))

    def test_без_details_берём_статус(self):
        raw = json.dumps({"error": {"code": 401, "status": "UNAUTHENTICATED"}})
        self.assertEqual(fcm_relay.error_code(raw), "UNAUTHENTICATED")

    def test_чужой_отказ_не_считается_мёртвым_токеном(self):
        # Своя авария не повод выкидывать живой токен из профиля.
        self.assertFalse(fcm_relay.token_is_gone("UNAUTHENTICATED"))
        self.assertFalse(fcm_relay.token_is_gone("UNAVAILABLE"))
        self.assertFalse(fcm_relay.token_is_gone("INTERNAL"))

    def test_не_json_не_роняет_разбор(self):
        self.assertEqual(fcm_relay.error_code("<html>502</html>"), "<html>502</html>")


if __name__ == "__main__":
    unittest.main(verbosity=2)
