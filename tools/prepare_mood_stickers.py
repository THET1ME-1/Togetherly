#!/usr/bin/env python3
"""Готовит сгенерированные стикеры настроений к укладке в приложение.

Генератор рисует белый кант как придётся: вокруг ушей он есть, вокруг тела
обрывается, ширина гуляет от картинки к картинке. Здесь кант срезается и
рисуется заново — одинаковый по всему периметру и на всех эмоциях сразу.

Что делает:
  * срезает мягкий полупрозрачный край (иначе на тёмной теме сквозь него
    просвечивает фон и читается как серый ободок);
  * обрезает пустые поля и центрирует персонажа;
  * рисует ровный белый кант по всему силуэту;
  * приводит к квадрату и сохраняет webp с прозрачностью.

    python3 tools/prepare_mood_stickers.py raw/ assets/images/mood_packs/bunny/

Имена файлов сохраняются: назовите исходники как ждёт приложение — happy.png,
love.png, и на выходе получите happy.webp, love.webp.
"""
import argparse
import collections
import pathlib

from PIL import Image, ImageFilter

# Ширина белого канта в долях от стороны кадра: 1.8% от 1024 ≈ 18 px.
BORDER = 0.018

# Ниже этого значения альфа считается пустотой. Резкая граница вместо
# растушёвки: полупрозрачный край на тёмной теме даёт грязный ободок.
ALPHA_CUT = 128

# Поле вокруг персонажа, чтобы кант не упирался в край кадра.
MARGIN = 0.04


def drop_background(im: Image.Image) -> Image.Image:
    """Убирает подложку, если картинка пришла без прозрачности.

    Генераторы отдают «прозрачный» фон нарисованной шахматкой: альфа-канала
    нет, вместо него серо-белые клетки. Отличить их от рисунка по яркости
    нельзя — зайка сама белая, и заливка «по светлому» съедает ей тело.

    Поэтому ищем именно СЕРЫЕ клетки: чистый серый (R=G=B) в узкой полосе
    яркости, какого в рисунке нет — там всё либо белое, либо розовое. Найденные
    клетки раздуваем на шаг узора, чтобы прихватить белые клетки между ними, и
    заливаем от краёв только по этой маске.
    """
    im = im.convert("RGBA")
    if im.getchannel("A").getextrema()[0] == 0:
        return im  # прозрачность уже есть

    w, h = im.size
    rgb = im.convert("RGB")
    px = rgb.load()

    # Цвет тёмной клетки берём из угла: он и задаёт полосу поиска.
    cr, cg, cb = px[2, 2]
    if abs(cr - cg) > 6 or abs(cg - cb) > 6:
        return im  # угол цветной — подложки в клетку тут нет

    grey = Image.new("L", im.size, 0)
    gp = grey.load()
    found = 0
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if (
                abs(r - cr) < 7
                and abs(g - cg) < 7
                and abs(b - cb) < 7
                and max(r, g, b) - min(r, g, b) < 6
            ):
                gp[x, y] = 255
                found += 1
    if found < w * h * 0.02:
        return im  # клеток почти нет — подложка не распознана, не трогаем

    # Шаг узора: раздуваем найденные клетки, чтобы слиться с белыми соседями.
    step = max(3, round(min(w, h) * 0.03)) | 1
    spread = grey.filter(ImageFilter.MaxFilter(step))

    seen = bytearray(w * h)
    sp = spread.load()
    stack = []
    for x in range(w):
        for y in (0, h - 1):
            if sp[x, y] and not seen[y * w + x]:
                seen[y * w + x] = 1
                stack.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if sp[x, y] and not seen[y * w + x]:
                seen[y * w + x] = 1
                stack.append((x, y))

    out = im.load()
    while stack:
        x, y = stack.pop()
        out[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and sp[nx, ny]:
                seen[ny * w + nx] = 1
                stack.append((nx, ny))

    # Заливка идёт по раздутой маске и объедает кромку зубцами: часть канта и
    # шерсти попадает под неё. Затягиваем выемки замыканием — расширяем силуэт
    # и тут же сжимаем обратно, так дырки исчезают, а размер остаётся прежним.
    heal = (step // 2) | 1
    alpha = im.getchannel("A")
    alpha = alpha.filter(ImageFilter.MaxFilter(heal)).filter(
        ImageFilter.MinFilter(heal)
    )
    im.putalpha(alpha)
    return im


def hard_alpha(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    im.putalpha(im.getchannel("A").point(lambda a: 255 if a >= ALPHA_CUT else 0))
    return im


def strip_existing_border(im: Image.Image) -> Image.Image:
    """Сжимает силуэт внутрь, срезая кант, нарисованный генератором.

    Съедаем по краю столько же, сколько потом нарисуем сами, — иначе к чужому
    канту добавится наш, и стикер обрастёт двойной каймой.
    """
    px = round(im.width * BORDER)
    if px < 1:
        return im
    alpha = im.getchannel("A").filter(ImageFilter.MinFilter(px * 2 + 1))
    out = im.copy()
    out.putalpha(alpha)
    return out


def trim(im: Image.Image) -> Image.Image:
    box = im.getchannel("A").getbbox()
    return im.crop(box) if box else im


def add_border(im: Image.Image, px: int) -> Image.Image:
    """Рисует белый кант по всему периметру силуэта."""
    pad = px * 2
    canvas = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    canvas.alpha_composite(im, (pad, pad))

    # Расширяем силуэт: получившаяся маска и есть кант.
    spread = canvas.getchannel("A").filter(ImageFilter.MaxFilter(px * 2 + 1))
    border = Image.new("RGBA", canvas.size, (255, 255, 255, 0))
    border.putalpha(spread)
    border_rgb = Image.new("RGBA", canvas.size, (255, 255, 255, 255))
    border_rgb.putalpha(spread)

    out = Image.alpha_composite(border_rgb, canvas)
    return out


def square(im: Image.Image) -> Image.Image:
    side = round(max(im.width, im.height) * (1 + MARGIN * 2))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
    return canvas


def prepare(
    path: pathlib.Path, out_dir: pathlib.Path, size: int, redraw_border: bool
) -> pathlib.Path:
    im = drop_background(Image.open(path))
    im = hard_alpha(im)
    if redraw_border:
        # Кант рвётся у ног или на теле — срезаем чужой и рисуем ровный.
        im = strip_existing_border(im)
        im = trim(im)
        im = add_border(im, round(max(im.size) * BORDER))
    else:
        im = trim(im)
    im = square(im)
    im = im.resize((size, size), Image.LANCZOS)

    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{path.stem}.webp"
    im.save(out, "WEBP", quality=92, method=6, lossless=False)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=pathlib.Path, help="папка с исходниками")
    ap.add_argument("dst", type=pathlib.Path, help="куда класть готовые webp")
    ap.add_argument("--size", type=int, default=512, help="сторона кадра, px")
    ap.add_argument(
        "--redraw-border",
        action="store_true",
        help="срезать кант генератора и нарисовать свой (когда он рвётся)",
    )
    args = ap.parse_args()

    files = sorted(
        p for p in args.src.iterdir() if p.suffix.lower() in {".png", ".webp"}
    )
    if not files:
        raise SystemExit(f"в {args.src} нет картинок")

    for p in files:
        out = prepare(p, args.dst, args.size, args.redraw_border)
        print(f"{p.name} → {out.name}")
    print(f"готово: {len(files)} шт., {args.size}×{args.size}")


if __name__ == "__main__":
    main()
