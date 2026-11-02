# Рисунок Ту для иконки приложения: тот же вектор, что в мастерской значков
# (togetherly-badges-hand, mascot.js), с двумя правками из hearts.js — зрачки
# заменены чёрными сердечками, рта нет. Поза: поворот и наклон влево-вверх.
#
#   python3 render_tu_hearts.py '[[37.0,48.4,4.2,-12],[52.4,46.4,4.8,4]]' 0 \
#     "framer(1,(tt)=>blobScene('b',{mood:'calm',yaw:-0.24,pitch:-0.12,lean:-0.07,lx:-3.2,ly:-1.6,fx:-0.6,open:1,dx:-2,dy:-1}))"
#
# Первый аргумент — сердечки [x, y, размер, поворот] в координатах лица Ту,
# второй — время кадра, третий — сцена. Итог — tu_hearts_big.png 2240×2240
# рядом со скриптом. Иконку из него собирает tool/gen_tu_icon.py: масштаб 0,86,
# сдвиг (-124, -360) на полотне 1024 (слой с запасом — 1536, сдвиг +256).
import io
import os
import sys

from playwright.sync_api import sync_playwright
from PIL import Image

W = os.environ.get('BADGES_DIR', os.path.expanduser('~/Projects/GitHub/togetherly-badges-hand'))
S = os.path.dirname(os.path.abspath(__file__))
SIDE = 160
HEARTS = sys.argv[1]
T = float(sys.argv[2]) if len(sys.argv) > 2 else 0
SCENE = sys.argv[3] if len(sys.argv) > 3 else "BLOB_MOODS.idle('b',false)"

page = ("<!doctype html><html><head><meta charset='utf-8'><style>body{margin:0;background:transparent}"
        f"#pad{{width:{SIDE}px;height:{SIDE}px}}#pad svg{{display:block}}</style></head><body><div id='pad'></div>"
        + ''.join(f"<script src='file://{W}/{f}'></script>" for f in ('badges.js', 'anim.js', 'anim2.js', 'mascot.js'))
        + f"<script src='file://{S}/hearts.js'></script></body></html>")
html = os.path.join(S, 'tu_hearts.html')
open(html, 'w').write(page)
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width': SIDE, 'height': SIDE}, device_scale_factor=14)
    pg.add_init_script(f"window.HEARTS={HEARTS}")
    pg.goto('file://' + html)
    pg.wait_for_timeout(400)
    pg.evaluate("()=>{setBlobTouchMarks(false); setBlobMoodTint(null); window.SCENE=" + SCENE + ";}")
    pg.evaluate(f"()=>{{document.getElementById('pad').innerHTML=SCENE({T},{SIDE});}}")
    Image.open(io.BytesIO(pg.screenshot(omit_background=True))).convert('RGBA').save(os.path.join(S, 'tu_hearts_big.png'))
    b.close()
os.remove(html)
