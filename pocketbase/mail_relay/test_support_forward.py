"""Перекладка писем support@ в Gmail: правила без сети.

    python3 -m unittest discover -s pocketbase/mail_relay -p 'test_*.py'
"""
import json
import unittest

import support_forward as forward


def letter(sender, subject="Не могу войти", keywords=None):
    return {
        "id": "m1",
        "blobId": "b1",
        "from": [{"email": sender}],
        "subject": subject,
        "keywords": keywords or {},
    }


class WorthCopying(unittest.TestCase):
    def test_letter_from_a_person_is_copied(self):
        self.assertTrue(forward.worth_copying(letter("anna@gmail.com")))

    def test_own_bounce_is_not_copied(self):
        self.assertFalse(forward.worth_copying(letter("MAILER-DAEMON@togetherly.day")))
        self.assertFalse(forward.worth_copying(letter("postmaster@togetherly.day")))

    def test_feedback_without_account_mail_is_copied(self):
        # Обращение из приложения от человека без почты приходит от имени ящика.
        self.assertTrue(forward.worth_copying(letter("support@togetherly.day", "[Приложение] Ошибка")))

    def test_foreign_bounce_is_copied(self):
        # Отказ чужого сервера говорит, что ответ человеку не дошёл.
        self.assertTrue(forward.worth_copying(letter("mailer-daemon@icloud.com")))

    def test_letter_without_sender_is_copied(self):
        self.assertTrue(forward.worth_copying({"id": "m1", "blobId": "b1", "from": None}))


class InboxQuery(unittest.TestCase):
    def test_asks_only_fresh_letters_without_the_mark(self):
        calls = forward.inbox_query("acc", "inbox1", "2026-10-28T00:00:00Z")
        conditions = calls[0][1]["filter"]["conditions"]
        self.assertIn({"inMailbox": "inbox1"}, conditions)
        self.assertIn({"notKeyword": forward.COPIED}, conditions)
        self.assertIn({"notKeyword": forward.REFUSED}, conditions)
        self.assertIn({"after": "2026-10-28T00:00:00Z"}, conditions)

    def test_oldest_letter_goes_first(self):
        calls = forward.inbox_query("acc", "inbox1", "2026-10-28T00:00:00Z")
        self.assertEqual(calls[0][1]["sort"], [{"property": "receivedAt", "isAscending": True}])


class DownloadUrl(unittest.TestCase):
    def test_letter_is_read_from_the_local_server(self):
        url = forward.download_url("acc", "blob/1")
        self.assertTrue(url.startswith("http://127.0.0.1:8080/jmap/download/acc/blob%2F1/"))
        self.assertIn("accept=message%2Frfc822", url)


class ImportRequest(unittest.TestCase):
    def test_letter_lands_unread_in_the_inbox(self):
        headers, body = forward.import_request(b"From: a@b.c\r\n\r\nhello", boundary="edge")
        self.assertEqual(headers["Content-Type"], 'multipart/related; boundary="edge"')
        first, second = body.split(b"--edge\r\n")[1:3]
        labels = json.loads(first.split(b"\r\n\r\n", 1)[1])
        self.assertEqual(labels, {"labelIds": ["INBOX", "UNREAD"]})
        self.assertIn(b"Content-Type: message/rfc822", second)

    def test_letter_bytes_are_untouched(self):
        raw = b"From: a@b.c\r\nSubject: =?utf-8?b?0J/RgNC40LLQtdGC?=\r\n\r\n\xd0\xbf\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82\r\n"
        _, body = forward.import_request(raw, boundary="edge")
        self.assertIn(b"\r\n\r\n" + raw + b"\r\n--edge--", body)

    def test_spam_filter_of_gmail_cannot_hide_the_letter(self):
        self.assertIn("neverMarkSpam=true", forward.IMPORT_URL)


class MarkRequest(unittest.TestCase):
    def test_mark_keeps_other_keywords(self):
        calls = forward.mark_request("acc", "m1", forward.COPIED)
        self.assertEqual(calls[0][1]["update"], {"m1": {"keywords/" + forward.COPIED: True}})


if __name__ == "__main__":
    unittest.main()
