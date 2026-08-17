#!/usr/bin/env python3
"""Читает отчёт о падении .ips и печатает причину с верхушкой стека.

Нужен, чтобы отличать настоящее падение расширения от обычного завершения:
в системном журнале обе картины выглядят как «exited with context», а .ips
пишется только при аварии.

Запуск: python3 tool/ips_report.py <файл.ips>
"""

import json
import sys


def main() -> int:
    path = sys.argv[1]
    raw = open(path, encoding="utf-8", errors="replace").read()
    # Первая строка .ips — короткий заголовок, тело идёт следом отдельным JSON.
    _, _, body = raw.partition("\n")
    try:
        d = json.loads(body)
    except Exception:
        print(raw[:2000])
        return 0

    print("процесс:", d.get("procName"), d.get("bundleInfo"))
    print("причина:", json.dumps(d.get("exception", {}), ensure_ascii=False))
    term = d.get("termination")
    if term:
        print("остановка:", json.dumps(term, ensure_ascii=False)[:400])
    if d.get("asi"):
        # Сюда Swift кладёт текст fatalError/precondition — с файлом и строкой.
        print("сообщение runtime:", json.dumps(d["asi"], ensure_ascii=False)[:1000])

    imgs = d.get("usedImages", [])
    faulting = d.get("faultingThread", 0)
    threads = d.get("threads", [])
    if faulting < len(threads):
        print(f"— поток {faulting} (упавший) —")
        for fr in threads[faulting].get("frames", [])[:16]:
            idx = fr.get("imageIndex", -1)
            name = imgs[idx].get("name", "?") if 0 <= idx < len(imgs) else "?"
            print(f"   {name}  {fr.get('symbol', '')} +{fr.get('imageOffset')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
