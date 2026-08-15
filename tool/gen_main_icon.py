#!/usr/bin/env python3
"""Основная иконка приложения: кроп исходника до квадрата и launcher-ассеты.

Рисунок заказчика (1182x1280) НЕ правится — только кадрируется в квадрат по
нижнему краю, чтобы фигура вошла целиком. Дальше:

* `docs/branding/app-icon-512.png` (512x512) — источник для
  `flutter_launcher_icons` (Android `launcher_icon` + все иконки iOS) и файл
  для магазинов; лежит вне сборки;
* `assets/images/logo/app_icon.webp` — та же картинка для превью в листе выбора
  иконки: превью рисуется 60 px, а PNG стоил бы сборке 145 КБ вместо 12;
* `mipmap-*/launcher_icon_round.png` — круглая версия для alias `.IconDefault`:
  `flutter_launcher_icons` её не делает, а лончеры с круглой маской без неё
  режут углы сами.

Запуск из корня проекта:
    python3 tool/gen_main_icon.py
    dart run flutter_launcher_icons     # раскладывает square-версии и iOS
"""
from PIL import Image, ImageDraw
import os

SRC = "docs/branding/raw/app-icon-source.png"
ASSET = "assets/images/logo/app_icon.webp"
STORE = "docs/branding/app-icon-512.png"
RES = "android/app/src/main/res"

DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Передний слой адаптивной иконки: полотно 108dp, под маской остаются
# центральные 72dp. Фигуру вписываем в 80% — маски лончеров срезают углы, но
# не столько, сколько допускает спецификация, и на 66% маскот выглядел бы
# потерянным среди полей.
FG_DENSITIES = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}
FG_FILL = 0.8
# Тот же цвет, что в values/colors.xml: слой кроет всё полотно, поэтому
# background из XML под ним не виден, и края обязан закрыть сам foreground.
FG_BG = (253, 227, 226)


def square(img):
    """Квадрат по нижнему краю: фигура стоит на дне кадра, верх — фон."""
    w, h = img.size
    side = min(w, h)
    return img.crop((0, h - side, w, h))


def round_crop(img):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse([0, 0, img.size[0] - 1, img.size[1] - 1], fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def main():
    master = square(Image.open(SRC).convert("RGB"))
    icon512 = master.resize((512, 512), Image.LANCZOS)
    icon512.save(STORE)
    icon512.save(ASSET, "WEBP", quality=92, method=6)

    rmaster = round_crop(master)
    for folder, px in DENSITIES.items():
        d = os.path.join(RES, folder)
        os.makedirs(d, exist_ok=True)
        rmaster.resize((px, px), Image.LANCZOS).save(
            os.path.join(d, "launcher_icon_round.png"))

    for folder, px in FG_DENSITIES.items():
        d = os.path.join(RES, folder)
        os.makedirs(d, exist_ok=True)
        layer = Image.new("RGBA", (px, px), FG_BG + (255,))
        inner = max(1, round(px * FG_FILL))
        fig = master.resize((inner, inner), Image.LANCZOS).convert("RGBA")
        off = (px - inner) // 2
        layer.paste(fig, (off, off), fig)
        layer.save(os.path.join(d, "launcher_icon_fg.png"))

    print(f"готово: {ASSET}, {STORE} (512x512), круглые mipmap x{len(DENSITIES)}, "
          f"передний слой адаптивной иконки x{len(FG_DENSITIES)}")


if __name__ == "__main__":
    main()
