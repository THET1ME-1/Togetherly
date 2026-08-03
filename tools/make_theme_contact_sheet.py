#!/usr/bin/env python3
"""Контактный лист тем: все палитры на одном экране, светлые и тёмные.

Двадцать пять тем на телефоне перебирают вручную и по одной, поэтому судить о
качестве палитры так невозможно. Витрина рисуется golden-тестом, а этот скрипт
складывает кадры в два листа — по одному на режим.

    flutter test test/goldens/theme_showcase.dart --update-goldens
    python3 tools/make_theme_contact_sheet.py

Результат: `build/theme-sheets/themes-light.png` и `themes-dark.png`.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("нужен Pillow: pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "test/goldens/themes"
OUT = ROOT / "build/theme-sheets"
FONT = ROOT / "assets/fonts/Onest.ttf"
PER_ROW = 5
SCALE = 0.42


def names() -> dict[int, str]:
    """Названия читаются из каталога палитр, чтобы не расходиться с кодом."""
    source = (ROOT / "lib/theme/app_palettes.dart").read_text(encoding="utf-8")
    out: dict[int, str] = {}
    for line in source.splitlines():
        line = line.strip()
        if not line.startswith("Palette("):
            continue
        head = line[len("Palette("):]
        index, rest = head.split(",", 1)
        title = rest.split("'")[1]
        out[int(index)] = title
    return out


def sheet(mode: str, titles: dict[int, str]) -> Path | None:
    files = sorted(SRC.glob(f"*-{mode}.png"))
    if not files:
        return None
    shots = [(int(f.stem.split("-")[0]), Image.open(f)) for f in files]
    tw, th = shots[0][1].size
    tw, th = int(tw * SCALE), int(th * SCALE)
    caption = 34
    rows = (len(shots) + PER_ROW - 1) // PER_ROW
    dark = mode == "dark"
    canvas = Image.new(
        "RGB",
        (PER_ROW * (tw + 16) + 16, rows * (th + caption + 16) + 16),
        (24, 22, 28) if dark else (245, 243, 248),
    )
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(str(FONT), 22) if FONT.exists() \
        else ImageFont.load_default()
    ink = (235, 230, 240) if dark else (30, 26, 34)

    for i, (index, shot) in enumerate(shots):
        x = 16 + (i % PER_ROW) * (tw + 16)
        y = 16 + (i // PER_ROW) * (th + caption + 16)
        canvas.paste(shot.resize((tw, th), Image.LANCZOS), (x, y))
        draw.text((x + 2, y + th + 6),
                  f"{index} · {titles.get(index, '?')}", font=font, fill=ink)

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"themes-{mode}.png"
    canvas.save(path)
    return path


def main() -> None:
    if not SRC.exists():
        sys.exit("сначала прогони golden-тест витрины: "
                 "flutter test test/goldens/theme_showcase.dart --update-goldens")
    titles = names()
    for mode in ("light", "dark"):
        path = sheet(mode, titles)
        print(path if path else f"кадров для режима {mode} нет")


if __name__ == "__main__":
    main()
