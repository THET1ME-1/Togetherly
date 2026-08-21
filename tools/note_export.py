#!/usr/bin/env python3
"""Готовит фигурку к сохранению на устройство: квадрат, форма внутри, подпись.

Что получается. Квадратный mp4 480×480: сама фигурка вырезана по своей форме
(сердце, звёздочка, ромбик — та, которой её отправляли), вокруг чёрное поле, в
правом нижнем углу подпись «Togetherly». Так же Telegram отдаёт свой кружок:
видео остаётся круглым, а файл — обычным квадратным роликом, который откроет
любая галерея и примет любой мессенджер.

Почему на сервере. Наложить маску и подпись умеет только ffmpeg, а тащить его
в приложение — это +12 МБ к сборке ради кнопки, которую нажимают изредка.
Здесь ffmpeg уже стоит и уже жмёт фигурки (`note_shrink.py`).

Маска рисуется из того же радиального профиля, что и форма в приложении
(`note_shapes.json` собран из `lib/widgets/chat/note_shapes.dart`), поэтому
скачанный ролик обрезан ровно так же, как выглядел в чате.

Запуск:
  note_export.py --src <файл> --shape heart --out <файл.mp4> [--label Togetherly]
"""

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SHAPES = os.path.join(HERE, "note_shapes.json")
FONT = "/opt/pocketbase/fonts/Onest.ttf"

SIDE = 480
CRF = "26"          # сохранённый файл человек может смотреть и вне чата
FFMPEG_TIMEOUT = 240


def load_shape(shape_id):
    with open(SHAPES) as f:
        shapes = json.load(f)
    return shapes.get(shape_id) or shapes.get("circle")


def mask_png(shape, path, side=SIDE):
    """Белый силуэт формы на чёрном — по нему ffmpeg вырежет альфу.

    Профиль хранится долями от полуширины и отложен от центра ВПИСАННОГО круга,
    а не от середины рамки: у сердца широкая часть ниже, и кадр в приложении
    прижат к ней же.
    """
    from PIL import Image, ImageDraw

    prof = shape["prof"]
    cx = side * (shape["cx"] / 200.0)
    cy = side * (shape["cy"] / 200.0)
    unit = side / 2.0
    pts = []
    for i, r in enumerate(prof):
        a = 2 * math.pi * i / len(prof)
        pts.append((cx + r * unit * math.cos(a), cy + r * unit * math.sin(a)))

    # Рисуем вчетверо крупнее и уменьшаем: у ffmpeg нет сглаживания краёв, а
    # ступенька по контуру сердца видна сразу.
    scale = 4
    big = Image.new("L", (side * scale, side * scale), 0)
    ImageDraw.Draw(big).polygon([(x * scale, y * scale) for x, y in pts], fill=255)
    big.resize((side, side), Image.LANCZOS).save(path)


def export(src, shape_id, out, label="Togetherly"):
    shape = load_shape(shape_id)
    tmp = tempfile.mkdtemp(prefix="noteexp_")
    mask = os.path.join(tmp, "mask.png")
    try:
        mask_png(shape, mask)
        # Порядок: кадр → квадрат → маска в альфу → поверх чёрного поля →
        # подпись. Подпись рисуется последней, поэтому ложится и на поле, и на
        # саму фигурку, если форма достаёт до угла.
        # `color=` — бесконечный источник, и без `shortest` overlay ждёт его
        # вечно: первый прогон висел, пока не сработал таймаут. Маска —
        # одиночный кадр, поэтому её вход зациклен (`-loop 1`), а длину задаёт
        # само видео.
        chain = (
            "[0:v]crop='min(iw,ih)':'min(iw,ih)',scale=%d:%d:flags=lanczos,"
            "format=yuva420p[v];"
            "[1:v]format=gray,scale=%d:%d[m];"
            "[v][m]alphamerge[va];"
            "color=black:s=%dx%d:r=24[bg];"
            "[bg][va]overlay=0:0:shortest=1:format=auto[shaped]"
            % (SIDE, SIDE, SIDE, SIDE, SIDE, SIDE)
        )
        if label and os.path.exists(FONT):
            chain += (
                ";[shaped]drawtext=fontfile=%s:text='%s':fontsize=22:"
                "fontcolor=white@0.92:x=w-tw-18:y=h-th-16[out]" % (FONT, label)
            )
            last = "[out]"
        else:
            last = "[shaped]"

        cmd = [
            "nice", "-n", "10", "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-i", src, "-loop", "1", "-i", mask,
            "-filter_complex", chain,
            "-map", last, "-map", "0:a?",
            "-c:v", "libx264", "-preset", "medium", "-crf", CRF,
            "-profile:v", "high", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "64k", "-ac", "1",
            "-movflags", "+faststart", "-shortest",
            out,
        ]
        res = subprocess.run(cmd, capture_output=True, timeout=FFMPEG_TIMEOUT)
        if res.returncode != 0:
            sys.stderr.write(res.stderr.decode(errors="replace")[:600])
            return False
        return os.path.exists(out) and os.path.getsize(out) > 0
    finally:
        subprocess.run(["rm", "-rf", tmp], timeout=30)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--shape", default="circle")
    ap.add_argument("--out", required=True)
    ap.add_argument("--label", default="Togetherly")
    args = ap.parse_args()
    ok = export(args.src, args.shape, args.out, args.label)
    if not ok:
        return 1
    print(args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
