"""Карточка с QR на страницу розыгрыша.

Модули рисуются кругами со связками к соседям — «пилюльный» рисунок читается
сканером так же, как квадратный, а выглядит мягче. Глаза (три угловых знака)
рисуются отдельно, иначе связки превратили бы их в кляксу.

Уровень коррекции H: 30% символа можно закрыть, поэтому иконка в центре
сканированию не мешает. Держим её в пределах 9 модулей из 33 — это 7% площади.
"""
import sys
sys.path.insert(0, 'libs')

import segno
from PIL import Image, ImageDraw, ImageFont, ImageFilter

URL = 'https://togetherly.day/club/?s=qr'
ICON = '/home/alelx/Projects/GitHub/Togetherly/docs/branding/app-icon-512.png'
S = 3                      # супер-сэмплинг: рисуем крупно, потом уменьшаем
M = 24 * S                 # сторона модуля
QUIET = 4                  # тихая зона в модулях

F_TITLE = 'unbounded-800.ttf'
F_BOLD = 'onest-700.ttf'
F_TEXT = 'onest-500.ttf'


def font(path, size):
    return ImageFont.truetype(path, size * S)


def rounded(draw, box, r, fill):
    draw.rounded_rectangle(box, radius=r, fill=fill)


def qr_layer(matrix, n):
    """Маска модулей: круги плюс связки к соседям справа и снизу."""
    side = (n + QUIET * 2) * M
    mask = Image.new('L', (side, side), 0)
    d = ImageDraw.Draw(mask)

    def dark(r, c):
        return 0 <= r < n and 0 <= c < n and matrix[r][c]

    def eye(r, c):
        # три угловых знака рисуем отдельно
        return ((r < 7 and c < 7) or (r < 7 and c >= n - 7) or (r >= n - 7 and c < 7))

    rad = M * 0.5
    for r in range(n):
        for c in range(n):
            if not matrix[r][c] or eye(r, c):
                continue
            x = (c + QUIET) * M + M / 2
            y = (r + QUIET) * M + M / 2
            d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=255)
            if dark(r, c + 1) and not eye(r, c + 1):
                d.rectangle([x, y - rad, x + M, y + rad], fill=255)
            if dark(r + 1, c) and not eye(r + 1, c):
                d.rectangle([x - rad, y, x + rad, y + M], fill=255)

    # угловые знаки: скруглённая рамка и зрачок
    for (r0, c0) in ((0, 0), (0, n - 7), (n - 7, 0)):
        x0 = (c0 + QUIET) * M
        y0 = (r0 + QUIET) * M
        outer = [x0, y0, x0 + 7 * M, y0 + 7 * M]
        rounded(d, outer, M * 0.8, 255)
        inner = [x0 + M, y0 + M, x0 + 6 * M, y0 + 6 * M]
        rounded(d, inner, M * 0.4, 0)
        pupil = [x0 + 2 * M, y0 + 2 * M, x0 + 5 * M, y0 + 5 * M]
        rounded(d, pupil, M * 0.6, 255)
    return mask


def gradient(size, c1, c2):
    w, h = size
    g = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(g)
    for i in range(h):
        t = i / max(h - 1, 1)
        d.line([(0, i), (w, i)], fill=tuple(round(a + (b - a) * t) for a, b in zip(c1, c2)))
    return g


def watermark(canvas, text, color, alpha):
    """Бледная строка, повторённая по диагонали, — знак, что карточка наша."""
    w, h = canvas.size
    layer = Image.new('RGBA', (w * 2, h * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = font(F_BOLD, 22)
    step_x, step_y = 300 * S, 150 * S
    for y in range(0, h * 2, step_y):
        for x in range(0, w * 2, step_x):
            d.text((x, y), text, font=f, fill=color + (alpha,))
    layer = layer.rotate(-28, resample=Image.BICUBIC, center=(w, h))
    canvas.alpha_composite(layer.crop((w // 2, h // 2, w // 2 + w, h // 2 + h)))


def card(style):
    q = segno.make(URL, error='h', boost_error=True)
    matrix = [[1 if v else 0 for v in row] for row in q.matrix]
    n = len(matrix)

    qr_side = (n + QUIET * 2) * M
    pad = 54 * S
    top = 150 * S
    bottom = 250 * S
    W = qr_side + pad * 2
    H = top + qr_side + bottom

    if style == 'light':
        bg1, bg2 = (255, 244, 245), (255, 223, 229)
        plate = (255, 255, 255)
        mod1, mod2 = (255, 77, 66), (255, 46, 154)
        ink, dim = (34, 25, 26), (130, 105, 110)
        wm_color, wm_alpha = (255, 120, 140), 26
        accent = (255, 46, 154)
    else:
        bg1, bg2 = (18, 10, 12), (32, 12, 24)
        # код держим прямой полярности на светлой плашке: инверсию
        # читают не все сканеры, а печать её и вовсе не любит
        plate = (255, 255, 255)
        mod1, mod2 = (255, 46, 154), (108, 43, 217)
        ink, dim = (244, 238, 246), (169, 155, 176),
        wm_color, wm_alpha = (182, 255, 60), 20
        accent = (182, 255, 60)

    canvas = gradient((W, H), bg1, bg2).convert('RGBA')
    watermark(canvas, 'togetherly', wm_color, wm_alpha)
    d = ImageDraw.Draw(canvas)

    # шапка карточки
    f_kicker = font(F_BOLD, 15)
    kicker = 'PLAY BOY’S PARTY × TOGETHERLY'
    d.text((W / 2, 46 * S), kicker, font=f_kicker, fill=accent, anchor='mm')
    f_head = font(F_TITLE, 31)
    d.text((W / 2, 92 * S), 'Три Togetherly+', font=f_head, fill=ink, anchor='mm')

    # плашка под кодом
    rounded(d, [pad - 18 * S, top - 18 * S, W - pad + 18 * S, top + qr_side + 18 * S],
            44 * S, plate)

    mask = qr_layer(matrix, n)
    grad = gradient((qr_side, qr_side), mod1, mod2)
    canvas.paste(grad, (pad, top), mask)

    # метка в центре: иконка приложения на своей подложке
    hole = 9 * M
    cx, cy = pad + qr_side / 2, top + qr_side / 2
    rounded(d, [cx - hole / 2, cy - hole / 2, cx + hole / 2, cy + hole / 2], hole * 0.29, plate)
    icon_side = int(hole * 0.78)
    icon = Image.open(ICON).convert('RGBA').resize((icon_side, icon_side), Image.LANCZOS)
    r_mask = Image.new('L', (icon_side, icon_side), 0)
    ImageDraw.Draw(r_mask).rounded_rectangle([0, 0, icon_side, icon_side],
                                             radius=int(icon_side * 0.27), fill=255)
    canvas.paste(icon, (int(cx - icon_side / 2), int(cy - icon_side / 2)), r_mask)

    # подпись под кодом
    base = top + qr_side + 52 * S
    d.text((W / 2, base), 'togetherly.day/club', font=font(F_TITLE, 26), fill=ink, anchor='mm')
    d.text((W / 2, base + 52 * S), 'Наведи камеру — участвуй в розыгрыше',
           font=font(F_TEXT, 19), fill=dim, anchor='mm')
    d.text((W / 2, base + 92 * S), 'Scanează și participă la concurs',
           font=font(F_TEXT, 19), fill=dim, anchor='mm')
    d.text((W / 2, base + 148 * S), 'SKAL CLUB · 19.09 · 22:00',
           font=font(F_BOLD, 16), fill=accent, anchor='mm')

    out = canvas.convert('RGB').resize((W // S, H // S), Image.LANCZOS)
    name = f'qr-club-{style}.png'
    out.save(name, optimize=True)
    return name, out.size


for style in ('light', 'dark'):
    print(*card(style))
