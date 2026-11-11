#!/usr/bin/env python3
"""Догоняющий тихий пуш «обнови виджеты» (TOG-90, 11.11.2026).

Тихий пуш уходит не чаще раза в 15 минут на телефон. Правку партнёра,
пришедшую раньше, сервер молча выбрасывал: человек сменил статус в 12:00 и
ещё раз в 12:05, а виджет у второго так и стоял со статусом из 12:00, пока
не случится третья правка. На Android это прикрывала задача раз в 15 минут,
на iPhone не прикрывало ничто. Теперь выброшенная правка ставит один
отложенный пуш на конец окна.

Запуск: python3 pocketbase/hotpath/test_wake_catch_up.py
"""
import asyncio
import importlib.util
import logging
import random
import sqlite3
import time
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("hotpath_src", Path(__file__).parent / "hotpath.py")
source = spec.loader.get_source("hotpath_src")
block_start = source.index("MIN_WAKE_GAP_MS = ")
block_end = source.index("\ndef _второй_из_канала(")


class FakeAnswer:
    def json(self):
        return {"ok": True}


class FakePushClient:
    def __init__(self):
        self.sent = []

    async def post(self, url, json):
        self.sent.append(json["token"])
        return FakeAnswer()


def load_block(gap_ms: int):
    """Кусок hotpath с тихими пушами и подставными соседями."""
    people = {}
    client = FakePushClient()

    async def push_targets(group_id, author_uid, thread=""):
        return [dict(person) for uid, person in people.items() if uid != author_uid]

    def mark_woke(uid, now_ms):
        people[uid]["bg_ms"] = now_ms

    namespace = {
        "asyncio": asyncio, "time": time, "sqlite3": sqlite3, "random": random,
        "log": logging.getLogger("test"), "push_client": client,
        "APNS_RELAY": "apns", "FCM_RELAY": "fcm",
        "_forget_token": lambda uid, field: None,
        "_push_targets": push_targets,
    }
    exec(compile(source[block_start:block_end], "hotpath.py", "exec"), namespace)
    namespace["MIN_WAKE_GAP_MS"] = gap_ms
    namespace["CATCH_UP_SLACK_SECONDS"] = (0.01, 0.02)
    namespace["_mark_woke"] = mark_woke
    return namespace, people, client


def person(uid: str, woke_ms_ago: int | None) -> dict:
    now_ms = int(time.time() * 1000)
    return {"uid": uid, "apns": "", "sandbox": False, "fcm": "token-" + uid,
            "bg_ms": 0 if woke_ms_ago is None else now_ms - woke_ms_ago}


class CatchUp(unittest.IsolatedAsyncioTestCase):
    async def test_давно_не_будили_пуш_уходит_сразу(self):
        block, people, client = load_block(gap_ms=200)
        people["partner"] = person("partner", woke_ms_ago=None)

        await block["_wake_group"]("g", "author")

        self.assertEqual(client.sent, ["token-partner"])
        self.assertEqual(block["_pending_catch_up"], {})

    async def test_правка_внутри_окна_доезжает_в_его_конце(self):
        block, people, client = load_block(gap_ms=200)
        people["partner"] = person("partner", woke_ms_ago=50)

        await block["_wake_group"]("g", "author")
        self.assertEqual(client.sent, [], "пуш ушёл чаще, чем раз в окно")
        self.assertIn("partner", block["_pending_catch_up"], "выброшенная правка не поставила догоняющий пуш")

        await asyncio.sleep(0.4)
        self.assertEqual(client.sent, ["token-partner"], "догоняющий пуш не пришёл")
        self.assertEqual(block["_pending_catch_up"], {})

    async def test_сколько_бы_правок_ни_выбросили_догоняющий_один(self):
        block, people, client = load_block(gap_ms=200)
        people["partner"] = person("partner", woke_ms_ago=50)

        for _ in range(5):
            await block["_wake_group"]("g", "author")
        await asyncio.sleep(0.4)

        self.assertEqual(client.sent, ["token-partner"])

    # Второй рабочий процесс мог разбудить телефон раньше: тогда догоняющий
    # молчит и новый не ставит, иначе пуши пошли бы по кругу.
    async def test_догоняющий_не_ставит_себя_заново(self):
        block, people, client = load_block(gap_ms=200)
        people["partner"] = person("partner", woke_ms_ago=50)

        await block["_wake_group"]("g", "author")
        people["partner"]["bg_ms"] = int(time.time() * 1000) + 150
        await asyncio.sleep(0.4)

        self.assertEqual(client.sent, [])
        self.assertEqual(block["_pending_catch_up"], {}, "догоняющий пуш поставил сам себя ещё раз")

    async def test_точка_на_карте_тоже_догоняет(self):
        block, people, client = load_block(gap_ms=200)
        people["partner"] = person("partner", woke_ms_ago=50)
        block["_второй_из_канала"] = lambda channel, author: "partner"
        block["_push_candidates"] = lambda group_id, author_uid, members: [dict(people["partner"])]

        async def nobody_online(uids):
            return set()

        block["_online_uids"] = nobody_online
        wake_channel_start = source.index("async def _wake_channel(")
        wake_channel_end = source.index("\n\n\n", wake_channel_start)
        exec(compile(source[wake_channel_start:wake_channel_end], "hotpath.py", "exec"), block)

        await block["_wake_channel"]("pair_author_partner", "author")
        self.assertEqual(client.sent, [])
        await asyncio.sleep(0.4)

        self.assertEqual(client.sent, ["token-partner"])


class Delay(unittest.TestCase):
    def test_ждём_до_конца_окна(self):
        block, _, _ = load_block(gap_ms=15 * 60 * 1000)
        block["CATCH_UP_SLACK_SECONDS"] = (2.0, 2.0)
        delay = block["_catch_up_delay_seconds"](bg_ms=1_000_000, now_ms=1_000_000 + 5 * 60 * 1000)
        self.assertAlmostEqual(delay, 10 * 60 + 2.0)

    def test_окно_уже_прошло_ждём_только_запас(self):
        block, _, _ = load_block(gap_ms=15 * 60 * 1000)
        block["CATCH_UP_SLACK_SECONDS"] = (2.0, 2.0)
        delay = block["_catch_up_delay_seconds"](bg_ms=1_000_000, now_ms=1_000_000 + 60 * 60 * 1000)
        self.assertAlmostEqual(delay, 2.0)


if __name__ == "__main__":
    unittest.main()
