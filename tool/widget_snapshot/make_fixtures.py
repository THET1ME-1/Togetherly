#!/usr/bin/env python3
"""Данные для снимка парного виджета на симуляторе (ios-widget-snapshot.yml).

photo.jpg — обычное фото: синее поле с белым кругом (контроль стенда).
sheet.webp — раскадровка живого фото как у сервера (`tools/widget_anim.py`):
6×3 клеток по 300 px, кадр N залит своим цветом и подписан полосами. Кадр 0
красный: по цвету середины снимка видно, что виджет вырезал именно первую
клетку, а не ужал весь лист.
manifest.json — манифест той же формы, что отдаёт сервер.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

out = sys.argv[1] if len(sys.argv) > 1 else 'fixtures'
os.makedirs(out, exist_ok=True)

COLS, ROWS, CELL = 6, 3, 300
COLORS = [
    (220, 40, 40), (240, 140, 30), (230, 200, 40), (80, 180, 80), (40, 160, 200), (60, 80, 200),
    (140, 70, 200), (200, 60, 160), (120, 120, 120), (30, 30, 30), (250, 250, 250), (100, 60, 30),
    (0, 120, 120), (180, 220, 120), (255, 180, 200), (90, 0, 0), (0, 0, 90), (200, 200, 255),
]

sheet = Image.new('RGB', (COLS * CELL, ROWS * CELL), (0, 0, 0))
d = ImageDraw.Draw(sheet)
for i, c in enumerate(COLORS):
    x, y = (i % COLS) * CELL, (i // COLS) * CELL
    d.rectangle([x, y, x + CELL - 1, y + CELL - 1], fill=c)
    # номер кадра полосками у верхнего края: i+1 белых полос
    for k in range(i + 1):
        d.rectangle([x + 10 + k * 15, y + 10, x + 18 + k * 15, y + 50], fill=(255, 255, 255))
sheet.save(os.path.join(out, 'sheet.webp'), 'WEBP', quality=90)

photo = Image.new('RGB', (900, 900), (30, 70, 200))
ImageDraw.Draw(photo).ellipse([250, 250, 650, 650], fill=(255, 255, 255))
photo.save(os.path.join(out, 'photo.jpg'), 'JPEG', quality=90)

manifest = {'cols': COLS, 'rows': ROWS, 'cell': CELL, 'frames': 18, 'step_ms': 83, 'source': 'video'}
with open(os.path.join(out, 'manifest.json'), 'w') as f:
    json.dump(manifest, f)
print('готово:', sorted(os.listdir(out)))
