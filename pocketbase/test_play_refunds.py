"""Правила снятия оплаченного при возврате Google Play (play_refunds.py).

Ошибка здесь стоит дорого в обе стороны: оставить Плюс после возврата —
человек пользуется даром (22.11.2026 так прожили четыре дня), снять лишнее —
отобрать купленное. Запуск: python3 pocketbase/test_play_refunds.py
"""

import unittest

from play_refunds import Purchase, User, plan

HOUR = 3_600_000


def user(uid, plus=True, platform="play", granted=0, groups=()):
    return User(uid=uid, plus=plus, platform=platform, granted_ms=granted, groups=tuple(groups))


class PlanTest(unittest.TestCase):
    def setUp(self):
        self.buy = Purchase(id="a" * 64, user_uid="payer", product="togetherly_plus", at_ms=10 * HOUR)
        self.gift = Purchase(id="b" * 64, user_uid="payer", product="togetherly_plus_gift", at_ms=10 * HOUR)

    def test_свой_плюс_из_play_снимается(self):
        actions = plan([self.buy], {self.buy.id: self.buy}, {"payer": user("payer")}, {})
        self.assertEqual([(a.kind, a.uid) for a in actions], [("revoke", "payer")])

    def test_плюс_из_другого_канала_не_трогаем(self):
        actions = plan([self.buy], {self.buy.id: self.buy}, {"payer": user("payer", platform="lava")}, {})
        self.assertEqual([a.kind for a in actions], ["manual"])

    def test_после_возврата_купил_снова_доступ_остаётся(self):
        again = Purchase(id="c" * 64, user_uid="payer", product="togetherly_plus", at_ms=20 * HOUR)
        purchases = {self.buy.id: self.buy, again.id: again}
        actions = plan([self.buy], purchases, {"payer": user("payer")}, {})
        self.assertEqual([a.kind for a in actions], ["manual"])

    def test_подарок_снимается_у_партнёра_которому_ушёл(self):
        users = {
            "payer": user("payer", groups=["g1"]),
            "partner": user("partner", platform="gift", granted=10 * HOUR + 9 * 60_000, groups=["g1"]),
        }
        actions = plan([self.gift], {self.gift.id: self.gift}, users, {"g1": ["payer", "partner"]})
        self.assertEqual([(a.kind, a.uid) for a in actions], [("revoke", "partner")])

    def test_подарок_выданный_раньше_покупки_не_этот(self):
        users = {
            "payer": user("payer", groups=["g1"]),
            "partner": user("partner", platform="gift", granted=5 * HOUR, groups=["g1"]),
        }
        actions = plan([self.gift], {self.gift.id: self.gift}, users, {"g1": ["payer", "partner"]})
        self.assertEqual([a.kind for a in actions], ["manual"])

    def test_был_ещё_подарок_после_возвращённого_не_трогаем(self):
        later = Purchase(id="d" * 64, user_uid="payer", product="togetherly_plus_gift", at_ms=12 * HOUR)
        users = {
            "payer": user("payer", groups=["g1"]),
            "partner": user("partner", platform="gift", granted=12 * HOUR, groups=["g1"]),
        }
        purchases = {self.gift.id: self.gift, later.id: later}
        actions = plan([self.gift], purchases, users, {"g1": ["payer", "partner"]})
        self.assertEqual([a.kind for a in actions], ["manual"])

    def test_монеты_и_незнакомые_чеки_только_сообщением(self):
        coins = Purchase(id="e" * 64, user_uid="payer", product="coins_500", at_ms=10 * HOUR)
        actions = plan([coins], {coins.id: coins}, {"payer": user("payer")}, {})
        self.assertEqual([a.kind for a in actions], ["manual"])
        unknown = Purchase(id="f" * 64, user_uid="", product="", at_ms=0)
        actions = plan([unknown], {}, {}, {})
        self.assertEqual([a.kind for a in actions], ["manual"])

    def test_плюса_уже_нет_снимать_нечего(self):
        actions = plan([self.buy], {self.buy.id: self.buy}, {"payer": user("payer", plus=False, platform="")}, {})
        self.assertEqual([a.kind for a in actions], ["done"])


if __name__ == "__main__":
    unittest.main()
