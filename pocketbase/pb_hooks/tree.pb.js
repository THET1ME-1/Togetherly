/// <reference path="../pb_data/types.d.ts" />

// Ёлка пары (26.11.2026, docs/superpowers/specs/2026-11-26-xmas-tree-design.md).
//
// Ёлка одна на пару и сезон: `pair_trees` (стиль, звезда, гирлянда), игрушки —
// `tree_toys`, по записи на игрушку (кто повесил, точка подвеса в единицах ёлки
// −8…108). Писать в коллекции может только сервер, клиенту правила закрыты;
// партнёру правки уходят каналом пары сами (`centrifugo.pb.js`, белый список).
//
// Коробка игрушек — `users.owned_toys` = {ключ: штук}, клиенту закрыта
// (`users_guard.pb.js`). Каждая ёлка наряжается из всей коробки: моих игрушек
// вида X на одной ёлке не больше, чем X у меня. Снять может любой из пары —
// счёт ведётся по автору, игрушка «возвращается» ему сама.
//
// Новому человеку при первом `state` сервер кладёт стартовый набор.
//
// !!! ГРАБЛИ PB JSVM: обработчик не видит функций уровня файла — помощники
// продублированы в каждом.

routerAdd("GET", "/api/tree/state", (e) => {
  const safe = (s, fb) => { try { const v = JSON.parse(s || ""); return v && typeof v === "object" && !Array.isArray(v) ? v : fb; } catch (_) { return fb; } };
  const q = e.request.url.query();
  const group = String(q.get("group") || "");
  const season = parseInt(q.get("season") || "0", 10);
  if (!group || !(season >= 2020 && season <= 2100)) return e.json(400, { ok: false, error: "bad_request" });
  const mine = e.auth.getStringSlice("group_ids") || [];
  if (mine.indexOf(group) === -1) return e.json(403, { ok: false, error: "not_member" });

  // Стартовый набор: один раз (отметка `_st`), даже если сундук уже успел
  // положить игрушку раньше, чем человек открыл ёлку. Ключи с «_» — служебные,
  // приложение их не показывает.
  const STARTER = { red: 2, blue: 1, gold: 1, mint: 1, tu: 1, cane: 1, flake: 2 };
  let owned = {};
  try {
    $app.runInTransaction((txApp) => {
      const u = txApp.findRecordById("users", e.auth.id);
      owned = safe(u.getString("owned_toys"), {});
      if (!owned._st) {
        for (const k in STARTER) owned[k] = (parseInt(owned[k] || 0, 10) || 0) + STARTER[k];
        owned._st = 1;
        u.set("owned_toys", JSON.stringify(owned));
        txApp.save(u);
      }
    });
  } catch (err) {
    $app.logger().warn("tree state: starter failed", "uid", e.auth.id, "error", String(err));
  }

  let tree = { kind: "fir", star: true, garland: true };
  const seasons = [];
  try {
    const ts = $app.findRecordsByFilter("pair_trees", "group_id = {:g}", "-season", 50, 0, { g: group });
    for (let i = 0; i < ts.length; i++) {
      const s = ts[i].getInt("season");
      seasons.push(s);
      if (s === season) tree = { kind: ts[i].getString("kind") || "fir", star: ts[i].getBool("star"), garland: ts[i].getBool("garland") };
    }
  } catch (_) {}
  const toys = [];
  try {
    const rs = $app.findRecordsByFilter("tree_toys", "group_id = {:g} && season = {:s}", "created", 200, 0, { g: group, s: season });
    for (let i = 0; i < rs.length; i++) {
      const r = rs[i];
      toys.push({ id: r.id, toy: r.getString("toy"), x: r.getFloat("x"), y: r.getFloat("y"), author: r.getString("author"), created: r.getString("created") });
    }
  } catch (_) {}
  return e.json(200, { ok: true, tree: tree, toys: toys, owned: owned, seasons: seasons });
}, $apis.requireAuth());

routerAdd("POST", "/api/tree/hang", (e) => {
  const safe = (s, fb) => { try { const v = JSON.parse(s || ""); return v && typeof v === "object" && !Array.isArray(v) ? v : fb; } catch (_) { return fb; } };
  const b = e.requestInfo().body || {};
  const group = String(b.group || "");
  const season = parseInt(b.season, 10);
  const toy = String(b.toy || "");
  const x = Number(b.x), y = Number(b.y);
  if (!group || !(season >= 2020 && season <= 2100) || !/^[a-z][a-z0-9]{0,23}$/.test(toy)) return e.json(400, { ok: false, error: "bad_request" });
  if (!isFinite(x) || !isFinite(y) || x < -8 || x > 108 || y < -8 || y > 108) return e.json(400, { ok: false, error: "bad_point" });
  const mine = e.auth.getStringSlice("group_ids") || [];
  if (mine.indexOf(group) === -1) return e.json(403, { ok: false, error: "not_member" });
  const MAX = 60;
  let out = { s: 500, b: { ok: false, error: "internal" } };
  try {
    $app.runInTransaction((txApp) => {
      // Первым шагом — запись: она берёт блокировку SQLite, и второй такой же
      // запрос (двойное касание, оба в паре разом) ждёт и читает уже свежий счёт.
      // Начни транзакцию с чтения — оба прочли бы «одна свободная» и повесили обе.
      txApp.db().newQuery("UPDATE users SET owned_toys = owned_toys WHERE id = {:id}").bind({ id: e.auth.id }).execute();
      const u = txApp.findRecordById("users", e.auth.id);
      const owned = safe(u.getString("owned_toys"), {});
      const have = parseInt(owned[toy] || 0, 10) || 0;
      const onTree = txApp.findRecordsByFilter("tree_toys", "group_id = {:g} && season = {:s}", "", MAX + 1, 0, { g: group, s: season });
      if (onTree.length >= MAX) { out = { s: 409, b: { ok: false, error: "full" } }; return; }
      let used = 0;
      for (let i = 0; i < onTree.length; i++) if (onTree[i].getString("author") === e.auth.id && onTree[i].getString("toy") === toy) used++;
      if (used >= have) { out = { s: 409, b: { ok: false, error: "not_owned" } }; return; }
      // ёлка этого сезона заводится с первой игрушкой
      let t = null;
      try { t = txApp.findFirstRecordByFilter("pair_trees", "group_id = {:g} && season = {:s}", { g: group, s: season }); } catch (_) { t = null; }
      if (!t) {
        t = new Record(txApp.findCollectionByNameOrId("pair_trees"));
        t.set("group_id", group); t.set("season", season); t.set("kind", "fir"); t.set("star", true); t.set("garland", true);
        txApp.save(t);
      }
      const r = new Record(txApp.findCollectionByNameOrId("tree_toys"));
      r.set("group_id", group); r.set("season", season); r.set("toy", toy);
      r.set("x", Math.round(x * 10) / 10); r.set("y", Math.round(y * 10) / 10); r.set("author", e.auth.id);
      txApp.save(r);
      out = { s: 200, b: { ok: true, toy: { id: r.id, toy: toy, x: r.getFloat("x"), y: r.getFloat("y"), author: e.auth.id, created: r.getString("created") } } };
    });
  } catch (err) {
    $app.logger().warn("tree hang failed", "uid", e.auth.id, "error", String(err));
    return e.json(500, { ok: false, error: "tx_failed" });
  }
  // Партнёру — каналом пары. Рассылку коллекций делает сборка PocketBase на Go
  // (`rtCollections` в pb-cgo/main.go), новая коллекция там требует пересборки;
  // ёлка меняется редко, поэтому маршрут шлёт сам. Сбой рассылки запись не ломает.
  if (out.s === 200) {
    try {
      const api = $os.getenv("CENTRIFUGO_API"), key = $os.getenv("CENTRIFUGO_API_KEY");
      const t = out.b.toy;
      if (api && key) $http.send({ method: "POST", url: api + "/publish", timeout: 3, headers: { "Content-Type": "application/json", "X-API-Key": key },
        body: JSON.stringify({ channel: "pair:" + group, data: { event: "create", collection: "tree_toys", record: { id: t.id, collectionName: "tree_toys", group_id: group, season: season, toy: t.toy, x: t.x, y: t.y, author: t.author, created: t.created } } }) });
    } catch (_) {}
  }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

routerAdd("POST", "/api/tree/move", (e) => {
  const b = e.requestInfo().body || {};
  const id = String(b.id || "");
  const x = Number(b.x), y = Number(b.y);
  if (!id || !isFinite(x) || !isFinite(y) || x < -8 || x > 108 || y < -8 || y > 108) return e.json(400, { ok: false, error: "bad_point" });
  let r = null;
  try { r = $app.findRecordById("tree_toys", id); } catch (_) { r = null; }
  if (!r) return e.json(404, { ok: false, error: "not_found" });
  const mine = e.auth.getStringSlice("group_ids") || [];
  if (mine.indexOf(r.getString("group_id")) === -1) return e.json(403, { ok: false, error: "not_member" });
  r.set("x", Math.round(x * 10) / 10); r.set("y", Math.round(y * 10) / 10);
  $app.save(r);
  try {
    const api = $os.getenv("CENTRIFUGO_API"), key = $os.getenv("CENTRIFUGO_API_KEY"), g = r.getString("group_id");
    if (api && key) $http.send({ method: "POST", url: api + "/publish", timeout: 3, headers: { "Content-Type": "application/json", "X-API-Key": key },
      body: JSON.stringify({ channel: "pair:" + g, data: { event: "update", collection: "tree_toys", record: { id: r.id, collectionName: "tree_toys", group_id: g, season: r.getInt("season"), toy: r.getString("toy"), x: r.getFloat("x"), y: r.getFloat("y"), author: r.getString("author"), created: r.getString("created") } } }) });
  } catch (_) {}
  return e.json(200, { ok: true });
}, $apis.requireAuth());

routerAdd("POST", "/api/tree/remove", (e) => {
  const b = e.requestInfo().body || {};
  const id = String(b.id || "");
  let r = null;
  try { r = $app.findRecordById("tree_toys", id); } catch (_) { r = null; }
  // уже снята (партнёр успел раньше) — для человека это тот же успех
  if (!r) return e.json(200, { ok: true, gone: true });
  const mine = e.auth.getStringSlice("group_ids") || [];
  if (mine.indexOf(r.getString("group_id")) === -1) return e.json(403, { ok: false, error: "not_member" });
  const g = r.getString("group_id"), s = r.getInt("season");
  $app.delete(r);
  try {
    const api = $os.getenv("CENTRIFUGO_API"), key = $os.getenv("CENTRIFUGO_API_KEY");
    if (api && key) $http.send({ method: "POST", url: api + "/publish", timeout: 3, headers: { "Content-Type": "application/json", "X-API-Key": key },
      body: JSON.stringify({ channel: "pair:" + g, data: { event: "delete", collection: "tree_toys", record: { id: id, collectionName: "tree_toys", group_id: g, season: s } } }) });
  } catch (_) {}
  return e.json(200, { ok: true });
}, $apis.requireAuth());

routerAdd("POST", "/api/tree/set", (e) => {
  const safe = (s, fb) => { try { const v = JSON.parse(s || ""); return v && typeof v === "object" && !Array.isArray(v) ? v : fb; } catch (_) { return fb; } };
  const b = e.requestInfo().body || {};
  const group = String(b.group || "");
  const season = parseInt(b.season, 10);
  if (!group || !(season >= 2020 && season <= 2100)) return e.json(400, { ok: false, error: "bad_request" });
  const mine = e.auth.getStringSlice("group_ids") || [];
  if (mine.indexOf(group) === -1) return e.json(403, { ok: false, error: "not_member" });
  const kind = b.kind == null ? null : String(b.kind);
  if (kind !== null && kind !== "fir" && kind !== "snowy") return e.json(400, { ok: false, error: "bad_kind" });
  if (kind === "snowy") {
    const owned = safe(e.auth.getString("owned_toys"), {});
    if (!((parseInt(owned.style_snowy || 0, 10) || 0) >= 1)) return e.json(409, { ok: false, error: "not_owned" });
  }
  let t = null;
  try { t = $app.findFirstRecordByFilter("pair_trees", "group_id = {:g} && season = {:s}", { g: group, s: season }); } catch (_) { t = null; }
  if (!t) {
    t = new Record($app.findCollectionByNameOrId("pair_trees"));
    t.set("group_id", group); t.set("season", season); t.set("kind", "fir"); t.set("star", true); t.set("garland", true);
  }
  if (kind !== null) t.set("kind", kind);
  if (typeof b.star === "boolean") t.set("star", b.star);
  if (typeof b.garland === "boolean") t.set("garland", b.garland);
  $app.save(t);
  try {
    const api = $os.getenv("CENTRIFUGO_API"), key = $os.getenv("CENTRIFUGO_API_KEY");
    if (api && key) $http.send({ method: "POST", url: api + "/publish", timeout: 3, headers: { "Content-Type": "application/json", "X-API-Key": key },
      body: JSON.stringify({ channel: "pair:" + group, data: { event: "update", collection: "pair_trees", record: { id: t.id, collectionName: "pair_trees", group_id: group, season: season, kind: t.getString("kind"), star: t.getBool("star"), garland: t.getBool("garland") } } }) });
  } catch (_) {}
  return e.json(200, { ok: true, tree: { kind: t.getString("kind"), star: t.getBool("star"), garland: t.getBool("garland") } });
}, $apis.requireAuth());

// Игрушка за монеты. Цена и способ — из записи каталога `toy_<ключ>`
// (`data.src = coins`), присланному числу не верим. Игрушки «только из сундука»
// здесь не продаются. Каждая покупка — ещё одна штука в коробку.
routerAdd("POST", "/api/toys/buy", (e) => {
  const safe = (s, fb) => { try { const v = JSON.parse(s || ""); return v && typeof v === "object" && !Array.isArray(v) ? v : fb; } catch (_) { return fb; } };
  const key = String((e.requestInfo().body || {}).key || "");
  if (!/^[a-z][a-z0-9]{0,23}$/.test(key)) return e.json(400, { ok: false, error: "not_for_sale" });
  let item = null;
  try { item = $app.findRecordById("catalog_items", "toy_" + key); } catch (_) { item = null; }
  if (!item || item.getString("kind") !== "toy" || !item.getBool("enabled")) return e.json(400, { ok: false, error: "not_for_sale" });
  const data = safe(item.getString("data"), {});
  const price = item.getInt("price") || 0;
  if (data.key !== key || data.src !== "coins" || price <= 0) return e.json(400, { ok: false, error: "not_for_sale" });
  let out = { s: 500, b: { ok: false, error: "internal" } };
  try {
    $app.runInTransaction((txApp) => {
      const u = txApp.findRecordById("users", e.auth.id);
      const coins = u.getInt("coins") || 0;
      if (coins < price) { out = { s: 402, b: { ok: false, error: "insufficient", coins: coins } }; return; }
      const owned = safe(u.getString("owned_toys"), {});
      owned[key] = (parseInt(owned[key] || 0, 10) || 0) + 1;
      u.set("coins", coins - price);
      u.set("owned_toys", JSON.stringify(owned));
      txApp.save(u);
      out = { s: 200, b: { ok: true, coins: coins - price, owned: owned } };
    });
  } catch (err) {
    $app.logger().warn("toy buy failed", "key", key, "error", String(err));
    return e.json(500, { ok: false, error: "tx_failed" });
  }
  return e.json(out.s, out.b);
}, $apis.requireAuth());
