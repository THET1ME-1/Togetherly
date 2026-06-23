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

// ── Покупка темы ────────────────────────────────────────────────────────────
routerAdd("POST", "/api/coins/purchase-theme", (e) => {
  const themeId = Number(e.requestInfo().body.themeId);
  if (!Number.isInteger(themeId) || themeId < 5 || themeId > 50) {
    return e.json(400, { ok: false, error: "bad themeId" });
  }
  const price = themeId === 16 ? 40 : 30; // override Aurora=40, иначе 30
  const rec = $app.findRecordById("users", e.auth.id);
  const coins = rec.getFloat("coins");
  const owned = (JSON.parse(rec.getString("owned_themes") || "[]") || []);
  if (owned.indexOf(themeId) !== -1) {
    return e.json(200, { ok: true, alreadyOwned: true, coins: coins, ownedThemes: owned });
  }
  if (coins < price) return e.json(200, { ok: false, error: "insufficient", coins: coins });
  const newOwned = owned.concat([themeId]).sort((a, b) => a - b);
  rec.set("coins", coins - price);
  rec.set("owned_themes", newOwned);
  $app.save(rec);
  return e.json(200, { ok: true, alreadyOwned: false, coins: coins - price, ownedThemes: newOwned });
}, $apis.requireAuth());

// ── Покупка профильной иконки ─────────────────────────────────────────────────
routerAdd("POST", "/api/coins/purchase-icon", (e) => {
  const iconId = String(e.requestInfo().body.iconId || "");
  const PRICES = {
    "Paw": 20, "Sun": 20, "Moon": 20, "Rainbow": 20, "Bunny": 20, "Frog": 20,
    "Lucky": 35, "UFO": 35, "Together": 35,
    "Soulmate": 50, "Perfect Match": 50, "Inseparable": 50,
  };
  const price = PRICES[iconId];
  if (!price) return e.json(400, { ok: false, error: "not for sale" });
  const rec = $app.findRecordById("users", e.auth.id);
  const coins = rec.getFloat("coins");
  const owned = (JSON.parse(rec.getString("owned_icons") || "[]") || []);
  if (owned.indexOf(iconId) !== -1) {
    return e.json(200, { ok: true, alreadyOwned: true, coins: coins, ownedIcons: owned });
  }
  if (coins < price) return e.json(200, { ok: false, error: "insufficient", coins: coins });
  const newOwned = owned.concat([iconId]);
  rec.set("coins", coins - price);
  rec.set("owned_icons", newOwned);
  $app.save(rec);
  return e.json(200, { ok: true, alreadyOwned: false, coins: coins - price, ownedIcons: newOwned });
}, $apis.requireAuth());

// ── Покупка одноразовой фичи ──────────────────────────────────────────────────
routerAdd("POST", "/api/coins/purchase-feature", (e) => {
  const featureId = String(e.requestInfo().body.featureId || "");
  const PRICES = { "days_widget_photos": 20 };
  const price = PRICES[featureId];
  if (!price) return e.json(400, { ok: false, error: "not for sale" });
  const rec = $app.findRecordById("users", e.auth.id);
  const coins = rec.getFloat("coins");
  const owned = (JSON.parse(rec.getString("owned_features") || "[]") || []);
  if (owned.indexOf(featureId) !== -1) {
    return e.json(200, { ok: true, alreadyOwned: true, coins: coins, ownedFeatures: owned });
  }
  if (coins < price) return e.json(200, { ok: false, error: "insufficient", coins: coins });
  const newOwned = owned.concat([featureId]);
  rec.set("coins", coins - price);
  rec.set("owned_features", newOwned);
  $app.save(rec);
  return e.json(200, { ok: true, alreadyOwned: false, coins: coins - price, ownedFeatures: newOwned });
}, $apis.requireAuth());

// ── Расходуемое списание (не «покупка навсегда») ──────────────────────────────
routerAdd("POST", "/api/coins/spend", (e) => {
  const actionId = String(e.requestInfo().body.actionId || "");
  const PRICES = { "chat_background": 20 };
  const price = PRICES[actionId];
  if (!price) return e.json(400, { ok: false, error: "unknown action" });
  const rec = $app.findRecordById("users", e.auth.id);
  const coins = rec.getFloat("coins");
  if (coins < price) return e.json(200, { ok: false, error: "insufficient", coins: coins });
  rec.set("coins", coins - price);
  $app.save(rec);
  return e.json(200, { ok: true, coins: coins - price, spent: price });
}, $apis.requireAuth());

// ── Ежедневный бонус (1, кулдаун 20ч) ─────────────────────────────────────────
routerAdd("POST", "/api/coins/daily-bonus", (e) => {
  const COOLDOWN = 20 * 60 * 60 * 1000;
  const rec = $app.findRecordById("users", e.auth.id);
  const now = Date.now();
  const last = rec.getFloat("last_daily_bonus_ms");
  if (last && now - last < COOLDOWN) {
    return e.json(200, { ok: false, cooldown: true, coins: rec.getFloat("coins") });
  }
  const coins = rec.getFloat("coins") + 1;
  rec.set("coins", coins);
  rec.set("last_daily_bonus_ms", now);
  $app.save(rec);
  return e.json(200, { ok: true, coins: coins, awarded: 1 });
}, $apis.requireAuth());

// ── Награда за воспоминание (1, кулдаун 20ч) ──────────────────────────────────
routerAdd("POST", "/api/coins/memory-reward", (e) => {
  const COOLDOWN = 20 * 60 * 60 * 1000;
  const rec = $app.findRecordById("users", e.auth.id);
  const now = Date.now();
  const last = rec.getFloat("last_memory_reward_ms");
  if (last && now - last < COOLDOWN) {
    return e.json(200, { ok: false, cooldown: true, coins: rec.getFloat("coins") });
  }
  const coins = rec.getFloat("coins") + 1;
  rec.set("coins", coins);
  rec.set("last_memory_reward_ms", now);
  $app.save(rec);
  return e.json(200, { ok: true, coins: coins, awarded: 1 });
}, $apis.requireAuth());

// ── Награда за рекламу (3, лимит 3/сутки; путь Яндекса) ───────────────────────
routerAdd("POST", "/api/coins/ad-reward", (e) => {
  const PER_DAY = 3, AMOUNT = 3;
  const rec = $app.findRecordById("users", e.auth.id);
  const today = new Date().toISOString().slice(0, 10);
  const countToday = rec.getString("ad_rewards_date") === today
    ? rec.getFloat("ad_rewards_today") : 0;
  if (countToday >= PER_DAY) {
    return e.json(200, { ok: false, rateLimited: true, coins: rec.getFloat("coins") });
  }
  const coins = rec.getFloat("coins") + AMOUNT;
  rec.set("coins", coins);
  rec.set("ad_rewards_date", today);
  rec.set("ad_rewards_today", countToday + 1);
  $app.save(rec);
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
    return e.json(200, { ok: true, alreadyGranted: true, coins: rec.getFloat("coins") });
  }
  const coins = rec.getFloat("coins") + AMOUNT;
  rec.set("coins", coins);
  rec.set("dev_coins_granted", true);
  $app.save(rec);
  return e.json(200, { ok: true, alreadyGranted: false, coins: coins, awarded: AMOUNT });
}, $apis.requireAuth());

// ── Награда за подключение партнёра (50, раз на уникальную пару) ───────────────
routerAdd("POST", "/api/coins/partner-invite", (e) => {
  const AMOUNT = 50;
  const partnerUid = String(e.requestInfo().body.partnerUid || "").trim();
  const rec = $app.findRecordById("users", e.auth.id);
  const coinsNow = rec.getFloat("coins");
  if (!partnerUid) return e.json(200, { ok: false, noPartner: true, coins: coinsNow });
  // Стабильный ключ партнёра: email (фолбэк uid).
  let partnerKey = partnerUid;
  try {
    const p = $app.findRecordById("users", partnerUid);
    const pe = String(p.getString("email") || "").trim().toLowerCase();
    if (pe) partnerKey = pe;
  } catch (_) { /* партнёра ещё нет — ключ = uid */ }
  const rewarded = (JSON.parse(rec.getString("partner_invite_rewarded_keys") || "[]") || []);
  if (rewarded.indexOf(partnerKey) !== -1) {
    return e.json(200, { ok: false, alreadyGranted: true, coins: coinsNow });
  }
  // Легаси «первое касание»: старый флаг стоит, набор пуст → сидируем без начисления.
  if (rewarded.length === 0 && rec.getBool("partner_invite_reward_granted")) {
    rec.set("partner_invite_rewarded_keys", rewarded.concat([partnerKey]));
    $app.save(rec);
    return e.json(200, { ok: false, alreadyGranted: true, coins: coinsNow });
  }
  const coins = coinsNow + AMOUNT;
  rec.set("coins", coins);
  rec.set("partner_invite_reward_granted", true);
  rec.set("partner_invite_rewarded_keys", rewarded.concat([partnerKey]));
  $app.save(rec);
  return e.json(200, { ok: true, coins: coins, awarded: AMOUNT });
}, $apis.requireAuth());

// ── Награда за 7-дневный mood-стрик (10, кулдаун 7д на группу) ─────────────────
routerAdd("POST", "/api/coins/mood-streak", (e) => {
  const AMOUNT = 10, COOLDOWN = 7 * 24 * 60 * 60 * 1000;
  const groupId = String(e.requestInfo().body.groupId || "").trim();
  if (!groupId) return e.json(400, { ok: false, error: "no group" });
  const rec = $app.findRecordById("users", e.auth.id);
  const now = Date.now();
  const map = (JSON.parse(rec.getString("mood_streak_rewards") || "{}") || {});
  const last = Number(map[groupId] || 0);
  if (last && now - last < COOLDOWN) {
    return e.json(200, { ok: false, cooldown: true, coins: rec.getFloat("coins") });
  }
  map[groupId] = now;
  const coins = rec.getFloat("coins") + AMOUNT;
  rec.set("coins", coins);
  rec.set("mood_streak_rewards", map);
  $app.save(rec);
  return e.json(200, { ok: true, coins: coins, awarded: AMOUNT });
}, $apis.requireAuth());
