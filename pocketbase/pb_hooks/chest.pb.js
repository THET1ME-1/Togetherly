/// Сундук недели: открывается за ролик, три раза в день, приз разыгрывает
/// сервер.
///
///   GET  /api/chest/state?tz=&platform=  — сколько осталось сегодня и шансы;
///   POST /api/chest/open                 — разыграть приз и выдать его.
///
/// В сундуке монеты, одиннадцать подарков, которых нет в витрине, и
/// Togetherly+. Шансы живут только здесь: экран сундука рисует ту таблицу,
/// что отдал `state`, поэтому проценты на экране всегда совпадают с розыгрышем.
///
/// Подарок из сундука ложится на полку получившего: запись `gifts` от
/// отправителя `chest` самому себе, сразу в состоянии `reacted`. Входящим он
/// не считается (там отбор по `state = "sent"`), и `gifts/send` его ключей не
/// знает — купить или подарить такой подарок нельзя.
///
/// Togetherly+ не выпадает на iPhone (там его не существует как понятия) и
/// тому, у кого он уже есть. Его доля уходит в «5 монет», и таблица, которую
/// видит человек, показывает ровно это.
///
/// «Сегодня» — по часам человека: `tz` — смещение от UTC в минутах. Подвинуть
/// часы можно, поэтому сверху стоит потолок за скользящие сутки.
///
/// ИДЕМПОТЕНТНОСТЬ: `openId` генерит клиент, он же `id` записи `chest_opens`.
/// Повтор после обрыва связи возвращает тот же приз и ничего не начисляет.
///
/// !!! ГРАБЛИ PB JSVM: обработчик исполняется в изолированном пуле и НЕ видит
/// функций уровня файла, поэтому таблица и хелперы продублированы в обоих.

routerAdd("GET", "/api/chest/state", (e) => {
  // Зеркало таблицы в /api/chest/open. Вес — в десятых долях процента.
  const ODDS = [
    ["coins5", "coins", 5, 350, "common"],
    ["coins10", "coins", 10, 200, "common"],
    ["cookieheart", "gift", 0, 50, "common"],
    ["teddy", "gift", 0, 40, "common"],
    ["potion", "gift", 0, 40, "common"],
    ["coins25", "coins", 25, 80, "rare"],
    ["throne", "gift", 0, 30, "rare"],
    ["champagne", "gift", 0, 30, "rare"],
    ["snowglobe", "gift", 0, 30, "rare"],
    ["rose", "gift", 0, 25, "rare"],
    ["perfume", "gift", 0, 25, "rare"],
    ["record", "gift", 0, 25, "rare"],
    ["locket", "gift", 0, 15, "legendary"],
    ["rings", "gift", 0, 10, "legendary"],
    ["plus", "plus", 0, 50, "legendary"],
  ];
  const PER_DAY = 3;

  const me = e.auth.id;
  const q = e.request.url.query();
  let tz = parseInt(q.get("tz") || "0", 10);
  if (!isFinite(tz) || tz < -840 || tz > 840) tz = 0;
  const ios = (q.get("platform") || "") === "ios";
  const shifted = new Date(Date.now() + tz * 60 * 1000);
  const day = shifted.toISOString().slice(0, 10);

  let user = null;
  try { user = $app.findRecordById("users", me); } catch (_) { user = null; }
  if (!user) return e.json(404, { ok: false, error: "no_user" });
  const noPlus = ios || user.getBool("plus");

  let used = 0;
  try {
    used = $app.findRecordsByFilter("chest_opens", "user_uid = {:me} && day = {:day}", "", PER_DAY, 0,
      { me: me, day: day }).length;
  } catch (_) { used = 0; }

  const odds = [];
  for (let i = 0; i < ODDS.length; i++) {
    const r = ODDS[i];
    if (r[1] === "plus" && noPlus) continue;
    let w = r[3];
    if (r[0] === "coins5" && noPlus) w += 50;
    odds.push({ key: r[0], kind: r[1], amount: r[2], weight: w, tier: r[4] });
  }
  return e.json(200, { ok: true, perDay: PER_DAY, left: Math.max(0, PER_DAY - used), day: day, odds: odds });
}, $apis.requireAuth());

routerAdd("POST", "/api/chest/open", (e) => {
  const ODDS = [
    ["coins5", "coins", 5, 350, "common"],
    ["coins10", "coins", 10, 200, "common"],
    ["cookieheart", "gift", 0, 50, "common"],
    ["teddy", "gift", 0, 40, "common"],
    ["potion", "gift", 0, 40, "common"],
    ["coins25", "coins", 25, 80, "rare"],
    ["throne", "gift", 0, 30, "rare"],
    ["champagne", "gift", 0, 30, "rare"],
    ["snowglobe", "gift", 0, 30, "rare"],
    ["rose", "gift", 0, 25, "rare"],
    ["perfume", "gift", 0, 25, "rare"],
    ["record", "gift", 0, 25, "rare"],
    ["locket", "gift", 0, 15, "legendary"],
    ["rings", "gift", 0, 10, "legendary"],
    ["plus", "plus", 0, 50, "legendary"],
  ];
  const PER_DAY = 3;
  // Потолок за скользящие сутки: против перевода часов туда-обратно.
  const PER_24H = 6;

  const body = new DynamicModel({ openId: "", groupId: "", tz: 0, platform: "" });
  e.bindBody(body);
  const openId = String(body.openId || "").trim();
  const groupId = String(body.groupId || "").trim();
  let tz = parseInt(String(body.tz), 10);
  if (!isFinite(tz) || tz < -840 || tz > 840) tz = 0;
  const ios = String(body.platform || "") === "ios";
  // Формат id записи PocketBase: он же станет id подарка на полке, а у
  // `gifts` поле id по умолчанию — 15 строчных букв и цифр.
  if (!/^[a-z0-9]{15}$/.test(openId) || !groupId) {
    return e.json(400, { ok: false, error: "bad_request" });
  }

  const me = e.auth.id;
  const now = Date.now();
  const day = new Date(now + tz * 60 * 1000).toISOString().slice(0, 10);

  // Состав пары — из Postgres, как в gifts.pb.js: зеркало в SQLite отстаёт.
  let members = [];
  try {
    const r = $http.send({
      url: "http://127.0.0.1:8120/internal/group-read?id=" + encodeURIComponent(groupId),
      method: "GET",
      timeout: 8,
    });
    const rec = (r && r.json && r.json.record) || null;
    if (rec && Array.isArray(rec.members)) members = rec.members;
  } catch (_) { members = []; }
  let isMember = false;
  for (let i = 0; i < members.length; i++) if (String(members[i]) === me) isMember = true;

  let out = { s: 500, b: { ok: false, error: "internal" } };
  try {
    $app.runInTransaction((txApp) => {
      const user = txApp.findRecordById("users", me);

      let existing = null;
      try { existing = txApp.findRecordById("chest_opens", openId); } catch (_) { existing = null; }
      if (existing) {
        if (existing.getString("user_uid") !== me) {
          out = { s: 409, b: { ok: false, error: "conflict" } };
          return;
        }
        let usedNow = 0;
        try {
          usedNow = txApp.findRecordsByFilter("chest_opens", "user_uid = {:me} && day = {:day}", "", PER_DAY, 0,
            { me: me, day: existing.getString("day") }).length;
        } catch (_) { usedNow = 0; }
        const key = existing.getString("prize");
        let kind = "coins";
        for (let i = 0; i < ODDS.length; i++) if (ODDS[i][0] === key) kind = ODDS[i][1];
        out = {
          s: 200,
          b: {
            ok: true, repeated: true,
            prize: { key: key, kind: kind, amount: existing.getInt("amount") },
            left: Math.max(0, PER_DAY - usedNow),
            coins: user.getInt("coins") || 0,
            plus: user.getBool("plus"),
          },
        };
        return;
      }

      if (!isMember) {
        out = { s: 403, b: { ok: false, error: "not_member" } };
        return;
      }

      let today = 0, lastDay = 0;
      try {
        today = txApp.findRecordsByFilter("chest_opens", "user_uid = {:me} && day = {:day}", "", PER_DAY, 0,
          { me: me, day: day }).length;
        const since = new Date(now - 24 * 60 * 60 * 1000).toISOString().replace("T", " ");
        lastDay = txApp.findRecordsByFilter("chest_opens", "user_uid = {:me} && created >= {:since}", "", PER_24H, 0,
          { me: me, since: since }).length;
      } catch (_) { today = 0; lastDay = 0; }
      if (today >= PER_DAY || lastDay >= PER_24H) {
        out = { s: 429, b: { ok: false, error: "chest_limit", left: 0 } };
        return;
      }

      // Розыгрыш по той же таблице, что показывает /api/chest/state.
      const noPlus = ios || user.getBool("plus");
      const pool = [];
      let total = 0;
      for (let i = 0; i < ODDS.length; i++) {
        const r = ODDS[i];
        if (r[1] === "plus" && noPlus) continue;
        let w = r[3];
        if (r[0] === "coins5" && noPlus) w += 50;
        pool.push([r[0], r[1], r[2], w]);
        total += w;
      }
      // Случайное число из криптостойкой строки, а не Math.random: пул JSVM
      // переиспользует рантаймы, и качеству его генератора верить незачем.
      const hex = $security.randomStringWithAlphabet(8, "0123456789abcdef");
      let roll = parseInt(hex, 16) % total;
      let prize = pool[0];
      for (let i = 0; i < pool.length; i++) {
        if (roll < pool[i][3]) { prize = pool[i]; break; }
        roll -= pool[i][3];
      }

      const rec = new Record(txApp.findCollectionByNameOrId("chest_opens"));
      rec.set("id", openId);
      rec.set("user_uid", me);
      rec.set("group_id", groupId);
      rec.set("day", day);
      rec.set("prize", prize[0]);
      rec.set("amount", prize[2]);
      txApp.save(rec);

      if (prize[1] === "coins") {
        user.set("coins", (user.getInt("coins") || 0) + prize[2]);
        txApp.save(user);
      } else if (prize[1] === "plus") {
        user.set("plus", true);
        user.set("plus_platform", "chest");
        user.set("last_plus_grant_ms", now);
        txApp.save(user);
      } else {
        // Подарок на полку: от сундука самому себе, уже принятый.
        const g = new Record(txApp.findCollectionByNameOrId("gifts"));
        g.set("id", openId);
        g.set("group_id", groupId);
        g.set("sender_uid", "chest");
        g.set("recipient_uid", me);
        g.set("gift_key", prize[0]);
        g.set("price", 0);
        g.set("refund", 0);
        g.set("state", "reacted");
        g.set("deliver_at", now);
        g.set("reacted_at", now);
        g.set("expires_at", now);
        txApp.save(g);
      }

      out = {
        s: 200,
        b: {
          ok: true, repeated: false,
          prize: { key: prize[0], kind: prize[1], amount: prize[2] },
          left: Math.max(0, PER_DAY - today - 1),
          coins: user.getInt("coins") || 0,
          plus: user.getBool("plus"),
        },
      };
    });
  } catch (err) {
    try {
      $http.send({
        url: "http://127.0.0.1:8000/api/1/store/",
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Sentry-Auth": "Sentry sentry_version=7, sentry_key=05953bce75c54cdb9fe149861d159da5",
        },
        body: JSON.stringify({
          message: "chest/open: " + String(err),
          level: "error",
          logger: "pb_hooks.chest",
          tags: { feature: "chest", route: "chest_open", open_id: openId, error_code: "server" },
        }),
        timeout: 5,
      });
    } catch (_) {}
    try { $app.logger().error("chest/open: " + String(err)); } catch (_) {}
    out = { s: 500, b: { ok: false, error: "internal" } };
  }
  return e.json(out.s, out.b);
}, $apis.requireAuth());
