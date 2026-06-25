/// Серверная логика «коинов» на PocketBase (миграция §6 — замена Firebase
/// Cloud Functions). Деньги считаются ТОЛЬКО здесь: цены/кулдауны/лимиты на
/// сервере, клиент не может их обойти. Зеркало functions/index.js.
///
/// ВАЖНО (PB JSVM): обработчик routerAdd сериализуется и исполняется в
/// изолированном пуле — он НЕ видит переменные/функции уровня файла. Поэтому
/// каждый роут самодостаточен (цены/логика инлайн). Доступны только фреймворк-
/// глобалы ($app, $apis, e.*). Поля users — snake_case; кулдауны — epoch-ms.
///
/// Ответ зеркалит Cloud Functions (camelCase: coins/ownedThemes/awarded/...),
/// чтобы клиентский _applyServerResult читал его без изменений.

// ── helpers ──────────────────────────────────────────────────────────────────

/// Безопасный JSON.parse для stored JSON полей: при corrupted данных возвращает
/// fallback вместо краша.
function _safeParse(str, fallback) {
  try { return JSON.parse(str || JSON.stringify(fallback)) || fallback; }
  catch (_) { return fallback; }
}

/// Валидация тела запроса: если body null/undefined — вернёт пустой объект.
function _body(e) {
  return (e.requestInfo().body || {});
}

/// Атомарное чтение записи + проверка conditions перед save.
/// Возвращает {rec, coins} или null если conditions не выполнены.
function _readAndCheck(e, extraCheck) {
  const rec = $app.findRecordById("users", e.auth.id);
  const coins = rec.getInt("coins") || 0;
  const check = extraCheck(rec, coins);
  if (check) return { rec, coins };
  return null;
}

// ── Покупка темы ────────────────────────────────────────────────────────────
routerAdd("POST", "/api/coins/purchase-theme", (e) => {
  const body = _body(e);
  const themeId = Number(body.themeId);
  if (!Number.isInteger(themeId) || themeId < 5 || themeId > 50) {
    return e.json(400, { ok: false, error: "bad themeId" });
  }
  const price = themeId === 16 ? 40 : 30;
  const ctx = _readAndCheck(e, (rec, coins) => {
    const owned = _safeParse(rec.getString("owned_themes"), []);
    if (owned.indexOf(themeId) !== -1) return { skip: true, owned };
    if (coins < price) return { skip: true, owned };
    return { ok: true, owned };
  });
  if (!ctx) return e.json(500, { ok: false, error: "read failed" });
  if (ctx.skip) {
    const owned = ctx.owned;
    if (owned.indexOf(themeId) !== -1) {
      return e.json(200, { ok: true, alreadyOwned: true, coins: ctx.coins, ownedThemes: owned });
    }
    return e.json(402, { ok: false, error: "insufficient", coins: ctx.coins });
  }
  const newOwned = ctx.owned.concat([themeId]).sort((a, b) => a - b);
  ctx.rec.set("coins", ctx.coins - price);
  ctx.rec.set("owned_themes", JSON.stringify(newOwned));
  try { $app.save(ctx.rec); }
  catch (err) { return e.json(500, { ok: false, error: "save failed" }); }
  return e.json(200, { ok: true, alreadyOwned: false, coins: ctx.coins - price, ownedThemes: newOwned });
}, $apis.requireAuth());

// ── Покупка профильной иконки ─────────────────────────────────────────────────
routerAdd("POST", "/api/coins/purchase-icon", (e) => {
  const body = _body(e);
  const iconId = String(body.iconId || "");
  const PRICES = {
    "Paw": 20, "Sun": 20, "Moon": 20, "Rainbow": 20, "Bunny": 20, "Frog": 20,
    "Lucky": 35, "UFO": 35, "Together": 35,
    "Soulmate": 50, "Perfect Match": 50, "Inseparable": 50,
  };
  const price = PRICES[iconId];
  if (!price) return e.json(400, { ok: false, error: "not for sale" });
  const ctx = _readAndCheck(e, (rec, coins) => {
    const owned = _safeParse(rec.getString("owned_icons"), []);
    if (owned.indexOf(iconId) !== -1) return { skip: true, owned };
    if (coins < price) return { skip: true, owned };
    return { ok: true, owned };
  });
  if (!ctx) return e.json(500, { ok: false, error: "read failed" });
  if (ctx.skip) {
    const owned = ctx.owned;
    if (owned.indexOf(iconId) !== -1) {
      return e.json(200, { ok: true, alreadyOwned: true, coins: ctx.coins, ownedIcons: owned });
    }
    return e.json(402, { ok: false, error: "insufficient", coins: ctx.coins });
  }
  const newOwned = ctx.owned.concat([iconId]);
  ctx.rec.set("coins", ctx.coins - price);
  ctx.rec.set("owned_icons", JSON.stringify(newOwned));
  try { $app.save(ctx.rec); }
  catch (err) { return e.json(500, { ok: false, error: "save failed" }); }
  return e.json(200, { ok: true, alreadyOwned: false, coins: ctx.coins - price, ownedIcons: newOwned });
}, $apis.requireAuth());

// ── Покупка одноразовой фичи ──────────────────────────────────────────────────
routerAdd("POST", "/api/coins/purchase-feature", (e) => {
  const body = _body(e);
  const featureId = String(body.featureId || "");
  const PRICES = { "days_widget_photos": 20 };
  const price = PRICES[featureId];
  if (!price) return e.json(400, { ok: false, error: "not for sale" });
  const ctx = _readAndCheck(e, (rec, coins) => {
    const owned = _safeParse(rec.getString("owned_features"), []);
    if (owned.indexOf(featureId) !== -1) return { skip: true, owned };
    if (coins < price) return { skip: true, owned };
    return { ok: true, owned };
  });
  if (!ctx) return e.json(500, { ok: false, error: "read failed" });
  if (ctx.skip) {
    const owned = ctx.owned;
    if (owned.indexOf(featureId) !== -1) {
      return e.json(200, { ok: true, alreadyOwned: true, coins: ctx.coins, ownedFeatures: owned });
    }
    return e.json(402, { ok: false, error: "insufficient", coins: ctx.coins });
  }
  const newOwned = ctx.owned.concat([featureId]);
  ctx.rec.set("coins", ctx.coins - price);
  ctx.rec.set("owned_features", JSON.stringify(newOwned));
  try { $app.save(ctx.rec); }
  catch (err) { return e.json(500, { ok: false, error: "save failed" }); }
  return e.json(200, { ok: true, alreadyOwned: false, coins: ctx.coins - price, ownedFeatures: newOwned });
}, $apis.requireAuth());

// ── Расходуемое списание (не «покупка навсегда») ──────────────────────────────
routerAdd("POST", "/api/coins/spend", (e) => {
  const body = _body(e);
  const actionId = String(body.actionId || "");
  const PRICES = { "chat_background": 20 };
  const price = PRICES[actionId];
  if (!price) return e.json(400, { ok: false, error: "unknown action" });
  const ctx = _readAndCheck(e, (rec, coins) => {
    if (coins < price) return { skip: true };
    return { ok: true };
  });
  if (!ctx) return e.json(500, { ok: false, error: "read failed" });
  if (ctx.skip) return e.json(402, { ok: false, error: "insufficient", coins: ctx.coins });
  ctx.rec.set("coins", ctx.coins - price);
  try { $app.save(ctx.rec); }
  catch (err) { return e.json(500, { ok: false, error: "save failed" }); }
  return e.json(200, { ok: true, coins: ctx.coins - price, spent: price });
}, $apis.requireAuth());

// ── Ежедневный бонус (1, кулдаун 20ч) ─────────────────────────────────────────
routerAdd("POST", "/api/coins/daily-bonus", (e) => {
  const COOLDOWN = 20 * 60 * 60 * 1000;
  const rec = $app.findRecordById("users", e.auth.id);
  const now = Date.now();
  const last = rec.getInt("last_daily_bonus_ms") || 0;
  if (last && now - last < COOLDOWN) {
    return e.json(200, { ok: false, cooldown: true, coins: rec.getInt("coins") || 0 });
  }
  const coins = (rec.getInt("coins") || 0) + 1;
  rec.set("coins", coins);
  rec.set("last_daily_bonus_ms", now);
  try { $app.save(rec); }
  catch (err) { return e.json(500, { ok: false, error: "save failed" }); }
  return e.json(200, { ok: true, coins: coins, awarded: 1 });
}, $apis.requireAuth());

// ── Награда за воспоминание (1, кулдаун 20ч) ──────────────────────────────────
routerAdd("POST", "/api/coins/memory-reward", (e) => {
  const COOLDOWN = 20 * 60 * 60 * 1000;
  const rec = $app.findRecordById("users", e.auth.id);
  const now = Date.now();
  const last = rec.getInt("last_memory_reward_ms") || 0;
  if (last && now - last < COOLDOWN) {
    return e.json(200, { ok: false, cooldown: true, coins: rec.getInt("coins") || 0 });
  }
  const coins = (rec.getInt("coins") || 0) + 1;
  rec.set("coins", coins);
  rec.set("last_memory_reward_ms", now);
  try { $app.save(rec); }
  catch (err) { return e.json(500, { ok: false, error: "save failed" }); }
  return e.json(200, { ok: true, coins: coins, awarded: 1 });
}, $apis.requireAuth());

// ── Награда за рекламу (3, лимит 3/сутки; путь Яндекса) ───────────────────────
routerAdd("POST", "/api/coins/ad-reward", (e) => {
  const PER_DAY = 3, AMOUNT = 3;
  const rec = $app.findRecordById("users", e.auth.id);
  const today = new Date().toISOString().slice(0, 10);
  const countToday = rec.getString("ad_rewards_date") === today
    ? (rec.getInt("ad_rewards_today") || 0) : 0;
  if (countToday >= PER_DAY) {
    return e.json(200, { ok: false, rateLimited: true, coins: rec.getInt("coins") || 0 });
  }
  const coins = (rec.getInt("coins") || 0) + AMOUNT;
  rec.set("coins", coins);
  rec.set("ad_rewards_date", today);
  rec.set("ad_rewards_today", countToday + 1);
  try { $app.save(rec); }
  catch (err) { return e.json(500, { ok: false, error: "save failed" }); }
  return e.json(200, { ok: true, coins: coins, awarded: AMOUNT });
}, $apis.requireAuth());

// ── Дев-коины (1000, только dev-email, единожды) ──────────────────────────────
routerAdd("POST", "/api/coins/dev-coins", (e) => {
  const DEV_EMAIL = "badzoff@gmail.com", AMOUNT = 1000;
  const rec = $app.findRecordById("users", e.auth.id);
  if (String(rec.getString("email")).toLowerCase() !== DEV_EMAIL) {
    return e.json(403, { ok: false, error: "dev only" });
  }
  if (rec.getBool("dev_coins_granted")) {
    return e.json(200, { ok: true, alreadyGranted: true, coins: rec.getInt("coins") || 0 });
  }
  const coins = (rec.getInt("coins") || 0) + AMOUNT;
  rec.set("coins", coins);
  rec.set("dev_coins_granted", true);
  try { $app.save(rec); }
  catch (err) { return e.json(500, { ok: false, error: "save failed" }); }
  return e.json(200, { ok: true, alreadyGranted: false, coins: coins, awarded: AMOUNT });
}, $apis.requireAuth());

// ── Награда за подключение партнёра (50, раз на уникальную пару) ───────────────
routerAdd("POST", "/api/coins/partner-invite", (e) => {
  const AMOUNT = 50;
  const body = _body(e);
  const partnerUid = String(body.partnerUid || "").trim();
  const rec = $app.findRecordById("users", e.auth.id);
  const coinsNow = rec.getInt("coins") || 0;
  if (!partnerUid) return e.json(200, { ok: false, noPartner: true, coins: coinsNow });
  let partnerKey = partnerUid;
  try {
    const p = $app.findRecordById("users", partnerUid);
    const pe = String(p.getString("email") || "").trim().toLowerCase();
    if (pe) partnerKey = pe;
  } catch (_) { /* партнёра ещё нет — ключ = uid */ }
  const rewarded = _safeParse(rec.getString("partner_invite_rewarded_keys"), []);
  if (rewarded.indexOf(partnerKey) !== -1) {
    return e.json(200, { ok: false, alreadyGranted: true, coins: coinsNow });
  }
  if (rewarded.length === 0 && rec.getBool("partner_invite_reward_granted")) {
    rec.set("partner_invite_rewarded_keys", JSON.stringify(rewarded.concat([partnerKey])));
    try { $app.save(rec); }
    catch (err) { return e.json(500, { ok: false, error: "save failed" }); }
    return e.json(200, { ok: false, alreadyGranted: true, coins: coinsNow });
  }
  const coins = coinsNow + AMOUNT;
  rec.set("coins", coins);
  rec.set("partner_invite_reward_granted", true);
  rec.set("partner_invite_rewarded_keys", JSON.stringify(rewarded.concat([partnerKey])));
  try { $app.save(rec); }
  catch (err) { return e.json(500, { ok: false, error: "save failed" }); }
  return e.json(200, { ok: true, coins: coins, awarded: AMOUNT });
}, $apis.requireAuth());

// ── Награда за 7-дневный mood-стрик (10, кулдаун 7д на группу) ─────────────────
routerAdd("POST", "/api/coins/mood-streak", (e) => {
  const AMOUNT = 10, COOLDOWN = 7 * 24 * 60 * 60 * 1000;
  const body = _body(e);
  const groupId = String(body.groupId || "").trim();
  if (!groupId) return e.json(400, { ok: false, error: "no group" });
  const rec = $app.findRecordById("users", e.auth.id);
  const now = Date.now();
  const map = _safeParse(rec.getString("mood_streak_rewards"), {});
  const last = Number(map[groupId] || 0);
  if (last && now - last < COOLDOWN) {
    return e.json(200, { ok: false, cooldown: true, coins: rec.getInt("coins") || 0 });
  }
  map[groupId] = now;
  const coins = (rec.getInt("coins") || 0) + AMOUNT;
  rec.set("coins", coins);
  rec.set("mood_streak_rewards", JSON.stringify(map));
  try { $app.save(rec); }
  catch (err) { return e.json(500, { ok: false, error: "save failed" }); }
  return e.json(200, { ok: true, coins: coins, awarded: AMOUNT });
}, $apis.requireAuth());
