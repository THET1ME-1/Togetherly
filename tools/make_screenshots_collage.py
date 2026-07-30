#!/usr/bin/env python3
"""Собирает коллаж скриншотов для README.

Исходники лежат в `docs/branding/raw/` и нумерованы в том порядке, в каком
попадут в полосу. Сняты с телефона: golden-тесты давали кадры без картинок —
в тестовом рендере изображения не декодируются, — а витрина без фотографий и
аватаров выглядит мёртвой.

Скрипт срезает системные полосы (часы с батарейкой сверху, кнопки навигации
снизу), приводит кадры к одной высоте и склеивает через равные промежутки.

    python3 tools/make_screenshots_collage.py
"""
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "branding" / "raw"
OUT = ROOT / "docs" / "branding" / "screenshots.png"

# Высота полосы и поля — как в прежнем коллаже, чтобы вёрстка README не поехала.
FRAME_H = 560
GAP = 18
PAD = 20

# Сколько срезать у кадра 1080×2400 сверху и снизу: статус-бар и системная
# навигация к приложению отношения не имеют и только сбивают взгляд.
CROP_TOP = 112
CROP_BOTTOM = 150

# Скруглённые углы: кадры читаются как экраны, а не как прямоугольные обрезки.
CORNER = 26


def rounded(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, im.width - 1, im.height - 1), radius=radius, fill=255
    )
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def frame(path: pathlib.Path) -> Image.Image:
    im = Image.open(path).convert("RGB")
    im = im.crop((0, CROP_TOP, im.width, im.height - CROP_BOTTOM))
    scale = FRAME_H / im.height
    im = im.resize((round(im.width * scale), FRAME_H), Image.LANCZOS)
    return rounded(im, CORNER)


def main() -> None:
    paths = sorted(RAW.glob("*.jpg")) + sorted(RAW.glob("*.png"))
    if not paths:
        raise SystemExit(f"нет исходников в {RAW}")

    frames = [frame(p) for p in paths]
    width = sum(f.width for f in frames) + GAP * (len(frames) - 1) + PAD * 2
    canvas = Image.new("RGBA", (width, FRAME_H + PAD * 2), (255, 255, 255, 0))

    x = PAD
    for f in frames:
        canvas.alpha_composite(f, (x, PAD))
        x += f.width + GAP

    canvas.convert("RGB").save(OUT, quality=95)
    print(
        f"коллаж собран: {OUT} ({canvas.width}×{canvas.height}), "
        f"кадров {len(frames)}: {', '.join(p.stem for p in paths)}"
    )


if __name__ == "__main__":
    main()
