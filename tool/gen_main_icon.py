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
# Доля ВИДИМОГО круга (72dp из 108), которую занимает фигура по ширине.
# Единица — «фигура ровно по кругу», но у маскота волнистый край, и в выемках
# между лепестками остаётся светлый фон. Перебор в четверть уводит выемки за
# границу маски: круг заполнен фигурой, глаза целиком в кадре. Больше 1,3
# начинает срезать глаза, проверено сборкой слоёв 1,06 / 1,25 / 1,40.
FG_FIGURE_FILL = 1.25
VISIBLE_FRACTION = 72 / 108
# Тот же цвет, что в values/colors.xml: слой кроет всё полотно, поэтому
# background из XML под ним не виден, и края обязан закрыть сам foreground.
FG_BG = (253, 227, 226)
# Всё, что светлее этого по каждому каналу, считаем фоном рисунка, а не фигурой.
FIGURE_EDGE = (246, 214, 214)


def figure_box(img):
    """Границы красной фигуры в кадре: по пикселям, которые не светлый фон."""
    rgb = img.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    left, top, right, bottom = w, h, -1, -1
    # Шаг по два пикселя: границы нужны с точностью до пары, зато вдвое быстрее.
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if r <= FIGURE_EDGE[0] or g <= FIGURE_EDGE[1] or b <= FIGURE_EDGE[2]:
                if x < left:
                    left = x
                if x > right:
                    right = x
                if y < top:
                    top = y
                if y > bottom:
                    bottom = y
    if right < 0:
        return (0, 0, w, h)
    return (left, top, right + 1, bottom + 1)


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

    # Кадр для переднего слоя: центр — центр фигуры, размер — так, чтобы фигура
    # заняла заданную долю видимого круга.
    box = figure_box(master)
    fig_w = box[2] - box[0]
    fig_cx = (box[0] + box[2]) / 2
    fig_cy = (box[1] + box[3]) / 2
    # Сторона кадра в пикселях исходника: фигура должна стать FG_FIGURE_FILL от
    # видимого круга, а тот сам — VISIBLE_FRACTION полотна.
    side = fig_w / (FG_FIGURE_FILL * VISIBLE_FRACTION)
    crop = (
        round(fig_cx - side / 2), round(fig_cy - side / 2),
        round(fig_cx + side / 2), round(fig_cy + side / 2),
    )
    # За краями исходника подставляем фон рисунка, а не чёрное поле.
    frame = Image.new("RGB", (round(side), round(side)), FG_BG)
    frame.paste(master, (-crop[0], -crop[1]))

    for folder, px in FG_DENSITIES.items():
        d = os.path.join(RES, folder)
        os.makedirs(d, exist_ok=True)
        frame.resize((px, px), Image.LANCZOS).convert("RGBA").save(
            os.path.join(d, "launcher_icon_fg.png"))

    print(f"готово: {ASSET}, {STORE} (512x512), круглые mipmap x{len(DENSITIES)}, "
          f"передний слой адаптивной иконки x{len(FG_DENSITIES)}")


if __name__ == "__main__":
    main()
