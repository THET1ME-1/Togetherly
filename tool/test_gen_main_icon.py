#!/usr/bin/env python3
"""Передний слой адаптивной иконки с рисунком целиком (--fit).

Лончер показывает из слоя 108dp только центральные 72dp. Хэллоуинский рисунок,
положенный на весь слой, выходил на телефоне увеличенным: глаза и поля шляпы,
без луны и метлы. Владелец, 19.10.2026: «нафига ты масштабируешь его? Верни
его нормальные размеры».

Запуск: python3 tool/test_gen_main_icon.py
"""
import os
import sys
import unittest

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_main_icon import fitted_layer  # noqa: E402


class РисунокЦеликом(unittest.TestCase):
    def setUp(self):
        self.picture = Image.new("RGB", (300, 300), (230, 80, 30))
        self.fill = (20, 16, 14, 255)
        self.layer = fitted_layer(self.picture, 108, self.fill)

    def test_слой_размером_с_полотно(self):
        self.assertEqual(self.layer.size, (108, 108))

    def test_рисунок_занимает_видимые_72dp(self):
        self.assertEqual(self.layer.getpixel((18, 18))[:3], (230, 80, 30))
        self.assertEqual(self.layer.getpixel((89, 89))[:3], (230, 80, 30))

    def test_поля_за_видимой_частью_залиты_фоном(self):
        self.assertEqual(self.layer.getpixel((17, 54)), self.fill)
        self.assertEqual(self.layer.getpixel((90, 54)), self.fill)
        self.assertEqual(self.layer.getpixel((54, 0)), self.fill)


if __name__ == "__main__":
    unittest.main(verbosity=2)
