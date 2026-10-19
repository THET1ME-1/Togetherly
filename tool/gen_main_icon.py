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

Сезонная иконка (Хэллоуин до 1 ноября 2026) — тот же путь с другим исходником.
Рисунок вертикальный, а сверху у него шляпа и луна, поэтому квадрат берётся
по центру. Этот рисунок владелец хочет видеть целиком, поэтому `--fit`:
    python3 tool/gen_main_icon.py docs/branding/raw/app-icon-halloween.png --center --fit
"""
from PIL import Image, ImageDraw
import os
import sys

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

# Передний слой адаптивной иконки: рисунок целиком, без единой правки. Полотно
# 108dp, круг из него вырезает сам лончер — иконка становится круглой там, где
# маска круглая, и скруглённым квадратом там, где такая.
#
# Ничего не вырезаем и не пересобираем по фигуре: две попытки «улучшить» кадр
# (вписать фигуру, потом уменьшить её на белом поле) автор отверг, и правильно —
# оригинал уже скомпонован.
FG_DENSITIES = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}


def square(img, center=False):
    """Квадрат по нижнему краю: фигура стоит на дне кадра, верх — фон.
    [center] берёт середину — для рисунка, где сверху есть что терять."""
    w, h = img.size
    side = min(w, h)
    top = (h - side) // 2 if center else h - side
    return img.crop((0, top, w, top + side))


# Слой с рисунком целиком (--fit): лончер показывает из 108dp только
# центральные 72dp, и хэллоуинский рисунок на весь слой выходил на телефоне
# увеличенным, без луны и метлы. Владелец, 19.10.2026: «нафига ты масштабируешь
# его? Верни его нормальные размеры». Поля под маской залиты цветом неба.
def fitted_layer(picture, px, fill):
    layer = Image.new("RGBA", (px, px), fill)
    side = round(px * 72 / 108)
    offset = (px - side) // 2
    layer.paste(picture.resize((side, side), Image.LANCZOS).convert("RGBA"), (offset, offset))
    return layer


def round_crop(img):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse([0, 0, img.size[0] - 1, img.size[1] - 1], fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def main():
    paths = [a for a in sys.argv[1:] if not a.startswith("--")]
    master = square(Image.open(paths[0] if paths else SRC).convert("RGB"),
                    center="--center" in sys.argv)
    icon512 = master.resize((512, 512), Image.LANCZOS)
    icon512.save(STORE)
    icon512.save(ASSET, "WEBP", quality=92, method=6)

    rmaster = round_crop(master)
    for folder, px in DENSITIES.items():
        d = os.path.join(RES, folder)
        os.makedirs(d, exist_ok=True)
        rmaster.resize((px, px), Image.LANCZOS).save(
            os.path.join(d, "launcher_icon_round.png"))

    # Цвет неба для полей — средний цвет левого верхнего угла рисунка
    sky = master.crop((0, 0, master.width // 20, master.height // 20)).resize((1, 1)).getpixel((0, 0))
    for folder, px in FG_DENSITIES.items():
        d = os.path.join(RES, folder)
        os.makedirs(d, exist_ok=True)
        if "--fit" in sys.argv:
            layer = fitted_layer(master, px, sky + (255,))
        else:
            layer = master.resize((px, px), Image.LANCZOS).convert("RGBA")
        layer.save(os.path.join(d, "launcher_icon_fg.png"))

    print(f"готово: {ASSET}, {STORE} (512x512), круглые mipmap x{len(DENSITIES)}, "
          f"передний слой адаптивной иконки x{len(FG_DENSITIES)}")


if __name__ == "__main__":
    main()
