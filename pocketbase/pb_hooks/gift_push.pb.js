/// <reference path="../pb_data/types.d.ts" />
// gift_push.pb.js — пуш получателю, что ему пришёл подарок (TOG-10, 21.10.2026).
//
// Подарки создают три роута: покупка (gifts.pb.js), подарок из сундука
// (chest.pb.js, /api/chest/give) и отданная рамка (frame_gift.pb.js). Хук
// висит на самой коллекции, поэтому говорит обо всех трёх; запись внутри
// транзакции роута доходит сюда после её фиксации.
//
// Отложенный подарок (письмо идёт сутки, завтрак ждёт утра) при создании
// молчит, о нём говорит крон в момент доставки.
//
// Правила и отправка — в gift_push.js: обработчик JSVM не видит функций
// уровня файла.

onRecordAfterCreateSuccess((e) => {
  try {
    const rule = require(`${__hooks}/gift_push.js`);
    if (rule.pushOnCreate(rule.fromRecord(e.record), Date.now())) rule.notify(e.record);
  } catch (err) {
    $app.logger().warn("подарок: пуш не ушёл", "err", String(err));
  }
  e.next();
}, "gifts");

cronAdd("giftDeliveredPush", "*/5 * * * *", () => {
  try {
    const rule = require(`${__hooks}/gift_push.js`);
    const now = Date.now();
    const from = rule.windowFrom(Number($app.store().get("giftPushCronAt") || 0), now);
    $app.store().set("giftPushCronAt", now);
    const recs = $app.findRecordsByFilter(
      "gifts",
      "state = 'sent' && deliver_at > {:from} && deliver_at <= {:to}",
      "", 200, 0, { from: from, to: now });
    for (let i = 0; i < recs.length; i++) {
      const rec = recs[i];
      const created = new Date(String(rec.getString("created")).replace(" ", "T")).getTime();
      if (rule.dueInWindow(rule.fromRecord(rec), from, now, created)) rule.notify(rec);
    }
  } catch (err) {
    $app.logger().warn("подарок: крон пушей", "err", String(err));
  }
});
