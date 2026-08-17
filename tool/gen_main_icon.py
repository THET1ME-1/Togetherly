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
# центральные 72dp.
#
# Рисунок не правим — только кадрируем. В нём фигура стоит справа, а слева
# светлое поле, и раньше вся картинка вместе с этим полем сжималась в 80%
# полотна: под круглой маской поле превращалось в широкую светлую дугу слева
# («уберите крупную обводку», 17.08.2026).
#
# Теперь кадр ведём по самой фигуре: её центр совпадает с центром полотна, а
# ширина фигуры занимает FG_FIGURE_FILL видимого круга. Светлое поле уходит за
# границу кадра, и под маской остаётся сам маскот.
FG_DENSITIES = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}
# Фигура должна попадать под маску ЦЕЛИКОМ, а вокруг оставаться белое поле —
# просьба автора 17.08.2026 («как на квадратной иконке весь виден и ещё белый
# фон»). Поэтому масштаб считаем не по ширине, а по описанной окружности:
# крайняя точка маскота ложится на границу безопасного круга 66dp из 108, и ни
# один лончер её не срежет, какой бы маской ни резал.
FG_SAFE_DIAMETER = 66 / 108
# Поле вокруг фигуры и фон адаптивной иконки — белые. Прежний светло-розовый
# (#FDE3E2) под круглой маской читался как цветная обводка.
FG_BG = (255, 255, 255)
# Всё, что светлее этого по каждому каналу, считаем фоном рисунка, а не фигурой.
FIGURE_EDGE = (246, 214, 214)


def figure_alpha(img):
    """Маска фигуры: непрозрачно там, где рисунок темнее светлого фона."""
    rgb = img.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    mask = Image.new("L", (w, h), 0)
    mpx = mask.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if r <= FIGURE_EDGE[0] or g <= FIGURE_EDGE[1] or b <= FIGURE_EDGE[2]:
                mpx[x, y] = 255
    return mask


def figure_geometry(mask):
    """Центр фигуры и радиус её описанной окружности — по пикселям маски."""
    w, h = mask.size
    px = mask.load()
    left, top, right, bottom = w, h, -1, -1
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if px[x, y]:
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
    cx, cy = (left + right) / 2, (top + bottom) / 2
    rmax = 0.0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if px[x, y]:
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if d > rmax:
                    rmax = d
    return cx, cy, rmax


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

    # Передний слой: фигура без фона рисунка, вписанная в безопасный круг.
    mask = figure_alpha(master)
    cx, cy, rmax = figure_geometry(mask)
    figure = master.convert("RGBA")
    figure.putalpha(mask)
    box = (round(cx - rmax), round(cy - rmax), round(cx + rmax), round(cy + rmax))
    # За краями исходника фигуры нет — добираем прозрачным полем, чтобы центр
    # описанной окружности остался центром слоя.
    square_fig = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0))
    square_fig.alpha_composite(figure, (-box[0], -box[1]))

    for folder, px in FG_DENSITIES.items():
        d = os.path.join(RES, folder)
        os.makedirs(d, exist_ok=True)
        layer = Image.new("RGBA", (px, px), FG_BG + (255,))
        inner = max(1, round(px * FG_SAFE_DIAMETER))
        fig = square_fig.resize((inner, inner), Image.LANCZOS)
        off = (px - inner) // 2
        layer.alpha_composite(fig, (off, off))
        layer.save(os.path.join(d, "launcher_icon_fg.png"))

    print(f"готово: {ASSET}, {STORE} (512x512), круглые mipmap x{len(DENSITIES)}, "
          f"передний слой адаптивной иконки x{len(FG_DENSITIES)}")


if __name__ == "__main__":
    main()
