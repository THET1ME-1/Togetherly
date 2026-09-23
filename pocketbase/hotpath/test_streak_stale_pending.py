#!/usr/bin/env python3
"""Устаревшее ожидание не обнуляет серию.

До фикса 20.09.2026 hotpath не очищал `streak_pending_date`/`streak_pending_uid`
после зачёта дня, и у тысяч пар осталось ожидание с датой уже закрытого дня.
Новое правило «днём серии считается дата первого отметившегося»
(`начало = min(today, ждёт_дату)`) принимало такое ожидание за соседний день:
зачёт следующего дня записывался датой закрытого, `_день_подряд` давал ложь, и
серия падала в единицу. За ночи на 21 и 22 сентября так сбросились около
1100 пар (жалоба #181: «вчера было 12 дней, сегодня 2»).

Тест гоняет настоящий `_record_activity_pg` на поддельном соединении Postgres.

Запуск: python3 pocketbase/hotpath/test_streak_stale_pending.py
"""
import asyncio
import json
import time
import unittest
from pathlib import Path

источник = (Path(__file__).parent / "hotpath.py").read_text(encoding="utf-8")
начало = источник.index("def _общий_день(")
конец = источник.index("\nКАРТЫ_УЧАСТНИКОВ", начало)


class Ответ:
    def __init__(self, content, status_code=200):
        self.content = content
        self.status_code = status_code


class Соединение:
    """Одна строка пары; UPDATE разбирается по набору колонок."""

    def __init__(self, строка):
        self.строка = строка

    def transaction(self):
        return _Пустой()

    async def fetchrow(self, sql, *args):
        return dict(self.строка)

    async def execute(self, sql, *args):
        if "streak_days = $1" in sql:
            серия, день, карта, _upd, _gid = args
            self.строка.update(streak_days=серия, streak_last_opened_date=день,
                               streak_pending_date="", streak_pending_uid="",
                               mascot_streaks=карта)
        elif "streak_pending_date = $1" in sql:
            день, uid, _upd, _gid = args
            self.строка.update(streak_pending_date=день, streak_pending_uid=uid)
        else:
            raise AssertionError(f"неожиданный запрос: {sql}")


class _Пустой:
    async def __aenter__(self):
        return None

    async def __aexit__(self, *exc):
        return False


class Пул:
    def __init__(self, conn):
        self.conn = conn

    def acquire(self):
        conn = self.conn

        class _Ctx:
            async def __aenter__(self):
                return conn

            async def __aexit__(self, *exc):
                return False
        return _Ctx()


def собрать(строка):
    пространство = {
        "time": time, "json": json, "asyncio": asyncio,
        "ORJSONResponse": Ответ, "now_pb": lambda: "2026-09-23 00:00:00.000Z",
    }
    exec(compile(источник[начало:конец], "hotpath.py", "exec"), пространство)
    пространство["_record_streak_sqlite"] = lambda *a: None
    conn = Соединение(строка)
    пространство["pg"] = Пул(conn)
    return пространство["_record_activity_pg"], conn


A, B = "uid_a", "uid_b"


def пара(серия, последний, ждёт_дату="", ждёт_кого=""):
    return {
        "members": json.dumps([A, B]), "streak_days": float(серия),
        "streak_last_opened_date": последний, "streak_pending_date": ждёт_дату,
        "streak_pending_uid": ждёт_кого, "active_mascot_id": "feya",
        "mascot_streaks": json.dumps({"feya": {"s": серия, "d": последний}}),
    }


def прогнать(строка, шаги):
    отметка, conn = собрать(строка)
    for uid, день in шаги:
        asyncio.run(отметка("g", uid, uid, день))
    s = conn.строка
    карта = s["mascot_streaks"]
    карта = json.loads(карта) if isinstance(карта, str) else карта
    return int(s["streak_days"]), s["streak_last_opened_date"], карта["feya"]["s"]


class УстаревшееОжидание(unittest.TestCase):
    def test_ожидание_закрытого_дня_второй_отмечается_первым(self):
        # Жалоба #181: 20-е закрыто (серия 12), ожидание осталось с датой 20-го
        # от неё. 21-го первым заходит он — это ещё не общий день.
        итог = прогнать(пара(12, "2026-09-20", "2026-09-20", A),
                        [(B, "2026-09-21"), (A, "2026-09-21")])
        self.assertEqual(итог, (13, "2026-09-21", 13))

    def test_ожидание_закрытого_дня_тот_же_человек_первым(self):
        итог = прогнать(пара(12, "2026-09-20", "2026-09-20", A),
                        [(A, "2026-09-21"), (B, "2026-09-21")])
        self.assertEqual(итог, (13, "2026-09-21", 13))

    def test_ожидание_раньше_закрытого_дня(self):
        # Старый полуночный зачёт: он отметил 19-е, она закрыла датой 20-го.
        итог = прогнать(пара(7, "2026-09-20", "2026-09-19", A),
                        [(B, "2026-09-21"), (A, "2026-09-21")])
        self.assertEqual(итог, (8, "2026-09-21", 8))


class ЖивоеОжиданиеНеТрогаем(unittest.TestCase):
    def test_через_полночь(self):
        итог = прогнать(пара(5, "2026-09-18", "2026-09-19", A),
                        [(B, "2026-09-20")])
        self.assertEqual(итог, (6, "2026-09-19", 6))

    def test_обычный_день(self):
        итог = прогнать(пара(5, "2026-09-18"),
                        [(A, "2026-09-19"), (B, "2026-09-19")])
        self.assertEqual(итог, (6, "2026-09-19", 6))

    def test_настоящий_пропуск(self):
        итог = прогнать(пара(5, "2026-09-18"),
                        [(A, "2026-09-20"), (B, "2026-09-20")])
        self.assertEqual(итог, (1, "2026-09-20", 1))

    def test_три_ночи_подряд(self):
        итог = прогнать(пара(5, "2026-09-15"),
                        [(A, "2026-09-16"), (B, "2026-09-17"),
                         (A, "2026-09-17"), (B, "2026-09-18"),
                         (A, "2026-09-18"), (B, "2026-09-19")])
        self.assertEqual(итог, (8, "2026-09-18", 8))


if __name__ == "__main__":
    unittest.main(verbosity=2)
