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
  if (data.key !== key || (src === "coins" && (byAd || price <= 0)) || (src === "ad" && !byAd) || (src !== "coins" && src !== "ad")) {
    return e.json(400, { ok: false, error: "not_for_sale" });
  }

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
      const cost = src === "coins" ? price : 0;
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
