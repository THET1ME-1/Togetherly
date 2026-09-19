#!/usr/bin/env python3
"""Точка на карте будит второго из пары (19.09.2026).

Виджет «Где мы» на iPhone перерисовывает только само приложение, а поднять
его в фоне может лишь тихий пуш. Раньше он уходил при правке виджетов и
настроения, а при новой точке — нет: карта партнёра на рабочем столе стояла,
пока он сам не откроет приложение. У `live_location` нет `group_id`, пара
зашита в имени канала `pair_<uid1>_<uid2>` — кого будить, берём оттуда.

Запуск: python3 pocketbase/hotpath/test_location_wake.py
"""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("hotpath_src", Path(__file__).parent / "hotpath.py")
источник = spec.loader.get_source("hotpath_src")
пространство: dict = {}
начало = источник.index("def _второй_из_канала(")
конец = источник.index("\nasync def _wake_channel(")
exec(compile(источник[начало:конец], "hotpath.py", "exec"), пространство)
второй = пространство["_второй_из_канала"]


class Канал(unittest.TestCase):
    def test_второй_из_пары(self):
        self.assertEqual(второй("pair_abc123_xyz789", "abc123"), "xyz789")
        self.assertEqual(второй("pair_abc123_xyz789", "xyz789"), "abc123")

    def test_автор_не_из_пары_не_будит_никого(self):
        self.assertEqual(второй("pair_abc123_xyz789", "чужой"), "")

    def test_канал_без_пары_не_будит(self):
        # Старые сборки писали точку в канал с id группы: там партнёра не
        # видно, а будить наугад нельзя.
        self.assertEqual(второй("grp123456789012", "abc123"), "")
        self.assertEqual(второй("", "abc123"), "")
        self.assertEqual(второй("pair_abc", "abc"), "")

    def test_длинные_uid_из_firebase(self):
        a, b = "Zk3f9QmPpXa1b2c3d4e5f6g7h8i9", "q1w2e3r4t5y6u7i"
        self.assertEqual(второй(f"pair_{a}_{b}", b), a)


if __name__ == "__main__":
    unittest.main()
