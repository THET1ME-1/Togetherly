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

import math

from PIL import Image, ImageDraw, ImageFont, ImageColor

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



def halftone(d, box, color, opacity=0.55):
    """Растр точками: радиус растёт к правому нижнему углу.

    Те же числа, что у виджета (`TogetherTrackSpec`): шаг 15, крупнейшая
    точка 5.2, проявляются с 0.18 доли пути до дальнего угла.
    """
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    far = math.hypot(w, h)
    step, max_r = 15, 5.2
    r_, g_, b_ = ImageColor.getrgb(color)
    y = step / 2
    while y < h:
        x = step / 2
        while x < w:
            t = math.hypot(x, y) / far
            r = (t - 0.18) * max_r
            if r >= 0.5:
                d.ellipse(
                    [((x0 + x - r) * S, (y0 + y - r) * S),
                     ((x0 + x + r) * S, (y0 + y + r) * S)],
                    fill=(r_, g_, b_, int(255 * opacity)),
                )
            x += step
        y += step


def track_line(d, x0, x1, y, percent, track, fill, ring, has_prev, mid_stop):
    """Дорожка вех: линия, пройденная часть и отметки."""
    d.line([(x0 * S, y * S), (x1 * S, y * S)], fill=track, width=int(5 * S))
    here = x0 + (x1 - x0) * percent / 100
    d.line([(x0 * S, y * S), (here * S, y * S)], fill=fill, width=int(5 * S))
    circle(d, x0, y, 6, fill if has_prev else track)
    if mid_stop:
        circle(d, (x0 + x1) / 2, y, 6, track)
    circle(d, x1, y, 6, track)
    circle(d, here, y, 9.5, ring)
    circle(d, here, y, 7, fill)


# ── 01 «Вместе» ──────────────────────────────────────────────────────────────


def together_2x2() -> None:
    img, d = canvas(200, 200)
    card(d, (0, 0, 200, 200), 32, PRIMARY)
    halftone(d, (0, 0, 200, 200), PRIMARY_DARK)

    circle(d, 32, 32, 15, PRIMARY_DARK, outline=PRIMARY, width=2)
    text(d, (32, 33), "А", 12, 800, ON_PRIMARY_CONTAINER, anchor="mm")
    circle(d, 54, 32, 15, TERTIARY_CONTAINER, outline=PRIMARY, width=2)
    text(d, (54, 33), "М", 12, 800, ON_TERTIARY_CONTAINER, anchor="mm")

    text(d, (18, 106), "205", 48, 800, ON_PRIMARY, anchor="ls")
    text(d, (18, 126), "дней вместе", 14, 600, CAPTION_ON_PRIMARY, anchor="ls")
    text(d, (18, 156), "300 дней · через 95", 12, 700, CAPTION_ON_PRIMARY, anchor="ls")
    track_line(d, 24, 176, 176, 52, PRIMARY_DARK, ON_PRIMARY, PRIMARY, True, False)
    save(img, "tg_preview_together_2x2")
def together_4x2() -> None:
    img, d = canvas(424, 200)
    card(d, (0, 0, 424, 200), 32, PRIMARY)
    halftone(d, (0, 0, 424, 200), PRIMARY_DARK)

    text(d, (22, 76), "205", 52, 800, ON_PRIMARY, anchor="ls")
    w = d.textlength("205", font=font(52, 800)) / S
    text(d, (22 + w + 10, 76), "дней вместе", 16, 700, CAPTION_ON_PRIMARY, anchor="ls")
    text(d, (22, 98), "С 1 ноября 2025", 13, 600, CAPTION_ON_PRIMARY)

    circle(d, 368, 40, 15, PRIMARY_DARK, outline=PRIMARY, width=2)
    text(d, (368, 41), "А", 12, 800, ON_PRIMARY_CONTAINER, anchor="mm")
    circle(d, 390, 40, 15, TERTIARY_CONTAINER, outline=PRIMARY, width=2)
    text(d, (390, 41), "М", 12, 800, ON_TERTIARY_CONTAINER, anchor="mm")

    track_line(d, 30, 386, 150, 52, PRIMARY_DARK, ON_PRIMARY, PRIMARY, True, True)
    text(d, (22, 168), "200 дней", 13, 700, CAPTION_ON_PRIMARY)
    text(d, (212, 168), "300 дней · через 95", 13, 700, ON_PRIMARY, anchor="ma")
    text(d, (394, 168), "1 год", 13, 700, CAPTION_ON_PRIMARY, anchor="ra")
    save(img, "tg_preview_together_4x2")
def together_4x4() -> None:
    img, d = canvas(424, 424)
    card(d, (0, 0, 424, 424), 36, SURFACE)
    halftone(d, (0, 0, 424, 424), TRACK_ON_CONTAINER)

    text(d, (24, 26), "АНЯ + МИША", 13, 800, ON_SURFACE_VARIANT)
    circle(d, 368, 33, 14, PRIMARY_DARK)
    text(d, (368, 34), "А", 11, 800, ON_PRIMARY_CONTAINER, anchor="mm")
    circle(d, 390, 33, 14, TERTIARY_CONTAINER)
    text(d, (390, 34), "М", 11, 800, ON_TERTIARY_CONTAINER, anchor="mm")

    text(d, (24, 118), "205", 68, 800, ON_SURFACE, anchor="ls")
    w = d.textlength("205", font=font(68, 800)) / S
    text(d, (24 + w + 12, 104), "дней вместе", 16, 700, ON_SURFACE_VARIANT, anchor="ls")
    text(d, (24 + w + 12, 122), "с 1 ноября 2025", 13, 600, OUTLINE, anchor="ls")

    rows = [
        ("200 дней", "Прошли 20 мая", ON_SURFACE, ON_SURFACE_VARIANT),
        ("Сегодня", "52% пути до 300 дней", ON_SURFACE, ON_SURFACE_VARIANT),
        ("300 дней", "через 95 дней", ON_SURFACE, ON_SURFACE_VARIANT),
        ("1 год", "1 ноября", ON_SURFACE, TERTIARY),
    ]
    top, bottom = 170, 390
    ys = [top + (bottom - top) * (i + 0.5) / len(rows) for i in range(len(rows))]
    d.line([(40 * S, ys[0] * S), (40 * S, ys[-1] * S)], fill=TRACK_ON_CONTAINER, width=int(4 * S))
    d.line([(40 * S, ys[0] * S), (40 * S, ys[1] * S)], fill=PRIMARY, width=int(4 * S))
    for i, (title, sub, c1, c2) in enumerate(rows):
        if i == 1:
            circle(d, 40, ys[i], 9.5, SURFACE)
            circle(d, 40, ys[i], 7, PRIMARY)
        elif i == len(rows) - 1:
            circle(d, 40, ys[i], 7, TERTIARY_CONTAINER)
        else:
            circle(d, 40, ys[i], 7, PRIMARY if i < 1 else TRACK_ON_CONTAINER)
        text(d, (62, ys[i] - 13), title, 15, 700, c1)
        text(d, (62, ys[i] + 3), sub, 12, 600, c2)
    save(img, "tg_preview_together_4x4")
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


# ── 05 «Настроение» ──────────────────────────────────────────────────────────


def mood_2x2() -> None:
    img, d = canvas(200, 200)
    card(d, (0, 0, 200, 200), 32, SURFACE)

    text(d, (18, 20), "СЕГОДНЯ", 11, 800, ON_SURFACE_VARIANT)

    circle(d, 23, 62, 5, PRIMARY)
    text(d, (34, 62), "Я · спокойно", 12, 700, ON_SURFACE, anchor="lm")
    circle(d, 23, 84, 5, TERTIARY)
    text(d, (34, 84), "Миша · устал", 12, 700, ON_SURFACE, anchor="lm")

    # Три кнопки выбора: активная — контейнерная.
    pad, gap = 18, 6
    w = (200 - pad * 2 - gap * 2) / 3
    for i in range(3):
        x = pad + i * (w + gap)
        active = i == 1
        card(d, (x, 148, x + w, 180), 14,
             PRIMARY_CONTAINER if active else SURFACE_CONTAINER)
        ink = ON_PRIMARY_CONTAINER if active else ON_SURFACE_VARIANT
        cx, cy = x + w / 2, 164
        circle(d, cx, cy, 8, ink)
        circle(d, cx, cy, 6, PRIMARY_CONTAINER if active else SURFACE_CONTAINER)
        circle(d, cx - 2.4, cy - 1.6, 1.1, ink)
        circle(d, cx + 2.4, cy - 1.6, 1.1, ink)
    save(img, "tg_preview_mood_2x2")


def mood_4x2() -> None:
    img, d = canvas(424, 200)
    card(d, (0, 0, 424, 200), 32, SURFACE)

    text(d, (22, 24), "НЕДЕЛЯ НАСТРОЕНИЙ", 11, 800, ON_SURFACE_VARIANT)
    text(d, (402, 25), "совпало 5 из 7", 11, 700, OUTLINE, anchor="ra")

    mine = [58, 72, 40, 86, 64, 94, 52]
    partner = [46, 78, 36, 92, 58, 88, 34]
    top, bottom = 66, 150
    zone = bottom - top
    day_gap, bar_gap = 9, 3
    day_w = (424 - 44 - day_gap * 6) / 7
    bar_w = (day_w - bar_gap) / 2

    for i in range(7):
        left = 22 + i * (day_w + day_gap)
        for j, (vals, color) in enumerate(((mine, PRIMARY), (partner, TERTIARY))):
            x = left + j * (bar_w + bar_gap)
            h = zone * vals[i] / 100
            card(d, (x, bottom - h, x + bar_w, bottom), int(bar_w / 2.4), color)
        text(d, (left + day_w / 2, 166), "пнвтсрчтптсбвс"[i * 2:i * 2 + 2],
             10, 700, OUTLINE, anchor="ma")
    save(img, "tg_preview_mood_4x2")


# ── 06 «До встречи» ──────────────────────────────────────────────────────────


def countdown_2x2() -> None:
    img, d = canvas(200, 200)
    card(d, (0, 0, 200, 200), 32, TERTIARY_CONTAINER)

    text(d, (18, 20), "Аэропорт · 8 августа", 11, 700, TERTIARY)
    text(d, (18, 138), "12", 44, 800, ON_TERTIARY_CONTAINER, anchor="ls")
    text(d, (18, 158), "дней до встречи", 11, 700, ON_TERTIARY_CONTAINER, anchor="ls")
    save(img, "tg_preview_countdown_2x2")


def countdown_4x2() -> None:
    img, d = canvas(424, 200)
    card(d, (0, 0, 424, 200), 32, SURFACE)

    text(d, (22, 26), "Встречаемся в Тбилиси", 13, 800, ON_SURFACE)
    card(d, (340, 20, 402, 42), 11, TERTIARY_CONTAINER)
    text(d, (371, 31), "8 АВГ", 10, 800, ON_TERTIARY_CONTAINER, anchor="mm")

    tiles = (("12", "дней", PRIMARY_CONTAINER, ON_PRIMARY_CONTAINER, PRIMARY_ALT),
             ("6", "часов", SURFACE_CONTAINER, ON_SURFACE, ON_SURFACE_VARIANT),
             ("42", "минут", SURFACE_CONTAINER, ON_SURFACE, ON_SURFACE_VARIANT))
    gap = 8
    w = (424 - 44 - gap * 2) / 3
    for i, (value, label, bg, fg, sub) in enumerate(tiles):
        x = 22 + i * (w + gap)
        card(d, (x, 56, x + w, 140), 22, bg)
        text(d, (x + w / 2, 92), value, 24, 800, fg, anchor="mm")
        text(d, (x + w / 2, 120), label, 10, 700, sub, anchor="mm")

    card(d, (22, 156, 402, 172), 8, "#E8DEF8")
    card(d, (22, 156, 22 + (402 - 22) * 0.74, 172), 8, PRIMARY)
    save(img, "tg_preview_countdown_4x2")


# ── 07 «Кольцо года» и «Календарь лет» ───────────────────────────────────────

TRACK_ON_SURFACE = "#E8DEF8"


def months_grid(d, x, y, filled, rows, dot, gap, past, current, future) -> None:
    """Сетка месяцев: двенадцать колонок, ряд — год."""
    for row in range(rows):
        for col in range(12):
            i = row * 12 + col
            color = past if i < filled else current if i == filled else future
            cx = x + col * (dot + gap) + dot / 2
            cy = y + row * (dot + gap) + dot / 2
            circle(d, cx, cy, dot / 2, color)


# Превью «Кольца года» рисует test/goldens/year_ring_preview_png.dart тем же
# виджетом, что и каталог приложения: с 14.09.2026 раскладка одна на все места.


def grid_2x2() -> None:
    img, d = canvas(200, 200)
    card(d, (0, 0, 200, 200), 32, SURFACE)
    d.rounded_rectangle(
        (S, S, 199 * S, 199 * S), radius=32 * S, outline=TRACK_ON_SURFACE, width=S,
    )

    months_grid(d, 20, 20, 68, 6, 8, 4, PRIMARY, TERTIARY, TRACK_ON_SURFACE)
    text(d, (20, 148), "2126", 46, 800, ON_SURFACE, anchor="ls")
    text(d, (20, 166), "дней вместе", 13, 800, PRIMARY, anchor="ls")
    text(d, (20, 182), "6-й год · ещё 355", 11, 800, ON_SURFACE_VARIANT, anchor="ls")
    save(img, "tg_preview_grid_2x2")


def grid_4x2() -> None:
    img, d = canvas(424, 200)
    card(d, (0, 0, 424, 200), 32, SURFACE)
    d.rounded_rectangle(
        (S, S, 423 * S, 199 * S), radius=32 * S, outline=TRACK_ON_SURFACE, width=S,
    )

    text(d, (24, 76), "2126", 54, 800, ON_SURFACE, anchor="ls")
    text(d, (150, 76), "дней", 16, 800, ON_SURFACE_VARIANT, anchor="ls")
    text(d, (400, 40), "5 ЛЕТ 10 ДНЕЙ", 12, 800, PRIMARY, anchor="ra")
    text(d, (400, 58), "с 30.09.2020", 12, 800, ON_SURFACE_VARIANT, anchor="ra")

    months_grid(d, 24, 104, 68, 6, 9, 5, PRIMARY, TERTIARY, TRACK_ON_SURFACE)

    card(d, (330, 108, 400, 172), 20, SURFACE_CONTAINER)
    text(d, (365, 132), "355", 21, 800, PRIMARY, anchor="mm")
    text(d, (365, 154), "до 6 лет", 11, 800, ON_SURFACE_VARIANT, anchor="mm")
    save(img, "tg_preview_grid_4x2")


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


def note_card(w: int, h: int, name: str, lines: list[str], big: bool = False) -> None:
    """Заметка в стиле M3: тональная карточка, чип с листиком, подпись автора."""
    img, d = canvas(w, h)
    card(d, (0, 0, w, h), 32, SURFACE_CONTAINER)

    # Чип с иконкой листика и надпись раздела.
    circle(d, 30, 32, 13, PRIMARY_CONTAINER)
    d.rounded_rectangle(
        [(24 * S, 26 * S), (36 * S, 39 * S)], radius=2 * S, fill=ON_PRIMARY_CONTAINER)
    text(d, (50, 26), "ЗАМЕТКА", 10, 800, ON_SURFACE_VARIANT)

    y = 56
    for line in lines:
        text(d, (20, y), line, 14 if not big else 15, 700, ON_SURFACE)
        y += 22

    # Подпись: точка-аватар и «кто · когда».
    circle(d, 27, h - 24, 7, TERTIARY_CONTAINER)
    text(d, (40, h - 30), "Саша · 12:40", 10, 700, ON_SURFACE_VARIANT)

    # Карандаш в углу.
    circle(d, w - 28, h - 28, 15, PRIMARY)
    d.line(
        [((w - 34) * S, (h - 22) * S), ((w - 22) * S, (h - 34) * S)],
        fill=ON_PRIMARY, width=3 * S)
    save(img, name)


def note_2x2() -> None:
    note_card(200, 200, "tg_preview_note_2x2", ["Купи молоко", "и что-нибудь", "к чаю 🙂"])


def note_4x2() -> None:
    note_card(
        424, 200, "tg_preview_note_4x2",
        ["Купи молоко и что-нибудь к чаю.", "Вечером посмотрим то кино."])


def note_4x4() -> None:
    note_card(
        424, 424, "tg_preview_note_4x4",
        [
            "Список на выходные:",
            "— забрать посылку",
            "— заехать к твоим",
            "— купить корм коту",
        ],
        big=True,
    )


# ── «Маскот на столе» ────────────────────────────────────────────────────────

MASCOT_FRAME = ROOT / "tools/assets/mascot_preview_frame.png"


def mascot(img: Image.Image, cx: int, cy: int, side: int) -> None:
    """Кадр персонажа в превью: увеличение только целым числом и без фильтра.

    Дробный масштаб и сглаживание мылят пиксель-арт — то же правило держат и
    виджет, и приложение.
    """
    src = Image.open(MASCOT_FRAME).convert("RGBA")
    k = max(1, int(side * S) // src.width)
    big = src.resize((src.width * k, src.height * k), Image.NEAREST)
    img.alpha_composite(big, (int(cx * S - big.width / 2), int(cy * S - big.height / 2)))


def pill(d, box, radius, fill, label, size, weight, ink):
    card(d, box, radius, fill)
    text(d, ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2 + 1), label, size, weight, ink, anchor="mm")


def mascot_4x1() -> None:
    img, d = canvas(424, 92)
    card(d, (0, 0, 424, 92), 28, PRIMARY_CONTAINER)
    mascot(img, 46, 46, 44)
    text(d, (80, 34), "Пудя", 16, 800, ON_SURFACE, anchor="lm")
    text(d, (80, 58), "подросток · до взрослого 18 дней", 12, 600, ON_SURFACE_VARIANT, anchor="lm")
    text(d, (404, 36), "12", 26, 800, ON_PRIMARY_CONTAINER, anchor="rm")
    text(d, (404, 62), "дней серии", 11, 600, ON_SURFACE_VARIANT, anchor="rm")
    save(img, "tg_preview_mascot_4x1")


def mascot_2x2() -> None:
    img, d = canvas(200, 200)
    card(d, (0, 0, 200, 200), 32, SURFACE_CONTAINER)
    text(d, (16, 26), "Пудя", 13, 800, ON_SURFACE, anchor="lm")
    pill(d, (126, 16, 184, 38), 11, TERTIARY_CONTAINER, "подросток", 10, 700, ON_TERTIARY_CONTAINER)
    mascot(img, 100, 108, 86)
    card(d, (16, 160, 184, 168), 4, TRACK_ON_CONTAINER)
    card(d, (16, 160, 83, 168), 4, PRIMARY)
    text(d, (16, 182), "до взрослого 18 дней", 10, 600, ON_SURFACE_VARIANT, anchor="lm")
    save(img, "tg_preview_mascot_2x2")


def mascot_4x2() -> None:
    img, d = canvas(424, 200)
    card(d, (0, 0, 424, 200), 32, SURFACE_CONTAINER)
    card(d, (16, 16, 168, 184), 22, PRIMARY_CONTAINER)
    mascot(img, 92, 100, 104)
    text(d, (190, 62), "Пудя", 21, 800, ON_SURFACE, anchor="lm")
    text(d, (190, 88), "подросток · 12 дней серии", 13, 600, ON_SURFACE_VARIANT, anchor="lm")
    card(d, (190, 120, 404, 128), 4, TRACK_ON_CONTAINER)
    card(d, (190, 120, 276, 128), 4, PRIMARY)
    text(d, (190, 146), "до взрослого 18 дней", 12, 600, ON_SURFACE_VARIANT, anchor="lm")
    save(img, "tg_preview_mascot_4x2")


def mascot_4x4() -> None:
    img, d = canvas(424, 424)
    card(d, (0, 0, 424, 424), 32, SURFACE_CONTAINER)
    card(d, (14, 14, 410, 268), 24, PRIMARY_CONTAINER)
    card(d, (14, 200, 410, 268), 24, TRACK_ON_CONTAINER)
    mascot(img, 212, 126, 150)
    pill(d, (30, 30, 156, 58), 14, SURFACE, "Пудя · подросток", 12, 700, ON_SURFACE)
    pill(d, (268, 30, 394, 58), 14, TERTIARY_CONTAINER, "не спит до 23:00", 11, 700, ON_TERTIARY_CONTAINER)

    tiles = [("12", "дней серии"), ("", "до взрослого 18"), ("64", "рекорд")]
    w = (424 - 28 - 16) / 3
    for i, (value, label) in enumerate(tiles):
        x = 14 + i * (w + 8)
        card(d, (x, 284, x + w, 410), 18, PRIMARY_CONTAINER)
        cx = x + w / 2
        if value:
            text(d, (cx, 330), value, 24, 800, ON_PRIMARY_CONTAINER, anchor="mm")
        else:
            card(d, (x + 18, 326, x + w - 18, 334), 4, TRACK_ON_CONTAINER)
            card(d, (x + 18, 326, x + 18 + (w - 36) * 0.22, 334), 4, PRIMARY)
        text(d, (cx, 364), label, 10, 600, ON_SURFACE_VARIANT, anchor="mm")
    save(img, "tg_preview_mascot_4x4")


if __name__ == "__main__":
    print("Превью виджетов →", OUT)
    together_2x2()
    together_4x2()
    together_4x4()
    miss_2x2()
    miss_4x2()
    miss_4x1()
    mood_2x2()
    mood_4x2()
    countdown_2x2()
    countdown_4x2()
    grid_2x2()
    grid_4x2()
    photo_day()
    self_photo()
    partner_photo()
    photo_grid()
    note_2x2()
    note_4x2()
    note_4x4()
    mascot_4x1()
    mascot_2x2()
    mascot_4x2()
    mascot_4x4()
    print("готово")
