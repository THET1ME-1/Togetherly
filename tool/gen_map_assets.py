#!/usr/bin/env python3
"""Ассеты карты «Где мы»: базовый стиль подложки и контуры суши для глобуса.

    python3 tool/gen_map_assets.py

Стиль берётся с OpenFreeMap (positron) и чистится от того, чего отрисовщик
vector_tile_renderer не умеет или что нам не нужно: растровый рельеф, спрайты,
дорожные щиты. Цвета в файле остаются исходные — приложение перекрашивает
слои по теме в `lib/services/map/map_style.dart`.

Контуры суши — Natural Earth из пакета world-atlas (TopoJSON). Пишутся в
простой бинарный формат, который читает `lib/widgets/map/land_shapes.dart`:

    uint32 ringCount
    повторить ringCount раз:
        uint32 n
        n × (float32 долгота, float32 широта)

Кольца всех полигонов (и внешние, и дыры) идут подряд, заливка evenOdd.
"""
import json
import struct
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets' / 'map'

STYLE_URL = 'https://tiles.openfreemap.org/styles/positron'
LAND = {
    'land_110m.bin': ('https://cdn.jsdelivr.net/npm/world-atlas@2/land-110m.json', 0.0),
    'land_50m.bin': ('https://cdn.jsdelivr.net/npm/world-atlas@2/land-50m.json', 0.03),
}
# Щиты рисуются спрайтами, которых у нас нет; ни одной подписи в них нет.
DROP_LAYERS = {'highway-shield-non-us', 'highway-shield-us-interstate', 'road_shield_us'}


def fetch(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'Togetherly-assets/1.0'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def base_style():
    s = fetch(STYLE_URL)
    layers = [l for l in s['layers']
              if l.get('source') in (None, 'openmaptiles') and l['id'] not in DROP_LAYERS]
    return {
        'version': 8,
        'name': 'togetherly-base',
        'sources': {'openmaptiles': {'type': 'vector'}},
        'layers': layers,
    }


def decode_topology(topo):
    sx, sy = topo['transform']['scale']
    tx, ty = topo['transform']['translate']
    arcs = []
    for arc in topo['arcs']:
        x = y = 0
        pts = []
        for dx, dy in arc:
            x += dx
            y += dy
            pts.append((x * sx + tx, y * sy + ty))
        arcs.append(pts)

    def ring(indices):
        out = []
        for i in indices:
            pts = arcs[i] if i >= 0 else list(reversed(arcs[~i]))
            out.extend(pts if not out else pts[1:])
        return out

    rings = []
    geoms = topo['objects']['land']
    geoms = geoms['geometries'] if geoms['type'] == 'GeometryCollection' else [geoms]
    for g in geoms:
        polys = g['arcs'] if g['type'] == 'MultiPolygon' else [g['arcs']]
        for poly in polys:
            for r in poly:
                rings.append(ring(r))
    return rings


def simplify(pts, tol):
    """Дуглас — Пекер в градусах; первая и последняя точки остаются."""
    if tol <= 0 or len(pts) < 5:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = pts[a]
        bx, by = pts[b]
        dx, dy = bx - ax, by - ay
        l2 = dx * dx + dy * dy
        best, idx = 0.0, -1
        for i in range(a + 1, b):
            px, py = pts[i]
            if l2 == 0:
                d = (px - ax) ** 2 + (py - ay) ** 2
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
                d = (px - ax - t * dx) ** 2 + (py - ay - t * dy) ** 2
            if d > best:
                best, idx = d, i
        if idx >= 0 and best > tol * tol:
            keep[idx] = True
            stack.append((a, idx))
            stack.append((idx, b))
    return [p for p, k in zip(pts, keep) if k]


def write_land(name, url, tol):
    rings = [simplify(r, tol) for r in decode_topology(fetch(url))]
    rings = [r for r in rings if len(r) >= 4]
    buf = bytearray(struct.pack('<I', len(rings)))
    for r in rings:
        buf += struct.pack('<I', len(r))
        for lon, lat in r:
            buf += struct.pack('<ff', lon, lat)
    (OUT / name).write_bytes(bytes(buf))
    print(f'{name}: {len(rings)} колец, {sum(map(len, rings))} точек, {len(buf) // 1024} КБ')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    style = base_style()
    (OUT / 'base_style.json').write_text(json.dumps(style, ensure_ascii=False, separators=(',', ':')))
    print(f'base_style.json: {len(style["layers"])} слоёв')
    for name, (url, tol) in LAND.items():
        write_land(name, url, tol)


if __name__ == '__main__':
    main()
