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

    def test_обложка_только_данными(self):
        # Новая сборка рисует уведомление сама (`FcmService` → `NotifCover`):
        # с готовым `notification` система нарисовала бы его за неё.
        cover = {"v": 1, "kind": "miss", "title": "Скучает по тебе"}
        msg = fcm_relay.build_message({"title": "Алина", "body": "Хочу обнять", "tag": "miss",
                                       "data": {"kind": "miss"}, "cover": cover,
                                       "data_only": True}, "tok")
        self.assertNotIn("notification", msg)
        self.assertEqual(msg["android"], {"priority": "high"})
        self.assertEqual(json.loads(msg["data"]["cover"]), cover)
        self.assertEqual(msg["data"]["kind"], "miss")

    def test_большая_обложка_уходит_прежним_пушем(self):
        # FCM отбивает данные больше 4096 байт: новая сборка получит обычный
        # пуш системы, а не тишину.
        text = "Очень длинное сообщение партнёру " * 40
        msg = fcm_relay.build_message({"title": "Алина", "body": text, "tag": "chat",
                                       "data": {"kind": "chat"},
                                       "cover": {"v": 1, "kind": "chat", "body": text},
                                       "data_only": True}, "tok")
        self.assertIn("notification", msg)
        self.assertNotIn("cover", msg["data"])

    def test_обложка_старой_сборке_не_мешает(self):
        msg = fcm_relay.build_message({"title": "Алина", "body": "Привет", "tag": "chat",
                                       "cover": {"v": 1}}, "tok")
        self.assertIn("notification", msg)
        self.assertNotIn("cover", msg["data"])

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


class Outbox(unittest.TestCase):
    """TOG-90: подарок стоял в общей очереди за тихими пушами виджетов."""

    def test_пуш_с_баннером_уходит_раньше_тихих(self):
        box = fcm_relay.Outbox(bulk_max=100, urgent_max=100)
        for i in range(5):
            box.put({"n": "тихий %d" % i}, urgent=False)
        box.put({"n": "подарок"}, urgent=True)
        job, urgent = box.get()
        self.assertEqual(job["n"], "подарок")
        self.assertTrue(urgent)
        self.assertEqual(box.get()[0]["n"], "тихий 0")

    def test_полные_тихие_не_вытесняют_баннер(self):
        box = fcm_relay.Outbox(bulk_max=2, urgent_max=2)
        self.assertTrue(box.put({}, urgent=False))
        self.assertTrue(box.put({}, urgent=False))
        self.assertFalse(box.put({}, urgent=False))
        self.assertTrue(box.put({}, urgent=True))
        self.assertEqual(box.sizes(), {"urgent": 1, "bulk": 2})

    def test_тихий_пуш_не_срочный(self):
        self.assertFalse(fcm_relay.is_urgent({"silent": True}))
        self.assertTrue(fcm_relay.is_urgent({"title": "Аня", "body": "подарок"}))


class FakeConn:
    """Соединение, которое падает заданное число раз, потом отвечает 200."""

    made = []

    def __init__(self, host, timeout):
        self.fails = FakeConn.fail_next.pop(0) if FakeConn.fail_next else 0
        self.closed = False
        FakeConn.made.append(self)

    def request(self, method, path, body, headers):
        if self.fails:
            self.fails -= 1
            raise ConnectionResetError("Google закрыл соединение")

    def getresponse(self):
        class R:
            status = 200

            def read(self):
                return b"{}"
        return R()

    def close(self):
        self.closed = True


class KeepAlive(unittest.TestCase):
    def setUp(self):
        self._real = fcm_relay.http.client.HTTPSConnection
        fcm_relay.http.client.HTTPSConnection = FakeConn
        FakeConn.made = []
        FakeConn.fail_next = []
        fcm_relay._local.conn = None

    def tearDown(self):
        fcm_relay.http.client.HTTPSConnection = self._real
        fcm_relay._local.conn = None

    def test_соединение_живёт_между_пушами(self):
        fcm_relay._post("/x", b"{}", {})
        fcm_relay._post("/x", b"{}", {})
        self.assertEqual(len(FakeConn.made), 1)

    def test_закрытое_гуглом_соединение_открывается_заново(self):
        fcm_relay._post("/x", b"{}", {})
        fcm_relay._local.conn.fails = 1
        code, _ = fcm_relay._post("/x", b"{}", {})
        self.assertEqual(code, 200)
        self.assertEqual(len(FakeConn.made), 2)

    def test_свежее_соединение_не_повторяем(self):
        # Ошибка на свежем соединении настоящая: повтор мог бы задвоить пуш.
        FakeConn.fail_next = [1]
        with self.assertRaises(ConnectionResetError):
            fcm_relay._post("/x", b"{}", {})
        self.assertEqual(len(FakeConn.made), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
