/// <reference path="../pb_data/types.d.ts" />
// reels_invite.pb.js — «партнёр зовёт смотреть совместную ленту».
//
// Решение владельца 05.10.2026: ленту запускает только тот, у кого
// Togetherly+, а партнёру приходит пуш «Аня зовёт смотреть TikTok»; по нему
// он входит в ленту и без своего Плюса.
//
//   POST /api/reels/invite {group_id, feed}        — запустил ленту, позвать
//   POST /api/reels/invite {group_id, stop: true}  — вышел из ленты
//   GET  /api/reels/active?group_id=               — зовёт ли партнёр сейчас
//
// Зов живёт в $app.store(): перезапуск сервера его теряет, и это не беда —
// запустивший позовёт снова при следующем входе. Заводить поле ради трёх
// часов жизни незачем.
//
// Пуш уходит и тому, кто сейчас в приложении (`force`): внутри приложения о
// зове иначе не узнать. Частоту держит правило из reels_invite.js.
//
// JSVM-грабли: обработчик не видит функций уровня файла — всё внутри, правила
// через require. Членство — по users.group_ids, как в draw_invite.pb.js.

routerAdd("POST", "/api/reels/invite", (e) => {
  const me = e.auth ? e.auth.id : "";
  if (!me) return e.json(401, { ok: false, error: "no auth" });

  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const groupId = String(body.group_id || "").trim();
  if (!groupId) return e.json(400, { ok: false, error: "no group_id" });

  let mine = [];
  try { mine = e.auth.getStringSlice("group_ids") || []; } catch (_) { mine = []; }
  if (mine.indexOf(groupId) === -1) return e.json(403, { ok: false, error: "not your group" });

  const rule = require(`${__hooks}/reels_invite.js`);
  const key = "reels:" + groupId;
  const now = Date.now();

  if (body.stop) {
    const s = $app.store().get(key);
    if (s && s.by === me) { s.stopped = true; $app.store().set(key, s); }
    return e.json(200, { ok: true });
  }

  // Запускает только купивший: это и есть цена ленты.
  if (!e.auth.get("plus")) {
    $app.logger().warn("зов в ленту: нет Плюса", "uid", me);
    return e.json(403, { ok: false, error: "no_plus" });
  }

  let group;
  try { group = $app.findRecordById("groups", groupId); } catch (_) {
    return e.json(404, { ok: false, error: "no group" });
  }
  if (group.get("disbanded")) return e.json(200, { ok: true, sent: false, why: "disbanded" });

  const feed = rule.feedOf(body.feed) || "shorts";
  const name = String(e.auth.getString("display_name") || "").trim();
  $app.store().set(key, { by: me, name: name, feed: feed, at: now });

  const lastKey = "reelsInviteAt:" + me;
  if (!rule.mayInvite(Number($app.store().get(lastKey) || 0), now)) {
    return e.json(200, { ok: true, sent: false, why: "too soon" });
  }
  const msg = rule.message(name, feed);
  const push = require(`${__hooks}/apns_push.js`);
  // Ключ `from` в данных пуша Firebase держит за собой: с ним FCM отвечает
  // INVALID_ARGUMENT, а релей считает такой отказ мёртвым токеном и вычищает
  // его из профиля (поймано на тестовой паре 05.10.2026). Поэтому `by`.
  push.notifyGroup(groupId, me, msg.title, msg.body, "reels",
    { force: true, data: { feed: feed, group: groupId, by: me, name: name } });
  $app.store().set(lastKey, now);
  $app.logger().warn("зов в ленту отправлен", "uid", me, "group", groupId, "feed", feed);
  return e.json(200, { ok: true, sent: true });
});

routerAdd("GET", "/api/reels/active", (e) => {
  const me = e.auth ? e.auth.id : "";
  if (!me) return e.json(401, { ok: false, error: "no auth" });
  const groupId = String(e.request.url.query().get("group_id") || "").trim();
  let mine = [];
  try { mine = e.auth.getStringSlice("group_ids") || []; } catch (_) { mine = []; }
  if (!groupId || mine.indexOf(groupId) === -1) return e.json(403, { ok: false, error: "not your group" });

  const rule = require(`${__hooks}/reels_invite.js`);
  const s = $app.store().get("reels:" + groupId);
  if (!s || s.by === me || !rule.isActive(s, Date.now())) return e.json(200, { ok: true, active: false });
  return e.json(200, { ok: true, active: true, feed: s.feed, name: s.name, by: s.by, at: s.at });
});
