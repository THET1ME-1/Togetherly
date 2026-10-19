#!/usr/bin/env python3
"""Картинки темы «Хэллоуин»: плитка узора и тыква для кружка ленты палитр.

Рисунки не рисуются заново: это неподвижные кадры хэллоуинского набора из
мастерской значков (`~/Projects/togetherly-badges-hand`, папки `out/` и
`out_gifts/`). Из каждого берётся только контур тушью — тёмные непрозрачные
пиксели — и ложится белой маской. Цвет и силу узору даёт тема
(`ThemePattern.tint` в `lib/theme/app_theme.dart`), поэтому оттенок правится
там числом, без перерисовки файла.

* `assets/images/themes/halloween_pattern.png` — бесшовная плитка 1080×1080
  под плотность 3 (на экране квадрат 360). Шестнадцать предметов шахматным
  порядком, каждый повёрнут на ±18°. Раскладка та же, что в утверждённом
  макете «Б. Узор» (зерно 13), только в полтора раза крупнее: макет держал
  плитку 720 под плотность 2.
* `assets/images/themes/halloween_pumpkin.webp` — тыква целиком, 144 точки:
  кружок в ленте рисуется не крупнее 56 точек.

Запуск из корня проекта:
    python3 tool/gen_halloween_pattern.py [папка мастерской]
"""
import os
import random
import sys

from PIL import Image, ImageChops

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    '~/Projects/togetherly-badges-hand')
OUT = 'assets/images/themes'

# Девять предметов набора, порядок как в макете: от него зависит раскладка.
ITEMS = [('out', 'pumpkin'), ('out', 'bat'), ('out', 'cauldron'),
         ('out', 'spider'), ('out', 'crystalball'), ('out', 'mummy'),
         ('out', 'vampire'), ('out_gifts', 'candybucket'),
         ('out_gifts', 'lantern')]

SCALE = 1.5
TILE, STEP, ITEM = int(720 * SCALE), int(180 * SCALE), int(104 * SCALE)


def still(folder, key):
    return Image.open(f'{SRC}/{folder}/{key}/still.png').convert('RGBA')


def ink(im):
    """Контур тушью белой маской: пиксели темнее 70 при непрозрачности от 40."""
    dark = im.convert('L').point(lambda v: 255 if v < 70 else 0)
    solid = im.getchannel('A').point(lambda a: 255 if a > 40 else 0)
    mask = ImageChops.multiply(dark, solid)
    white = Image.new('L', im.size, 255)
    return Image.merge('RGBA', (white, white, white, mask))


def pattern():
    random.seed(13)
    pool = [ink(still(f, k)) for f, k in ITEMS]
    alpha = Image.new('L', (TILE, TILE), 0)
    cells = TILE // STEP
    for row in range(cells):
        for col in range(cells):
            piece = pool[(row * 4 + col * 3) % len(pool)].copy()
            piece.thumbnail((ITEM, ITEM), Image.LANCZOS)
            piece = piece.rotate(random.uniform(-18, 18),
                                 resample=Image.BICUBIC, expand=True)
            mask = piece.getchannel('A')
            # Сдвиги берутся тем же порядком, что в макете, и растягиваются:
            # так раскладка совпадает с утверждённой картинкой.
            dx = (STEP // 2 if row % 2 else 0) + round(
                random.randint(-10, 10) * SCALE)
            x = col * STEP + dx + (STEP - mask.width) // 2
            y = row * STEP + round(random.randint(-10, 10) * SCALE) + (
                STEP - mask.height) // 2
            # Плитка бесшовная: кусок, вылезший за край, ложится с другой
            # стороны. Маски складываются по максимуму — контуры не темнеют
            # там, где соседи сошлись.
            for wx in (-TILE, 0, TILE):
                for wy in (-TILE, 0, TILE):
                    layer = Image.new('L', (TILE, TILE), 0)
                    layer.paste(mask, (x + wx, y + wy))
                    alpha = ImageChops.lighter(alpha, layer)
    white = Image.new('L', (TILE, TILE), 255)
    return Image.merge('LA', (white, alpha))


def pumpkin():
    im = still('out', 'pumpkin')
    im.thumbnail((144, 144), Image.LANCZOS)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    tile = pattern()
    tile.save(f'{OUT}/halloween_pattern.png', optimize=True)
    pumpkin().save(f'{OUT}/halloween_pumpkin.webp', 'WEBP', quality=90,
                   method=6)
    for name in ('halloween_pattern.png', 'halloween_pumpkin.webp'):
        print(name, os.path.getsize(f'{OUT}/{name}') // 1024, 'КБ')


if __name__ == '__main__':
    main()
