/// <reference path="../pb_data/types.d.ts" />
// counters.pb.js — СЕРВЕРНОЕ ведение счётчиков ПАРЫ для достижений.
// AchievementService (клиент) читает их прямо из group-дока:
//   messages_count  → «Первое сообщение / 100 / 1000 сообщений»
//   drawings_count  → «Первый рисунок»
//   memories_count  → плитка «Воспоминаний» в профиле, виджеты, достижения ленты
//
// ЗАЧЕМ НА СЕРВЕРЕ (а не в клиенте):
//  • messages_count — колонки не существовало, клиент её НИКОГДА не инкрементил →
//    достижения чата стояли на 0 у ВСЕХ пар (на проде у пары с 266 сообщениями —
//    0/1). Считаем по факту создания записи в chat_messages.
//  • drawings_count — клиент инкрементил лишь при создании холста ЧЕРЕЗ галерею;
//    массовый залив локальных холстов при паринге (canvas_storage_service
//    .pushAllToFirebase) и дефолтный «Canvas 1» шли МИМО счётчика → у пары с 43
//    холстами счётчик 0 («Первый рисунок 0/1»). Считаем по факту записи в
//    canvas_catalogue (единый источник — обе стороны видят один каталог).
//  • memories_count — клиент вёл его ОТДЕЛЬНОЙ операцией очереди (counterInc)
//    рядом с созданием записи, и любая её потеря расходилась навсегда: очередь
//    выбросила операцию, роут ответил отказом, приложение переставили, запись
//    завёл сам сервер (салют из подарков в gifts.pb.js) — во всех случаях
//    воспоминание в ленте есть, а цифра его не видит. На 5 августа 2026
//    расходилось 1618 пар из 6813: 1382 счётчика занижены (765 из них ровно на
//    единицу), 236 завышены. Жалоба звучит как «воспоминаний два, показывает
//    одно, добавляю заново — не видит».
//
// Серверный счёт чинит ВСЕХ разом и БЕЗ релиза: выпущенный клиент эти поля уже
// читает. Клиентские инкременты drawings_count и memories_count обезврежены в
// groups.pb.js (роут /api/group/increment для них → no-op ok), иначе старые
// версии, всё ещё дёргающие increment, задвоили бы счётчик с этим хуком.
//
// АТОМАРНО: read-modify-write в $app.runInTransaction — PB держит единственный
// write-коннект, поэтому параллельные создания сообщений с двух устройств
// сериализуются (без транзакции lost-update занижал бы счётчик к порогам
// 100/1000). Хук onRecordAfter*Success срабатывает ПОСЛЕ коммита создания →
// собственная транзакция безопасна (ср. birthdays.pb.js: $app.save в afterSuccess).
//
// JSVM-грабли (см. groups.pb.js): хендлер сериализуется и файловых функций НЕ
// видит → вся логика инлайн; сбой счётчика не должен ронять создание записи
// (весь хендлер в try/catch); e.next() — всегда.

// ── Сообщение создано → messages_count += 1 ─────────────────────────────────
onRecordAfterCreateSuccess((e) => {
  try {
    const groupId = e.record.getString("group_id");
    if (groupId) {
      $app.runInTransaction((txApp) => {
        const g = txApp.findRecordById("groups", groupId);
        g.set("messages_count", (g.getInt("messages_count") || 0) + 1);
        txApp.save(g);
      });
    }
  } catch (err) {
    console.log("counters: chat_messages inc failed", err);
  }
  e.next();
}, "chat_messages");

// ── Холст добавлен в каталог → drawings_count += 1 ──────────────────────────
onRecordAfterCreateSuccess((e) => {
  try {
    const groupId = e.record.getString("group_id");
    if (groupId) {
      $app.runInTransaction((txApp) => {
        const g = txApp.findRecordById("groups", groupId);
        g.set("drawings_count", (g.getInt("drawings_count") || 0) + 1);
        txApp.save(g);
      });
    }
  } catch (err) {
    console.log("counters: canvas_catalogue inc failed", err);
  }
  e.next();
}, "canvas_catalogue");

// ── Холст удалён из каталога → drawings_count -= 1 (не ниже 0) ───────────────
onRecordAfterDeleteSuccess((e) => {
  try {
    const groupId = e.record.getString("group_id");
    if (groupId) {
      $app.runInTransaction((txApp) => {
        const g = txApp.findRecordById("groups", groupId);
        const next = (g.getInt("drawings_count") || 0) - 1;
        g.set("drawings_count", next < 0 ? 0 : next);
        txApp.save(g);
      });
    }
  } catch (err) {
    console.log("counters: canvas_catalogue dec failed", err);
  }
  e.next();
}, "canvas_catalogue");

// ── Воспоминание создано → memories_count += 1 ──────────────────────────────
// Считаем ЛЮБУЮ запись ленты, кем бы она ни была заведена: своим клиентом,
// чужим старым клиентом или самим сервером (салют из gifts.pb.js).
onRecordAfterCreateSuccess((e) => {
  try {
    const groupId = e.record.getString("group_id");
    if (groupId && !e.record.getBool("deleted")) {
      $app.runInTransaction((txApp) => {
        const g = txApp.findRecordById("groups", groupId);
        g.set("memories_count", (g.getInt("memories_count") || 0) + 1);
        txApp.save(g);
      });
    }
  } catch (err) {
    console.log("counters: memories inc failed", err);
  }
  e.next();
}, "memories");

// ── Воспоминание удалено → memories_count -= 1 (не ниже 0) ──────────────────
onRecordAfterDeleteSuccess((e) => {
  try {
    const groupId = e.record.getString("group_id");
    if (groupId && !e.record.getBool("deleted")) {
      $app.runInTransaction((txApp) => {
        const g = txApp.findRecordById("groups", groupId);
        const next = (g.getInt("memories_count") || 0) - 1;
        g.set("memories_count", next < 0 ? 0 : next);
        txApp.save(g);
      });
    }
  } catch (err) {
    console.log("counters: memories dec failed", err);
  }
  e.next();
}, "memories");

// ── Мягкое удаление и его отмена → memories_count -= 1 / += 1 ───────────────
// Лента прячет записи с deleted = true, значит и цифра обязана их прятать.
// Правок у воспоминания много (подпись, закрепление, избранное, счётчик
// комментариев), поэтому флаг сверяется с прежним значением ДО транзакции:
// обычная правка не должна дёргать запись группы вовсе.
onRecordAfterUpdateSuccess((e) => {
  try {
    const groupId = e.record.getString("group_id");
    const now = e.record.getBool("deleted");
    const was = e.record.original().getBool("deleted");
    if (groupId && now !== was) {
      $app.runInTransaction((txApp) => {
        const g = txApp.findRecordById("groups", groupId);
        const next = (g.getInt("memories_count") || 0) + (now ? -1 : 1);
        g.set("memories_count", next < 0 ? 0 : next);
        txApp.save(g);
      });
    }
  } catch (err) {
    console.log("counters: memories soft-delete sync failed", err);
  }
  e.next();
}, "memories");
