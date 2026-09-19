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

import asyncio
import json
import os

from movies import (
    RateLimiter,
    WikidataSearch,
    cache_fresh,
    classify_source,
    compact_entity,
    doc_from_compact,
    kind_of,
    norm_query,
    search_params,
    search_ids,
    trim_payload,
)

_FIX = os.path.join(os.path.dirname(__file__), "fixtures", "wikidata_sample.json")
with open(_FIX, encoding="utf-8") as _f:
    SAMPLE = json.load(_f)
ENT = SAMPLE["entities"]["entities"]


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


# ── Викиданные (19.09.2026) ────────────────────────────────────────────────
#
# Бесплатный тариф poiskkino — 200 запросов в сутки на всех, к обеду он
# выгорал, и фильмы не добавлял никто. Платный дорог, TMDB запрещает
# коммерцию. Викиданные отдают названия, год, тип и номер Кинопоиска под CC0,
# без ключа. Образец ответа снят с живого API: fixtures/wikidata_sample.json.


class WikidataKindTest(unittest.TestCase):
    def test_фильм(self):
        self.assertEqual(compact_entity(ENT["Q13417189"])["kind"], "movie")

    def test_сериал(self):
        self.assertEqual(compact_entity(ENT["Q79784"])["kind"], "tv-series")

    def test_мультфильм(self):
        self.assertEqual(compact_entity(ENT["Q246283"])["kind"], "cartoon")

    def test_аниме(self):
        self.assertEqual(compact_entity(ENT["Q25929253"])["kind"], "anime")

    def test_анимация_сильнее_простого_фильма(self):
        self.assertEqual(kind_of(["Q11424", "Q202866"]), "cartoon")

    def test_из_фильма_и_сериала_берётся_первый(self):
        self.assertEqual(kind_of(["Q11424", "Q5398426"]), "movie")
        self.assertEqual(kind_of(["Q5398426", "Q11424"]), "tv-series")

    def test_не_кино_не_годится(self):
        self.assertIsNone(kind_of(["Q5"]))


class WikidataCompactTest(unittest.TestCase):
    def test_номер_кинопоиска_и_imdb(self):
        c = compact_entity(ENT["Q13417189"])
        self.assertEqual(c["kp"], 258687)
        self.assertEqual(c["imdb"], "tt0816692")

    def test_год_выхода_самый_ранний(self):
        self.assertEqual(compact_entity(ENT["Q13417189"])["year"], 2014)

    def test_годы_сериала(self):
        c = compact_entity(ENT["Q79784"])
        self.assertEqual((c["start"], c["end"]), (1994, 2004))

    def test_порно_выбрасывается(self):
        self.assertTrue(compact_entity(ENT["Q50412717"])["adult"])
        self.assertFalse(compact_entity(ENT["Q13417189"])["adult"])

    def test_жанры_короткими_ключами(self):
        genres = compact_entity(ENT["Q13417189"])["genres"]
        self.assertIn("scifi", genres)
        self.assertIn("adventure", genres)
        self.assertLessEqual(len(genres), 3)
        self.assertEqual(len(genres), len(set(genres)))

    def test_страна(self):
        self.assertEqual(compact_entity(ENT["Q13417189"])["country"], "Q30")

    def test_у_будущего_фильма_без_даты_года_нет(self):
        self.assertIsNone(compact_entity(ENT["Q123515453"])["year"])

    def test_объём_маленький(self):
        # Ради этого всё и затевалось: полная запись весит сотни килобайт.
        self.assertLess(len(json.dumps(compact_entity(ENT["Q13417189"]))), 1500)


class WikidataDocTest(unittest.TestCase):
    """Документ повторяет форму poiskkino: клиент читает его тем же разбором."""

    def doc(self, qid, lang="ru", countries=None):
        return doc_from_compact(compact_entity(ENT[qid]), lang,
                                countries or {"Q30": {"ru": "США", "en": "United States"}})

    def test_название_на_языке_человека(self):
        self.assertEqual(self.doc("Q13417189")["name"], "Интерстеллар")
        self.assertEqual(self.doc("Q13417189", lang="en")["name"], "Interstellar")

    def test_оригинальное_название_рядом(self):
        self.assertEqual(self.doc("Q13417189")["alternativeName"], "Interstellar")

    def test_оригинал_латиницей_а_не_иероглифами(self):
        # P1476 у аниме — японское «NARUTO -ナルト-», Кинопоиск пишет «Naruto».
        self.assertEqual(self.doc("Q25929253")["alternativeName"], "Naruto")

    def test_оригинал_не_повторяет_название(self):
        self.assertNotIn("alternativeName", self.doc("Q13417189", lang="en"))

    def test_номер_и_постер_кинопоиска(self):
        d = self.doc("Q13417189")
        self.assertEqual(d["id"], 258687)
        self.assertEqual(d["poster"]["previewUrl"],
                         "https://st.kp.yandex.net/images/film_iphone/iphone360_258687.jpg")
        self.assertEqual(d["link"], "https://www.kinopoisk.ru/film/258687/")

    def test_без_кинопоиска_ссылка_на_imdb_и_без_постера(self):
        d = self.doc("Q29957438")
        self.assertEqual(d["id"], 0)
        self.assertNotIn("poster", d)
        self.assertTrue(d["link"].startswith("https://www.imdb.com/title/tt"))

    def test_год_и_диапазон_сериала(self):
        self.assertEqual(self.doc("Q13417189")["year"], 2014)
        self.assertEqual(self.doc("Q79784")["releaseYears"], [{"start": 1994, "end": 2004}])

    def test_жанры_и_страна_словами(self):
        d = self.doc("Q13417189")
        names = [g["name"] for g in d["genres"]]
        self.assertIn("фантастика", names)
        self.assertEqual(d["countries"], [{"name": "США"}])
        en = [g["name"] for g in self.doc("Q13417189", lang="en")["genres"]]
        self.assertIn("sci-fi", en)

    def test_общий_ярлык_mul_годится_любому_языку(self):
        # У «Друзей» нет ни английского, ни немецкого ярлыка: Викиданные
        # держат «Friends» одним общим (mul). Без него немец видел «Друзья».
        self.assertEqual(self.doc("Q79784", lang="de")["name"], "Friends")
        self.assertEqual(self.doc("Q79784")["name"], "Друзья")

    def test_незнакомый_язык_падает_на_английский(self):
        self.assertEqual(self.doc("Q13417189", lang="xx")["name"], "Interstellar")


class WikidataSearchParamsTest(unittest.TestCase):
    def test_фильтр_по_типу_в_запросе(self):
        p = search_params("интерстеллар", wildcard=False)
        self.assertIn("haswbstatement:P31=Q11424", p["srsearch"])
        self.assertIn("P31=Q5398426", p["srsearch"])
        self.assertTrue(p["srsearch"].startswith("интерстеллар "))

    def test_звёздочка_к_последнему_слову(self):
        p = search_params("гарри поттер и фило", wildcard=True)
        self.assertTrue(p["srsearch"].startswith("гарри поттер и фило* "))

    def test_номера_из_ответа_поиска(self):
        self.assertEqual(search_ids(SAMPLE["search"])[0], "Q13417189")
        self.assertEqual(search_ids(None), [])


class _FakeCache:
    def __init__(self):
        self.data = {}

    async def get(self, ids):
        return {i: self.data[i] for i in ids if i in self.data}

    async def put(self, items):
        self.data.update(items)


def _fake_fetch(calls):
    async def fetch(params):
        calls.append(params)
        if params.get("list") == "search":
            if params["srsearch"].startswith("пусто"):
                return {"query": {"search": []}}
            ids = ["Q13417189", "Q50412717", "Q79784"]
            if "*" in params["srsearch"]:
                ids = ["Q246283", "Q13417189"]
            return {"query": {"search": [{"title": i} for i in ids]}}
        if params.get("action") == "wbgetentities":
            ids = params["ids"].split("|")
            if params.get("props") == "labels":
                return {"entities": {i: {"labels": {"ru": {"value": "США"}, "en": {"value": "United States"}}}
                                     for i in ids}}
            return {"entities": {i: ENT[i] for i in ids if i in ENT}}
        raise AssertionError(params)
    return fetch


class WikidataSearchTest(unittest.TestCase):
    def run_search(self, q, cache=None, calls=None):
        calls = [] if calls is None else calls
        ws = WikidataSearch(fetch=_fake_fetch(calls), cache=cache or _FakeCache())
        return asyncio.run(ws.search(q, "ru")), calls

    def test_точное_совпадение_выше_звёздочки_и_без_повторов(self):
        docs, _ = self.run_search("интерстеллар")
        names = [d["name"] for d in docs]
        self.assertEqual(names[0], "Интерстеллар")
        self.assertEqual(names.count("Интерстеллар"), 1)
        self.assertIn("Холодное сердце", names)

    def test_порно_в_выдачу_не_попадает(self):
        docs, _ = self.run_search("интерстеллар")
        self.assertFalse(any("XXX" in (d.get("name") or "") for d in docs))

    def test_второй_раз_записи_берутся_из_кэша(self):
        cache = _FakeCache()
        self.run_search("интерстеллар", cache=cache)
        calls = []
        self.run_search("интерстеллар", cache=cache, calls=calls)
        heavy = [c for c in calls if c.get("action") == "wbgetentities"]
        self.assertEqual(heavy, [])

    def test_короткое_слово_без_звёздочки(self):
        _, calls = self.run_search("оно")
        searches = [c["srsearch"] for c in calls if c.get("list") == "search"]
        self.assertTrue(all("*" not in s.split(" haswbstatement")[0] for s in searches))

    def test_пустой_поиск_пустой_ответ(self):
        docs, _ = self.run_search("пусто совсем")
        self.assertEqual(docs, [])


if __name__ == "__main__":
    unittest.main()
