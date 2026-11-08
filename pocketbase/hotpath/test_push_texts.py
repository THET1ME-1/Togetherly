#!/usr/bin/env python3
"""Уведомления на языке получателя (отзыв в App Store 19.08.2026: «The
notification and widgets are in Russian though the app I have set to
English»).

Запуск: python3 pocketbase/hotpath/test_push_texts.py
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from push_texts import ТЕКСТЫ, ЯЗЫКИ, пуш  # noqa: E402

источник = (Path(__file__).parent / "hotpath.py").read_text(encoding="utf-8")


class ТекстыПушей(unittest.TestCase):
    def test_каждый_текст_есть_на_всех_языках(self):
        for ключ, варианты in ТЕКСТЫ.items():
            for код in ЯЗЫКИ:
                self.assertTrue(варианты.get(код), f"{ключ}: нет {код}")

    def test_подстановки_одни_и_те_же_во_всех_языках(self):
        for ключ, варианты in ТЕКСТЫ.items():
            метки = {м for м in ("{label}", "{text}") if м in варианты["ru"]}
            for код, текст in варианты.items():
                for м in метки:
                    self.assertIn(м, текст, f"{ключ}/{код}")

    def test_язык_получателя(self):
        self.assertEqual(пуш("miss_hug", "en"), "Hug back")
        self.assertEqual(пуш("mood_today", "uk", label="😊"), "Сьогодні: 😊")

    def test_старая_сборка_без_языка_получает_русский(self):
        self.assertEqual(пуш("miss_hug", ""), "Обними в ответ")
        self.assertEqual(пуш("miss_hug", None), "Обними в ответ")
        self.assertEqual(пуш("miss_hug", "ja"), "Обними в ответ")

    def test_в_hotpath_не_осталось_русских_текстов_пушей(self):
        for старое in ('"Обними в ответ"', '"Голосовое сообщение"', '"Сообщение"',
                       '"Добавил воспоминание"', '"Настроение партнёра"',
                       '"Скучает по тебе"', '"Партнёр отметил настроение"'):
            self.assertNotIn(старое, источник, старое)


if __name__ == "__main__":
    unittest.main(verbosity=2)
