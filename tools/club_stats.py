#!/usr/bin/env python3
"""Сводка по розыгрышу на togetherly.day/club: сколько участников и откуда.

Заходы считает Umami (сайт «Розыгрыш — Play Boy's Party»), а здесь точные
числа из базы: участие — это запись в club_entries, метка источника лежит в
поле src и приходит из адреса (?s=qr, ?s=ig и так далее).

Запускать НА СЕРВЕРЕ: API суперюзера снаружи закрыт.

    ssh -i ~/.ssh/togetherly_vps root@77.91.95.34
    cd /opt/pocketbase && ./pocketbase superuser create tmp-stats@x.local <пароль>
    SU=tmp-stats@x.local SP=<пароль> python3 - < tools/club_stats.py
    ./pocketbase superuser delete tmp-stats@x.local

Победителей тянуть отсюда же: `--draw 3` выбирает случайных и помечает
`winner`, но Togetherly+ не выдаёт — это отдельный осознанный шаг.
"""
import os
import sys
import json
import random
import urllib.request
import urllib.error
from collections import Counter

BASE = 'http://127.0.0.1:8090'
CAMPAIGN = 'playboysparty'


def call(path, method='GET', token=None, body=None):
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(BASE + path, method=method, data=data)
    if token:
        req.add_header('Authorization', token)
    if data:
        req.add_header('Content-Type', 'application/json')
    try:
        raw = urllib.request.urlopen(req, timeout=30).read()
        return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {'http': e.code, 'body': e.read().decode()[:300]}


def main():
    token = call('/api/collections/_superusers/auth-with-password', 'POST',
                 body={'identity': os.environ['SU'], 'password': os.environ['SP']}).get('token')
    if not token:
        print('не вышло войти суперюзером')
        return 1

    items, page = [], 1
    while True:
        chunk = call(f'/api/collections/club_entries/records?perPage=500&page={page}'
                     f'&filter=source%3D%22{CAMPAIGN}%22&sort=created', token=token)
        items += chunk.get('items', [])
        if page >= chunk.get('totalPages', 1):
            break
        page += 1

    print(f'Участников: {len(items)}')
    if not items:
        return 0

    by_src = Counter((e.get('src') or 'direct') for e in items)
    print('\nОткуда пришли:')
    width = max(len(s) for s in by_src) + 2
    for src, n in by_src.most_common():
        доля = round(n * 100 / len(items))
        print(f'  {src:<{width}} {n:>4}  {доля:>3}%  {"▮" * max(1, round(доля / 4))}')

    по_дням = Counter(e['created'][:10] for e in items)
    print('\nПо дням:')
    for день, n in sorted(по_дням.items()):
        print(f'  {день}  {n}')

    победители = [e for e in items if e.get('winner')]
    if победители:
        print(f'\nОтмечены победителями: {len(победители)}')

    if '--draw' in sys.argv:
        сколько = int(sys.argv[sys.argv.index('--draw') + 1])
        пул = [e for e in items if not e.get('winner')]
        выбор = random.sample(пул, min(сколько, len(пул)))
        print(f'\nЖребий на {сколько}:')
        for e in выбор:
            u = call('/api/collections/users/records/' + e['user'], token=token)
            call('/api/collections/club_entries/records/' + e['id'], 'PATCH', token, {'winner': True})
            print(f'  {u.get("email", e["user"])}  (участник от {e["created"][:16]}, источник {e.get("src") or "direct"})')
        print('\nОтмечены winner. Togetherly+ выдавать отдельно: '
              'PATCH users/<id> {"plus": true, "plus_platform": "code"}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
