/// Серверная логика «коинов» на PocketBase (миграция §6 — замена Firebase
/// Cloud Functions). Деньги считаются ТОЛЬКО здесь: цены/кулдауны/лимиты на
/// сервере, клиент не может их обойти. Зеркало functions/index.js.
///
/// ВАЖНО (PB JSVM грабли):
///  1) обработчик routerAdd сериализуется и исполняется в изолированном пуле — он
///     НЕ видит переменные/функции уровня файла. Поэтому каждый роут самодостаточен
///     (хелперы/цены/логика ИНЛАЙН внутри обработчика). Доступны только фреймворк-
///     глобалы ($app, $apis, e.*). Поля users — snake_case; кулдауны — epoch-ms.
///  2) АТОМАРНОСТЬ (COIN-1): любой read-modify-write баланса обёрнут в
///     $app.runInTransaction((txApp) => …). PB исполняет транзакции на единственном
///     неконкурентном write-коннекте → два параллельных запроса сериализуются:
///     второй читает уже обновлённый баланс. Это исключает двойное списание/начисление
///     (double-purchase, double-bonus, double-ad-reward). Внутри tx используем
///     ТОЛЬКО txApp (txApp.findRecordById / txApp.save), иначе операция не попадёт
///     в транзакцию. e.json вызываем ПОСЛЕ коммита (out перехватываем в замыкании).
///
/// Ответ зеркалит Cloud Functions (camelCase: coins/ownedThemes/awarded/...),
/// чтобы клиентский _applyServerResult читал его без изменений.

// ── Покупка темы ────────────────────────────────────────────────────────────
routerAdd("POST", "/api/coins/purchase-theme", (e) => {
  const safeParse = (s, fb) => { try { return JSON.parse(s || JSON.stringify(fb)) || fb; } catch (_) { return fb; } };
  const body = (e.requestInfo().body || {});
  const themeId = Number(body.themeId);
  if (!Number.isInteger(themeId) || themeId < 5 || themeId > 50) {
    return e.json(400, { ok: false, error: "bad themeId" });
  }
  const price = themeId === 16 ? 40 : 30;
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);
      const coins = rec.getInt("coins") || 0;
      const owned = safeParse(rec.getString("owned_themes"), []);
      if (owned.indexOf(themeId) !== -1) {
        out = { s: 200, b: { ok: true, alreadyOwned: true, coins: coins, ownedThemes: owned } };
        return;
      }
      if (coins < price) {
        out = { s: 402, b: { ok: false, error: "insufficient", coins: coins } };
        return;
      }
      const newOwned = owned.concat([themeId]).sort((a, b) => a - b);
      rec.set("coins", coins - price);
      rec.set("owned_themes", JSON.stringify(newOwned));
      txApp.save(rec);
      out = { s: 200, b: { ok: true, alreadyOwned: false, coins: coins - price, ownedThemes: newOwned } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Покупка профильной иконки ─────────────────────────────────────────────────
routerAdd("POST", "/api/coins/purchase-icon", (e) => {
  const safeParse = (s, fb) => { try { return JSON.parse(s || JSON.stringify(fb)) || fb; } catch (_) { return fb; } };
  const body = (e.requestInfo().body || {});
  const iconId = String(body.iconId || "");
  const PRICES = {
    "Paw": 20, "Sun": 20, "Moon": 20, "Rainbow": 20, "Bunny": 20, "Frog": 20,
    "Lucky": 35, "UFO": 35, "Together": 35,
    "Soulmate": 50, "Perfect Match": 50, "Inseparable": 50,
  };
  const price = PRICES[iconId];
  if (!price) return e.json(400, { ok: false, error: "not for sale" });
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);
      const coins = rec.getInt("coins") || 0;
      const owned = safeParse(rec.getString("owned_icons"), []);
      if (owned.indexOf(iconId) !== -1) {
        out = { s: 200, b: { ok: true, alreadyOwned: true, coins: coins, ownedIcons: owned } };
        return;
      }
      if (coins < price) {
        out = { s: 402, b: { ok: false, error: "insufficient", coins: coins } };
        return;
      }
      const newOwned = owned.concat([iconId]);
      rec.set("coins", coins - price);
      rec.set("owned_icons", JSON.stringify(newOwned));
      txApp.save(rec);
      out = { s: 200, b: { ok: true, alreadyOwned: false, coins: coins - price, ownedIcons: newOwned } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Покупка одноразовой фичи ──────────────────────────────────────────────────
routerAdd("POST", "/api/coins/purchase-feature", (e) => {
  const safeParse = (s, fb) => { try { return JSON.parse(s || JSON.stringify(fb)) || fb; } catch (_) { return fb; } };
  const body = (e.requestInfo().body || {});
  const featureId = String(body.featureId || "");
  const PRICES = { "days_widget_photos": 20 };
  let price = PRICES[featureId] || 0;

  // Элементы каталога продаются по СВОЕЙ цене, из своей же записи: ключ
  // владения выглядит как `вид:id` (`mascot:kuku`). Благодаря этому новый
  // платный персонаж заводится одной записью в `catalog_items` и продаётся
  // сразу — без правки этого хука и без новой сборки приложения.
  //
  // Цену берём с сервера, а не из запроса: присланному числу верить нельзя,
  // иначе любой купил бы маскота за одну монету.
  if (!price && featureId.indexOf(":") > 0) {
    const parts = featureId.split(":");
    const kind = String(parts[0] || "");
    const itemId = String(parts[1] || "");
    // Вид ключа владения → значение `kind` в каталоге. Новый вид платного
    // добавляется сюда одной строкой; сами элементы по-прежнему заводятся
    // записью в `catalog_items`, без сборки.
    const KINDS = { "mascot": "mascot_anim", "mood_pack": "mood_pack" };
    const wantKind = KINDS[kind];
    if (!wantKind || !itemId) return e.json(400, { ok: false, error: "not for sale" });

    let item = null;
    try { item = $app.findRecordById("catalog_items", itemId); } catch (_) { item = null; }
    if (!item) return e.json(400, { ok: false, error: "not for sale" });
    if (item.getString("kind") !== wantKind) return e.json(400, { ok: false, error: "not for sale" });
    if (!item.getBool("enabled")) return e.json(400, { ok: false, error: "not for sale" });
    if (item.getBool("is_free")) return e.json(400, { ok: false, error: "already free" });

    price = item.getInt("price") || 0;
    if (!price) {
      // Запасной путь: цена лежит в манифесте рядом с остальным про элемент.
      const data = safeParse(item.getString("data"), {});
      const unlock = (data && data.unlock) || {};
      price = typeof unlock.price === "number" ? unlock.price : 0;
    }
  }

  if (!price || price < 0) return e.json(400, { ok: false, error: "not for sale" });
  // Элементы каталога общие на пару: маскот живёт на главной у обоих, и серию
  // они растят вдвоём. Ключ поэтому кладётся ЕЩЁ И на группу — так партнёр
  // получает купленное, не платя второй раз. У покупателя ключ остаётся в
  // своём `owned_features` навсегда, даже если пара разойдётся.
  //
  // Раздача идёт и при повторном запросе: тот, кто купил в прошлой паре, обязан
  // поделиться и в новой, иначе персонаж достался бы только ему.
  const shareToGroups = (txApp, rec, key) => {
    if (key.indexOf(":") <= 0) return;
    const parse = (s, fb) => { try { return JSON.parse(s || JSON.stringify(fb)) || fb; } catch (_) { return fb; } };
    // `group_ids` — это relation, а не json: строкой его читать бесполезно,
    // нужен getStringSlice. На этом раздача купленного молча не работала.
    let groupIds = [];
    try { groupIds = rec.getStringSlice("group_ids") || []; } catch (_) { groupIds = []; }
    if (!groupIds.length) groupIds = parse(rec.getString("pair_ids"), []);
    for (let i = 0; i < groupIds.length; i++) {
      let grp = null;
      try { grp = txApp.findRecordById("groups", String(groupIds[i])); } catch (_) { grp = null; }
      if (!grp) continue;
      const gOwned = parse(grp.getString("owned_features"), []);
      if (gOwned.indexOf(key) !== -1) continue;
      grp.set("owned_features", JSON.stringify(gOwned.concat([key])));
      txApp.save(grp);
    }
  };

  let out;
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);
      const coins = rec.getInt("coins") || 0;
      const owned = safeParse(rec.getString("owned_features"), []);
      if (owned.indexOf(featureId) !== -1) {
        shareToGroups(txApp, rec, featureId);
        out = { s: 200, b: { ok: true, alreadyOwned: true, coins: coins, ownedFeatures: owned } };
        return;
      }
      if (coins < price) {
        out = { s: 402, b: { ok: false, error: "insufficient", coins: coins } };
        return;
      }
      const newOwned = owned.concat([featureId]);
      rec.set("coins", coins - price);
      rec.set("owned_features", JSON.stringify(newOwned));
      txApp.save(rec);
      shareToGroups(txApp, rec, featureId);

      out = { s: 200, b: { ok: true, alreadyOwned: false, coins: coins - price, ownedFeatures: newOwned } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Расходуемое списание (не «покупка навсегда») ──────────────────────────────
routerAdd("POST", "/api/coins/spend", (e) => {
  const body = (e.requestInfo().body || {});
  const actionId = String(body.actionId || "");
  const PRICES = { "chat_background": 20 };
  const price = PRICES[actionId];
  if (!price) return e.json(400, { ok: false, error: "unknown action" });
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);
      const coins = rec.getInt("coins") || 0;
      if (coins < price) {
        out = { s: 402, b: { ok: false, error: "insufficient", coins: coins } };
        return;
      }
      rec.set("coins", coins - price);
      txApp.save(rec);
      out = { s: 200, b: { ok: true, coins: coins - price, spent: price } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Ежедневный бонус (1, кулдаун 20ч) ─────────────────────────────────────────
routerAdd("POST", "/api/coins/daily-bonus", (e) => {
  const COOLDOWN = 20 * 60 * 60 * 1000;
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);
      const now = Date.now();
      const last = rec.getInt("last_daily_bonus_ms") || 0;
      if (last && now - last < COOLDOWN) {
        out = { s: 200, b: { ok: false, cooldown: true, coins: rec.getInt("coins") || 0 } };
        return;
      }
      const coins = (rec.getInt("coins") || 0) + 1;
      rec.set("coins", coins);
      rec.set("last_daily_bonus_ms", now);
      txApp.save(rec);
      out = { s: 200, b: { ok: true, coins: coins, awarded: 1 } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Ежемесячные монеты владельцам Togetherly+ ────────────────────────────────
//
// Разовая покупка имеет неприятное свойство: заплатил, получил, забыл.
// Небольшое начисление раз в месяц напоминает, что покупка продолжает
// работать, и стоит нам ничего — монеты внутренние.
//
// Клиент дёргает роут при входе; сервер сам решает, пора ли. Дату держим в
// том же виде, что и остальные кулдауны, — миллисекундами на записи юзера.
routerAdd("POST", "/api/coins/plus-monthly", (e) => {
  const AMOUNT = 150;
  const PERIOD = 30 * 24 * 60 * 60 * 1000;
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);

      if (!rec.getBool("plus")) {
        out = { s: 200, b: { ok: false, error: "no_plus" } };
        return;
      }

      const now = Date.now();
      const last = rec.getInt("last_plus_grant_ms") || 0;
      if (last && now - last < PERIOD) {
        out = {
          s: 200,
          b: {
            ok: false,
            cooldown: true,
            nextAt: last + PERIOD,
            coins: rec.getInt("coins") || 0,
          },
        };
        return;
      }

      const coins = (rec.getInt("coins") || 0) + AMOUNT;
      rec.set("coins", coins);
      rec.set("last_plus_grant_ms", now);
      txApp.save(rec);
      out = { s: 200, b: { ok: true, coins: coins, awarded: AMOUNT } };
    });
  } catch (err) {
    return e.json(500, { ok: false, error: "tx failed" });
  }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Награда за воспоминание (1, кулдаун 20ч) ──────────────────────────────────
routerAdd("POST", "/api/coins/memory-reward", (e) => {
  const COOLDOWN = 20 * 60 * 60 * 1000;
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);
      const now = Date.now();
      const last = rec.getInt("last_memory_reward_ms") || 0;
      if (last && now - last < COOLDOWN) {
        out = { s: 200, b: { ok: false, cooldown: true, coins: rec.getInt("coins") || 0 } };
        return;
      }
      const coins = (rec.getInt("coins") || 0) + 1;
      rec.set("coins", coins);
      rec.set("last_memory_reward_ms", now);
      txApp.save(rec);
      out = { s: 200, b: { ok: true, coins: coins, awarded: 1 } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Награда за рекламу (3, лимит 3/сутки; путь Яндекса) ───────────────────────
routerAdd("POST", "/api/coins/ad-reward", (e) => {
  const PER_DAY = 3, AMOUNT = 3;
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);
      const today = new Date().toISOString().slice(0, 10);
      const countToday = rec.getString("ad_rewards_date") === today
        ? (rec.getInt("ad_rewards_today") || 0) : 0;
      if (countToday >= PER_DAY) {
        out = { s: 200, b: { ok: false, rateLimited: true, coins: rec.getInt("coins") || 0 } };
        return;
      }
      const coins = (rec.getInt("coins") || 0) + AMOUNT;
      rec.set("coins", coins);
      rec.set("ad_rewards_date", today);
      rec.set("ad_rewards_today", countToday + 1);
      txApp.save(rec);
      out = { s: 200, b: { ok: true, coins: coins, awarded: AMOUNT } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Дев-коины (1000, только dev-email, единожды) ──────────────────────────────
routerAdd("POST", "/api/coins/dev-coins", (e) => {
  const DEV_EMAIL = "badzoff@gmail.com", AMOUNT = 1000;
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);
      if (String(rec.getString("email")).toLowerCase() !== DEV_EMAIL) {
        out = { s: 403, b: { ok: false, error: "dev only" } };
        return;
      }
      if (rec.getBool("dev_coins_granted")) {
        out = { s: 200, b: { ok: true, alreadyGranted: true, coins: rec.getInt("coins") || 0 } };
        return;
      }
      const coins = (rec.getInt("coins") || 0) + AMOUNT;
      rec.set("coins", coins);
      rec.set("dev_coins_granted", true);
      txApp.save(rec);
      out = { s: 200, b: { ok: true, alreadyGranted: false, coins: coins, awarded: AMOUNT } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Награда за подключение партнёра (50, раз на уникальную пару) ───────────────
routerAdd("POST", "/api/coins/partner-invite", (e) => {
  const AMOUNT = 50;
  const safeParse = (s, fb) => { try { return JSON.parse(s || JSON.stringify(fb)) || fb; } catch (_) { return fb; } };
  const body = (e.requestInfo().body || {});
  const partnerUid = String(body.partnerUid || "").trim();
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);
      const coinsNow = rec.getInt("coins") || 0;
      if (!partnerUid) {
        out = { s: 200, b: { ok: false, noPartner: true, coins: coinsNow } };
        return;
      }
      let partnerKey = partnerUid;
      try {
        const p = txApp.findRecordById("users", partnerUid);
        const pe = String(p.getString("email") || "").trim().toLowerCase();
        if (pe) partnerKey = pe;
      } catch (_) { /* партнёра ещё нет — ключ = uid */ }
      const rewarded = safeParse(rec.getString("partner_invite_rewarded_keys"), []);
      if (rewarded.indexOf(partnerKey) !== -1) {
        out = { s: 200, b: { ok: false, alreadyGranted: true, coins: coinsNow } };
        return;
      }
      if (rewarded.length === 0 && rec.getBool("partner_invite_reward_granted")) {
        rec.set("partner_invite_rewarded_keys", JSON.stringify(rewarded.concat([partnerKey])));
        txApp.save(rec);
        out = { s: 200, b: { ok: false, alreadyGranted: true, coins: coinsNow } };
        return;
      }
      const coins = coinsNow + AMOUNT;
      rec.set("coins", coins);
      rec.set("partner_invite_reward_granted", true);
      rec.set("partner_invite_rewarded_keys", JSON.stringify(rewarded.concat([partnerKey])));
      txApp.save(rec);
      out = { s: 200, b: { ok: true, coins: coins, awarded: AMOUNT } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── Награда за 7-дневный mood-стрик (10, кулдаун 7д на группу) ─────────────────
routerAdd("POST", "/api/coins/mood-streak", (e) => {
  const AMOUNT = 10, COOLDOWN = 7 * 24 * 60 * 60 * 1000;
  const safeParse = (s, fb) => { try { return JSON.parse(s || JSON.stringify(fb)) || fb; } catch (_) { return fb; } };
  const body = (e.requestInfo().body || {});
  const groupId = String(body.groupId || "").trim();
  if (!groupId) return e.json(400, { ok: false, error: "no group" });
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const rec = txApp.findRecordById("users", e.auth.id);
      const now = Date.now();
      const map = safeParse(rec.getString("mood_streak_rewards"), {});
      const last = Number(map[groupId] || 0);
      if (last && now - last < COOLDOWN) {
        out = { s: 200, b: { ok: false, cooldown: true, coins: rec.getInt("coins") || 0 } };
        return;
      }
      map[groupId] = now;
      const coins = (rec.getInt("coins") || 0) + AMOUNT;
      rec.set("coins", coins);
      rec.set("mood_streak_rewards", JSON.stringify(map));
      txApp.save(rec);
      out = { s: 200, b: { ok: true, coins: coins, awarded: AMOUNT } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// ── IAP: начисление коинов после покупки (§6, замена Firebase grantCoinsPurchase) ──
// Идемпотентность по purchaseToken (id записи iap_purchases): один токен = одно
// начисление. Защита: productId по whitelist COIN_PACKS. Реальной Play/RuStore-
// валидации нет (её не было и в Firebase — только whitelist+идемпотентность).
// Транзакция (COIN-1): начисление+запись токена атомарны → два параллельных
// запроса с одним токеном не дадут двойного начисления.
routerAdd("POST", "/api/coins/iap-purchase", (e) => {
  const body = (e.requestInfo().body || {});
  const productId = String(body.productId || "");
  const purchaseToken = String(body.purchaseToken || "");
  const COIN_PACKS = { "coins_10": 10, "coins_50": 50, "coins_120": 120, "coins_300": 300 };
  const PLUS_PRODUCT = "togetherly_plus";
  const amount = COIN_PACKS[productId];
  if (!amount && productId !== PLUS_PRODUCT) {
    return e.json(400, { ok: false, error: "unknown productId" });
  }
  if (!purchaseToken) return e.json(400, { ok: false, error: "purchaseToken required" });

  // Ключ записи о покупке = sha256 от токена, а НЕ сам токен.
  //
  // Токен Google выглядит как `ndecncajl….AO-J1OzF…` — с точкой посередине, а
  // PocketBase точку в первичном ключе запрещает на уровне движка
  // (`validation_forbidden_pk_character`). Пока сюда клали сам токен, любая
  // покупка Play падала на сохранении записи, роут отвечал `500 tx failed`, и
  // за всю историю в `iap_purchases` не появилось ни одной строки: 30 июля так
  // потерялась оплата Togetherly+ на 9,99 €. Хеш даёт те же 64 безопасных
  // символа и ту же идемпотентность: один токен — одна запись.
  const tokenKey = $security.sha256(purchaseToken);

  // ── сверка чека с Google ──────────────────────────────────────────────────
  //
  // Без неё purchaseToken можно выдумать и получить монеты или вечный Plus
  // даром: до этого сервер верил клиенту на слово. Подпись RS256 в JSVM не
  // сделать, поэтому поход в Play API вынесен в локальную службу
  // (`tools/play_verify.py`, 127.0.0.1:8097), а сюда приходит только вердикт.
  //
  // Три исхода, и обходиться с ними надо по-разному:
  //   valid=true   — покупка настоящая, начисляем;
  //   valid=false  — Google такой покупки не знает или она отменена: отказ;
  //   ok=false     — сверить НЕ ВЫШЛО (служба легла, Google не ответил). Тут
  //                  начисляем: ломать покупку живому человеку из-за своей же
  //                  аварии нельзя, а след в журнале останется.
  //
  // RuStore проверяем не здесь: у него свой API, и его токен Google отвергнет.
  // Пока RuStore-сборка не выпущена, ветка нужна на будущее.
  const store = String(body.store || "").toLowerCase();
  if (store !== "rustore") {
    let verdict = { ok: false, reason: "unreachable" };
    try {
      const res = $http.send({
        url: "http://127.0.0.1:8097/verify",
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ productId: productId, purchaseToken: purchaseToken }),
        timeout: 20,
      });
      const parsed = res.json;
      if (parsed && parsed.ok === true) {
        verdict = { ok: true, valid: parsed.valid === true, reason: parsed.reason || "" };
      } else if (parsed && parsed.reason) {
        verdict = { ok: false, reason: String(parsed.reason) };
      }
    } catch (err) {
      verdict = { ok: false, reason: "send_failed" };
    }

    if (verdict.ok && !verdict.valid) {
      try {
        $app.logger().error("iap: чек не подтверждён",
          "product", productId, "uid", e.auth.id, "reason", verdict.reason);
      } catch (_) {}
      return e.json(403, { ok: false, error: "purchase_not_verified" });
    }
    if (!verdict.ok) {
      try {
        $app.logger().error("iap: сверка не удалась, начисляю без неё",
          "product", productId, "uid", e.auth.id, "reason", verdict.reason);
      } catch (_) {}
    }
  }

  // Togetherly+ из Google Play (товар togetherly_plus, способ покупки lifetime).
  // Монеты не начисляем — ставим флаг доступа, тот же, что даёт lava.top-вебхук
  // и погашение кода. Идемпотентность общая с монетами: один purchaseToken =
  // одна запись в iap_purchases, повторный вызов ничего не меняет.
  if (productId === PLUS_PRODUCT) {
    let plusOut;
    try {
      $app.runInTransaction((txApp) => {
        const user = txApp.findRecordById("users", e.auth.id);
        let already = null;
        try { already = txApp.findRecordById("iap_purchases", tokenKey); } catch (_) { already = null; }
        if (already) {
          plusOut = { s: 200, b: { ok: true, alreadyGranted: true, plus: true, coins: user.getInt("coins") || 0 } };
          return;
        }
        user.set("plus", true);
        // Покупка через биллинг Google Play. Отмечаем источник: витрина
        // Togetherly+ живёт только на Android, и по полю видно, откуда доступ
        // у человека, который заходит ещё и с iPhone.
        user.set("plus_platform", "play");
        txApp.save(user);
        const col = txApp.findCollectionByNameOrId("iap_purchases");
        const rec = new Record(col);
        rec.set("id", tokenKey);
        rec.set("token", purchaseToken);
        rec.set("user_uid", e.auth.id);
        rec.set("product_id", productId);
        rec.set("amount", 0);
        rec.set("at", new Date().toISOString());
        txApp.save(rec);
        plusOut = { s: 200, b: { ok: true, alreadyGranted: false, plus: true, coins: user.getInt("coins") || 0 } };
      });
    } catch (err) {
      return e.json(500, { ok: false, error: "tx failed" });
    }
    return e.json(plusOut.s, plusOut.b);
  }
  let out;
  try {
    $app.runInTransaction((txApp) => {
      const user = txApp.findRecordById("users", e.auth.id);
      let already = null;
      try { already = txApp.findRecordById("iap_purchases", tokenKey); } catch (_) { already = null; }
      if (already) {
        out = { s: 200, b: { ok: true, alreadyGranted: true, coins: user.getInt("coins") || 0 } };
        return;
      }
      const newCoins = (user.getInt("coins") || 0) + amount;
      user.set("coins", newCoins);
      txApp.save(user);
      const col = txApp.findCollectionByNameOrId("iap_purchases");
      const rec = new Record(col);
      rec.set("id", tokenKey);
        rec.set("token", purchaseToken);
      rec.set("user_uid", e.auth.id);
      rec.set("product_id", productId);
      rec.set("amount", amount);
      rec.set("at", new Date().toISOString());
      txApp.save(rec);
      out = { s: 200, b: { ok: true, alreadyGranted: false, coins: newCoins, awarded: amount } };
    });
  } catch (err) { return e.json(500, { ok: false, error: "tx failed" }); }
  return e.json(out.s, out.b);
}, $apis.requireAuth());
