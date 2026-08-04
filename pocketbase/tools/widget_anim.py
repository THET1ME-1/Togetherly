#!/opt/pocketbase/tools/heicenv/bin/python
"""Живое фото для виджета: из видео или гифки — одна картинка-раскадровка.

Зачем именно так. `ImageView` внутри виджета не проигрывает ни видео, ни
анимированный drawable: RemoteViews инфлейтит только классы из белого списка, а
плеера там нет. Анимацию покадрово толкает приложение — значит ему нужны кадры,
а не файл. Кадры готовит сервер: телефон партнёра (часто слабый) не должен
разбирать видео, `MediaMetadataRetriever` тратит на кадр 100–200 мс.

Что получается на выходе: один webp, где 18 кадров лежат сеткой 6×3, и манифест
рядом. Вес предсказуем по построению — около 300 КБ против непредсказуемых
мегабайт у видео, а приём тот же, которым рисуются анимированные маскоты
(`drawImageRect` по клеткам атласа).

Исходное видео после обработки удаляется: на диске остаётся только раскадровка.

  widget_anim.py --ids a,b,c     обработать записи media (так зовёт хук)
  widget_anim.py                 пройти необработанные (так ходит крон)
  widget_anim.py --keep-source   не удалять исходник (для отладки)
  widget_anim.py --file X --id Y  обработать файл напрямую, мимо базы (проверка)
"""
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile

from PIL import Image

DB = "/opt/pocketbase/pb_data/data.db"
STORE = "/opt/pocketbase/pb_data/storage/pbc_2708086759"
OUT = "/opt/pocketbase/pb_data/widget_anim"

COLS, ROWS = 6, 3          # 18 кадров: столько влезает в 300 КБ и хватает глазу
CELL = 300                 # сторона кадра: плитка виджета крупнее не бывает
SPAN_MS = 1500             # берём первые полторы секунды
STEP_MS = SPAN_MS // (COLS * ROWS)
# Границы шага для анимации: ниже 90 мс лончер не успевает перерисовать виджет,
# выше 200 движение распадается на отдельные картинки.
MIN_STEP_MS, MAX_STEP_MS = 90, 200
QUALITY = 74
VIDEO_EXT = (".mp4", ".mov", ".m4v", ".webm", ".3gp")
GIF_EXT = (".gif", ".webp")

keep_source = "--keep-source" in sys.argv
only_ids = []
direct_file = direct_id = None
for i, a in enumerate(sys.argv):
    if a == "--ids" and i + 1 < len(sys.argv):
        only_ids = [x for x in sys.argv[i + 1].replace(" ", "").split(",") if x]
    elif a == "--file" and i + 1 < len(sys.argv):
        direct_file = sys.argv[i + 1]
    elif a == "--id" and i + 1 < len(sys.argv):
        direct_id = sys.argv[i + 1]

os.makedirs(OUT, exist_ok=True)


def source_path(rec_id: str, name: str) -> str:
    # Проверочный режим отдаёт путь как есть: записи в базе тогда ещё нет.
    if direct_file and rec_id == direct_id:
        return direct_file
    return os.path.join(STORE, rec_id, name)


def sheet_path(rec_id: str) -> str:
    return os.path.join(OUT, f"{rec_id}.webp")


def frames_from_video(src: str, work: str) -> tuple:
    """Кадры из видео. Один вызов ffmpeg вместо восемнадцати: перебор по времени
    поштучно стоил бы секунд, а фильтр fps отдаёт всё за один проход."""
    fps = 1000.0 / STEP_MS
    pattern = os.path.join(work, "f%03d.png")
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-t", f"{SPAN_MS / 1000:.3f}", "-i", src,
        "-vf", f"fps={fps:.4f},scale={CELL}:{CELL}:force_original_aspect_ratio=increase,"
               f"crop={CELL}:{CELL}",
        "-frames:v", str(COLS * ROWS), pattern,
    ]
    subprocess.run(cmd, check=True, timeout=60)
    frames = sorted(os.path.join(work, f) for f in os.listdir(work) if f.endswith(".png"))
    return frames, STEP_MS


def frames_from_animation(src: str, work: str) -> tuple:
    """Кадры из гифки или анимированного webp — Pillow умеет их сам.

    Шаг берётся из самой анимации, а не из видео-константы. У гифки своя
    скорость: кадров бывает шесть на две секунды, и показ по 83 мс гнал бы её
    втрое быстрее оригинала. Длинную обрезаем по первым трём секундам —
    восемнадцать кадров с шагом в полсекунды читаются как слайдшоу, а не как
    живое фото.
    """
    im = Image.open(src)
    total = getattr(im, "n_frames", 1)

    # Раскладка по времени, а не по номерам кадров: у гифки кадры бывают разной
    # длительности, и равномерная выборка по индексу дёргалась бы.
    starts, clock = [], 0
    for i in range(total):
        im.seek(i)
        starts.append(clock)
        clock += int(im.info.get("duration") or 100)
    span = min(clock, 3000) if clock > 0 else SPAN_MS
    step = max(MIN_STEP_MS, min(MAX_STEP_MS, round(span / (COLS * ROWS))))

    picked = []
    for i in range(COLS * ROWS):
        want = i * step
        # Ближайший кадр, который к этому моменту уже показан.
        idx = 0
        for j, s in enumerate(starts):
            if s <= want:
                idx = j
            else:
                break
        im.seek(idx)
        frame = im.convert("RGB")
        side = min(frame.size)
        left = (frame.width - side) // 2
        top = (frame.height - side) // 2
        frame = frame.crop((left, top, left + side, top + side)).resize(
            (CELL, CELL), Image.LANCZOS)
        p = os.path.join(work, f"f{i:03d}.png")
        frame.save(p)
        picked.append(p)
    return picked, step


def build(rec_id: str, name: str) -> bool:
    src = source_path(rec_id, name)
    if not os.path.exists(src):
        return False
    lower = name.lower()
    work = tempfile.mkdtemp(prefix="wanim_")
    try:
        if lower.endswith(VIDEO_EXT):
            frames, step_ms = frames_from_video(src, work)
        elif lower.endswith(GIF_EXT):
            frames, step_ms = frames_from_animation(src, work)
        else:
            return False
        if not frames:
            return False

        sheet = Image.new("RGB", (COLS * CELL, ROWS * CELL), (0, 0, 0))
        for i in range(COLS * ROWS):
            # Кадров может приехать меньше, чем клеток (короткое видео) —
            # добираем последним, чтобы в атласе не осталось чёрных дыр.
            f = frames[min(i, len(frames) - 1)]
            sheet.paste(Image.open(f), ((i % COLS) * CELL, (i // COLS) * CELL))

        tmp = sheet_path(rec_id) + ".part"
        sheet.save(tmp, "WEBP", quality=QUALITY, method=4)
        os.replace(tmp, sheet_path(rec_id))

        manifest = {
            "cols": COLS, "rows": ROWS, "cell": CELL,
            "frames": COLS * ROWS, "step_ms": step_ms,
            "source": "video" if lower.endswith(VIDEO_EXT) else "animation",
        }
        with open(os.path.join(OUT, f"{rec_id}.json"), "w", encoding="ascii") as fh:
            json.dump(manifest, fh, ensure_ascii=True)

        if not keep_source:
            # Исходник больше не нужен: виджету достаточно раскадровки, а видео
            # на диске — это те самые мегабайты, ради которых всё и затевалось.
            try:
                os.remove(src)
            except OSError:
                pass
        return True
    finally:
        shutil.rmtree(work, ignore_errors=True)


if direct_file:
    rows = [(direct_id or "direct", os.path.basename(direct_file))]
    db = None
else:
    db = sqlite3.connect("file:" + DB + "?mode=ro", uri=True)
if db is not None and only_ids:
    qs = ",".join("?" * len(only_ids))
    rows = db.execute("SELECT id, file FROM media WHERE id IN (%s)" % qs, only_ids).fetchall()
elif db is not None:
    rows = db.execute(
        "SELECT id, file FROM media WHERE kind = 'widget_anim' ORDER BY rowid DESC LIMIT 200"
    ).fetchall()
if db is not None:
    db.close()

done = failed = skipped = 0
for rec_id, name in rows:
    if os.path.exists(sheet_path(rec_id)) and os.path.getsize(sheet_path(rec_id)) > 0:
        skipped += 1
        continue
    try:
        if build(rec_id, name):
            done += 1
        else:
            skipped += 1
    except Exception as exc:
        failed += 1
        print(rec_id, name, "не вышло:", exc)

print("готово %d, пропущено %d, не вышло %d" % (done, skipped, failed))
