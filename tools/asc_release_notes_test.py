#!/usr/bin/env python3
"""Проверки заметок для заявки в App Store.

Запуск: `python3 tools/asc_release_notes_test.py`
"""

import pathlib
import unittest

from asc_release_notes import build_localizations, strip_unsupported


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


class BuildLocalizations(unittest.TestCase):
    def test_заполняет_только_основную_локаль(self):
        # Новая локаль App Store требует ещё описание, ключевые слова и адрес
        # поддержки: заявка 1.26.0 упала именно на этом, когда мы завели
        # английскую страницу с одним лишь «Что нового». Трогаем ту, что уже
        # заполнена целиком, — основную.
        built = build_localizations("ru")
        self.assertEqual([item["locale"] for item in built], ["ru"])
        self.assertIn("Виджеты", built[0]["whats_new"])

    def test_для_чужой_локали_берёт_английский_текст(self):
        english = (
            pathlib.Path(__file__).resolve().parent.parent
            / "distribution"
            / "whatsnew"
            / "whatsnew-en-US"
        ).read_text(encoding="utf-8")
        built = build_localizations("de-DE")
        self.assertEqual([item["locale"] for item in built], ["de-DE"])
        self.assertEqual(built[0]["whats_new"], strip_unsupported(english))

    def test_заполняет_каждую_локаль_версии(self):
        # Заявка 1.31.4 упала 4 сентября: «Что нового» ушло одной русской
        # странице, а английская осталась пустой, и Apple отверг версию
        # целиком («You must provide a value for the attribute whatsNew»).
        built = build_localizations("ru", ["ru", "en-US"])
        self.assertEqual([item["locale"] for item in built], ["ru", "en-US"])
        self.assertIn("Виджеты", built[0]["whats_new"])
        self.assertIn("Widgets", built[1]["whats_new"])

    def test_основная_локаль_идёт_первой_и_не_дублируется(self):
        built = build_localizations("ru", ["en-US", "ru", "en-US"])
        self.assertEqual([item["locale"] for item in built], ["ru", "en-US"])

    def test_заметки_приходят_без_эмодзи(self):
        built = build_localizations("ru")
        self.assertNotIn("🫦", built[0]["whats_new"])


if __name__ == "__main__":
    unittest.main()
