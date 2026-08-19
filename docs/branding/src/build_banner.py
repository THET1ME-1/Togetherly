#!/usr/bin/env python3
"""Шапка README: собирает banner.html с подшитыми шрифтами и иконкой, снимает PNG.

Шрифты и иконка кладутся в разметку base64 — снимок должен получаться одинаковым
на любой машине, без установленных шрифтов. Готовый файл: docs/branding/readme-banner.png.

Запуск: python3 docs/branding/src/build_banner.py
"""
import base64, pathlib, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
SRC = pathlib.Path(__file__).parent


def b64(path: pathlib.Path) -> str:
    return base64.b64encode(path.read_bytes()).decode()


def main() -> None:
    html = (SRC / "banner.html").read_text()
    html = html.replace("FONT_UNBOUNDED", "data:font/ttf;base64," + b64(ROOT / "assets/fonts/Unbounded.ttf"))
    html = html.replace("FONT_ONEST", "data:font/ttf;base64," + b64(ROOT / "assets/fonts/Onest.ttf"))
    html = html.replace("ICON", "data:image/png;base64," + b64(ROOT / "docs/branding/app-icon-512.png"))

    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(html)
        page = f.name

    out = ROOT / "docs/branding/readme-banner.png"
    subprocess.run(["node", str(SRC / "shot-banner.js"), page, str(out)], check=True)

    # Снимок делается вдвое крупнее ради чёткости, а в репозиторий кладём
    # ровно 1280×440: гигабайты в истории гита ради шапки ни к чему.
    try:
        from PIL import Image

        img = Image.open(out)
        img.resize((1280, 440), Image.LANCZOS).save(out, optimize=True)
    except ImportError:
        print("Pillow не найден — снимок остался в удвоенном размере")
    print("шапка:", out)


if __name__ == "__main__":
    main()
