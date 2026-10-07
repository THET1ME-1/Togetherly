"""Проверки memory_thumbs.py без сервера: python3 pocketbase/test_memory_thumbs.py

Правило обложки по ссылке обязано совпадать с приложением
(`lib/utils/video_link_thumb.dart`, тест `test/utils/video_link_thumb_test.dart`):
сервер вписывает её в записи, приложение выводит на лету, и разъезд дал бы
разные картинки у одной записи в зависимости от версии.
"""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import memory_thumbs as mt  # noqa: E402

YT = 'https://i.ytimg.com/vi/ro0KqgvlS4Y/hqdefault.jpg'
RT_ID = 'c6cc4d620b1d4338901770a44b3e82f4'
RT = f'https://rutube.ru/api/video/{RT_ID}/thumbnail/?redirect=1'


class LinkThumb(unittest.TestCase):
    def test_youtube(self):
        for url in (
            'https://youtu.be/ro0KqgvlS4Y',
            'https://youtu.be/ro0KqgvlS4Y?si=63ToTj-Jgj_an5CT',
            'https://www.youtube.com/watch?v=ro0KqgvlS4Y&t=12',
            'https://m.youtube.com/watch?feature=share&v=ro0KqgvlS4Y',
            'https://youtube.com/shorts/ro0KqgvlS4Y?feature=share',
            'https://www.youtube.com/embed/ro0KqgvlS4Y',
            'https://www.youtube.com/live/ro0KqgvlS4Y',
        ):
            self.assertEqual(mt.link_thumb(url), YT, url)

    def test_rutube(self):
        self.assertEqual(mt.link_thumb(f'https://rutube.ru/video/{RT_ID}/'), RT)
        self.assertEqual(mt.link_thumb(f'https://rutube.ru/shorts/{RT_ID}/'), RT)

    def test_nothing(self):
        for url in ('https://vk.com/video-220754053_456239310', 'pb://media/abc/f.mp4', '', 'не ссылка',
                    'https://youtu.be/short', 'javascript:alert(1)'):
            self.assertEqual(mt.link_thumb(url), '', url)

    def test_same_cases_as_app(self):
        """Каждая ссылка из теста приложения даёт здесь ту же обложку."""
        here = os.path.dirname(__file__)
        dart = open(os.path.join(here, '..', 'test', 'utils', 'video_link_thumb_test.dart'), encoding='utf-8').read()
        pairs = re.findall(r"expect\(videoLinkThumb\('([^']*)'\),\s*(yt|thumb|'')\)", dart)
        self.assertGreater(len(pairs), 8, 'тест приложения разобран')
        want = {'yt': YT, 'thumb': RT, "''": ''}
        for url, kind in pairs:
            url = url.replace('$id', RT_ID)
            self.assertEqual(mt.link_thumb(url), want[kind], url)


class PbRef(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(mt.pb_ref('pb://media/ugq8nbu7sf4a9pl/1786453555756_v5zdc99cy.mp4'),
                         ('ugq8nbu7sf4a9pl', '1786453555756_v5zdc99cy.mp4'))

    def test_reject(self):
        for bad in ('https://x/y', 'pb://users/a/b', 'pb://media/../etc/passwd', 'pb://media/a', "pb://media/a/b'c"):
            self.assertIsNone(mt.pb_ref(bad), bad)


class Sql(unittest.TestCase):
    def test_update_only_empty(self):
        sql = mt.set_image_sql('abc123def456ghi', 'https://i.ytimg.com/vi/x/hqdefault.jpg', '2026-10-05 21:00:00.000Z')
        # Чужую обложку, вписанную в ту же минуту телефоном, не трогаем.
        self.assertIn("coalesce(data->>'imageUrl','') = ''", sql)
        self.assertIn("updated = '2026-10-05 21:00:00.000Z'", sql)
        self.assertIn("WHERE id = 'abc123def456ghi'", sql)

    def test_quotes_escaped(self):
        sql = mt.set_image_sql('cmnwiwwyv895nf1', "https://x/a'b", 'now')
        self.assertIn("a''b", sql)

    def test_bad_id_refused(self):
        with self.assertRaises(ValueError):
            mt.set_image_sql("a'; drop table memories; --", 'u', 'now')


class TikTok(unittest.TestCase):
    """Обложка TikTok (07.10.2026): открытой обложки по номеру у него нет,
    адрес даёт oEmbed, а живёт он двое суток — кадр сохраняется к нам."""

    def test_links(self):
        for url in ('https://vm.tiktok.com/ZGdQKq65S/',
                    'https://vt.tiktok.com/ZSbj74KPo/',
                    'https://www.tiktok.com/@thunf3tna0r/video/7657495716188753172',
                    'https://www.tiktok.com/@selqira0/photo/7689170120257686805',
                    'https://m.tiktok.com/v/7657495716188753172.html'):
            self.assertTrue(mt.is_tiktok(url), url)

    def test_not_links(self):
        for url in ('https://youtu.be/ro0KqgvlS4Y', 'https://tiktok.com.evil.ru/x',
                    'https://nottiktok.com/x', 'pb://media/a/b.mp4', '', 'javascript:alert(1)'):
            self.assertFalse(mt.is_tiktok(url), url)

    def test_oembed_thumb(self):
        good = ('https://p16-common-sign.tiktokcdn-eu.com/tos-alisg-p-0037/oYT~tplv-tiktokx-origin.image'
                '?x-expires=1791550800&x-signature=v6DS')
        self.assertEqual(mt.tiktok_thumb_of({'thumbnail_url': good}), good)

    def test_oembed_thumb_refused(self):
        # Только https и только сеть TikTok: адрес из ответа уйдёт в загрузку
        # с сервера, и подложенный внутренний адрес туда попасть не должен.
        for bad in ({}, {'thumbnail_url': ''}, {'thumbnail_url': 'http://p16.tiktokcdn.com/a.jpg'},
                    {'thumbnail_url': 'https://127.0.0.1/a.jpg'},
                    {'thumbnail_url': 'https://tiktokcdn.com.evil.ru/a.jpg'},
                    {'thumbnail_url': 42}):
            self.assertEqual(mt.tiktok_thumb_of(bad), '', bad)


if __name__ == '__main__':
    unittest.main(verbosity=2)
