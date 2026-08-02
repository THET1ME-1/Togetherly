#!/usr/bin/env python3
"""Загрузчик страниц магазинов для превью товара.

ЗАЧЕМ ОТДЕЛЬНЫЙ СЕРВИС: раньше страницу тянул сам pb_hook. Он проверял адрес
перед запросом, но клиент PocketBase молча идёт по редиректам, и проверка
обходилась в один шаг: внешний сервер отвечал `302 Location:
http://127.0.0.1:9988/`, и пользователю возвращалось содержимое службы,
доступной только с localhost. Проверено живьём 2 августа 2026 — вернулся
`og:title` внутреннего сервиса.

Здесь редиректы разбираются вручную: каждый следующий адрес проходит ту же
проверку, что и первый. Плюс адрес резолвится в IP, и приватные, локальные и
служебные диапазоны отсекаются — строковый чёрный список не ловил ни
`http://127.1`, ни `http://2130706433`, ни `http://[::1]`.

Слушает только localhost: наружу его пускать незачем, ходит в него один
pb_hook.

    python3 fetcher.py            # порт 8110
"""

from __future__ import annotations

import ipaddress
import json
import socket
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8110
MAX_BYTES = 512 * 1024
TIMEOUT = 8
MAX_HOPS = 4
UA = "Mozilla/5.0 (compatible; TogetherlyBot/1.0; +https://togetherly.duckdns.org)"


class Denied(Exception):
    """Адрес трогать нельзя."""


def check_url(raw: str) -> str:
    parts = urllib.parse.urlsplit(raw)
    if parts.scheme not in ("http", "https"):
        raise Denied("only http(s)")
    host = parts.hostname or ""
    if not host:
        raise Denied("no host")
    port = parts.port or (443 if parts.scheme == "https" else 80)
    if port not in (80, 443):
        raise Denied("port not allowed")

    # Резолвим сами: только так видно, что `shop.example` смотрит в 10.0.0.5.
    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
    except socket.gaierror as exc:
        raise Denied("dns failed") from exc

    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if (ip.is_private or ip.is_loopback or ip.is_link_local
                or ip.is_reserved or ip.is_multicast or ip.is_unspecified):
            raise Denied("private address")
    return raw


def fetch(raw: str) -> tuple[str, str]:
    """Возвращает (итоговый адрес, html). Каждый переход проверяется заново."""
    url = check_url(raw)
    for _ in range(MAX_HOPS):
        req = urllib.request.Request(url, headers={
            "User-Agent": UA,
            "Accept-Language": "ru,en;q=0.8",
        })
        opener = urllib.request.build_opener(_NoRedirect)
        try:
            with opener.open(req, timeout=TIMEOUT) as resp:
                return url, resp.read(MAX_BYTES).decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            if exc.code not in (301, 302, 303, 307, 308):
                raise Denied(f"shop answered {exc.code}") from exc
            location = exc.headers.get("Location") or ""
            if not location:
                raise Denied("redirect without location") from exc
            # Относительный редирект склеиваем, абсолютный проверяем целиком.
            url = check_url(urllib.parse.urljoin(url, location))
        except (urllib.error.URLError, TimeoutError, socket.timeout) as exc:
            raise Denied("fetch failed") from exc
    raise Denied("too many redirects")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Ни одного автоматического перехода: их разбирает [fetch]."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        parts = urllib.parse.urlsplit(self.path)
        if parts.path != "/preview":
            return self._json(404, {"ok": False, "error": "not found"})
        query = urllib.parse.parse_qs(parts.query)
        raw = (query.get("url") or [""])[0].strip()
        if not raw:
            return self._json(400, {"ok": False, "error": "url required"})
        try:
            final, html = fetch(raw)
        except Denied as exc:
            return self._json(200, {"ok": False, "error": str(exc)})
        except Exception:  # noqa: BLE001 — сервису падать нельзя
            return self._json(200, {"ok": False, "error": "fetch failed"})
        return self._json(200, {"ok": True, "url": final, "html": html})

    def _json(self, status: int, body: dict) -> None:
        raw = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, *args) -> None:
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
