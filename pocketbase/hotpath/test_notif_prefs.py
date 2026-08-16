#!/usr/bin/env python3
"""Выключатели уведомлений в приложении обязаны работать.

Жалоба 16.08.2026: «выключение уведомлений в приложении не помогает, они не
выключаются». Так и было: переключатели сохранялись и в prefs, и на сервер
(`users.notif_miss_you`, `notif_chat`, `notif_mood`, `notif_new_memory`), но
ни hotpath, ни хук `apns_push.js` эти поля не читали — пуши уходили всем
подряд. На 16 августа выключенным «Скучаю» стоял у 16 507 человек, и все они
продолжали получать уведомления.

Здесь проверяется правило: какому виду уведомления какой выключатель
соответствует и что делать с незаполненным полем.

Запуск: python3 pocketbase/hotpath/test_notif_prefs.py
"""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "hotpath_src", Path(__file__).parent / "hotpath.py")
источник = spec.loader.get_source("hotpath_src")

# Карта выключателей объявлена рядом с функцией — берём её тем же куском.
пространство: dict = {}
начало = источник.index("ВЫКЛЮЧАТЕЛИ = {")
# Кусок кончается там, где начинается следующая функция ПОСЛЕ нашей.
конец = источник.index("\ndef _miss_you_push_text(")
exec(compile(источник[начало:конец], "hotpath.py", "exec"), пространство)
_разрешено = пространство["_уведомление_разрешено"]


class Выключатели(unittest.TestCase):
    def test_выключенное_не_шлём(self):
        человек = {"notif_miss_you": 0, "notif_chat": 1,
                   "notif_mood": 1, "notif_new_memory": 1}
        self.assertFalse(_разрешено("miss", человек))
        self.assertTrue(_разрешено("chat", человек))

    def test_каждый_вид_смотрит_на_свой_флаг(self):
        выкл = {"notif_miss_you": 1, "notif_chat": 0,
                "notif_mood": 0, "notif_new_memory": 0}
        self.assertTrue(_разрешено("miss", выкл))
        self.assertFalse(_разрешено("chat", выкл))
        self.assertFalse(_разрешено("mood", выкл))
        self.assertFalse(_разрешено("memory", выкл))

    def test_поле_не_заполнено_значит_включено(self):
        # Старые аккаунты полей не имеют вовсе: молчать им нельзя.
        self.assertTrue(_разрешено("miss", {}))
        self.assertTrue(_разрешено("chat", {"notif_chat": None}))

    def test_незнакомый_вид_проходит(self):
        # Тихое пробуждение виджетов и всё новое не должно молча пропадать
        # из-за отсутствия выключателя.
        self.assertTrue(_разрешено("widgets", {"notif_chat": 0}))
        self.assertTrue(_разрешено("", {"notif_chat": 0}))


if __name__ == "__main__":
    unittest.main(verbosity=2)
