#!/usr/bin/env python3
"""Сброс пережатой фигурки из кэша раздачи без перебора кэша (19.10.2026).

`drop_cache` искал файл командой `grep -rl` по всему кэшу nginx: 42 ГБ на
каждую пережатую фигурку, крон раз в три минуты. Ночью 19.10 один такой поиск
шёл больше минуты и ел полядра. Имя файла в кэше nginx — md5 ключа, папки
задаёт `levels=1:2`, так что путь считается сразу.

    python3 tools/test_note_shrink_cache.py
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import note_shrink  # noqa: E402

провалы = []


def проверить(имя, ok, подробно=""):
    print(("ОК   " if ok else "ПЛОХО") + f" {имя} {'' if ok else подробно}")
    if not ok:
        провалы.append(имя)


# Живой образец с сервера 19.10.2026: файл кэша и ключ из его заголовка
# «KEY: /api/files/media/9krwn3w6hqmnxy6/vid_…_o7tynxo9iy.mp4||».
пути = note_shrink.cache_paths(
    "9krwn3w6hqmnxy6", "vid_2026_10_19_01_27_47_1346841867_o7tynxo9iy.mp4")
проверить("путь живого файла кэша угадан",
          "/var/cache/nginx/files/7/87/904093a056500afc3c1a3011bb8a0877" in пути, str(пути))

with tempfile.TemporaryDirectory() as root:
    свои = note_shrink.cache_paths("rec1", "a.mp4", roots=[root])
    for p in свои:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").close()
    чужой = os.path.join(root, "0", "00", "0" * 32)
    os.makedirs(os.path.dirname(чужой), exist_ok=True)
    open(чужой, "w").close()
    note_shrink.drop_cache("rec1", "a.mp4", roots=[root])
    проверить("свой файл выброшен из кэша", not any(os.path.exists(p) for p in свои))
    проверить("чужой файл кэша не тронут", os.path.exists(чужой))
    note_shrink.drop_cache("rec1", "a.mp4", roots=[root])
    проверить("повторный сброс не падает", True)

print(f"\nпровалов: {len(провалы)}")
raise SystemExit(1 if провалы else 0)
