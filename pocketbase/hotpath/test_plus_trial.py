#!/usr/bin/env python3
"""Пробный Плюс из сундука тоже Плюс для карточки партнёра.

Сундук выдаёт Плюс на 7 дней полем `users.plus_trial_until`, а `plus` не
трогает. Метку `plus` в карточке виджета ставил `_user_has_plus` только по
`plus`, поэтому у партнёра того, кто выбил пробный Плюс, на плитке совместной
ленты висел замок вместо входа (обращение 558, 02.11.2026).

Запуск: python3 pocketbase/hotpath/test_plus_trial.py
"""
import sqlite3
import unittest
from pathlib import Path

источник = (Path(__file__).parent / "hotpath.py").read_text(encoding="utf-8")
начало = источник.index("def _user_has_plus(")
конец = источник.index("\n\n\n", начало)

СЕЙЧАС = 1_800_000_000_000


def проверка(plus, trial_until):
    lite = sqlite3.connect(":memory:")
    lite.execute("CREATE TABLE users (id TEXT, plus BOOLEAN, plus_trial_until NUMERIC)")
    lite.execute("INSERT INTO users VALUES ('u1', ?, ?)", (plus, trial_until))
    среда = {"lite": lite, "sqlite3": sqlite3, "_now_ms": lambda: СЕЙЧАС}
    exec(источник[начало:конец], среда)
    return среда["_user_has_plus"]("u1")


class ПробныйПлюс(unittest.TestCase):
    def test_купленный_плюс(self):
        self.assertTrue(проверка(1, 0))

    def test_живой_пробный_плюс(self):
        self.assertTrue(проверка(0, СЕЙЧАС + 60_000))

    def test_истёкший_пробный_плюс(self):
        self.assertFalse(проверка(0, СЕЙЧАС - 60_000))

    def test_без_плюса(self):
        self.assertFalse(проверка(0, 0))


if __name__ == "__main__":
    unittest.main()
