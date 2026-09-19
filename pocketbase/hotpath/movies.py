"""Поиск фильмов для приложения: Викиданные первыми, poiskkino запасным.

Зачем свой сервер (19.09.2026). Бесплатный тариф poiskkino.dev — 200 запросов
в сутки на ВСЕХ: ключ лежал в APK, к обеду он выгорал, и фильмы не мог
добавить никто. Платный тариф дорог, TMDB запрещает коммерческое
использование. Викиданные отдают названия на всех языках, год, тип, жанры и
номер Кинопоиска под CC0 — без ключа и без условий.

Ходить туда прямо с телефона нельзя: запись фильма в Викиданных весит сотни
килобайт (справки и источники к каждому утверждению), десять штук — 287 КБ
сжатыми на каждый поиск. Сервер забирает их сам, ужимает до полутора
килобайт на фильм, держит в кэше и отдаёт телефону готовый список в той же
форме, что и poiskkino, — клиент читает его прежним разбором.

Постер берётся с серверов Кинопоиска по номеру фильма из Викиданных (P2603):
те же картинки отдавал и poiskkino.

Здесь только чистые функции и сборка поиска с подставными `fetch` и `cache` —
всё проверяется тестами без сети (`test_movies.py`). Маршрут, Postgres и
HTTP-клиенты живут в hotpath.py.
"""
from __future__ import annotations

import asyncio
import re
import time
from collections import deque

# ── Нормализация запроса ─────────────────────────────────────────────────────

_NOT_WORD = re.compile(r"[^\w\s]+", re.UNICODE)
_SPACES = re.compile(r"\s+")


def norm_query(q) -> str:
    """Ключ кэша и строка поиска: без регистра, ё, кавычек и лишних пробелов.

    Знаки препинания выбрасываются целиком: CirrusSearch понимает часть из
    них как синтаксис (`-` — исключить, `"` — фраза, `:` — фильтр), и строка
    от человека не должна менять смысл запроса.
    """
    s = str(q or "").lower().replace("ё", "е").replace("_", " ")
    s = _NOT_WORD.sub(" ", s)
    s = _SPACES.sub(" ", s).strip()[:80].strip()
    return s if len(s) >= 2 else ""


def cache_fresh(updated, now, ttl) -> bool:
    return updated is not None and now - updated <= ttl


class RateLimiter:
    """Скользящее окно на человека: один не выжжет запасной ключ всем."""

    def __init__(self, limit: int, window: float):
        self.limit = limit
        self.window = window
        self._hits: dict[str, deque] = {}

    def allow(self, key: str, now: float | None = None) -> bool:
        now = time.monotonic() if now is None else now
        q = self._hits.setdefault(key, deque())
        while q and now - q[0] > self.window:
            q.popleft()
        if len(q) >= self.limit:
            return False
        q.append(now)
        if len(self._hits) > 20000:  # не копим всех, кто когда-то искал
            for k in [k for k, v in self._hits.items() if not v]:
                del self._hits[k]
        return True


# ── poiskkino (запасной источник) ────────────────────────────────────────────

_KEEP = ("id", "name", "alternativeName", "enName", "year", "releaseYears",
         "poster", "genres", "countries", "rating", "description",
         "shortDescription", "type")


def trim_payload(payload, limit: int = 25) -> dict:
    """Ответ poiskkino без тяжёлого: актёры и трейлеры клиенту не нужны."""
    docs = payload.get("docs") if isinstance(payload, dict) else None
    if not isinstance(docs, list):
        return {"docs": []}
    out = []
    for d in docs[:limit]:
        if not isinstance(d, dict):
            continue
        t = {k: d[k] for k in _KEEP if k in d}
        rating = d.get("rating")
        if isinstance(rating, dict):
            t["rating"] = {"kp": rating.get("kp")}
        out.append(t)
    return {"docs": out}


def classify_source(status: int, body) -> tuple[str, str]:
    """Что значит ответ poiskkino: 403 у них — суточный лимит, а не ключ."""
    msg = ""
    if isinstance(body, dict):
        msg = str(body.get("message") or "")
    if status == 200:
        return "ok", msg
    if status == 403:
        return "quota", msg
    if status == 401:
        return "auth", msg
    return "error", msg or f"HTTP {status}"


# ── Викиданные ───────────────────────────────────────────────────────────────

# Класс записи (P31) → тип, как его называет poiskkino и понимает клиент.
_KINDS = {
    "Q11424": "movie",            # фильм
    "Q24869": "movie",            # полнометражный фильм
    "Q24862": "movie",            # короткометражный
    "Q506240": "movie",           # телефильм
    "Q93204": "movie",            # документальный
    "Q5398426": "tv-series",      # телесериал
    "Q1259759": "tv-series",      # мини-сериал
    "Q526877": "tv-series",       # веб-сериал
    "Q202866": "cartoon",         # анимационный фильм
    "Q29168811": "cartoon",       # полнометражный мультфильм
    "Q581714": "animated-series",
    "Q117467246": "animated-series",
    "Q117467240": "animated-series",
    "Q63952888": "anime",         # аниме-сериал
    "Q20650540": "anime",         # аниме-фильм
}
# Анимация точнее «фильма»: мультфильм часто записан и фильмом, и мультфильмом.
_KIND_RANK = {"anime": 3, "animated-series": 2, "cartoon": 1}

ADULT = {"Q185529"}  # порнофильм: такое в ленте пары не предлагаем

_SEARCH_TYPES = "|".join(f"P31={q}" for q in _KINDS)

# Жанры Викиданных дробные и длинные («научно-фантастический телесериал»),
# а клиент показывает их коротко, как Кинопоиск. Собрано по частоте на двух
# сотнях популярных фильмов и сериалов; незнакомый жанр просто не выводится.
_GENRE_GROUPS = {
    "action": "Q188473 Q343782 Q3990883 Q15637293 Q1535153 Q101720774",
    "comedy": ("Q157443 Q9335576 Q170238 Q40831 Q7696995 Q4765080 Q860626 "
               "Q118612349 Q1637212 Q95440291 Q622548 Q170539 Q53094 Q20652466 "
               "Q192881 Q859369 Q1548170 Q459435 Q761469 Q138603203 Q138603206 "
               "Q108466999"),
    "drama": "Q130232 Q1366112 Q21010853 Q113485322 Q7168625 Q775344",
    "adventure": ("Q319221 Q56064758 Q21802675 Q15712918 Q222639 Q2096633 "
                  "Q22981906 Q111997258"),
    "fantasy": ("Q157394 Q98526245 Q132311 Q15637301 Q794912 Q1128592 Q326439 "
                "Q130130466 Q1957385 Q3634883"),
    "scifi": ("Q471839 Q140472311 Q20443008 Q174526 Q1341051 Q47009776 Q904447 "
              "Q2447078 Q104765957 Q20656232 Q2973181 Q725757 Q103109864 "
              "Q112254601"),
    "thriller": ("Q2484376 Q67175872 Q182015 Q590103 Q109733304 Q19367312 "
                 "Q11304653 Q104623069 Q2297927 Q56320653"),
    "crime": "Q959790 Q9335577 Q2421031 Q185867 Q7444356 Q496523 Q2642760 Q586250",
    "horror": ("Q200092 Q20220309 Q853630 Q909586 Q43911809 Q604725 Q1538137 "
               "Q3072049 Q2137852 Q5258881 Q1342372"),
    "romance": "Q1054574 Q84270297 Q1919632 Q191489 Q19765983 Q2075808",
    "mystery": "Q1200678 Q101898470 Q25533274 Q56878968 Q186424 Q6585139 Q104623091",
    "family": "Q1361932 Q28026639",
    "kids": "Q2143665 Q1273568",
    "musical": "Q842256 Q2743",
    "war": "Q369747",
    "history": "Q17013749",
    "biography": "Q645928",
    "documentary": "Q93204",
    "western": "Q172980 Q78528852",
}
GENRES = {q: key for key, qs in _GENRE_GROUPS.items() for q in qs.split()}

GENRE_NAMES = {
    "action": {"ru": "боевик", "en": "action", "de": "Action", "fr": "action",
               "es": "acción", "it": "azione", "pt": "ação"},
    "comedy": {"ru": "комедия", "en": "comedy", "de": "Komödie", "fr": "comédie",
               "es": "comedia", "it": "commedia", "pt": "comédia"},
    "drama": {"ru": "драма", "en": "drama", "de": "Drama", "fr": "drame",
              "es": "drama", "it": "dramma", "pt": "drama"},
    "adventure": {"ru": "приключения", "en": "adventure", "de": "Abenteuer",
                  "fr": "aventure", "es": "aventura", "it": "avventura",
                  "pt": "aventura"},
    "fantasy": {"ru": "фэнтези", "en": "fantasy", "de": "Fantasy", "fr": "fantasy",
                "es": "fantasía", "it": "fantasy", "pt": "fantasia"},
    "scifi": {"ru": "фантастика", "en": "sci-fi", "de": "Science-Fiction",
              "fr": "science-fiction", "es": "ciencia ficción",
              "it": "fantascienza", "pt": "ficção científica"},
    "thriller": {"ru": "триллер", "en": "thriller", "de": "Thriller",
                 "fr": "thriller", "es": "suspense", "it": "thriller",
                 "pt": "suspense"},
    "crime": {"ru": "криминал", "en": "crime", "de": "Krimi", "fr": "policier",
              "es": "crimen", "it": "poliziesco", "pt": "crime"},
    "horror": {"ru": "ужасы", "en": "horror", "de": "Horror", "fr": "horreur",
               "es": "terror", "it": "horror", "pt": "terror"},
    "romance": {"ru": "мелодрама", "en": "romance", "de": "Liebesfilm",
                "fr": "romance", "es": "romance", "it": "sentimentale",
                "pt": "romance"},
    "mystery": {"ru": "детектив", "en": "mystery", "de": "Mystery",
                "fr": "mystère", "es": "misterio", "it": "mistero",
                "pt": "mistério"},
    "family": {"ru": "семейный", "en": "family", "de": "Familie", "fr": "famille",
               "es": "familiar", "it": "famiglia", "pt": "família"},
    "kids": {"ru": "детский", "en": "kids", "de": "Kinder", "fr": "enfants",
             "es": "infantil", "it": "per bambini", "pt": "infantil"},
    "musical": {"ru": "мюзикл", "en": "musical", "de": "Musical",
                "fr": "comédie musicale", "es": "musical", "it": "musical",
                "pt": "musical"},
    "war": {"ru": "военный", "en": "war", "de": "Krieg", "fr": "guerre",
            "es": "bélico", "it": "guerra", "pt": "guerra"},
    "history": {"ru": "история", "en": "history", "de": "Historie",
                "fr": "historique", "es": "histórico", "it": "storico",
                "pt": "histórico"},
    "biography": {"ru": "биография", "en": "biography", "de": "Biografie",
                  "fr": "biopic", "es": "biografía", "it": "biografico",
                  "pt": "biografia"},
    "documentary": {"ru": "документальный", "en": "documentary",
                    "de": "Dokumentarfilm", "fr": "documentaire",
                    "es": "documental", "it": "documentario",
                    "pt": "documentário"},
    "western": {"ru": "вестерн", "en": "western", "de": "Western",
                "fr": "western", "es": "western", "it": "western",
                "pt": "faroeste"},
}

LANGS = ("ru", "en", "de", "fr", "es", "it", "pt")
_SERIES = {"tv-series", "animated-series", "anime"}


def kind_of(classes) -> str | None:
    """Тип по классам записи. Анимация сильнее, из фильма и сериала — первый."""
    best, rank = None, -1
    for q in classes:
        k = _KINDS.get(q)
        if k is None:
            continue
        r = _KIND_RANK.get(k, 0)
        if r > rank:
            best, rank = k, r
    return best


def _values(claims, prop):
    out = []
    for c in (claims or {}).get(prop) or ():
        if not isinstance(c, dict) or c.get("rank") == "deprecated":
            continue
        dv = (c.get("mainsnak") or {}).get("datavalue") or {}
        if "value" in dv:
            out.append(dv["value"])
    return out


def _ids(claims, prop):
    return [v.get("id") for v in _values(claims, prop)
            if isinstance(v, dict) and v.get("id")]


def _year(v) -> int | None:
    """`+2014-10-26T00:00:00Z` → 2014. Даты до нашей эры кино не касаются."""
    t = v.get("time") if isinstance(v, dict) else None
    m = re.match(r"\+(\d{4})-", t or "")
    return int(m.group(1)) if m else None


def _years(claims, prop):
    return [y for y in (_year(v) for v in _values(claims, prop)) if y]


def compact_entity(ent) -> dict | None:
    """Полная запись Викиданных → то немногое, что нужно карточке фильма."""
    if not isinstance(ent, dict) or "missing" in ent:
        return None
    claims = ent.get("claims") or {}
    classes = _ids(claims, "P31")
    kind = kind_of(classes)
    labels = {lang: v.get("value") for lang, v in (ent.get("labels") or {}).items()
              if isinstance(v, dict) and v.get("value")}
    if kind is None:
        return {"qid": ent.get("id"), "labels": labels}

    kp = None
    for v in _values(claims, "P2603"):
        if str(v).isdigit():
            kp = int(v)
            break
    imdb = next((str(v) for v in _values(claims, "P345")
                 if re.fullmatch(r"tt\d+", str(v))), None)

    released = _years(claims, "P577")
    starts = _years(claims, "P580")
    ends = _years(claims, "P582")

    genres_q = _ids(claims, "P136")
    genres = []
    for q in genres_q:
        g = GENRES.get(q)
        if g and g not in genres:
            genres.append(g)

    titles = {}
    for v in _values(claims, "P1476"):
        if isinstance(v, dict) and v.get("text"):
            titles.setdefault(v.get("language") or "", v["text"])

    posters = [str(v) for v in _values(claims, "P3383") if v]
    countries = _ids(claims, "P495")

    return {
        "qid": ent.get("id"),
        "kind": kind,
        "labels": labels,
        "titles": titles,
        "kp": kp,
        "imdb": imdb,
        "year": min(released) if released else (min(starts) if starts else None),
        "start": min(starts) if starts else None,
        "end": max(ends) if ends else None,
        "genres": genres[:3],
        "country": countries[0] if countries else None,
        "poster": posters[0] if posters else None,
        "adult": bool(ADULT & (set(classes) | set(genres_q))),
    }


_READABLE = re.compile(r"[\sA-Za-z\u00C0-\u024F\u0400-\u04FF0-9\W]+")


def _pick_label(labels: dict, lang: str) -> str:
    # mul — общий ярлык для всех языков: Викиданные держат там имена, которые
    # не переводятся, и у «Друзей» английского ярлыка нет вовсе, есть «Friends» в mul.
    for code in (lang, "mul", "en", "ru"):
        if labels.get(code):
            return labels[code]
    return next(iter(labels.values()), "") if labels else ""


def doc_from_compact(c: dict, lang: str, countries: dict | None = None) -> dict:
    """Карточка в форме ответа poiskkino, на языке человека."""
    lang = lang if lang in LANGS else "en"
    labels = c.get("labels") or {}
    titles = c.get("titles") or {}

    name = labels.get(lang) or titles.get(lang) or _pick_label(labels, lang)
    if not name and titles:
        name = next(iter(titles.values()))
    # Оригинал показывают так, как его прочтёт человек: японское «NARUTO -ナルト-»
    # у аниме ему ничего не скажет, Кинопоиск пишет «Naruto».
    original = next((t for t in titles.values() if _READABLE.fullmatch(t)), None) \
        or labels.get("en") or labels.get("mul")

    doc = {"id": c.get("kp") or 0, "name": name, "type": c.get("kind") or "movie"}
    if original and original != name:
        doc["alternativeName"] = original
    if c.get("year"):
        doc["year"] = c["year"]
    if doc["type"] in _SERIES and c.get("start"):
        doc["releaseYears"] = [{"start": c["start"], "end": c.get("end")}]

    if c.get("kp"):
        url = f"https://st.kp.yandex.net/images/film_iphone/iphone360_{c['kp']}.jpg"
        doc["poster"] = {"url": url, "previewUrl": url}
        doc["link"] = f"https://www.kinopoisk.ru/film/{c['kp']}/"
    else:
        if c.get("poster"):
            from urllib.parse import quote
            url = ("https://commons.wikimedia.org/wiki/Special:FilePath/"
                   f"{quote(c['poster'].replace(' ', '_'))}?width=360")
            doc["poster"] = {"url": url, "previewUrl": url}
        if c.get("imdb"):
            doc["link"] = f"https://www.imdb.com/title/{c['imdb']}/"
        elif c.get("qid"):
            doc["link"] = f"https://www.wikidata.org/wiki/{c['qid']}"

    genres = [GENRE_NAMES[g].get(lang) or GENRE_NAMES[g]["en"]
              for g in c.get("genres") or () if g in GENRE_NAMES]
    if genres:
        doc["genres"] = [{"name": g} for g in genres]

    country = (countries or {}).get(c.get("country") or "")
    if country:
        label = _pick_label(country, lang)
        if label:
            doc["countries"] = [{"name": label}]
    return doc


def search_params(q: str, wildcard: bool, limit: int = 8) -> dict:
    """Полнотекстовый поиск с фильтром по классу: только фильмы и сериалы.

    Звёздочка к последнему слову находит недописанное («интерст» →
    «Интерстеллар»), но ранжирует хуже: «друзья*» ставит «Smiling Friends»
    выше «Друзей». Поэтому оба поиска идут вместе, и точный главнее.
    """
    text = f"{q}*" if wildcard else q
    return {
        "action": "query", "list": "search", "format": "json",
        "srsearch": f"{text} haswbstatement:{_SEARCH_TYPES}",
        "srlimit": str(limit), "srnamespace": "0", "srprop": "",
    }


def search_ids(payload) -> list[str]:
    try:
        hits = payload["query"]["search"]
    except (TypeError, KeyError):
        return []
    return [h["title"] for h in hits
            if isinstance(h, dict) and re.fullmatch(r"Q\d+", str(h.get("title")))]


class WikidataSearch:
    """Сборка поиска: два запроса поиска, записи фильмов, названия стран.

    `fetch(params) -> dict` ходит в api.php Викиданных, `cache` держит ужатые
    записи (`get(ids) -> {qid: compact}`, `put({qid: compact})`). Повторный
    поиск того же фильма тяжёлых записей не тянет вовсе.
    """

    def __init__(self, fetch, cache, limit: int = 10):
        self.fetch = fetch
        self.cache = cache
        self.limit = limit

    async def search(self, q: str, lang: str) -> list[dict]:
        q = norm_query(q)
        if not q:
            return []
        # С трёх букв звёздочка цепляет всё подряд («оно*»), а точный поиск
        # короткое слово и так найдёт.
        wild = len(q.split(" ")[-1]) >= 4
        jobs = [self.fetch(search_params(q, wildcard=False))]
        if wild:
            jobs.append(self.fetch(search_params(q, wildcard=True)))
        answers = await asyncio.gather(*jobs, return_exceptions=True)
        if all(isinstance(a, BaseException) for a in answers):
            raise answers[0]

        ids: list[str] = []
        for a in answers:
            if isinstance(a, BaseException):
                continue
            for i in search_ids(a):
                if i not in ids:
                    ids.append(i)
        ids = ids[: self.limit]
        if not ids:
            return []

        compact = await self._entities(ids, props="labels|claims")
        films = [compact[i] for i in ids
                 if compact.get(i) and compact[i].get("kind")
                 and not compact[i].get("adult")]

        country_ids = sorted({f["country"] for f in films if f.get("country")})
        countries = await self._entities(country_ids, props="labels") if country_ids else {}
        country_labels = {k: v.get("labels") or {} for k, v in countries.items()}

        docs = []
        for f in films:
            d = doc_from_compact(f, lang, country_labels)
            if d.get("name"):
                docs.append(d)
        return docs

    async def _entities(self, ids, props) -> dict:
        have = await self.cache.get(ids)
        need = [i for i in ids if i not in have]
        if need:
            payload = await self.fetch({
                "action": "wbgetentities", "format": "json",
                "ids": "|".join(need), "props": props,
                "languages": "|".join(("mul",) + LANGS),
            })
            fresh = {}
            for qid, ent in ((payload or {}).get("entities") or {}).items():
                ent = dict(ent, id=ent.get("id") or qid)
                c = compact_entity(ent) if props != "labels" else {
                    "qid": qid,
                    "labels": {l: v.get("value") for l, v in (ent.get("labels") or {}).items()
                               if isinstance(v, dict) and v.get("value")},
                }
                if c is not None:
                    fresh[qid] = c
            if fresh:
                await self.cache.put(fresh)
            have = {**have, **fresh}
        return have
