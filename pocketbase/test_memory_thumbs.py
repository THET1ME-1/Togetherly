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


class TikTokShort(unittest.TestCase):
    """Короткую ссылку oEmbed не понимает (400) — её раскрывают напрямую."""

    def test_canonical(self):
        loc = ('https://www.tiktok.com/@/video/7635947641318165768?_r=1&_d=secCg&u_code=eej8'
               '&share_item_id=7635947641318165768')
        self.assertEqual(mt.tiktok_canonical(loc), 'https://www.tiktok.com/@/video/7635947641318165768')
        self.assertEqual(mt.tiktok_canonical('https://www.tiktok.com/@mila.k/photo/7689170120257686805?x=1'),
                         'https://www.tiktok.com/@mila.k/photo/7689170120257686805')

    def test_deleted(self):
        # Удалённый ролик: короткая ссылка ведёт на главную TikTok.
        self.assertEqual(mt.tiktok_canonical('https://www.tiktok.com/?_r=1'), '')
        self.assertEqual(mt.tiktok_canonical(''), '')

    def test_short(self):
        self.assertTrue(mt.tiktok_is_short('https://vt.tiktok.com/ZSxTjxu37/'))
        self.assertTrue(mt.tiktok_is_short('https://vm.tiktok.com/ZNR78DvFd/'))
        self.assertFalse(mt.tiktok_is_short('https://www.tiktok.com/@a/video/1'))


class YandexBlur(unittest.TestCase):
    def test_blur_removed(self):
        url = ('http://avatars.mds.yandex.net/i?id=76f0-406746-vthumb&shower=30&blur=30&n=13')
        self.assertEqual(mt.unblur(url), 'http://avatars.mds.yandex.net/i?id=76f0-406746-vthumb&n=13')

    def test_other_untouched(self):
        url = 'https://i.pinimg.com/736x/a.jpg?blur=30'
        self.assertEqual(mt.unblur(url), url)


class VkVideo(unittest.TestCase):
    """ВК Видео: страница — пустая оболочка, обложку отдаёт встраиваемый плеер."""

    def test_ids(self):
        cases = {
            'https://vkvideo.ru/video-71299670_456242822': ('-71299670', '456242822', ''),
            'https://m.vk.com/video-56028029_456249855': ('-56028029', '456249855', ''),
            'https://vksport.vkvideo.ru/video-203488550_456240447?t=54m30s': ('-203488550', '456240447', ''),
            'https://vk.com/video123_456?list=abc': ('123', '456', ''),
            'https://vk.com/feed?z=video-1_2%2Fabc': ('-1', '2', ''),
            'https://vkvideo.ru/clip-30022666_456245733': ('-30022666', '456245733', ''),
            'https://vk.com/video_ext.php?oid=-5&id=7&hash=ab12': ('-5', '7', 'ab12'),
        }
        for url, want in cases.items():
            self.assertEqual(mt.vk_video_ids(url), want, url)

    def test_not_video(self):
        for url in ('https://vk.ru/audio819062209_456240268_274a579c002c273cd7', 'https://vk.com/id1',
                    'https://vkvideo.ru.evil.com/video-1_2', 'https://youtu.be/ro0KqgvlS4Y', ''):
            self.assertIsNone(mt.vk_video_ids(url), url)

    def test_poster_from_embed(self):
        html = ('..."image":[{"url":"https:\\/\\/sun9-1.vkuserphoto.ru\\/a.jpg","width":320,"height":240,'
                '"with_padding":1},{"url":"https:\\/\\/sun9-2.vkuserphoto.ru\\/b.jpg","width":1280,"height":720},'
                '{"url":"https:\\/\\/sun9-3.vkuserphoto.ru\\/c.jpg","width":720,"height":405},'
                '{"url":"https:\\/\\/sun9-4.vkuserphoto.ru\\/d.jpg","width":4096,"height":2304}],'
                '"first_frame":[{"url":"https:\\/\\/iv.okcdn.ru\\/x","width":1280}]...')
        # Без полей по краям и самый маленький не уже 720: 4096 — лишние мегабайты.
        self.assertEqual(mt.vk_poster_of(html), 'https://sun9-3.vkuserphoto.ru/c.jpg')

    def test_poster_missing(self):
        self.assertEqual(mt.vk_poster_of('<html>нет данных</html>'), '')


class PageImage(unittest.TestCase):
    def test_og_image(self):
        html = '<meta property="og:image" content="https://i.pinimg.com/736x/a.jpg"/>'
        self.assertEqual(mt.og_image_of(html), 'https://i.pinimg.com/736x/a.jpg')
        html = '<meta content="https://avatars.mds.yandex.net/a?x=1&amp;y=2" property="og:image">'
        self.assertEqual(mt.og_image_of(html), 'https://avatars.mds.yandex.net/a?x=1&y=2')
        self.assertEqual(mt.og_image_of('<meta name="twitter:image" content="https://a.b/c.png">'),
                         'https://a.b/c.png')

    def test_generic_logo_refused(self):
        # Rutube на плейлисте отдаёт свой логотип — это не обложка ролика.
        self.assertEqual(mt.og_image_of(
            '<meta property="og:image" content="https://static.rtbcdn.ru/static/img/png/ogimglogo.png">'), '')

    def test_hosts(self):
        for url in ('https://www.kinopoisk.ru/series/256124/', 'https://music.yandex.ru/album/626064',
                    'https://pin.it/5ML4wEyiT', 'https://www.twitch.tv/t2x2', 'https://ok.ru/video/1',
                    'https://dzen.ru/video/watch/abc', 'https://yandex.ru/video/touch/preview/1',
                    'https://vimeo.com/1', 'https://rutube.ru/plst/519449/'):
            self.assertTrue(mt.page_thumb_host(url), url)
        for url in ('https://lord.kim/x', 'https://rt.pornhub.com/view_video.php', 'https://yandex.ru/search',
                    'https://vkvideo.ru/video-1_2', 'https://youtu.be/ro0KqgvlS4Y', 'http://127.0.0.1/'):
            self.assertFalse(mt.page_thumb_host(url), url)


if __name__ == '__main__':
    unittest.main(verbosity=2)
