#!/usr/bin/env python3
"""Клапан и выбор канала в почтовом релее.

Запуск: python3 -m unittest discover -s pocketbase/mail_relay -p 'test_*.py'

Зачем клапан (14.08.2026): за сутки прилетело 3580 запросов «забыл пароль» —
во время аварии люди жали кнопку без остановки. Релей отправил 458 писем,
выжег суточную квоту Gmail (500 на аккаунт), и почта поддержки перестала
уходить: владелец не мог отвечать людям из собственного ящика.

Зачем два канала: письма робота ушли на Resend, а ящик Gmail остался живым
людям. Gmail держим запасным — если Resend упрётся в свой суточный потолок,
письмо всё равно доедет.
"""
import json
import os
import tempfile
import unittest

from gmail_relay import Channel, Dedup, State, deliver, resend_headers, resend_payload

HOUR = 3600


class DedupTest(unittest.TestCase):
    def test_первое_письмо_не_видели(self):
        d = Dedup(window=1800)
        self.assertFalse(d.seen("a@example.com", "Сброс пароля", now=1000))

    def test_повтор_в_окне_ловится(self):
        d = Dedup(window=1800)
        d.note("a@example.com", "Сброс пароля", now=1000)
        self.assertTrue(d.seen("a@example.com", "Сброс пароля", now=1060))

    def test_после_окна_снова_можно(self):
        d = Dedup(window=1800)
        d.note("a@example.com", "Сброс пароля", now=1000)
        self.assertFalse(d.seen("a@example.com", "Сброс пароля", now=1000 + 1801))

    def test_другой_адрес_и_другая_тема_не_задеты(self):
        d = Dedup(window=1800)
        d.note("a@example.com", "Сброс пароля", now=1000)
        self.assertFalse(d.seen("b@example.com", "Сброс пароля", now=1060))
        self.assertFalse(d.seen("a@example.com", "Подтверждение почты", now=1060))

    def test_регистр_и_пробелы_не_обманывают(self):
        d = Dedup(window=1800)
        d.note("A@Example.com ", "Сброс пароля", now=1000)
        self.assertTrue(d.seen("a@example.com", " сброс пароля", now=1060))


class ChannelTest(unittest.TestCase):
    def test_свежий_канал_готов(self):
        c = Channel("resend", daily_budget=2, cooldown=900)
        self.assertEqual(c.ready(now=1000), (True, ""))

    def test_бюджет_кончается(self):
        c = Channel("resend", daily_budget=2, cooldown=900)
        c.note_sent(now=1000)
        c.note_sent(now=1001)
        self.assertEqual(c.ready(now=1002), (False, "budget"))

    def test_бюджет_освобождается_через_сутки(self):
        c = Channel("resend", daily_budget=1, cooldown=900)
        c.note_sent(now=1000)
        self.assertEqual(c.ready(now=1000 + 24 * HOUR + 1), (True, ""))

    def test_после_отказа_по_квоте_пауза(self):
        c = Channel("resend", daily_budget=10, cooldown=900)
        c.note_quota_error(now=5000)
        self.assertEqual(c.ready(now=5300), (False, "cooldown"))
        self.assertEqual(c.ready(now=5901), (True, ""))

    def test_остаток_бюджета_виден(self):
        c = Channel("gmail", daily_budget=250, cooldown=900)
        c.note_sent(now=1000)
        self.assertEqual(c.remaining(now=1000), 249)


class ResendPayloadTest(unittest.TestCase):
    def test_ответ_ведёт_в_ящик_поддержки(self):
        p = resend_payload(["a@example.com"], "Сброс пароля", "<b>x</b>", "x")
        self.assertIn("@", p["reply_to"])
        self.assertEqual(p["to"], ["a@example.com"])
        self.assertEqual(p["html"], "<b>x</b>")

    def test_свой_user_agent_обязателен(self):
        """Без него Cloudflare перед Resend отвечает 403 «error code: 1010»."""
        h = resend_headers("re_test")
        self.assertTrue(h["User-Agent"])
        self.assertNotIn("urllib", h["User-Agent"].lower())
        self.assertEqual(h["Authorization"], "Bearer re_test")

    def test_письмо_без_html_не_несёт_пустое_поле(self):
        p = resend_payload(["a@example.com"], "Тема", "", "текст")
        self.assertNotIn("html", p)
        self.assertEqual(p["text"], "текст")


class DeliverTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "state.json")
        self.calls = []

    def make(self, resend_budget=100, gmail_budget=250):
        state = State(self.path)
        dedup = Dedup(window=1800, state=state)
        channels = [
            Channel("resend", daily_budget=resend_budget, cooldown=900, state=state),
            Channel("gmail", daily_budget=gmail_budget, cooldown=900, state=state),
        ]
        return dedup, channels

    def senders(self, resend=None, gmail=None):
        def make(name, behaviour):
            def send(to, subject, html, text):
                self.calls.append(name)
                if callable(behaviour):
                    return behaviour()
                return behaviour
            return send
        return {
            "resend": make("resend", resend if resend is not None else "id-resend"),
            "gmail": make("gmail", gmail if gmail is not None else "id-gmail"),
        }

    def test_основной_канал_шлёт_запасной_молчит(self):
        dedup, channels = self.make()
        code, body = deliver(["a@example.com"], "Сброс пароля", "", "текст",
                             now=1000, senders=self.senders(),
                             channels=channels, dedup=dedup)
        self.assertEqual(code, 200)
        self.assertEqual(body["channel"], "resend")
        self.assertEqual(self.calls, ["resend"])

    def test_повтор_отбивается_до_каналов(self):
        dedup, channels = self.make()
        deliver(["a@example.com"], "Сброс пароля", "", "т", now=1000,
                senders=self.senders(), channels=channels, dedup=dedup)
        self.calls.clear()
        code, body = deliver(["a@example.com"], "Сброс пароля", "", "т", now=1060,
                             senders=self.senders(), channels=channels, dedup=dedup)
        self.assertEqual(code, 429)
        self.assertEqual(body["skipped"], "dedup")
        self.assertEqual(self.calls, [])

    def test_кончился_бюджет_основного_шлёт_запасной(self):
        dedup, channels = self.make(resend_budget=1)
        deliver(["a@example.com"], "Тема", "", "т", now=1000,
                senders=self.senders(), channels=channels, dedup=dedup)
        self.calls.clear()
        code, body = deliver(["b@example.com"], "Тема", "", "т", now=1001,
                             senders=self.senders(), channels=channels, dedup=dedup)
        self.assertEqual(code, 200)
        self.assertEqual(body["channel"], "gmail")
        self.assertEqual(self.calls, ["gmail"])

    def test_основной_упал_по_квоте_письмо_уходит_запасным(self):
        dedup, channels = self.make()

        def boom():
            raise RuntimeError("quota exceeded")

        code, body = deliver(["a@example.com"], "Тема", "", "т", now=1000,
                             senders=self.senders(resend=boom),
                             channels=channels, dedup=dedup)
        self.assertEqual(code, 200)
        self.assertEqual(body["channel"], "gmail")
        self.assertEqual(self.calls, ["resend", "gmail"])
        # Упавший канал ушёл в паузу и в следующий раз не пробуется.
        self.calls.clear()
        deliver(["b@example.com"], "Тема", "", "т", now=1100,
                senders=self.senders(), channels=channels, dedup=dedup)
        self.assertEqual(self.calls, ["gmail"])

    def test_оба_канала_молчат(self):
        dedup, channels = self.make(resend_budget=0, gmail_budget=0)
        code, body = deliver(["a@example.com"], "Тема", "", "т", now=1000,
                             senders=self.senders(), channels=channels, dedup=dedup)
        self.assertEqual(code, 429)
        self.assertEqual(body["skipped"], "budget")
        self.assertEqual(self.calls, [])

    def test_неудача_обоих_каналов_отдаёт_ошибку(self):
        dedup, channels = self.make()

        def boom():
            raise RuntimeError("сеть отвалилась")

        code, body = deliver(["a@example.com"], "Тема", "", "т", now=1000,
                             senders=self.senders(resend=boom, gmail=boom),
                             channels=channels, dedup=dedup)
        self.assertEqual(code, 502)
        self.assertEqual(self.calls, ["resend", "gmail"])

    def test_неудачное_письмо_можно_повторить_сразу(self):
        """Дедуп отмечаем только на успехе, иначе сбой съест попытку человека."""
        dedup, channels = self.make()

        def boom():
            raise RuntimeError("сеть отвалилась")

        deliver(["a@example.com"], "Тема", "", "т", now=1000,
                senders=self.senders(resend=boom, gmail=boom),
                channels=channels, dedup=dedup)
        self.calls.clear()
        code, _ = deliver(["a@example.com"], "Тема", "", "т", now=1010,
                          senders=self.senders(), channels=channels, dedup=dedup)
        self.assertEqual(code, 200)

    def test_состояние_переживает_перезапуск(self):
        dedup, channels = self.make()
        deliver(["a@example.com"], "Тема", "", "т", now=1000,
                senders=self.senders(), channels=channels, dedup=dedup)
        dedup2, channels2 = self.make()
        code, body = deliver(["a@example.com"], "Тема", "", "т", now=1060,
                             senders=self.senders(), channels=channels2, dedup=dedup2)
        self.assertEqual(code, 429)
        self.assertEqual(body["skipped"], "dedup")
        self.assertEqual(channels2[0].remaining(now=1060), 99)

    def test_в_файле_состояния_нет_открытых_адресов(self):
        dedup, channels = self.make()
        deliver(["secret.person@example.com"], "Сброс пароля", "", "т", now=1000,
                senders=self.senders(), channels=channels, dedup=dedup)
        with open(self.path, encoding="utf-8") as f:
            raw = f.read()
        self.assertNotIn("secret.person", raw)
        self.assertIn("channels", json.loads(raw))


if __name__ == "__main__":
    unittest.main()
