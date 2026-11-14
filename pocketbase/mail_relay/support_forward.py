#!/usr/bin/env python3
"""Письма ящика support@togetherly.day — во «Входящие» stgroup.dev@gmail.com.

Владелец читает почту в Gmail, а в ящик на своём сервере не заглядывает никто.
Переслать письмо обычной почтой нельзя: у адреса сервера нет обратной записи
(PTR), и Gmail такие письма отбивает. Поэтому письмо кладётся в Gmail как есть,
через его API (messages.import): отправитель, тема и вложения остаются
прежними, и ответ из Gmail уходит человеку.

Проход: взять из «Входящих» письма без метки, положить каждое в Gmail,
поставить метку. Копия письма в ящике остаётся. С аргументом `watch` служба
живёт постоянно: проход идёт сразу, как почтовый сервер сообщил о новом
письме, а в тишине — раз в минуту на случай пропущенной вести.

Каждый проход вешает в Gmail метку «Поддержка» на все письма, адресованные
support@: и на переложенные отсюда, и на пришедшие почтой через Cloudflare.
Остальная почта владельца мешает искать письма людей, а фильтр Gmail ключ с
правом gmail.modify завести не может.

Окружение: SUPPORT_JMAP_BASIC (готовая строка «Basic …» ящика support@),
GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, GMAIL_READ_REFRESH_TOKEN (ключ с правом
gmail.modify), SUPPORT_FORWARD_SINCE (письма старше этого времени не трогаем).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

JMAP_URL = "http://127.0.0.1:8080/jmap/"
JMAP_USING = ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"]
TOKEN_URL = "https://oauth2.googleapis.com/token"

# Фильтр спама Gmail выключен: письмо в поддержку не должно пропасть в «Спаме».
IMPORT_URL = (
    "https://gmail.googleapis.com/upload/gmail/v1/users/me/messages/import"
    "?uploadType=multipart&neverMarkSpam=true&internalDateSource=dateHeader"
    "&processForCalendar=false"
)

GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me/"

# Метка писем людей в Gmail и поиск ещё не помеченных.
LABEL_NAME = "Поддержка"
LABEL_SEARCH = f"to:support@togetherly.day -label:{LABEL_NAME}"
LABEL_COLOR = {"backgroundColor": "#16a765", "textColor": "#ffffff"}

# Метки письма в ящике: «уже в Gmail» и «Gmail не принял».
COPIED = "gmail_copied"
REFUSED = "gmail_refused"

# Свои служебные отправители: отказы доставки собственного сервера.
OWN_ROBOTS = ("mailer-daemon@togetherly.day", "postmaster@togetherly.day")

BATCH = 20

# Сервер сам сообщает о новом письме и кладёт трубку; молчит — проход раз в минуту.
NEWS_URL = "http://127.0.0.1:8080/jmap/eventsource/?types=Email&closeafter=state&ping=0"
QUIET_SECONDS = 60


def worth_copying(email):
    senders = email.get("from") or []
    address = (senders[0].get("email") or "").lower() if senders else ""
    return address not in OWN_ROBOTS


def inbox_query(account_id, inbox_id, since):
    conditions = [
        {"inMailbox": inbox_id},
        {"notKeyword": COPIED},
        {"notKeyword": REFUSED},
        {"after": since},
    ]
    query = {
        "accountId": account_id,
        "filter": {"operator": "AND", "conditions": conditions},
        "sort": [{"property": "receivedAt", "isAscending": True}],
        "limit": BATCH,
    }
    get = {
        "accountId": account_id,
        "#ids": {"resultOf": "q", "name": "Email/query", "path": "/ids"},
        "properties": ["id", "blobId", "from", "subject", "receivedAt"],
    }
    return [["Email/query", query, "q"], ["Email/get", get, "g"]]


def download_url(account_id, blob_id):
    blob = urllib.parse.quote(blob_id, safe="")
    kind = urllib.parse.quote("message/rfc822", safe="")
    return f"http://127.0.0.1:8080/jmap/download/{account_id}/{blob}/letter.eml?accept={kind}"


def import_request(raw_letter, label_id=None, boundary="togetherly-support-letter"):
    label_ids = ["INBOX", "UNREAD"] + ([label_id] if label_id else [])
    labels = json.dumps({"labelIds": label_ids}).encode()
    edge = boundary.encode()
    body = (
        b"--" + edge + b"\r\n"
        b"Content-Type: application/json; charset=UTF-8\r\n\r\n" + labels + b"\r\n"
        b"--" + edge + b"\r\n"
        b"Content-Type: message/rfc822\r\n\r\n" + raw_letter + b"\r\n"
        b"--" + edge + b"--\r\n"
    )
    headers = {"Content-Type": f'multipart/related; boundary="{boundary}"'}
    return headers, body


def mark_request(account_id, email_id, mark):
    update = {email_id: {"keywords/" + mark: True}}
    return [["Email/set", {"accountId": account_id, "update": update}, "m"]]


# ------------------------------------------------------------------ сеть
def jmap_headers():
    return {"Authorization": os.environ.get("SUPPORT_JMAP_BASIC", ""), "Content-Type": "application/json"}


def jmap_call(calls):
    body = json.dumps({"using": JMAP_USING, "methodCalls": calls}).encode()
    request = urllib.request.Request(JMAP_URL, data=body, headers=jmap_headers())
    return json.load(urllib.request.urlopen(request, timeout=60))["methodResponses"]


def jmap_account_and_inbox():
    request = urllib.request.Request(JMAP_URL + "session", headers=jmap_headers())
    account_id = list(json.load(urllib.request.urlopen(request, timeout=30))["accounts"])[0]
    boxes = jmap_call([["Mailbox/get", {"accountId": account_id}, "0"]])[0][1]["list"]
    inbox_id = [box["id"] for box in boxes if box.get("role") == "inbox"][0]
    return account_id, inbox_id


def read_letter(account_id, blob_id):
    request = urllib.request.Request(download_url(account_id, blob_id), headers=jmap_headers())
    return urllib.request.urlopen(request, timeout=120).read()


# Пропуск Gmail живёт час: проход идёт раз в минуту, и просить новый каждый раз незачем.
token_cache = {"token": "", "until": 0.0}


def gmail_token():
    if token_cache["until"] > time.time():
        return token_cache["token"]
    form = urllib.parse.urlencode({
        "client_id": os.environ["GMAIL_CLIENT_ID"],
        "client_secret": os.environ["GMAIL_CLIENT_SECRET"],
        "refresh_token": os.environ["GMAIL_READ_REFRESH_TOKEN"],
        "grant_type": "refresh_token",
    }).encode()
    answer = json.load(urllib.request.urlopen(TOKEN_URL, data=form, timeout=30))
    token_cache["token"] = answer["access_token"]
    token_cache["until"] = time.time() + answer.get("expires_in", 3600) - 300
    return token_cache["token"]


def gmail_call(token, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
    request = urllib.request.Request(GMAIL_API + path, data=data, headers=headers)
    answer = urllib.request.urlopen(request, timeout=60).read()
    return json.loads(answer) if answer else {}


def support_label(token):
    """Номер метки «Поддержка»; нет метки — заводит."""
    for label in gmail_call(token, "labels").get("labels", []):
        if label["name"] == LABEL_NAME:
            return label["id"]
    created = gmail_call(token, "labels", {
        "name": LABEL_NAME,
        "labelListVisibility": "labelShow",
        "messageListVisibility": "show",
        "color": LABEL_COLOR,
    })
    print(f"заведена метка «{LABEL_NAME}»", flush=True)
    return created["id"]


def label_support_letters(token, label_id):
    """Метит письма на support@, у которых метки ещё нет. Возвращает, сколько пометил."""
    marked = 0

    # Помеченные выпадают из поиска сами, поэтому каждый круг берёт следующую пачку.
    for _ in range(20):
        query = urllib.parse.urlencode({"q": LABEL_SEARCH, "maxResults": 500})
        ids = [m["id"] for m in gmail_call(token, "messages?" + query).get("messages", [])]
        if not ids:
            break
        gmail_call(token, "messages/batchModify", {"ids": ids, "addLabelIds": [label_id]})
        marked += len(ids)
    return marked


def put_into_gmail(raw_letter, token, label_id=None):
    headers, body = import_request(raw_letter, label_id)
    headers["Authorization"] = "Bearer " + token
    request = urllib.request.Request(IMPORT_URL, data=body, headers=headers)
    return json.load(urllib.request.urlopen(request, timeout=120))["id"]


def run_once():
    token = gmail_token()

    # Метка не должна держать перекладку: без неё письмо всё равно уходит в Gmail.
    try:
        label_id = support_label(token)
    except Exception as error:
        print(f"метка не получена: {error!r}", flush=True)
        label_id = None

    copied = copy_letters(token, label_id)

    if label_id:
        marked = label_support_letters(token, label_id)
        if marked:
            print(f"метка «{LABEL_NAME}»: {marked}", flush=True)
    return copied


def copy_letters(token, label_id):
    account_id, inbox_id = jmap_account_and_inbox()
    since = os.environ["SUPPORT_FORWARD_SINCE"]
    letters = jmap_call(inbox_query(account_id, inbox_id, since))[1][1]["list"]
    copied = 0
    for email in letters:
        about = f"{email['receivedAt'][:16]} «{(email.get('subject') or '')[:60]}»"

        # Свой отказ доставки в Gmail не нужен: метим и идём дальше.
        if not worth_copying(email):
            jmap_call(mark_request(account_id, email["id"], COPIED))
            continue

        # Письмо, которое Gmail не принимает совсем, не должно держать очередь.
        try:
            put_into_gmail(read_letter(account_id, email["blobId"]), token, label_id)
        except urllib.error.HTTPError as error:
            if error.code != 400:
                raise
            print(f"Gmail не принял письмо {about}: {error.read()[:300]!r}", flush=True)
            jmap_call(mark_request(account_id, email["id"], REFUSED))
            continue

        jmap_call(mark_request(account_id, email["id"], COPIED))
        print(f"в Gmail: {about}", flush=True)
        copied += 1
    return copied


def wait_for_news(open_url=urllib.request.urlopen, nap=time.sleep):
    """Ждёт, пока сервер скажет о перемене в письмах. Правда — весть пришла."""
    request = urllib.request.Request(NEWS_URL, headers=jmap_headers())
    try:
        open_url(request, timeout=QUIET_SECONDS).read()
        return True
    except TimeoutError:
        return False
    except Exception as error:
        if isinstance(getattr(error, "reason", None), TimeoutError):
            return False

        # Сервер не отвечает вовсе: пауза, чтобы не крутить цикл вхолостую.
        nap(QUIET_SECONDS)
        return False


def watch():
    while True:
        try:
            run_once()
        except Exception as error:
            print(f"проход сорвался: {error!r}", flush=True)
        wait_for_news()


if __name__ == "__main__":
    if sys.argv[1:] == ["watch"]:
        watch()
    run_once()
