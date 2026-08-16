#!/usr/bin/env python3
"""Импульс «Скучаю» обязан приходить уведомлением.

Жалоба 16.08.2026 со снимком шторки: уведомления из чата приходят, а «Скучаю»
нет. Причина в переезде: коллекция `miss_you` ушла в hotpath 14 августа, а пуш
по ней слал хук PocketBase (`push_apns.pb.js`, обработчик на update записи).
Хуки для переехавших коллекций больше не срабатывают вовсе — и уведомление
тихо пропало, при том что realtime-обновление счётчика осталось на месте.
Отсюда и картина «сердечко прилетело, а телефон молчит».

Здесь проверяется текст пуша: он повторяет прежний хук слово в слово, иначе
люди заметят подмену.

Запуск: python3 pocketbase/hotpath/test_miss_you_push.py
"""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "hotpath_src", Path(__file__).parent / "hotpath.py")
источник = spec.loader.get_source("hotpath_src")

пространство: dict = {}
начало = источник.index("def _miss_you_push_text(")
конец = источник.index("\ndef ", начало + 10)
exec(compile(источник[начало:конец], "hotpath.py", "exec"), пространство)
_miss_you_push_text = пространство["_miss_you_push_text"]


class ТекстПуша(unittest.TestCase):
    def test_своё_пожелание_идёт_как_есть(self):
        self.assertEqual(_miss_you_push_text("Приходи скорее"), "Приходи скорее")

    def test_без_пожелания_прежняя_строка(self):
        self.assertEqual(_miss_you_push_text(""), "Обними в ответ")
        self.assertEqual(_miss_you_push_text(None), "Обними в ответ")

    def test_пробелы_не_считаются_текстом(self):
        self.assertEqual(_miss_you_push_text("   "), "Обними в ответ")

    def test_длинное_пожелание_режется(self):
        длинное = "я" * 300
        итог = _miss_you_push_text(длинное)
        self.assertLessEqual(len(итог), 120)
        self.assertTrue(итог.endswith("…"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
