/// <reference path="../pb_data/types.d.ts" />
// draw_invite.pb.js — «партнёр зовёт порисовать».
//
// ЗАЧЕМ: просьба тестера 17.08.2026 — «партнёр заходит рисовать, и второму
// приходит уведомление, мол зовёт порисовать». Раньше о том, что человек сел за
// холст, второй узнавал случайно: пуши шли на чат, настроение, «Скучаю» и
// воспоминания, а рисование молчало.
//
// ПОЧЕМУ РОУТ, А НЕ ХУК НА ЗАПИСЬ: при входе в раскраску приложение на сервер
// ничего не пишет, оно только читает. Первая запись появляется, когда палец уже
// поехал, — это `canvas_live`, и она обновляется каждые 150 мс на каждого
// рисующего. Хук на такой коллекции стоил бы сотни вызовов JSVM в секунду ради
// одного пуша раз в полчаса; ровно так JS-обвязка рассылки съедала четверть
// процессора базы, пока её не вынесли нативно. Штрихи (`canvas_strokes`) ведёт
// hotpath на питоне, и синхронный запрос в пуш-релей задержал бы саму запись.
//
// Частоту держит `users.draw_invite_ms` и правило из `draw_invite.js`: не чаще
// одного зова в полчаса. Партнёру, который сейчас в приложении, не шлём вовсе —
// он и так видит, что происходит на холсте.
//
// JSVM-грабли: обработчик не видит функций уровня файла, поэтому всё внутри, а
// правило частоты подключается через require. Список участников читается
// `getStringSlice` — `get("members")` по json-полю в этой сборке JSVM молча
// отдаёт не строку и не массив.

routerAdd("POST", "/api/draw/invite", (e) => {
  const me = e.auth ? e.auth.id : "";
  if (!me) return e.json(401, { ok: false, error: "no auth" });

  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const groupId = String(body.group_id || "").trim();
  if (!groupId) return e.json(400, { ok: false, error: "no group_id" });

  // Членство сверяем по users.group_ids — то же быстрое правило, что и во всех
  // парных роутах: через @collection.groups ответы уходили за 30 секунд.
  let mine = [];
  try { mine = e.auth.getStringSlice("group_ids") || []; } catch (_) { mine = []; }
  if (mine.indexOf(groupId) === -1) {
    return e.json(403, { ok: false, error: "not your group" });
  }

  let group;
  try { group = $app.findRecordById("groups", groupId); } catch (_) {
    return e.json(404, { ok: false, error: "no group" });
  }
  if (group.get("disbanded")) return e.json(200, { ok: true, sent: false, why: "disbanded" });

  const push = require(`${__hooks}/apns_push.js`);
  const rule = require(`${__hooks}/draw_invite.js`);

  // Кому не надо — решает общая рассылка: `sendTo` молчит для того, кто сейчас
  // в приложении, и для того, кто выключил этот вид уведомлений.
  //
  // Здесь остаётся только защита от лавины. Без неё десять входов в раскраску
  // за вечер дают партнёру десять пушей — на «Скучаю» этот урок уже пройден.
  const now = Date.now();
  const last = Number(e.auth.get("draw_invite_ms") || 0);
  if (!rule.mayInvite(last, now, rule.GAP_MS)) {
    return e.json(200, { ok: true, sent: false, why: "too soon" });
  }

  const name = String(e.auth.getString("display_name") || "").trim() || "Партнёр";
  push.notifyGroup(groupId, me, name + " зовёт порисовать",
    "Открыл раскраску — заходите рисовать вместе", "draw");

  try {
    e.auth.set("draw_invite_ms", now);
    $app.save(e.auth);
  } catch (err) {
    // Отметка не записалась — зов уже ушёл, поэтому только пишем в журнал:
    // ронять ответ незачем, худшее следствие — лишний зов через минуту.
    $app.logger().warn("зов порисовать: отметка не записалась", "err", String(err));
  }

  return e.json(200, { ok: true, sent: true });
});
