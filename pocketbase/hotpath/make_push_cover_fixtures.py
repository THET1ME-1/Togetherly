"""Примеры обложек «А» для тестов приложения: `test/fixtures/push_cover_cases.json`.

Обложку собирают три места — сервер (`push_cover.py`), Dart для своих
уведомлений (`lib/models/push_cover.dart`) и Kotlin её разбирает
(`notif/Cover.kt`). Тесты Dart и Kotlin сверяются с этим файлом, поэтому
правится он только скриптом:

    python3 pocketbase/hotpath/make_push_cover_fixtures.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import push_cover  # noqa: E402

F = "https://togetherly.day/api/files"

# Каталог примеров: записи как в боевой базе (файлы и data).
КАТАЛОГ = {
    "art_act_miss": [["sm_a.webp", "lg_a.webp", "still_miss.png"], {}],
    "art_act_rest": [["still_rest.png"], {}],
    "art_act_wake": [["still_wake.png"], {}],
    "art_act_draw": [["still_draw.png"], {}],
    "art_chest_idle2": [["sm_c.webp", "still_chest.png"], {}],
    "moti": [[], {"moods": [{"id": "love", "url": f"{F}/catalog_items/moti/love_x.webp"},
                            {"id": "sad", "url": f"{F}/catalog_items/moti/sad_x.webp"}]}],
    "gift_bouquet": [["sm_b.webp", "still_bouquet.png"], {}],
    "frame_hearts": [["still_hearts.png"], {}],
    "frame_cloud": [["still_cloud.png"], {"hole": 27}],
    "art_act_sad": [["still_sad.png"], {}],
    "art_guide_wait": [["still_wait.png"], {}],
    "art_ach_together_365": [["still_year.png"], {}],
    "art_act_phone": [["still_phone.png"], {}],
}

ПРИМЕРЫ = [
    ("miss", "ru", {"from_name": "Алина", "body": "Хочу обнять", "group_id": "g1", "event_id": "e1",
                    "from_uid": "u1", "avatar": "pb://media/r1/a.jpg", "frame": "hearts"}),
    ("miss", "en", {"body": "I miss you"}),
    ("mood", "ru", {"from_name": "Алина", "mood_id": "love", "label": "Влюблённость"}),
    ("mood", "uk", {"from_name": "Аліна", "mood_id": "pride", "label": "Гордість"}),
    ("chat", "ru", {"from_name": "Алина", "body": "Ты уже дома?", "avatar": "pb://media/r1/a.jpg",
                    "frame": "cloud", "message_id": "m1", "group_id": "g1", "from_uid": "u1",
                    "ts": 1795873555018, "photo": "pb://media/r2/n.webp"}),
    ("chat", "de", {"from_name": "Alina", "body": "Hallo", "group_id": "g1"}),
    ("memory", "ru", {"from_name": "Алина", "title": "Вечер на крыше", "photo": "pb://media/r9/p.webp"}),
    ("memory", "fr", {"from_name": "Alina"}),
    ("date", "es", {"from_name": "Alina", "title": "Concierto", "symbol": "theater_comedy"}),
    ("snowball", "it", {"from_name": "Alina", "group_id": "g1"}),
    ("gift", "pt", {"from_name": "Alina", "gift_key": "bouquet", "title": "Buquê"}),
    ("gift", "ru", {"from_name": "Алина", "gift_key": "frame_hearts", "title": "Рамка"}),
    ("comment", "zh", {"from_name": "阿琳娜", "body": "想再去", "photo": "pb://media/r1/p.webp"}),
    ("draw", "ru", {"from_name": "Алина", "title": "Порисуем?", "body": "Открой холст"}),
    ("plusgift", "en", {"from_name": "Alina", "title": "Togetherly+", "body": "A gift for you"}),
    ("pair_reset", "ru", {"title": "Пароль меняют", "body": "Если это не вы"}),
    ("security", "en", {"title": "Password changed", "body": "All good"}),
    ("date_remind", "ru", {"title": "Годовщина", "body": "Завтра", "symbol": "cake"}),
    ("evening", "ru", {"title": "Как прошёл день?", "body": "Отметь настроение"}),
    ("chest", "uk", {"title": "Скриня знову повна", "body": "Зазирни"}),
    ("capsule", "ru", {"title": "Письмо из прошлого", "body": "Капсула открылась", "capsule_id": "mem123"}),
    ("celebration", "en", {"title": "One year together", "body": "Today", "art_id": "art_ach_together_365"}),
    ("celebration", "ru", {"title": "Завтра день рождения", "body": "Не забудь"}),
    ("mascot_miss", "de", {"title": "Tu vermisst dich", "body": "Schau rein"}),
    ("invite", "pt", {"title": "Convide seu par", "body": "O código espera"}),
    ("days", "ru", {"title": "128 дней вместе", "body": "И это только начало"}),
    ("reels", "ru", {"from_name": "Алина", "title": "Алина зовёт смотреть TikTok",
                     "body": "Заходи, листаем вместе", "feed": "tiktok", "group_id": "g1",
                     "from_uid": "u1", "avatar": "pb://media/r1/a.jpg"}),
    ("reels", "en", {"title": "Your partner invites you", "body": "Join"}),
    ("badge", "ru", {"title": "Вам вручён значок «Спонсор»!", "body": "Спасибо за поддержку"}),
    ("mood_lock", "ru", {"group_id": "g1", "body": "Алина: Влюблённость", "mood_id": "sad",
                         "title": "Грущу", "choices": [{"id": "love", "label": "Люблю"},
                                                       {"id": "sad", "label": "Грущу"},
                                                       {"id": "pride", "label": "Горжусь"}]}),
]


def look(item_id):
    found = КАТАЛОГ.get(item_id)
    return (found[0], found[1]) if found else None


# Подписи, которые обложка берёт помимо КЛЮЧИ_ТЕКСТОВ (общие с прежними пушами).
ОБЩИЕ = ("partner", "message", "miss_title", "mood_title", "date_untitled", "snow_title", "snow_body")


def dart_texts():
    """`lib/l10n/push_cover_texts.dart`: подписи обложки для Dart, из того же
    `push_texts.ТЕКСТЫ`, что и у сервера."""
    import push_texts
    ключи = list(push_cover.КЛЮЧИ_ТЕКСТОВ) + [k for k in ОБЩИЕ if k not in push_cover.КЛЮЧИ_ТЕКСТОВ]
    строки = [
        "// Создано pocketbase/hotpath/make_push_cover_fixtures.py — руками не править.",
        "//",
        "// Подписи обложки уведомлений «А» на девяти языках, те же, что у сервера",
        "// (`push_texts.py`): своё уведомление приложения выглядит как пуш.",
        "",
        "const List<String> kPushCoverLanguages = [" +
        ", ".join(f"'{код}'" for код in push_texts.ЯЗЫКИ) + "];",
        "",
        "const Map<String, Map<String, String>> kPushCoverTexts = {",
    ]
    for ключ in ключи:
        строки.append(f"  '{ключ}': {{")
        for код in push_texts.ЯЗЫКИ:
            текст = push_texts.ТЕКСТЫ[ключ][код].replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
            строки.append(f"    '{код}': '{текст}',")
        строки.append("  },")
    строки.append("};")
    return "\n".join(строки) + "\n"


def main():
    cases = [{"kind": k, "lang": lang, "ctx": ctx, "cover": push_cover.cover(k, lang, ctx, look)}
             for k, lang, ctx in ПРИМЕРЫ]
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    out = os.path.join(root, "test", "fixtures", "push_cover_cases.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"catalog": КАТАЛОГ, "cases": cases}, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"{len(cases)} примеров → {os.path.relpath(out, root)}")
    dart = os.path.join(root, "lib", "l10n", "push_cover_texts.dart")
    with open(dart, "w", encoding="utf-8") as f:
        f.write(dart_texts())
    print(f"подписи → {os.path.relpath(dart, root)}")


if __name__ == "__main__":
    main()
