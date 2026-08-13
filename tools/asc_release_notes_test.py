#!/usr/bin/env python3
"""Проверки заметок для заявки в App Store.

Запуск: `python3 tools/asc_release_notes_test.py`
"""

import unittest

from asc_release_notes import strip_unsupported


class StripUnsupported(unittest.TestCase):
    def test_снимает_эмодзи_заголовка(self):
        # Apple отвергла заявку 1.26.0 дословно так: «What's New in This
        # Version can’t contain the following character(s): 🫦».
        self.assertEqual(
            strip_unsupported("🫦 Togetherly • v1.26.0"),
            "Togetherly • v1.26.0",
        )

    def test_снимает_эмодзи_из_середины_строки(self):
        self.assertEqual(
            strip_unsupported("Виджеты 💜 на экране блокировки"),
            "Виджеты на экране блокировки",
        )

    def test_оставляет_тире_кавычки_и_буквы(self):
        text = "— Виджеты на экране блокировки: «Скучаю» и настроение обоих."
        self.assertEqual(strip_unsupported(text), text)

    def test_не_плодит_двойные_пробелы(self):
        self.assertEqual(
            strip_unsupported("Дни 🎉 вместе"),
            "Дни вместе",
        )

    def test_пустая_строка_после_чистки_не_остаётся_в_тексте(self):
        # Заголовок из одного эмодзи схлопывается вместе со своей строкой,
        # иначе заметки начинались бы с пустой строки.
        self.assertEqual(
            strip_unsupported("🫦\n\nВиджеты вернулись"),
            "Виджеты вернулись",
        )

    def test_сохраняет_разбивку_на_строки(self):
        self.assertEqual(
            strip_unsupported("— Первое\n— Второе"),
            "— Первое\n— Второе",
        )


if __name__ == "__main__":
    unittest.main()
