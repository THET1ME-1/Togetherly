#!/usr/bin/env python3
"""Прокси поиска фильмов: нормализация, кэш, лимиты, разбор ответа источника.

Запуск: python3 -m unittest discover -s pocketbase/hotpath -p 'test_*.py'

Зачем прокси (14.08.2026): ключ poiskkino.dev лежал прямо в APK, и все
пользователи ходили в источник напрямую одним общим ключом. Бесплатный тариф —
200 запросов в сутки на всех, поэтому к утру поиск отдавал 403 и в приложении
загоралось «Поиск недоступен — впишите название вручную». Теперь запросы идут
через сервер: ключ на сервере, ответы кэшируются, один человек не может выжечь
лимит для остальных.
"""
import unittest

from movies import (
    RateLimiter,
    cache_fresh,
    classify_source,
    norm_query,
    trim_payload,
)


class NormQueryTest(unittest.TestCase):
    def test_регистр_и_пробелы_схлопываются(self):
        self.assertEqual(norm_query("  Счастливого   ДНЯ смерти "), "счастливого дня смерти")

    def test_буква_ё_не_плодит_второй_ключ(self):
        self.assertEqual(norm_query("Ёлки"), norm_query("Елки"))

    def test_кавычки_и_знаки_не_мешают_совпадению(self):
        self.assertEqual(norm_query('«Матрица»'), norm_query("Матрица"))

    def test_слишком_короткий_запрос_пустой(self):
        self.assertEqual(norm_query("а"), "")
        self.assertEqual(norm_query("   "), "")

    def test_длина_ограничена(self):
        self.assertLessEqual(len(norm_query("ф" * 500)), 80)


class TrimPayloadTest(unittest.TestCase):
    def doc(self, **kw):
        base = {
            "id": 301, "name": "Матрица", "alternativeName": "The Matrix",
            "enName": None, "year": 1999,
            "poster": {"url": "https://x/p.jpg", "previewUrl": "https://x/s.jpg"},
            "genres": [{"name": "фантастика"}, {"name": "боевик"}],
            "countries": [{"name": "США"}],
            "rating": {"kp": 8.5, "imdb": 8.7, "await": 1},
            "description": "Жизнь Томаса Андерсона…",
            "type": "movie",
            "videos": {"trailers": [{"url": "…"}]},
            "persons": [{"name": "Киану Ривз"}] * 50,
        }
        base.update(kw)
        return base

    def test_остаются_поля_которые_читает_клиент(self):
        out = trim_payload({"docs": [self.doc()]})
        d = out["docs"][0]
        for field in ("id", "name", "alternativeName", "year", "poster",
                      "genres", "countries", "rating", "description", "type"):
            self.assertIn(field, d)

    def test_тяжёлое_выбрасывается(self):
        d = trim_payload({"docs": [self.doc()]})["docs"][0]
        self.assertNotIn("persons", d)
        self.assertNotIn("videos", d)

    def test_у_рейтинга_остаётся_только_кп(self):
        d = trim_payload({"docs": [self.doc()]})["docs"][0]
        self.assertEqual(d["rating"], {"kp": 8.5})

    def test_список_обрезается(self):
        out = trim_payload({"docs": [self.doc() for _ in range(60)]}, limit=25)
        self.assertEqual(len(out["docs"]), 25)

    def test_сериальный_диапазон_лет_сохраняется(self):
        d = trim_payload({"docs": [self.doc(releaseYears=[{"start": 2018, "end": 2022}])]})["docs"][0]
        self.assertEqual(d["releaseYears"], [{"start": 2018, "end": 2022}])

    def test_мусор_вместо_ответа_не_роняет(self):
        self.assertEqual(trim_payload(None), {"docs": []})
        self.assertEqual(trim_payload({"docs": "нет"}), {"docs": []})


class CacheTest(unittest.TestCase):
    def test_свежая_запись_годится(self):
        self.assertTrue(cache_fresh(updated=1000, now=1000 + 3600, ttl=86400))

    def test_протухшая_не_годится(self):
        self.assertFalse(cache_fresh(updated=1000, now=1000 + 86401, ttl=86400))

    def test_пустая_запись_не_годится(self):
        self.assertFalse(cache_fresh(updated=None, now=1000, ttl=86400))


class RateLimiterTest(unittest.TestCase):
    def test_в_пределах_нормы_пускает(self):
        r = RateLimiter(limit=3, window=3600)
        for i in range(3):
            self.assertTrue(r.allow("u1", now=1000 + i))

    def test_перебор_отбивается(self):
        r = RateLimiter(limit=2, window=3600)
        r.allow("u1", now=1000)
        r.allow("u1", now=1001)
        self.assertFalse(r.allow("u1", now=1002))

    def test_сосед_не_страдает(self):
        r = RateLimiter(limit=1, window=3600)
        r.allow("u1", now=1000)
        self.assertTrue(r.allow("u2", now=1000))

    def test_окно_съезжает(self):
        r = RateLimiter(limit=1, window=3600)
        r.allow("u1", now=1000)
        self.assertTrue(r.allow("u1", now=1000 + 3601))


class ClassifySourceTest(unittest.TestCase):
    def test_успех(self):
        kind, _ = classify_source(200, {"docs": []})
        self.assertEqual(kind, "ok")

    def test_суточный_лимит(self):
        kind, _ = classify_source(403, {"message": "Вы израсходовали ваш суточный лимит"})
        self.assertEqual(kind, "quota")

    def test_битый_ключ(self):
        kind, _ = classify_source(401, {"message": "invalid token"})
        self.assertEqual(kind, "auth")

    def test_прочая_беда(self):
        kind, _ = classify_source(502, {})
        self.assertEqual(kind, "error")


if __name__ == "__main__":
    unittest.main()
