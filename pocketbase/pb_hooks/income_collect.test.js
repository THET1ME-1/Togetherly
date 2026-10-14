// Сводка дохода: реклама Яндекса при ограничении длины периода.
//
// Запуск: node pocketbase/pb_hooks/income_collect.test.js
//
// С октября 2026 РСЯ отвечает 400 «Очень большой период» на любой запрос
// длиннее восьми дней: и на готовые периоды (30days, thismonth, lastmonth),
// и на явные даты. Сводка просила тридцать дней одним запросом и показывала
// «РСЯ ответила 400» при работающей рекламе. Здесь сеть подменена
// такой же строгой: длинный период она не отдаёт, короткий отдаёт по доллару
// в день.
const assert = require('node:assert/strict');

const DAY = 864e5;
const calls = [];
let written = null;

function rsya(url) {
  const q = new URL(url).searchParams, period = q.getAll('period');
  calls.push(period.join('…'));
  if (period.length !== 2) return { statusCode: 400, raw: '{"errors":[{"detail":"[Очень большой период]"}]}' };
  const [a, b] = period.map(d => Date.parse(d + 'T00:00:00Z')), days = Math.round((b - a) / DAY) + 1;
  if (!(days >= 1 && days <= 8)) return { statusCode: 400, raw: '{"errors":[{"detail":"[Очень большой период]"}]}' };
  const byDay = q.get('dimension_field') === 'date|day', byName = q.get('entity_field') || (q.get('dimension_field') || '').split('|')[0];
  let points;
  if (byDay) points = Array.from({ length: days }, (_, n) => ({ dimensions: { date: [new Date(a + n * DAY).toISOString().slice(0, 10)] }, measures: [{ partner_wo_nds: 1, shows: 100 }] }));
  else if (q.get('entity_field') || q.get('dimension_field')) points = [{ dimensions: { [byName]: 'Баннер' }, measures: [{ partner_wo_nds: days, shows: days * 100 }] }, { dimensions: { [byName]: 'Сундук' }, measures: [{ partner_wo_nds: days * 2, shows: days * 10 }] }];
  else points = [{ dimensions: {}, measures: [{ partner_wo_nds: days }] }];
  return { statusCode: 200, json: { data: { points } } };
}

global.$http = { send: ({ url }) => (url.includes('partner.yandex.ru') ? rsya(url) : { statusCode: 500, raw: '{}' }) };
global.$os = { readFile: path => { if (path.endsWith('.rsya_token')) return 'жетон'; throw new Error('нет файла'); }, writeFile: (path, text) => { written = text; } };
global.$app = { logger: () => ({ warn() {}, info() {}, error() {} }), db: () => { throw new Error('базы в проверке нет'); } };

const result = require('./income_collect.js')();
const r = result.sources.rsya;

let ok = true;
const check = (name, fn) => { try { fn(); console.log('  ✓ ' + name); } catch (e) { ok = false; console.log('  ✗ ' + name + ' — ' + String(e.message).split('\n')[0]); } };

console.log('реклама Яндекса при периоде не длиннее восьми дней');
check('сводка собирается, а не падает с «РСЯ ответила 400»', () => assert.equal(r.ok, true, r.reason));
check('ни один запрос не длиннее семи дней: день в запасе', () => { assert.ok(calls.length > 0); for (const c of calls) { const [a, b] = c.split('…').map(d => Date.parse(d + 'T00:00:00Z')); assert.ok(Math.round((b - a) / DAY) + 1 <= 7, c); } });
check('ряд по дням за тридцать дней цел и без дыр', () => {
  assert.equal(r.days.length, 30);
  for (let n = 1; n < r.days.length; n++) assert.equal(Date.parse(r.days[n].d) - Date.parse(r.days[n - 1].d), DAY, r.days[n].d);
  assert.equal(r.days[r.days.length - 1].d, new Date().toISOString().slice(0, 10));
});
check('сегодня, вчера и тридцать дней считаются из ряда', () => { assert.equal(r.today, 1); assert.equal(r.yesterday, 1); assert.equal(r.d30, 30); assert.equal(r.d30_shows, 3000); });
check('текущий месяц — сумма его дней', () => assert.equal(r.month, new Date().getUTCDate()));
check('прошлый месяц сложен из кусков целиком', () => { const now = new Date(); assert.equal(r.prev_month, new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 0)).getUTCDate()); });
check('разбивки сложены по названию со всех кусков', () => {
  for (const key of ['formats', 'geo', 'os', 'blocks']) {
    assert.deepEqual(r[key].map(x => x.name), ['Сундук', 'Баннер'], key);
    assert.equal(r[key][0].v, 60, key); assert.equal(r[key][1].v, 30, key); assert.equal(r[key][1].s, 3000, key);
  }
});
check('сводка записана файлом', () => assert.ok(written && JSON.parse(written).sources.rsya.ok === true));

process.exit(ok ? 0 : 1);
