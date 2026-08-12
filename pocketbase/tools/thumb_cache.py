#!/opt/pocketbase/tools/heicenv/bin/python
"""Миниатюры webp для админки модерации: pb_data/thumb_cache.

Зачем. Сетка «Контента» тянула оригиналы по 1–2 МБ (1920×1920) в плитку
365 px — 3 МБ на первый экран. Миниатюры PocketBase не спасают: исходники в
webp, а он перекодирует такую миниатюру в PNG, и 600×600 весит больше самого
оригинала. Здесь Pillow из того же окружения, что делает HEIC-копии, и на
выходе webp: плитка 20–30 КБ, полноэкранный кадр 150–250 КБ.

Сюда же попадают снимки с айфонов: HEIC читается через pillow-heif и отдаётся
таким же webp, что и всё прочее, поэтому в админке он ничем не отличается от
обычной фотографии.

Два размера на файл, и оба нужны:
  512  — плитка сетки, обрезка по центру в квадрат (365 css × dpr 2 — 360 мылит);
  1600 — полноэкранный просмотр, вписано по длинной стороне.
Оригинал остаётся доступным по кнопке в лайтбоксе: модерации иногда нужно
разглядеть кадр без пережатия.

  thumb_cache.py                  прогреть последние NEWEST записей (так ходит крон)
  thumb_cache.py --ids a,b,c      сделать конкретные записи (так зовёт роут)
  thumb_cache.py --all            пройти всю коллекцию (долго)
  thumb_cache.py --rebuild        пересобрать, не пропуская готовые
"""
import os
import sqlite3
import sys

from PIL import Image, ImageOps
import pillow_heif

DB = "/opt/pocketbase/pb_data/data.db"
STORE = "/opt/pocketbase/pb_data/storage/pbc_2708086759"
CACHE = "/opt/pocketbase/pb_data/thumb_cache"
NEWEST = 600  # прогрев кроном: свежие записи и есть то, что смотрят
SIZES = {512: 74, 1600: 82}  # ширина → качество webp
SKIP_EXT = (".mp4", ".mov", ".m4a", ".aac", ".webm", ".mp3", ".wav")

# Снимки с айфонов (HEIC) браузеры, кроме Safari, не рисуют вовсе, и раньше их
# обходил отдельный кэш. Теперь они идут общим путём: libheif читает исходник,
# наружу уходит тот же webp, что у остальных фотографий.
pillow_heif.register_heif_opener()

rebuild = "--rebuild" in sys.argv
only_ids = []
for i, a in enumerate(sys.argv):
    if a == "--ids" and i + 1 < len(sys.argv):
        only_ids = [x for x in sys.argv[i + 1].replace(" ", "").split(",") if x]

os.makedirs(CACHE, exist_ok=True)
db = sqlite3.connect("file:" + DB + "?mode=ro", uri=True)
if only_ids:
    qs = ",".join("?" * len(only_ids))
    rows = db.execute("SELECT id, file FROM media WHERE id IN (%s)" % qs, only_ids).fetchall()
elif "--all" in sys.argv:
    rows = db.execute("SELECT id, file FROM media").fetchall()
else:
    # У коллекции media нет системных created/updated (её завели без них),
    # поэтому «свежие» берём по порядку вставки.
    rows = db.execute(
        "SELECT id, file FROM media ORDER BY rowid DESC LIMIT ?", (NEWEST,)).fetchall()
db.close()


def out_path(rec_id, width):
    return os.path.join(CACHE, "%s_%d.webp" % (rec_id, width))


def build(rec_id, name):
    """Вернуть число сделанных файлов. Оба размера читают исходник один раз."""
    if name.lower().endswith(SKIP_EXT):
        return 0
    need = [w for w in SIZES if rebuild or not (
        os.path.exists(out_path(rec_id, w)) and os.path.getsize(out_path(rec_id, w)) > 0)]
    if not need:
        return 0
    src = os.path.join(STORE, rec_id, name)
    if not os.path.exists(src):
        return 0
    base = Image.open(src)
    base.load()
    base = ImageOps.exif_transpose(base)
    if base.mode not in ("RGB", "L"):
        base = base.convert("RGB")
    made = 0
    for w in sorted(need):
        im = base.copy()
        if w == 512:
            # Плитка квадратная: вписывать нельзя, иначе в сетке поля по краям.
            im = ImageOps.fit(im, (w, w), Image.LANCZOS, centering=(0.5, 0.42))
        else:
            im.thumbnail((w, w), Image.LANCZOS)
        tmp = out_path(rec_id, w) + ".part"
        im.save(tmp, "WEBP", quality=SIZES[w], method=4)
        # Готовый файл появляется одним движением: крон и роут ходят сюда
        # одновременно, и недописанный webp попал бы в браузер.
        os.replace(tmp, out_path(rec_id, w))
        made += 1
    return made


done = failed = 0
for rec_id, name in rows:
    try:
        done += build(rec_id, name)
    except Exception as exc:
        failed += 1
        print(rec_id, name, "не вышло:", exc)
        for w in SIZES:
            junk = out_path(rec_id, w) + ".part"
            if os.path.exists(junk):
                os.remove(junk)

print("сделано файлов %d, записей %d, не вышло %d" % (done, len(rows), failed))
