#!/usr/bin/env python3
"""Сгоревшую серию можно вернуть за рекламный ролик.

Просьба из чата 25.09.2026: «А есть восстановление серии как в ТикТоке?».
Решение владельца: возвращать за ролик сколько угодно раз, «даже если через
день». Возврат живёт в пределах трёх дней после обрыва — иначе «серия»
перестаёт значить «мы оба тут».

Серия обрывается двумя способами, и оба надо уметь вернуть:
- пара ещё не вернулась — последний общий день позавчера или раньше, на
  экране 0, а в базе прежнее число;
- пара уже вернулась, и зачёт дня сбросил серию в единицу — тогда прежнее
  число помнит запись маскота (`lost`, `lost_d`, `lost_g`).

Тест гоняет настоящие `_record_activity_pg` и `_restore_streak_pg` на
поддельном соединении Postgres, как test_streak_stale_pending.py.

Запуск: python3 pocketbase/hotpath/test_streak_restore.py
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
        if sql.startswith("UPDATE groups SET mascot_streaks = $1, streak_days = $2"):
            карта, серия, день, _upd, _gid = args
            self.строка.update(mascot_streaks=карта, streak_days=серия,
                               streak_last_opened_date=день)
        elif "streak_days = $1" in sql:
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


A, B = "uid_a", "uid_b"


def пара(серия, последний, карта=None):
    return {
        "members": json.dumps([A, B]), "streak_days": float(серия),
        "streak_last_opened_date": последний, "streak_pending_date": "",
        "streak_pending_uid": "", "active_mascot_id": "feya",
        "mascot_streaks": json.dumps(карта or {"feya": {"s": серия, "d": последний}}),
    }


class Пара:
    """Пара на поддельной базе: отметки дней и возврат серии."""

    def __init__(self, строка):
        пространство = {
            "time": time, "json": json, "asyncio": asyncio,
            "ORJSONResponse": Ответ, "now_pb": lambda: "2026-09-25 00:00:00.000Z",
        }
        exec(compile(источник[начало:конец], "hotpath.py", "exec"), пространство)
        пространство["_record_streak_sqlite"] = lambda *a: None
        self.conn = Соединение(строка)
        пространство["pg"] = Пул(self.conn)
        self.отметка = пространство["_record_activity_pg"]
        self.возврат = пространство["_restore_streak_pg"]

    def оба(self, день):
        asyncio.run(self.отметка("g", A, A, день))
        asyncio.run(self.отметка("g", B, B, день))

    def вернуть(self, день, кто=A):
        ответ = asyncio.run(self.возврат("g", кто, день))
        return ответ.status_code, ответ.content

    @property
    def маскот(self):
        карта = self.conn.строка["mascot_streaks"]
        карта = json.loads(карта) if isinstance(карта, str) else карта
        return карта["feya"]

    @property
    def серия(self):
        return int(self.conn.строка["streak_days"])


class СбросПомнитСерию(unittest.TestCase):
    def test_сброс_кладёт_прежнюю_серию_в_маскота(self):
        п = Пара(пара(12, "2026-09-20"))
        п.оба("2026-09-23")  # 21-го и 22-го не было
        self.assertEqual(п.маскот["s"], 1)
        self.assertEqual(п.маскот["lost"], 12)
        self.assertEqual(п.маскот["lost_g"], 12)
        self.assertEqual(п.маскот["lost_d"], "2026-09-23")

    def test_серия_из_одного_дня_не_считается_потерей(self):
        п = Пара(пара(1, "2026-09-20"))
        п.оба("2026-09-23")
        self.assertNotIn("lost", п.маскот)

    def test_память_переживает_следующий_общий_день(self):
        п = Пара(пара(12, "2026-09-20"))
        п.оба("2026-09-23")
        п.оба("2026-09-24")
        self.assertEqual(п.маскот["s"], 2)
        self.assertEqual(п.маскот["lost"], 12)


class ВозвратПослеСброса(unittest.TestCase):
    def test_ролик_складывает_прежнюю_серию_с_новой(self):
        п = Пара(пара(12, "2026-09-20"))
        п.оба("2026-09-23")
        код, ответ = п.вернуть("2026-09-23")
        self.assertEqual(код, 200, ответ)
        self.assertEqual(п.маскот["s"], 13)
        self.assertEqual(п.серия, 13)
        self.assertNotIn("lost", п.маскот)

    def test_через_день_после_сброса_тоже_можно(self):
        п = Пара(пара(12, "2026-09-20"))
        п.оба("2026-09-23")
        п.оба("2026-09-24")
        код, _ = п.вернуть("2026-09-24")
        self.assertEqual(код, 200)
        self.assertEqual(п.маскот["s"], 14)
        self.assertEqual(п.серия, 14)

    def test_второй_раз_ту_же_серию_не_вернуть(self):
        п = Пара(пара(12, "2026-09-20"))
        п.оба("2026-09-23")
        п.вернуть("2026-09-23")
        код, _ = п.вернуть("2026-09-23")
        self.assertEqual(код, 409)
        self.assertEqual(п.маскот["s"], 13)

    def test_после_трёх_дней_возврата_нет(self):
        п = Пара(пара(12, "2026-09-20"))
        п.оба("2026-09-23")
        код, _ = п.вернуть("2026-09-27")
        self.assertEqual(код, 409)


class ВозвратДоСброса(unittest.TestCase):
    def test_пропущенный_вчерашний_день_закрывается(self):
        # Последний общий день 20-го, 21-го никого, сегодня 22-е: на экране 0.
        п = Пара(пара(12, "2026-09-20"))
        код, _ = п.вернуть("2026-09-22")
        self.assertEqual(код, 200)
        self.assertEqual(п.маскот["d"], "2026-09-21")
        self.assertEqual(п.маскот["s"], 12)
        # Сегодня оба пришли — серия идёт дальше, а не с единицы.
        п.оба("2026-09-22")
        self.assertEqual(п.маскот["s"], 13)
        self.assertEqual(п.серия, 13)

    def test_живую_серию_возвращать_нечего(self):
        п = Пара(пара(12, "2026-09-21"))
        код, _ = п.вернуть("2026-09-22")
        self.assertEqual(код, 409)
        self.assertEqual(п.маскот["d"], "2026-09-21")

    def test_после_долгого_перерыва_возврата_нет(self):
        п = Пара(пара(12, "2026-09-10"))
        код, _ = п.вернуть("2026-09-22")
        self.assertEqual(код, 409)

    def test_чужой_серию_не_вернёт(self):
        п = Пара(пара(12, "2026-09-20"))
        код, _ = п.вернуть("2026-09-22", кто="чужой")
        self.assertEqual(код, 403)
        self.assertEqual(п.маскот["d"], "2026-09-20")


if __name__ == "__main__":
    unittest.main(verbosity=2)
