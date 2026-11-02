#!/usr/bin/env python3
"""Иконка «Ту» на выбор: рисованный маскот с глазами-сердечками.

Рисунок собран один раз (docs/branding/raw/tu-icon-src/) и лежит двумя
файлами: `app-icon-tu.png` (1024, сама иконка) и `app-icon-tu-layer.png`
(1536, та же композиция с запасом по краям, центр 1024 совпадает с иконкой).
Отсюда скрипт раскладывает:

* `mipmap-*/ic_launcher_tu_fg.png` — передний слой адаптивной иконки, 108dp.
  Лончер показывает центральные 72dp, это и есть иконка 1:1; запас за краем
  виден только при параллаксе и в крупных масках, там Ту продолжается сам, а не
  обрывается полосой фона;
* `mipmap-*/ic_launcher_tu.png` и `ic_launcher_tu_round.png` — квадрат и круг
  для лончеров без адаптивных иконок;
* `assets/images/logo/app_icon_tu.webp` — превью в листе выбора иконки.

Запуск из корня проекта:
    python3 tool/gen_tu_icon.py
"""
import os

from PIL import Image, ImageDraw

ICON = "docs/branding/raw/app-icon-tu.png"
LAYER = "docs/branding/raw/app-icon-tu-layer.png"
ASSET = "assets/images/logo/app_icon_tu.webp"
RES = "android/app/src/main/res"

DENSITIES = {"mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96, "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192}
FG_DENSITIES = {"mipmap-mdpi": 108, "mipmap-hdpi": 162, "mipmap-xhdpi": 216, "mipmap-xxhdpi": 324, "mipmap-xxxhdpi": 432}


def round_crop(img):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse([0, 0, img.size[0] - 1, img.size[1] - 1], fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def main():
    icon = Image.open(ICON).convert("RGB")
    layer = Image.open(LAYER).convert("RGB")
    icon.resize((512, 512), Image.LANCZOS).save(ASSET, "WEBP", quality=92, method=6)
    for folder, px in DENSITIES.items():
        d = os.path.join(RES, folder)
        square = icon.resize((px, px), Image.LANCZOS)
        square.save(os.path.join(d, "ic_launcher_tu.png"), optimize=True)
        round_crop(square).save(os.path.join(d, "ic_launcher_tu_round.png"), optimize=True)
    for folder, px in FG_DENSITIES.items():
        layer.resize((px, px), Image.LANCZOS).save(os.path.join(RES, folder, "ic_launcher_tu_fg.png"), optimize=True)
    print(f"готово: {ASSET}, квадрат и круг x{len(DENSITIES)}, передний слой x{len(FG_DENSITIES)}")


if __name__ == "__main__":
    main()
