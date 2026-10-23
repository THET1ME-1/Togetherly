"""Проверка: медленная загрузка не обрывается сервером раньше срока.

PocketBase ставит 5 минут на чтение и на запись запроса, и загрузка фото на
медленной мобильной сети обрывалась ровно на 300-й секунде (22.10.2026). Сборка
берёт срок из PB_HTTP_TIMEOUT (по умолчанию 15 минут). Тест поднимает копию
PocketBase с коротким сроком и шлёт тело запроса по байту в секунду: при сроке
короче загрузки сервер обрывает соединение, при сроке длиннее — отвечает.

Запуск: python3 slow_upload_test.py <путь к бинарю pocketbase>
Поднимает свою копию во временной папке, ничего снаружи не трогает.
"""
import os
import socket
import subprocess
import sys
import tempfile
import time

BINARY = sys.argv[1]
SECONDS_OF_UPLOAD = 12
ok = True


def check(name, condition):
    global ok
    ok = ok and condition
    print(("  ✓ " if condition else "  ✗ ") + name, flush=True)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def start(timeout):
    """Копия PocketBase во временной папке; возвращает процесс, порт и журнал."""
    folder = tempfile.mkdtemp(prefix="pb-slow-")
    port = free_port()
    env = dict(os.environ)
    if timeout:
        env["PB_HTTP_TIMEOUT"] = timeout
    log_path = os.path.join(folder, "pb.log")
    process = subprocess.Popen(
        [BINARY, "serve", "--http", f"127.0.0.1:{port}", "--dir", os.path.join(folder, "pb_data")],
        stdout=open(log_path, "w"), stderr=subprocess.STDOUT, env=env)
    for _ in range(100):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                return process, port, log_path
        except OSError:
            time.sleep(0.2)
    process.kill()
    raise SystemExit("PocketBase не поднялся")


def slow_upload(port):
    """Шлёт тело кусками раз в секунду и возвращает первую строку ответа или ''."""
    # Целый JSON, закрывающая скобка приходит последней: сервер обязан
    # дочитать тело до конца, прежде чем ответить
    body = b'{"identity":"a@b.c","password":"' + b"x" * 40 + b'"}'
    piece = -(-len(body) // SECONDS_OF_UPLOAD)
    connection = socket.create_connection(("127.0.0.1", port), timeout=60)
    connection.sendall(
        b"POST /api/collections/users/auth-with-password HTTP/1.1\r\n"
        b"Host: 127.0.0.1\r\nContent-Type: application/json\r\n"
        + f"Content-Length: {len(body)}\r\n\r\n".encode())
    try:
        for start_at in range(0, len(body), piece):
            connection.sendall(body[start_at:start_at + piece])
            time.sleep(1)
        answer = connection.recv(200)
    except OSError:
        answer = b""
    finally:
        connection.close()
    return answer.split(b"\r\n")[0].decode(errors="replace")


for timeout, should_answer in (("8s", False), ("30s", True)):
    process, port, _ = start(timeout)
    try:
        started = time.time()
        first_line = slow_upload(port)
        spent = time.time() - started
        print(f"    срок {timeout}: загрузка {spent:.0f} с, ответ «{first_line or 'обрыв'}»")
        if should_answer:
            check(f"при сроке {timeout} сервер дождался тела и ответил", first_line.startswith("HTTP/1.1"))
        else:
            check(f"при сроке {timeout} сервер оборвал загрузку", not first_line.startswith("HTTP/1.1"))
    finally:
        process.kill()

process, _, log_path = start("")
time.sleep(1)
process.kill()
check("без переменной срок 15 минут", "срок запроса — 15m0s" in open(log_path, encoding="utf-8").read())

print("ВСЁ ВЕРНО" if ok else "ЕСТЬ ОШИБКИ")
sys.exit(0 if ok else 1)
