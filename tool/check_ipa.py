#!/usr/bin/env python3
"""Разбор собранного IPA — проверка того, что делалось вслепую.

Устройства под рукой нет, но артефакт сборки говорит о многом: версия
виджет-расширения (из-за расхождения с версией приложения виджеты не
появлялись в галерее вовсе), общий контейнер App Group, ключи Info.plist,
подключённые фреймворки.

Запуск: python3 tool/check_ipa.py путь/к/файлу.ipa
"""

import plistlib
import re
import sys
import zipfile

FAILURES = []
NOTES = []


def check(name: str, ok: bool, extra: str = "") -> None:
    print(("  ✓ " if ok else "  ✗ ") + name, extra)
    if not ok:
        FAILURES.append(name)


def note(text: str) -> None:
    print("  · " + text)
    NOTES.append(text)


def main(path: str) -> int:
    zf = zipfile.ZipFile(path)
    names = zf.namelist()

    app_plists = [n for n in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
    if not app_plists:
        print("В архиве нет Info.plist приложения — это точно IPA?")
        return 1
    app = plistlib.loads(zf.read(app_plists[0]))

    print("Приложение")
    check("идентификатор com.togetherly.love",
          app.get("CFBundleIdentifier") == "com.togetherly.love",
          str(app.get("CFBundleIdentifier")))
    app_version = str(app.get("CFBundleShortVersionString"))
    app_build = str(app.get("CFBundleVersion"))
    note(f"версия {app_version} ({app_build})")
    check("схема loveapp:// на месте",
          any("loveapp" in str(u.get("CFBundleURLSchemes"))
              for u in app.get("CFBundleURLTypes", [])))
    check("ключа Apple Music нет — он ронял приложение",
          "NSAppleMusicUsageDescription" not in app)
    check("фоновые режимы для пушей объявлены",
          "remote-notification" in (app.get("UIBackgroundModes") or []),
          str(app.get("UIBackgroundModes")))

    print("\nВиджет-расширение")
    ext_plists = [
        n for n in names
        if re.fullmatch(r"Payload/[^/]+\.app/PlugIns/[^/]+\.appex/Info\.plist", n)
    ]
    check("расширение попало в сборку", bool(ext_plists),
          ", ".join(n.split("/")[-2] for n in ext_plists))
    for n in ext_plists:
        ext = plistlib.loads(zf.read(n))
        title = n.split("/")[-2]
        point = (ext.get("NSExtension") or {}).get("NSExtensionPointIdentifier")
        if point != "com.apple.widgetkit-extension":
            continue
        ext_version = str(ext.get("CFBundleShortVersionString"))
        ext_build = str(ext.get("CFBundleVersion"))
        note(f"{title}: версия {ext_version} ({ext_build})")
        # Ровно то, из-за чего виджетов не было: iOS не регистрирует
        # расширение, если его версия расходится с версией приложения.
        check(f"{title}: версия совпадает с приложением",
              ext_version == app_version, f"{ext_version} против {app_version}")
        check(f"{title}: номер сборки совпадает с приложением",
              ext_build == app_build, f"{ext_build} против {app_build}")

    print("\nФреймворки")
    frameworks = {
        n.split("/")[-2] for n in names
        if re.fullmatch(r"Payload/[^/]+\.app/Frameworks/[^/]+\.framework/.*", n)
    }
    note(f"всего фреймворков: {len(frameworks)}")
    check("нативный вход Apple собран",
          any("sign_in_with_apple" in f for f in frameworks),
          ", ".join(sorted(f for f in frameworks if "sign_in" in f)) or "не найден")
    check("реклама Яндекса на месте",
          any("yandex" in f.lower() or "YandexMobileAds" in f for f in frameworks))

    print("\nИтог")
    if FAILURES:
        print("НЕ СОШЛОСЬ:", "; ".join(FAILURES))
        return 1
    print("ВСЁ СОШЛОСЬ")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
