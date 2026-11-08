/// <reference path="../pb_data/types.d.ts" />

// Магазин гардероба Ту (01.11.2026): вещь за монеты или за просмотр ролика.
//
// Вещь — запись `catalog_items` вида `wear` с id `wear_<ключ>`. Цена и способ
// получения (`data.src`: `coins`, `ad`, `chest`) берутся из записи, а не из
// запроса: присланному числу верить нельзя. Сундучные вещи здесь не продаются,
// их выдаёт `chest.pb.js`. Купленное ложится в `users.owned_wear` — то же
// поле, что пишет сундук; клиент его менять не может (`users_guard.pb.js`).
//
// Ролик сервер проверить не умеет, как и у подарков за рекламу: вещь за ролик
// бесплатная, и подделанный запрос даёт ровно то же, что честный просмотр.
//
// С 09.11.2026 вещь за монеты можно забрать и роликами: ролик на каждые 50
// монет цены, с округлением вверх (зеркало — `wearAdsNeeded` в
// lib/models/tu_wear.dart). Каждый ролик — отдельный запрос с `ad: true`,
// досмотренные копятся в `users.wear_ad_views` (`{ключ: {n, at}}`, клиенту
// закрыто в users_guard), на последнем вещь выдаётся. Между роликами одной
// вещи не меньше 10 секунд: короче ролик не бывает, и подделка хотя бы
// тратит время. Вещь за ролик (`src: ad`) — тот же путь с одним роликом.
//
// Хелперы инлайнятся в обработчик: JSVM не видит функций уровня файла.
routerAdd("POST", "/api/wear/buy", (e) => {
  const safeParse = (s, fb) => { try { return JSON.parse(s || JSON.stringify(fb)) || fb; } catch (_) { return fb; } };
  const body = (e.requestInfo().body || {});
  const key = String(body.key || "").trim();
  const byAd = body.ad === true;
  const slug = key.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");

  let item = null;
  try { item = slug ? $app.findRecordById("catalog_items", "wear_" + slug) : null; } catch (_) { item = null; }
  if (!item || item.getString("kind") !== "wear" || !item.getBool("enabled")) {
    return e.json(400, { ok: false, error: "not_for_sale" });
  }
  const data = safeParse(item.getString("data"), {});
  const src = String(data.src || "");
  const price = item.getInt("price") || 0;
  if (data.key !== key || (src === "coins" && price <= 0) || (src === "ad" && !byAd) || (src !== "coins" && src !== "ad")) {
    return e.json(400, { ok: false, error: "not_for_sale" });
  }
  const AD_GAP_MS = 10000;
  const need = src === "ad" ? 1 : Math.ceil(price / 50);

  let out = { s: 500, b: { ok: false, error: "internal" } };
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);
      const coins = rec.getInt("coins") || 0;
      const owned = safeParse(rec.getString("owned_wear"), []);
      if (owned.indexOf(key) !== -1) {
        out = { s: 200, b: { ok: true, already: true, coins: coins, ownedWear: owned } };
        return;
      }
      if (byAd) {
        let views = safeParse(rec.getString("wear_ad_views"), {});
        if (typeof views !== "object" || Array.isArray(views)) views = {};
        const prev = views[key] || {};
        const now = Date.now();
        if (prev.at && now - prev.at < AD_GAP_MS) {
          out = { s: 429, b: { ok: false, error: "too_fast", progress: prev.n || 0, need: need } };
          return;
        }
        const n = (prev.n || 0) + 1;
        const granted = n >= need;
        if (granted) delete views[key];
        else views[key] = { n: n, at: now };
        const next = granted ? owned.concat([key]) : owned;
        rec.set("wear_ad_views", JSON.stringify(views));
        if (granted) rec.set("owned_wear", JSON.stringify(next));
        txApp.save(rec);
        out = { s: 200, b: { ok: true, already: false, granted: granted, progress: granted ? need : n, need: need, coins: coins, ownedWear: next } };
        return;
      }
      const cost = price;
      if (coins < cost) {
        out = { s: 402, b: { ok: false, error: "insufficient", coins: coins } };
        return;
      }
      const next = owned.concat([key]);
      if (cost) rec.set("coins", coins - cost);
      rec.set("owned_wear", JSON.stringify(next));
      txApp.save(rec);
      out = { s: 200, b: { ok: true, already: false, coins: coins - cost, ownedWear: next } };
    });
  } catch (err) {
    $app.logger().warn("wear buy failed", "key", key, "error", String(err));
    return e.json(500, { ok: false, error: "tx_failed" });
  }
  return e.json(out.s, out.b);
}, $apis.requireAuth());
