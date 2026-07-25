#!/usr/bin/env python3
"""Превью виджетов для списка лончера.

Лончеры без поддержки previewLayout (MIUI в их числе) берут из
appwidget-provider только previewImage. Картинки рисуются здесь, а не руками,
чтобы после правки разметки превью можно было пересобрать одной командой:

    python3 tools/gen_widget_previews.py

Пропорции — из хендофа (2×2 = 200×200, 4×2 = 424×200, 4×4 = 424×424,
4×1 = 424×92), масштаб ×2. Цвета — тональная палитра проекта.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "android/app/src/main/res/drawable-nodpi"
FONT = ROOT / "assets/fonts/Onest.ttf"

S = 2  # масштаб относительно размеров хендофа

# ── Палитра ──────────────────────────────────────────────────────────────────
PRIMARY = "#6750A4"
ON_PRIMARY = "#FFFFFF"
PRIMARY_CONTAINER = "#EADDFF"
ON_PRIMARY_CONTAINER = "#21005D"
PRIMARY_DARK = "#D0BCFF"
PRIMARY_ALT = "#4F378B"
SECONDARY_CONTAINER = "#E8DEF8"
TERTIARY = "#7D5260"
TERTIARY_CONTAINER = "#FFD8E4"
ON_TERTIARY_CONTAINER = "#31111D"
SURFACE = "#FEF7FF"
SURFACE_CONTAINER = "#F3EDF7"
ON_SURFACE = "#1D1B20"
ON_SURFACE_VARIANT = "#49454F"
OUTLINE = "#7A757F"
TRACK_ON_CONTAINER = "#D6C6F0"
CAPTION_ON_PRIMARY = "#E9DDFF"

_weights = {
    400: "Regular",
    500: "Medium",
    600: "SemiBold",
    700: "Bold",
    800: "ExtraBold",
}
_cache: dict[tuple[int, int], ImageFont.FreeTypeFont] = {}


def font(size: int, weight: int = 700) -> ImageFont.FreeTypeFont:
    key = (size, weight)
    if key not in _cache:
        f = ImageFont.truetype(str(FONT), size * S)
        f.set_variation_by_name(_weights[weight])
        _cache[key] = f
    return _cache[key]


def canvas(w: int, h: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def card(d: ImageDraw.ImageDraw, box, radius: int, fill: str) -> None:
    x0, y0, x1, y1 = (v * S for v in box)
    d.rounded_rectangle((x0, y0, x1, y1), radius=radius * S, fill=fill)


def circle(d: ImageDraw.ImageDraw, cx, cy, r, fill, outline=None, width=0):
    d.ellipse(
        ((cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S),
        fill=fill,
        outline=outline,
        width=width * S,
    )


def text(d, xy, s, size, weight, fill, anchor="la"):
    d.text((xy[0] * S, xy[1] * S), s, font=font(size, weight), fill=fill, anchor=anchor)


def heart(d, cx, cy, size, fill):
    """Сердце как две окружности и треугольник — иконка favorite в миниатюре."""
    r = size / 3.4
    circle(d, cx - r * 0.86, cy - r * 0.52, r, fill)
    circle(d, cx + r * 0.86, cy - r * 0.52, r, fill)
    d.polygon(
        [
            ((cx - r * 1.72) * S, (cy - r * 0.16) * S),
            ((cx + r * 1.72) * S, (cy - r * 0.16) * S),
            (cx * S, (cy + r * 1.72) * S),
        ],
        fill=fill,
    )


def save(img: Image.Image, name: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f"{name}.png")
    print(f"  {name}.png  {img.size[0]}×{img.size[1]}")


# ── 01 «Вместе» ──────────────────────────────────────────────────────────────


def together_2x2() -> None:
    img, d = canvas(200, 200)
    card(d, (0, 0, 200, 200), 32, PRIMARY)

    circle(d, 35, 35, 17, PRIMARY_DARK, outline=PRIMARY, width=2)
    text(d, (35, 36), "А", 13, 800, ON_PRIMARY_CONTAINER, anchor="mm")
    circle(d, 59, 35, 17, TERTIARY_CONTAINER, outline=PRIMARY, width=2)
    text(d, (59, 36), "М", 13, 800, ON_TERTIARY_CONTAINER, anchor="mm")

    # Число и подпись — по нижнему краю, с воздухом между ними.
    text(d, (18, 150), "205", 54, 800, ON_PRIMARY, anchor="ls")
    text(d, (18, 176), "дней вместе", 15, 600, CAPTION_ON_PRIMARY, anchor="ls")
    save(img, "tg_preview_together_2x2")


def together_4x2() -> None:
    img, d = canvas(424, 200)
    card(d, (0, 0, 424, 200), 32, PRIMARY_CONTAINER)

    text(d, (22, 24), "С 1 ноября 2025", 13, 700, PRIMARY_ALT)
    text(d, (22, 108), "205", 60, 800, ON_PRIMARY_CONTAINER, anchor="ls")
    # «дней» ставим по базовой линии числа, отступив на его реальную ширину.
    w = d.textlength("205", font=font(60, 800)) / S
    text(d, (22 + w + 10, 108), "дней", 17, 700, ON_PRIMARY_CONTAINER, anchor="ls")
    heart(d, 390, 42, 26, PRIMARY)

    text(d, (22, 146), "До года — 160 дней", 13, 700, PRIMARY_ALT)
    text(d, (402, 146), "56%", 13, 700, PRIMARY_ALT, anchor="ra")

    card(d, (22, 170, 402, 182), 6, TRACK_ON_CONTAINER)
    card(d, (22, 170, 22 + (402 - 22) * 0.56, 182), 6, PRIMARY)
    save(img, "tg_preview_together_4x2")


def together_4x4() -> None:
    img, d = canvas(424, 424)
    card(d, (0, 0, 424, 424), 36, SURFACE)

    text(d, (24, 26), "АНЯ + МИША", 14, 800, ON_SURFACE_VARIANT)
    heart(d, 396, 33, 22, PRIMARY)

    card(d, (24, 58, 400, 200), 28, PRIMARY)
    text(d, (46, 152), "205", 72, 800, ON_PRIMARY, anchor="ls")
    text(d, (46, 178), "дней вместе", 16, 600, CAPTION_ON_PRIMARY, anchor="ls")
    text(d, (378, 152), "6", 26, 800, ON_PRIMARY, anchor="rs")
    text(d, (378, 178), "месяцев", 12, 600, PRIMARY_DARK, anchor="rs")

    text(d, (24, 224), "ДАЛЬШЕ", 13, 800, OUTLINE)

    card(d, (24, 252, 400, 320), 20, SURFACE_CONTAINER)
    text(d, (42, 286), "300 дней", 15, 700, ON_SURFACE, anchor="lm")
    text(d, (382, 286), "через 95 дней", 13, 600, ON_SURFACE_VARIANT, anchor="rm")

    card(d, (24, 332, 400, 400), 20, TERTIARY_CONTAINER)
    text(d, (42, 366), "1 год", 15, 700, ON_TERTIARY_CONTAINER, anchor="lm")
    text(d, (382, 366), "1 ноября", 13, 600, TERTIARY, anchor="rm")
    save(img, "tg_preview_together_4x4")


# ── 02 «Скучаю» ──────────────────────────────────────────────────────────────


def miss_2x2() -> None:
    img, d = canvas(200, 200)
    card(d, (0, 0, 200, 200), 32, TERTIARY_CONTAINER)

    text(d, (18, 20), "Мише", 13, 700, TERTIARY)
    heart(d, 172, 27, 20, TERTIARY)

    text(d, (18, 132), "Скучаю", 26, 800, ON_TERTIARY_CONTAINER, anchor="ls")

    card(d, (18, 148, 122, 182), 17, TERTIARY)
    text(d, (70, 165), "Отправить", 13, 700, ON_PRIMARY, anchor="mm")
    save(img, "tg_preview_miss_2x2")


def miss_4x2() -> None:
    img, d = canvas(424, 200)
    card(d, (0, 0, 424, 200), 32, SURFACE)

    text(d, (22, 24), "СКУЧАЮ СЕГОДНЯ", 14, 800, ON_SURFACE)
    text(d, (402, 26), "последний раз в 14:32", 12, 600, OUTLINE, anchor="ra")

    # Кнопка 64×64 у правого края, две плашки делят остаток поровну.
    btn_x1, btn_x0 = 402, 402 - 64
    gap = 14
    tile_w = (btn_x0 - gap - 22 - gap) / 2

    card(d, (22, 100, 22 + tile_w, 178), 24, PRIMARY_CONTAINER)
    text(d, (40, 118), "Я", 12, 700, PRIMARY_ALT)
    text(d, (40, 166), "15", 34, 800, ON_PRIMARY_CONTAINER, anchor="ls")

    x = 22 + tile_w + gap
    card(d, (x, 100, x + tile_w, 178), 24, TERTIARY_CONTAINER)
    text(d, (x + 18, 118), "Миша", 12, 700, TERTIARY)
    text(d, (x + 18, 166), "22", 34, 800, ON_TERTIARY_CONTAINER, anchor="ls")

    card(d, (btn_x0, 114, btn_x1, 178), 22, PRIMARY)
    heart(d, (btn_x0 + btn_x1) / 2, 146, 30, ON_PRIMARY)
    save(img, "tg_preview_miss_4x2")


def miss_4x1() -> None:
    img, d = canvas(424, 92)
    card(d, (0, 0, 424, 92), 28, PRIMARY)

    circle(d, 42, 46, 22, PRIMARY_DARK)
    text(d, (42, 47), "М", 17, 800, ON_PRIMARY_CONTAINER, anchor="mm")

    text(d, (78, 32), "Скучаю", 16, 700, ON_PRIMARY, anchor="lm")
    text(d, (78, 58), "один тап — и партнёр узнает", 13, 500, PRIMARY_DARK, anchor="lm")
    heart(d, 388, 46, 26, TERTIARY_CONTAINER)
    save(img, "tg_preview_miss_4x1")


# ── Фото-виджеты (2×2) ───────────────────────────────────────────────────────


def photo_frame(d, box, fill, radius=32) -> None:
    """Заглушка фото: тональная заливка, солнце и горы — знак снимка."""
    x0, y0, x1, y1 = box
    card(d, box, radius, fill)
    w, h = x1 - x0, y1 - y0
    ink = "#FFFFFF"

    circle(d, x0 + w * 0.30, y0 + h * 0.34, min(w, h) * 0.075, ink)
    # Две «горы» по нижней трети — силуэт читается даже в мелком размере.
    base = y0 + h * 0.70
    d.polygon(
        [
            ((x0 + w * 0.18) * S, base * S),
            ((x0 + w * 0.42) * S, (base - h * 0.26) * S),
            ((x0 + w * 0.66) * S, base * S),
        ],
        fill=ink,
    )
    d.polygon(
        [
            ((x0 + w * 0.50) * S, base * S),
            ((x0 + w * 0.68) * S, (base - h * 0.18) * S),
            ((x0 + w * 0.86) * S, base * S),
        ],
        fill=ink,
    )


def photo_day() -> None:
    img, d = canvas(200, 200)
    photo_frame(d, (0, 0, 200, 200), SECONDARY_CONTAINER)
    card(d, (14, 158, 152, 186), 14, "#2B2431")
    text(d, (83, 172), "от Миши · 2 ч назад", 12, 700, ON_PRIMARY, anchor="mm")
    save(img, "preview_photo_day")


def self_photo() -> None:
    img, d = canvas(200, 200)
    photo_frame(d, (0, 0, 200, 200), PRIMARY_CONTAINER)
    card(d, (14, 14, 62, 40), 13, PRIMARY)
    text(d, (38, 27), "Я", 12, 800, ON_PRIMARY, anchor="mm")
    save(img, "preview_self_photo")


def partner_photo() -> None:
    img, d = canvas(200, 200)
    photo_frame(d, (0, 0, 200, 200), TERTIARY_CONTAINER)
    card(d, (14, 14, 86, 40), 13, TERTIARY)
    text(d, (50, 27), "Миша", 12, 800, ON_PRIMARY, anchor="mm")
    save(img, "preview_partner_photo")


def photo_grid() -> None:
    img, d = canvas(200, 200)
    card(d, (0, 0, 200, 200), 32, SURFACE)
    tints = [SECONDARY_CONTAINER, TERTIARY_CONTAINER, PRIMARY_CONTAINER, "#E8DEF8"]
    pad, gap = 12, 8
    cell = (200 - pad * 2 - gap) / 2
    for i, tint in enumerate(tints):
        x = pad + (i % 2) * (cell + gap)
        y = pad + (i // 2) * (cell + gap)
        photo_frame(d, (x, y, x + cell, y + cell), tint, radius=18)
    save(img, "preview_photo_grid")


if __name__ == "__main__":
    print("Превью виджетов →", OUT)
    together_2x2()
    together_4x2()
    together_4x4()
    miss_2x2()
    miss_4x2()
    miss_4x1()
    photo_day()
    self_photo()
    partner_photo()
    photo_grid()
    print("готово")
