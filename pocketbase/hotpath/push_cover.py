# -*- coding: utf-8 -*-
"""Обложка уведомления «А» (макет принят 28.11.2026, план
`docs/superpowers/plans/2026-11-28-notifications-cover.md`).

Сервер собирает для пуша поле `cover`: подпись «что и от кого», заголовок,
строку текста, тон (цвет плашки рисует приложение), картинку и кнопки на
языке получателя. Android новой сборки рисует уведомление сам по этому полю,
iPhone берёт картинку миниатюрой и аватар партнёра.

Правила владельца:
  * у событий партнёра обложка — его событие: Ту в позе, котик «Моти»,
    подарок, фото, аватар в рамке;
  * у уведомлений самого приложения обложка — его иконка (`{"app": true}`),
    картинка события — в развёрнутом виде (`art_big`);
  * настроение — котики «Моти», не розовые рожицы.

Картинки каталога — `still_*` записи (`catalog_items`), «Моти» — ссылки из
записи набора. Фото и аватары — из `media`: аватары открыты всем, фото
закрыты, телефон берёт к ним пропуск своим входом (`auth: true`).
"""

from push_texts import пуш

ФАЙЛЫ = "https://togetherly.day/api/files"

# Все ключи подписей обложки: тест проверяет, что у каждого девять языков.
КЛЮЧИ_ТЕКСТОВ = (
    "c_miss", "c_mood", "c_mood_today", "c_memory", "c_memory_new", "c_date_new", "c_date",
    "c_snow", "c_evening", "c_chest", "a_hug_back", "a_hug", "a_write", "a_reply", "a_read",
    "a_open", "a_watch", "a_throw", "a_mood", "a_task", "a_chest", "a_mood_back",
    "q_hug", "q_miss", "q_love",
)


def _каталог(look, item_id):
    """Ссылка на неподвижную картинку записи каталога или None."""
    found = look(item_id) if look else None
    if not found:
        return None
    files, _data = found
    for name in files or []:
        if str(name).startswith("still_"):
            return f"{ФАЙЛЫ}/catalog_items/{item_id}/{name}"
    return None


def _моти(look, mood_id):
    found = look("moti") if look else None
    if not found or not mood_id:
        return None
    _files, data = found
    for mood in (data or {}).get("moods") or []:
        if mood.get("id") == mood_id and mood.get("url"):
            return mood["url"]
    return None


def _из_медиа(pb, size):
    """`pb://media/<запись>/<файл>` → ссылка PocketBase с миниатюрой."""
    pb = (pb or "").strip()
    if not pb.startswith("pb://"):
        return pb if pb.startswith("https://") else ""
    path = pb[len("pb://"):]
    return f"{ФАЙЛЫ}/{path}?thumb={size}"


def _картинка(url, **extra):
    return {"url": url, **extra} if url else {"app": True}


def _кнопки(lang, *pairs):
    return [{"id": i, "label": пуш(key, lang)} for i, key in pairs]


def cover(kind, lang, ctx, look):
    """Поле `cover` пуша вида [kind] на языке [lang] или None, если вид
    обложки не знает (пуш уходит по-старому).

    [ctx] — что известно о событии: `from_name`, `body`, `title`, `label`,
    `mood_id`, `photo`, `avatar`, `frame`, `message_id`, `group_id`,
    `from_uid`, `symbol`. [look] — запись каталога по id: `(files, data)`.
    """
    имя = (ctx.get("from_name") or "").strip() or пуш("partner", lang)
    body = (ctx.get("body") or "").strip()
    title = (ctx.get("title") or "").strip()
    base = {"v": 1, "kind": kind}

    if kind == "miss":
        return base | {
            "kicker": f"{пуш('c_miss', lang)} · {имя}",
            "title": title or пуш("miss_title", lang),
            "body": body,
            "tone": "miss",
            "art": _картинка(_каталог(look, "art_act_miss")),
            "actions": _кнопки(lang, ("hug", "a_hug_back"), ("write", "a_write")),
            "link": "loveapp://miss",
        }

    if kind == "mood":
        return base | {
            "kicker": f"{пуш('c_mood', lang)} · {имя}",
            "title": (ctx.get("label") or "").strip() or пуш("mood_title", lang),
            "body": body or пуш("c_mood_today", lang),
            "tone": "mood",
            "art": _картинка(_моти(look, ctx.get("mood_id"))),
            "actions": _кнопки(lang, ("mood_back", "a_mood_back")),
            "link": "loveapp://mood",
        }

    if kind == "chat":
        return base | {
            "kicker": пуш("message", lang),
            "title": имя,
            "body": body,
            "tone": "chat",
            "art": _картинка(_из_медиа(ctx.get("avatar"), "200x200")),
            "actions": _кнопки(lang, ("reply", "a_reply"), ("hug", "a_hug"), ("read", "a_read")),
            "link": "loveapp://chat",
            "chat": {
                "from_uid": ctx.get("from_uid") or "",
                "from_name": имя,
                "group_id": ctx.get("group_id") or "",
                "message_id": ctx.get("message_id") or "",
                "avatar": _из_медиа(ctx.get("avatar"), "200x200"),
                "frame": (_каталог(look, "frame_" + ctx["frame"]) or "") if ctx.get("frame") else "",
                "image": _из_медиа(ctx.get("photo"), "400x400"),
                "quick": [пуш("q_hug", lang), пуш("q_miss", lang), пуш("q_love", lang)],
            },
        }

    if kind == "memory":
        фото = _из_медиа(ctx.get("photo"), "400x400")
        return base | {
            "kicker": f"{пуш('c_memory', lang)} · {имя}",
            "title": title or пуш("c_memory_new", lang),
            "body": body,
            "tone": "memory",
            "art": {"url": фото, "auth": True} if фото else {"app": True},
            "actions": _кнопки(lang, ("open", "a_watch")),
            "link": "loveapp://memory_lane",
        }

    if kind == "date":
        символ = (ctx.get("symbol") or "").strip()
        return base | {
            "kicker": f"{пуш('c_date_new', lang)} · {имя}",
            "title": title or пуш("date_untitled", lang),
            "body": body,
            "tone": "date",
            "art": {"symbol": символ} if символ else {"app": True},
            "actions": _кнопки(lang, ("open", "a_open")),
            "link": "loveapp://dates",
        }

    if kind == "snowball":
        return base | {
            "kicker": f"{пуш('c_snow', lang)} · {имя}",
            "title": title or пуш("snow_title", lang),
            "body": body or пуш("snow_body", lang),
            "tone": "snow",
            "art": _картинка(_каталог(look, "art_act_wake")),
            "actions": _кнопки(lang, ("throw", "a_throw")),
            "link": "loveapp://home",
        }

    # ── От самого приложения: обложка — иконка, картинка — в развёрнутом ──

    if kind == "date_remind":
        символ = (ctx.get("symbol") or "").strip()
        return base | {
            "kicker": пуш("c_date", lang),
            "title": title,
            "body": body,
            "tone": "date",
            "art": {"app": True},
            "art_big": {"symbol": символ} if символ else {"app": True},
            "actions": _кнопки(lang, ("open", "a_open")),
            "link": "loveapp://dates",
        }

    if kind == "evening":
        большая = _каталог(look, "art_act_rest")
        return base | {
            "kicker": пуш("c_evening", lang),
            "title": title,
            "body": body,
            "tone": "evening",
            "art": {"app": True},
            "art_big": _картинка(большая),
            "actions": _кнопки(lang, ("mood", "a_mood"), ("task", "a_task")),
            "link": "loveapp://mood",
        }

    if kind == "chest":
        # Обычный сундук с экрана сундука (`art_chest_idle2`, кадр покоя).
        большая = _каталог(look, "art_chest_idle2")
        return base | {
            "kicker": пуш("c_chest", lang),
            "title": title,
            "body": body,
            "tone": "chest",
            "art": {"app": True},
            "art_big": _картинка(большая),
            "actions": _кнопки(lang, ("chest", "a_chest")),
            "link": "loveapp://chest",
        }

    return None
