#!/usr/bin/env python3
"""История «Скучаю»: текст пуша об ответе и вид строки для приложения.

Запуск: python3 pocketbase/hotpath/test_miss_history.py
"""
import datetime
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("hotpath_src", Path(__file__).parent / "hotpath.py")
источник = spec.loader.get_source("hotpath_src")
пространство: dict = {}
начало = источник.index("_ИМПУЛЬС_ПОДПИСЬ = {")
конец = источник.index("\nasync def _miss_history(", начало)
exec(compile(источник[начало:конец], "hotpath.py", "exec"), пространство)
текст_ответа = пространство["_miss_reply_push_text"]
строка = пространство["_miss_event_json"]


class Ответ(unittest.TestCase):
    def test_на_стандартный_импульс(self):
        self.assertEqual(текст_ответа("want_hug", ""), "В ответ на «Хочу обнять»")

    def test_своё_пожелание_цитируется(self):
        self.assertEqual(текст_ответа("custom", "Слабак аххахах"), "В ответ на «Слабак аххахах»")

    def test_длинное_режется(self):
        self.assertTrue(текст_ответа("custom", "а" * 200).endswith("…»"))

    def test_незнакомый_вайб_как_скучаю(self):
        self.assertEqual(текст_ответа("что-то", None), "В ответ на «Я скучаю»")


class Строка(unittest.TestCase):
    def test_поля_для_приложения(self):
        t = datetime.datetime(2026, 9, 28, 9, 2, tzinfo=datetime.timezone.utc)
        r = строка({"id": "e1", "user_uid": "u", "vibe": "want_hug", "text": None,
                    "count": 3, "reply_to": None, "created": t})
        self.assertEqual(r, {"id": "e1", "uid": "u", "vibe": "want_hug", "text": "", "count": 3,
                             "replyTo": None, "at": int(t.timestamp() * 1000)})


if __name__ == "__main__":
    unittest.main()
