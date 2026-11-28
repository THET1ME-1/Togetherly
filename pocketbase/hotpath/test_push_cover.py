"""Обложка уведомления «А» (28.11.2026): python3 test_push_cover.py"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import push_cover as pc  # noqa: E402

F = "https://togetherly.day/api/files"
КАТАЛОГ = {
    "art_act_miss": (["sm_a.webp", "lg_a.webp", "still_miss.png"], {}),
    "art_act_rest": (["still_rest.png"], {}),
    "art_act_wake": (["still_wake.png"], {}),
    "art_act_draw": (["still_draw.png"], {}),
    "moti": ([], {"moods": [{"id": "love", "url": f"{F}/catalog_items/moti/love_x.webp"}]}),
    "gift_bouquet": (["sm_b.webp", "still_bouquet.png"], {}),
    "frame_hearts": (["still_hearts.png"], {}),
    "art_chest_idle2": (["sm_c.webp", "still_chest.png"], {}),
}


def собрать(kind, lang="ru", **ctx):
    return pc.cover(kind, lang, ctx, КАТАЛОГ.get)


def ids(c):
    return [a["id"] for a in c["actions"]]


class ОтПартнёра(unittest.TestCase):
    def test_скучаю(self):
        c = собрать("miss", from_name="Алина", body="Хочу обнять")
        self.assertEqual(c["v"], 1)
        self.assertEqual(c["kicker"], "Скучаю · Алина")
        self.assertEqual(c["title"], "Скучает по тебе")
        self.assertEqual(c["body"], "Хочу обнять")
        self.assertEqual(c["tone"], "miss")
        self.assertEqual(c["art"], {"url": f"{F}/catalog_items/art_act_miss/still_miss.png"})
        self.assertEqual(ids(c), ["hug", "write"])
        self.assertEqual(c["actions"][0]["label"], "Обнять в ответ")
        # Ссылка `loveapp://miss` у виджета сама шлёт «Скучаю»: нажатие на
        # уведомление обязано только открыть экран.
        self.assertEqual(c["link"], "loveapp://open/miss")

    def test_кнопки_экрана_со_ссылкой_действия_телефона_без(self):
        c = собрать("miss", from_name="Алина", body="Хочу обнять", group_id="g1", event_id="e1")
        self.assertNotIn("link", c["actions"][0])            # обнять — делает телефон
        self.assertEqual(c["actions"][1]["link"], "loveapp://open/chat")  # написать
        self.assertEqual(c["group"], "g1")
        self.assertEqual(c["event_id"], "e1")
        чат = собрать("chat", from_name="Алина", body="Привет", group_id="g1", ts=1700)
        self.assertTrue(all("link" not in a for a in чат["actions"]))
        self.assertEqual(чат["chat"]["ts"], 1700)
        вечер = собрать("evening", title="Как прошёл день?")
        self.assertEqual([a["link"] for a in вечер["actions"]],
                         ["loveapp://open/mood", "loveapp://open/task"])

    def test_у_каждого_вида_ссылка_на_экран(self):
        for вид in ("miss", "mood", "chat", "memory", "date", "snowball", "gift", "comment",
                    "draw", "plusgift", "pair_reset", "security", "date_remind", "evening", "chest"):
            c = собрать(вид, from_name="Алина", title="Т", body="Б")
            self.assertTrue(c["link"].startswith("loveapp://open/"), вид)
            for a in c["actions"]:
                if a["id"] not in ("reply", "hug", "read", "throw"):
                    self.assertTrue(a["link"].startswith("loveapp://open/"), (вид, a))

    def test_настроение_котиком_моти(self):
        c = собрать("mood", from_name="Алина", mood_id="love", label="Влюблённость")
        self.assertEqual(c["art"], {"url": f"{F}/catalog_items/moti/love_x.webp"})
        self.assertEqual(c["title"], "Влюблённость")
        self.assertEqual(c["kicker"], "Настроение · Алина")
        self.assertEqual(c["tone"], "mood")

    def test_незнакомое_настроение_своя_картинка_нет_значит_иконка(self):
        c = собрать("mood", from_name="Алина", mood_id="custom_123", label="Своё")
        self.assertEqual(c["art"], {"app": True})

    def test_чат_переписка_с_аватаром_в_рамке(self):
        c = собрать("chat", from_name="Алина", body="Ты уже дома?",
                    avatar="pb://media/rec1/profile.jpg", frame="hearts", message_id="m1",
                    group_id="g1", from_uid="u1")
        self.assertEqual(c["chat"]["avatar"], f"{F}/media/rec1/profile.jpg?thumb=200x200")
        self.assertEqual(c["chat"]["frame"], f"{F}/catalog_items/frame_hearts/still_hearts.png")
        self.assertEqual(c["chat"]["message_id"], "m1")
        self.assertEqual(len(c["chat"]["quick"]), 3)
        self.assertEqual(ids(c), ["reply", "hug", "read"])
        self.assertEqual(c["title"], "Алина")

    def test_чат_несёт_подписи_для_шторки_и_рамку(self):
        КАТАЛОГ["frame_cloud"] = (["still_cloud.png"], {"hole": 27})
        c = собрать("chat", from_name="Алина", body="Привет", frame="cloud")
        self.assertEqual(c["chat"]["frame_hole"], 27)
        self.assertEqual(собрать("chat", body="x", frame="hearts")["chat"]["frame_hole"], 31)
        self.assertEqual(c["chat"]["you"], "Вы")
        self.assertTrue(c["chat"]["queued"])
        self.assertTrue(c["chat"]["hugged"])

    def test_чат_без_аватара_и_рамки(self):
        c = собрать("chat", from_name="Алина", body="Привет", avatar="", frame="")
        self.assertEqual(c["chat"]["avatar"], "")
        self.assertEqual(c["chat"]["frame"], "")

    def test_воспоминание_с_фото(self):
        c = собрать("memory", from_name="Алина", title="Вечер на крыше",
                    photo="pb://media/rec9/p.webp")
        self.assertEqual(c["art"], {"url": f"{F}/media/rec9/p.webp?thumb=400x400", "auth": True})
        self.assertEqual(c["title"], "Вечер на крыше")

    def test_новая_дата_значком(self):
        c = собрать("date", from_name="Алина", title="Концерт", symbol="theater_comedy")
        self.assertEqual(c["art"], {"symbol": "theater_comedy"})
        self.assertEqual(c["kicker"], "Новая дата · Алина")

    def test_снежок(self):
        c = собрать("snowball", from_name="Алина")
        self.assertEqual(c["art"]["url"], f"{F}/catalog_items/art_act_wake/still_wake.png")
        self.assertEqual(ids(c), ["throw"])


class ИзХуков(unittest.TestCase):
    """Подарок, комментарий, рисование, Плюс, пароль — пушат хуки PocketBase,
    обложку они берут у hotpath (`/internal/push-cover`)."""

    def test_подарок(self):
        c = собрать("gift", from_name="Алина", gift_key="bouquet", title="Букет", body="С запиской")
        self.assertEqual(c["kicker"], "Подарок · Алина")
        self.assertEqual(c["art"], {"url": f"{F}/catalog_items/gift_bouquet/still_bouquet.png"})
        self.assertEqual(c["title"], "Букет")
        self.assertEqual(ids(c), ["open"])

    def test_подарок_рамкой(self):
        c = собрать("gift", from_name="Алина", gift_key="frame_hearts", title="Рамка")
        self.assertEqual(c["art"], {"url": f"{F}/catalog_items/frame_hearts/still_hearts.png"})

    def test_комментарий(self):
        c = собрать("comment", from_name="Алина", body="Хочу туда снова",
                    photo="pb://media/r1/p.webp", title="Вечер на крыше")
        self.assertEqual(c["kicker"], "Комментарий · Алина")
        self.assertEqual(c["art"]["auth"], True)
        self.assertEqual(c["body"], "Хочу туда снова")

    def test_рисование(self):
        c = собрать("draw", from_name="Алина", title="Порисуем?", body="Открой холст")
        self.assertEqual(c["art"]["url"], f"{F}/catalog_items/art_act_draw/still_draw.png")
        self.assertEqual(ids(c), ["open"])

    def test_плюс_в_подарок_и_пароль_иконкой(self):
        self.assertEqual(собрать("plusgift", from_name="Алина", title="Плюс")["art"], {"app": True})
        self.assertEqual(собрать("pair_reset", title="Пароль меняют")["art"], {"app": True})


class ОтПриложения(unittest.TestCase):
    """Обложка — иконка приложения, картинка события — в развёрнутом виде."""

    def test_вечернее(self):
        c = собрать("evening", title="Как прошёл день?", body="Отметь настроение")
        self.assertEqual(c["art"], {"app": True})
        self.assertEqual(c["art_big"], {"url": f"{F}/catalog_items/art_act_rest/still_rest.png"})
        self.assertEqual(ids(c), ["mood", "task"])
        self.assertEqual(c["kicker"], "Вечернее напоминание")

    def test_напоминание_о_дате(self):
        c = собрать("date_remind", title="Годовщина", body="Завтра", symbol="cake")
        self.assertEqual(c["art"], {"app": True})
        self.assertEqual(c["art_big"], {"symbol": "cake"})

    def test_сундук(self):
        c = собрать("chest", title="Сундук снова полный", body="Загляни")
        self.assertEqual(c["art"], {"app": True})
        self.assertEqual(c["art_big"], {"url": f"{F}/catalog_items/art_chest_idle2/still_chest.png"})
        self.assertEqual(ids(c), ["chest"])


class ЧтоИзЗаписи(unittest.TestCase):
    """Экран блокировки видят и чужие: закрытое уходит без фото и названия."""

    def test_открытое_с_фото_и_названием(self):
        ctx = pc.memory_ctx({"data": {"title": " Крыша ", "imageUrl": "pb://media/r/p.webp"}}, "Алина")
        self.assertEqual(ctx, {"from_name": "Алина", "title": "Крыша", "photo": "pb://media/r/p.webp"})

    def test_секретное_18_и_капсула_без_фото(self):
        for ключ in ("isSecret", "isAdult", "sealed"):
            данные = {"title": "Тайна", "imageUrl": "pb://media/r/p.webp", ключ: True}
            self.assertEqual(pc.memory_ctx({"data": данные}, "Алина"), {"from_name": "Алина"}, ключ)
            c = собрать("memory", **pc.memory_ctx({"data": данные}, "Алина"))
            self.assertEqual(c["art"], {"app": True}, ключ)
            self.assertNotIn("Тайна", str(c), ключ)

    def test_данные_строкой_как_из_базы(self):
        rec = {"data": '{"isSecret": true, "imageUrl": "pb://media/r/p.webp"}'}
        self.assertEqual(pc.memory_ctx(rec, "Алина"), {"from_name": "Алина"})
        self.assertEqual(pc.memory_ctx({"data": "не json"}, "Алина")["photo"], "")

    def test_настроение(self):
        self.assertEqual(pc.mood_ctx({"mood_id": "love", "label": " Влюблённость "}),
                         {"mood_id": "love", "label": "Влюблённость"})


class Прочее(unittest.TestCase):
    def test_язык_получателя(self):
        c = собрать("miss", lang="en", from_name="Alina", body="I miss you")
        self.assertEqual(c["kicker"], "Missing you · Alina")
        self.assertEqual(c["actions"][0]["label"], "Hug back")

    def test_все_подписи_на_девяти_языках(self):
        import push_texts as pt
        for ключ in pc.КЛЮЧИ_ТЕКСТОВ:
            for язык in pt.ЯЗЫКИ:
                self.assertTrue(pt.ТЕКСТЫ[ключ].get(язык), f"{ключ}:{язык}")

    def test_незнакомый_вид_без_обложки(self):
        self.assertIsNone(собрать("wallet"))

    def test_без_имени_партнёр(self):
        c = собрать("miss", body="Хочу обнять")
        self.assertEqual(c["kicker"], "Скучаю · Партнёр")


if __name__ == "__main__":
    unittest.main(verbosity=1)
