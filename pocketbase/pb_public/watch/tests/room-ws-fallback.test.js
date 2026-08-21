/**
 * Порядок адресов сокета и переход на запасной.
 *
 * У части операторов нестандартный порт 8443 не отвергается, а МОЛЧА
 * проглатывается: соединение висит до TCP-таймаута, страница всё это время
 * мертва — «у одного всё нажимается, другой просто существует в комнате»
 * (жалоба 21.08.2026). Перебор адресов внутри centrifuge-js трогается с места
 * только по событию close, которого в этом случае нет.
 *
 * Отсюда два правила: первым идёт тот путь, по которому уже пришла сама
 * страница (443 — раз она открылась, он проходит), а если за несколько секунд
 * подключиться не вышло, клиент пересобирается на следующем адресе.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const room = readFileSync(join(here, '..', 'room', 'room.js'), 'utf8');

test('первым идёт путь через тот же порт, что у самой страницы', () => {
  const list = room.slice(room.indexOf('const WS = ['));
  const first = list.indexOf('wss://togetherly.day/connection/websocket');
  const second = list.indexOf('wss://rt.togetherly.day:8443/connection/websocket');
  assert.ok(first > 0 && second > 0, 'оба адреса на месте');
  assert.ok(first < second, 'через 443 — первым, 8443 — запасным');
});

test('у подключения есть срок: висящий порт не должен держать комнату', () => {
  assert.ok(/CONNECT_TIMEOUT\s*=\s*\d+/.test(room),
      'задан срок ожидания подключения');
  assert.ok(room.includes('свалиться на запасной адрес'),
      'есть переход на запасной адрес');
});
