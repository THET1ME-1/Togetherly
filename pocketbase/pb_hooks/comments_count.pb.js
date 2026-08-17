/// <reference path="../pb_data/types.d.ts" />
// comments_count.pb.js — счётчик комментариев под воспоминанием считает сервер.
//
// ЗАЧЕМ: цифру вёл клиент. Он прибавлял единицу оптимистично в кэш и ещё раз
// операцией очереди, а очередь умеет повторять отправку, поэтому бейдж
// разъезжался с фактом в обе стороны. Замер 17.08.2026 по проду: из 5109
// воспоминаний с бейджем расходятся 3077, у 230 цифра завышена (410 лишних
// комментариев), у остальных 2847 — занижена, и человек не видит, что под
// снимком уже идёт разговор. Жалоба звучит как «пишет 6, на самом деле 1»
// (и наоборот — «не понятно, когда друг комментирует»).
//
// То же лечение, что у memories_count в counters.pb.js: считает сервер по факту
// записи, клиент цифру больше не выдумывает.
//
// Счётчик живёт в json-поле `data` воспоминания (в схеме `memories` отдельной
// колонки нет), поэтому читаем карту, правим одно поле и сохраняем обратно.
//
// JSVM-грабли: обработчик не видит функций уровня файла, поэтому сам пересчёт
// лежит в модуле comments_count.js и подключается через require.

onRecordAfterCreateSuccess((e) => {
  try {
    const пересчёт = require(`${__hooks}/comments_count.js`);
    пересчёт.apply(String(e.record.getString("memory_id") || ""));
  } catch (err) {
    $app.logger().warn("счётчик комментариев: create", "err", String(err));
  }
  e.next();
}, "memory_comments");

onRecordAfterUpdateSuccess((e) => {
  try {
    const пересчёт = require(`${__hooks}/comments_count.js`);
    пересчёт.apply(String(e.record.getString("memory_id") || ""));
  } catch (err) {
    $app.logger().warn("счётчик комментариев: update", "err", String(err));
  }
  e.next();
}, "memory_comments");

onRecordAfterDeleteSuccess((e) => {
  try {
    const пересчёт = require(`${__hooks}/comments_count.js`);
    пересчёт.apply(String(e.record.getString("memory_id") || ""));
  } catch (err) {
    $app.logger().warn("счётчик комментариев: delete", "err", String(err));
  }
  e.next();
}, "memory_comments");
