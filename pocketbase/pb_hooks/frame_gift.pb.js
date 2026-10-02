/// Рамка аватарки в подарок партнёру (02.10.2026, просьба из отзыва: «рамки
/// можно было дарить, хоть за жетоны, хоть за рекламу. у меня их 5, и я не
/// знаю, что с ними делать»).
///
///   GET  /api/frames/gift-quote?key=&groupId=  — можно ли подарить и за сколько;
///   POST /api/frames/give                      — отдать рамку партнёру.
///
/// Рамка ПЕРЕХОДИТ: у дарителя она пропадает (надетая снимается), у партнёра
/// появляется. Копий не бывает, поэтому рамки по-прежнему приходят в пару
/// только из сундука. Отданную рамку сундук снова может выдать дарителю.
///
/// Плата за передачу — монеты по редкости или ролик. Ролик делит лимит с
/// подарками за рекламу: три в сутки по записям `gifts` с нулевой ценой.
/// С Плюсом клиент шлёт `ad: true` без ролика, как и у обычных подарков.
///
/// Партнёру уходит запись `gifts` с ключом `frame_<ключ>`: она приходит как
/// подарок и ждёт отклика. Рамку партнёр получает сразу при отправке, отклик
/// ничего не выдаёт, поэтому сборки, которые не знают такой ключ, рамку тоже
/// видят (в магазине она станет «Твоей»).
///
/// ИДЕМПОТЕНТНОСТЬ: `giftId` генерит клиент, он же `id` записи `gifts`.
///
/// !!! Обработчик PB JSVM не видит функций уровня файла (см. coins.pb.js), всё
/// повторено в обоих роутах.

routerAdd("GET", "/api/frames/gift-quote", (e) => {
  // Цена по редкости, если в каталоге у рамки нет своей (`price`).
  const PRICE = { common: 20, rare: 40, legendary: 60 };
  const AD_PER_DAY = 3;
  const q = e.request.url.query();
  const key = String(q.get("key") || "").trim();
  const groupId = String(q.get("groupId") || "").trim();
  const me = e.auth.id;
  if (!/^[a-z0-9_]{1,40}$/.test(key) || !groupId) return e.json(400, { ok: false, error: "bad_request" });

  let item = null;
  try { item = $app.findRecordById("catalog_items", "frame_" + key); } catch (_) { item = null; }
  if (!item || item.getString("kind") !== "frame" || !item.getBool("enabled")) {
    return e.json(404, { ok: false, error: "unknown_frame" });
  }
  let rarity = "common";
  try { rarity = String(JSON.parse(item.getString("data") || "{}").rarity || "common"); } catch (_) {}
  const price = item.getInt("price") > 0 ? item.getInt("price") : (PRICE[rarity] || PRICE.common);

  let members = [];
  try {
    const r = $http.send({
      url: "http://127.0.0.1:8120/internal/group-read?id=" + encodeURIComponent(groupId),
      method: "GET",
      timeout: 8,
    });
    const g = (r && r.json && r.json.record) || null;
    if (g && Array.isArray(g.members)) members = g.members;
  } catch (_) { members = []; }
  let isMember = false, partner = "";
  for (let i = 0; i < members.length; i++) {
    const m = String(members[i]);
    if (m === me) isMember = true;
    else if (!partner) partner = m;
  }
  if (!isMember || !partner) return e.json(403, { ok: false, error: "not_member" });

  const fk = "frame:frame_" + key;
  const user = $app.findRecordById("users", me);
  let mine = [];
  try { mine = JSON.parse(user.getString("owned_features") || "[]") || []; } catch (_) { mine = []; }
  let theirs = [];
  try {
    theirs = JSON.parse($app.findRecordById("users", partner).getString("owned_features") || "[]") || [];
  } catch (_) { theirs = []; }

  let adUsed = 0;
  try {
    adUsed = $app.findRecordsByFilter(
      "gifts",
      "sender_uid = {:me} && price = 0 && deliver_at > {:since}",
      "", AD_PER_DAY, 0,
      { me: me, since: Date.now() - 24 * 60 * 60 * 1000 },
    ).length;
  } catch (_) { adUsed = 0; }

  return e.json(200, {
    ok: true,
    price: price,
    owns: mine.indexOf(fk) !== -1,
    partnerHas: theirs.indexOf(fk) !== -1,
    adLeft: Math.max(0, AD_PER_DAY - adUsed),
    coins: user.getInt("coins") || 0,
  });
}, $apis.requireAuth());

routerAdd("POST", "/api/frames/give", (e) => {
  const PRICE = { common: 20, rare: 40, legendary: 60 };
  const AD_PER_DAY = 3;
  const LIFE_MS = 24 * 60 * 60 * 1000;

  const body = new DynamicModel({ giftId: "", groupId: "", key: "", ad: false });
  e.bindBody(body);
  const giftId = String(body.giftId || "").trim();
  const groupId = String(body.groupId || "").trim();
  const key = String(body.key || "").trim();
  const byAd = body.ad === true;
  const me = e.auth.id;
  if (!/^[a-z0-9]{15}$/.test(giftId) || !groupId || !/^[a-z0-9_]{1,40}$/.test(key)) {
    return e.json(400, { ok: false, error: "bad_request" });
  }

  let item = null;
  try { item = $app.findRecordById("catalog_items", "frame_" + key); } catch (_) { item = null; }
  if (!item || item.getString("kind") !== "frame" || !item.getBool("enabled")) {
    return e.json(404, { ok: false, error: "unknown_frame" });
  }
  let rarity = "common";
  try { rarity = String(JSON.parse(item.getString("data") || "{}").rarity || "common"); } catch (_) {}
  const listPrice = item.getInt("price") > 0 ? item.getInt("price") : (PRICE[rarity] || PRICE.common);
  const price = byAd ? 0 : listPrice;

  // Пара — из Postgres, как в gifts.pb.js: зеркало в SQLite отстаёт.
  let members = [];
  try {
    const r = $http.send({
      url: "http://127.0.0.1:8120/internal/group-read?id=" + encodeURIComponent(groupId),
      method: "GET",
      timeout: 8,
    });
    const g = (r && r.json && r.json.record) || null;
    if (g && Array.isArray(g.members)) members = g.members;
  } catch (_) { members = []; }
  let isMember = false, partner = "";
  for (let i = 0; i < members.length; i++) {
    const m = String(members[i]);
    if (m === me) isMember = true;
    else if (!partner) partner = m;
  }

  const fk = "frame:frame_" + key;
  let out = { s: 500, b: { ok: false, error: "internal" } };
  try {
    $app.runInTransaction((txApp) => {
      const user = txApp.findRecordById("users", me);
      let mine = [];
      try { mine = JSON.parse(user.getString("owned_features") || "[]") || []; } catch (_) { mine = []; }

      // Повтор после обрыва связи: запись уже есть, ничего не трогаем.
      let existing = null;
      try { existing = txApp.findRecordById("gifts", giftId); } catch (_) { existing = null; }
      if (existing) {
        out = {
          s: 200,
          b: {
            ok: true, repeated: true,
            coins: user.getInt("coins") || 0,
            ownedFeatures: mine,
            frame: user.getString("frame"),
          },
        };
        return;
      }

      if (!isMember || !partner) {
        out = { s: 403, b: { ok: false, error: "not_member" } };
        return;
      }
      if (mine.indexOf(fk) === -1) {
        out = { s: 409, b: { ok: false, error: "not_owned" } };
        return;
      }
      const p = txApp.findRecordById("users", partner);
      let theirs = [];
      try { theirs = JSON.parse(p.getString("owned_features") || "[]") || []; } catch (_) { theirs = []; }
      if (theirs.indexOf(fk) !== -1) {
        out = { s: 409, b: { ok: false, error: "partner_has" } };
        return;
      }

      const coins = user.getInt("coins") || 0;
      if (byAd) {
        let sent = [];
        try {
          sent = txApp.findRecordsByFilter(
            "gifts",
            "sender_uid = {:me} && price = 0 && deliver_at > {:since}",
            "", AD_PER_DAY, 0,
            { me: me, since: Date.now() - 24 * 60 * 60 * 1000 },
          );
        } catch (_) { sent = []; }
        if (sent.length >= AD_PER_DAY) {
          out = { s: 429, b: { ok: false, error: "ad_limit", coins: coins } };
          return;
        }
      }
      if (coins < price) {
        out = { s: 402, b: { ok: false, error: "insufficient", coins: coins } };
        return;
      }

      const now = Date.now();
      const g = new Record(txApp.findCollectionByNameOrId("gifts"));
      g.set("id", giftId);
      g.set("group_id", groupId);
      g.set("sender_uid", me);
      g.set("recipient_uid", partner);
      g.set("gift_key", "frame_" + key);
      g.set("note", "");
      g.set("price", price);
      g.set("state", "sent");
      g.set("deliver_at", now);
      g.set("expires_at", now + LIFE_MS);
      txApp.save(g);

      theirs.push(fk);
      p.set("owned_features", JSON.stringify(theirs));
      txApp.save(p);

      mine = mine.filter((x) => x !== fk);
      user.set("owned_features", JSON.stringify(mine));
      if (user.getString("frame") === key) user.set("frame", "");
      user.set("coins", coins - price);
      txApp.save(user);

      out = {
        s: 200,
        b: {
          ok: true, repeated: false,
          coins: coins - price,
          ownedFeatures: mine,
          frame: user.getString("frame"),
        },
      };
    });
  } catch (err) {
    try { $app.logger().error("frames/give: " + String(err), "key", key, "gift", giftId); } catch (_) {}
    out = { s: 500, b: { ok: false, error: "internal" } };
  }
  if (out.s >= 400 && out.s !== 402 && out.s !== 429) {
    try { $app.logger().warn("frames/give отказ", "error", out.b.error, "key", key, "uid", me); } catch (_) {}
  }
  return e.json(out.s, out.b);
}, $apis.requireAuth());
