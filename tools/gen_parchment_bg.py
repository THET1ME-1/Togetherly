# -*- coding: utf-8 -*-
"""Сгенерировать тёплую текстуру «старой бумаги/пергамента» для темы parchment.

Фон делается светлым (карточки/текст приложения остаются читаемыми):
тёплый кремовый базовый тон + крупные сепия-разводы + мелкое волокно бумаги
+ лёгкая виньетка по краям (эффект состаренного листа).

Запуск из корня репо:  python tools/gen_parchment_bg.py
"""
import os
import random
import math
from PIL import Image, ImageDraw, ImageFilter

random.seed(20260607)

W, H = 1080, 1920
DST = os.path.join("assets", "images", "wallpapers")
os.makedirs(DST, exist_ok=True)

# ── Базовый кремовый тон ─────────────────────────────────────────────────────
base = Image.new("RGB", (W, H), (238, 224, 192))

# ── Крупные сепия-разводы (low-frequency mottling) ───────────────────────────
small = Image.new("L", (W // 16, H // 16))
sp = small.load()
for y in range(small.height):
    for x in range(small.width):
        sp[x, y] = random.randint(90, 165)
mottle = small.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(20))

# Тонируем разводы тёплой сепией поверх базового тона.
base_px = base.load()
mot_px = mottle.load()
for y in range(H):
    for x in range(W):
        m = mot_px[x, y] / 255.0           # 0.35..0.65 примерно
        r, g, b = base_px[x, y]
        # темнее развод → теплее/коричневее
        k = 0.78 + 0.22 * m
        r = int(r * k)
        g = int(g * (k - 0.02))
        b = int(b * (k - 0.06))            # меньше синего = теплее
        base_px[x, y] = (r, g, b)

# ── Мелкое волокно бумаги (high-frequency grain) ─────────────────────────────
grain = Image.new("L", (W, H))
gp = grain.load()
for y in range(H):
    for x in range(W):
        gp[x, y] = random.randint(118, 138)
grain = grain.filter(ImageFilter.GaussianBlur(0.4))
gp = grain.load()
for y in range(H):
    for x in range(W):
        d = (gp[x, y] - 128) * 0.35        # ±~3 уровня
        r, g, b = base_px[x, y]
        base_px[x, y] = (
            max(0, min(255, int(r + d))),
            max(0, min(255, int(g + d))),
            max(0, min(255, int(b + d * 0.9))),
        )

# ── Несколько еле заметных пятен (foxing) ────────────────────────────────────
spots = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sd = ImageDraw.Draw(spots)
for _ in range(40):
    cx, cy = random.randint(0, W), random.randint(0, H)
    rr = random.randint(20, 80)
    a = random.randint(8, 22)
    sd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(150, 110, 60, a))
spots = spots.filter(ImageFilter.GaussianBlur(18))
base = Image.alpha_composite(base.convert("RGBA"), spots).convert("RGB")
base_px = base.load()

# ── Виньетка (состаренные тёмные края) ───────────────────────────────────────
cx, cy = W / 2, H / 2
maxd = math.hypot(cx, cy)
for y in range(H):
    for x in range(W):
        d = math.hypot(x - cx, y - cy) / maxd
        v = 1.0 - 0.16 * (d ** 2.2)        # до -16% яркости в углах
        r, g, b = base_px[x, y]
        base_px[x, y] = (int(r * v), int(g * v), int(b * v))

out = os.path.join(DST, "parchment.webp")
base.save(out, "WEBP", quality=85, method=6)
print("OK  parchment.webp  %6.1f KB  (%dx%d)" % (os.path.getsize(out) / 1024, W, H))
