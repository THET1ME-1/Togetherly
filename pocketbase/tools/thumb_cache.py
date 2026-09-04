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

Видео проходит тем же путём, только картинку из него достаёт ffmpeg: секунда
от начала, один кадр, дальше общий Pillow. Без этого девять тысяч роликов
стояли в ленте пустыми плитками с надписью «кадр ещё готовится» — генератор
обходил их по расширению, и промах не закрывался никогда. Первый кадр часто
чёрный (камера открывает диафрагму), поэтому берём секунду; ролик короче —
отступаем в ноль. Звук картинки не имеет вовсе, и он по-прежнему пропускается:
его в ленте рисует не миниатюра, а плашка.

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
import shutil
import sqlite3
import subprocess
import sys
import tempfile

from PIL import Image, ImageOps
import pillow_heif

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pb_storage

DB = "/opt/pocketbase/pb_data/data.db"
STORE = "/opt/pocketbase/pb_data/storage/pbc_2708086759"
CACHE = "/opt/pocketbase/pb_data/thumb_cache"
NEWEST = 600  # прогрев кроном: свежие записи и есть то, что смотрят
SIZES = {512: 74, 1600: 82}  # ширина → качество webp
SKIP_EXT = (".m4a", ".aac", ".mp3", ".wav", ".ogg", ".flac")  # звук: кадра нет
VIDEO_EXT = (".mp4", ".mov", ".webm", ".mkv", ".avi")
FFMPEG = "/usr/bin/ffmpeg"
FRAME_AT = "1"          # секунда, с которой берём кадр
FFMPEG_TIMEOUT = 20

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


def video_frame(src, workdir):
    """Кадр из ролика в png. Пусто — значит ffmpeg не справился.

    Одно ядро на ролик (`-threads 1`) и `nice`: генератор ходит сюда прямо из
    запроса ленты, а рядом на этой же машине живут PocketBase и панель.
    Раскодировать больше одного кадра незачем, поэтому `-ss` стоит до `-i` —
    так ffmpeg прыгает по ключевым кадрам, а не проигрывает файл до нужной
    секунды.
    """
    dst = os.path.join(workdir, "frame.png")
    for отступ in (FRAME_AT, "0"):
        try:
            subprocess.run(
                ["nice", "-n", "10", FFMPEG, "-v", "error", "-y", "-threads", "1",
                 "-ss", отступ, "-i", src, "-frames:v", "1", dst],
                capture_output=True, timeout=FFMPEG_TIMEOUT, check=False)
        except (OSError, subprocess.TimeoutExpired) as exc:
            print("кадр не достался:", exc)
            return ""
        if os.path.exists(dst) and os.path.getsize(dst) > 0:
            return dst
        # Ролик короче секунды: пустой файл после первой попытки помешает
        # второй — ffmpeg молча решит, что писать некуда.
        if os.path.exists(dst):
            os.remove(dst)
    return ""


def build(rec_id, name):
    """Вернуть число сделанных файлов. Оба размера читают исходник один раз."""
    if name.lower().endswith(SKIP_EXT):
        return 0
    need = [w for w in SIZES if rebuild or not (
        os.path.exists(out_path(rec_id, w)) and os.path.getsize(out_path(rec_id, w)) > 0)]
    if not need:
        return 0
    # Исходник может лежать уже не на диске, а в бакете — модуль знает оба места.
    holder = pb_storage.Source(rec_id, name).open()
    if not holder.path:
        return 0
    frames = ""
    try:
        рисунок = holder.path
        if name.lower().endswith(VIDEO_EXT):
            frames = tempfile.mkdtemp(prefix="thumbvid_")
            рисунок = video_frame(holder.path, frames)
            if not рисунок:
                return 0
        base = Image.open(рисунок)
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
    finally:
        holder.close()
        if frames:
            shutil.rmtree(frames, ignore_errors=True)


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
