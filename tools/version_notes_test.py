#!/usr/bin/env python3
"""Проверки заметок для попапа самообновления.

Запуск: `python3 tools/version_notes_test.py`
"""

import unittest

from version_notes import notes_body


class NotesBody(unittest.TestCase):
    def test_снимает_строку_заголовка(self):
        # Заметки прежних релизов начинались со строки «🫦 Togetherly • v1.27.0»
        # — в попапе она не нужна.
        text = "🫦 Togetherly • v1.27.0\n\nВиджеты вернулись.\n\nИ фото тоже."
        self.assertEqual(notes_body(text), "Виджеты вернулись.\n\nИ фото тоже.")

    def test_первый_абзац_без_заголовка_остаётся(self):
        # У 1.31.4 заголовка в файле нет, и срез первой строки унёс целый
        # абзац: в попапе люди читали релиз со второго предложения.
        text = "Виджеты обновляются сами.\n\nУ каждой пары свой набор данных."
        self.assertEqual(notes_body(text), text)

    def test_заголовок_без_эмодзи_тоже_снимается(self):
        text = "Togetherly 1.30.0\n\nЧто нового."
        self.assertEqual(notes_body(text), "Что нового.")

    def test_пустой_файл_даёт_пустую_строку(self):
        self.assertEqual(notes_body(""), "")
        self.assertEqual(notes_body("\n\n"), "")


if __name__ == "__main__":
    unittest.main()
