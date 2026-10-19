#!/usr/bin/env python3
"""Надзиратель uvicorn не убивает рабочих hotpath за пять секунд тишины.

19.10.2026 вечером рабочий не успевал ответить на пинг надзирателя за срок по
умолчанию (5 с), получал SIGKILL посреди запросов, и точка входа отдавала до
80 тысяч ответов 502 в час: «Скучаю», штрихи, чат, виджеты. Срок поднят до
минуты, и этот тест держит его не ниже тридцати секунд.

Запуск: python3 pocketbase/hotpath/test_worker_healthcheck.py
"""
import ast
import os
import unittest

ФАЙЛ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hotpath.py")


def параметры_запуска() -> dict:
    """Именованные параметры вызова uvicorn.run в hotpath.py."""
    with open(ФАЙЛ, encoding="utf-8") as f:
        дерево = ast.parse(f.read())
    for узел in ast.walk(дерево):
        if (isinstance(узел, ast.Call) and isinstance(узел.func, ast.Attribute)
                and узел.func.attr == "run" and getattr(узел.func.value, "id", "") == "uvicorn"):
            return {к.arg: к.value for к in узел.keywords}
    raise AssertionError("в hotpath.py нет вызова uvicorn.run")


class СрокПроверкиРабочих(unittest.TestCase):
    def test_срок_проверки_задан_явно_и_не_меньше_полуминуты(self):
        срок = параметры_запуска().get("timeout_worker_healthcheck")
        self.assertIsNotNone(срок, "без явного срока uvicorn убивает рабочего через 5 с")
        self.assertIsInstance(срок, ast.Constant)
        self.assertGreaterEqual(срок.value, 30)


if __name__ == "__main__":
    unittest.main(verbosity=2)
