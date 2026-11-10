/// <reference path="../pb_data/types.d.ts" />
/// Сброс пароля через партнёра (05.11.2026, макет «Вход без писем»).
///
/// Человек забыл пароль, а письма сброса упираются в квоту почтового сервиса
/// (04.11.2026 кончилась месячная квота Resend, 94 человека остались без
/// писем). В приложении для пар у большинства есть второй человек с
/// открытым приложением, и он подтверждает, что это вы:
///
///   1. `request` — новый телефон присылает почту. Сервер находит аккаунт и
///      живую пару на двоих, кладёт код из шести цифр в память и шлёт
///      партнёру пуш. Ответ `via: partner` или `via: none` (пары нет —
///      приложение предлагает письмо).
///   2. `pending` — приложение партнёра забирает код и показывает его листом.
///      `deny` гасит запрос, а хозяину аккаунта уходит пуш «кто-то пытался
///      войти».
///   3. `verify` — новый телефон присылает почту и код, получает пропуск.
///   4. `complete` — пропуск и новый пароль; ответ как у входа по паролю.
///
/// Запросы живут в `$app.store()`, как код смены почты: перезапуск PocketBase
/// их теряет, и человек просто просит код ещё раз. Правила срока, попыток и
/// частоты — `partner_reset.js` (тест `partner_reset.test.js`).
///
/// Всё инлайн: JSVM не показывает обработчику функции уровня файла.

routerAdd("POST", "/api/auth/partner-reset/request", (e) => {
  const rule = require(`${__hooks}/partner_reset.js`);
  const push = require(`${__hooks}/apns_push.js`);
  const store = $app.store();
  const now = Date.now();

  // С одного адреса — не больше 30 запросов в час, как у письма сброса.
  const ipKey = "preset_ip_" + e.realIP();
  const hit = store.get(ipKey);
  const win = hit && now - hit.at < 3600 * 1000 ? hit : { at: now, n: 0 };
  if (win.n >= 30) return e.json(429, { code: "ip", message: "Слишком много запросов. Попробуйте через час." });
  store.set(ipKey, { at: win.at, n: win.n + 1 });

  let email = "";
  try {
    email = String((e.requestInfo().body || {}).email || "").trim();
  } catch (_) {
    email = "";
  }
  if (!email || email.indexOf("@") < 1 || email.length > 255) {
    return e.json(400, { code: "email", message: "Нужна почта." });
  }

  // Поиск без учёта регистра — как в email_case.pb.js: клавиатура ставит
  // первой букве заглавную сама.
  let user = null;
  try {
    user = $app.findAuthRecordByEmail("users", email);
  } catch (_) {
    user = null;
  }
  if (!user) {
    try {
      const rows = arrayOf(new DynamicModel({ id: "" }));
      $app.db()
        .newQuery("SELECT id FROM users WHERE lower(email) = lower({:e}) LIMIT 2")
        .bind({ e: email })
        .all(rows);
      if (rows.length === 1) user = $app.findRecordById("users", rows[0].id);
    } catch (_) {
      user = null;
    }
  }
  if (!user) return e.json(200, { via: "none" });

  // Живая пара на двоих: свежая первой.
  let groupIds = [];
  try { groupIds = user.getStringSlice("group_ids") || []; } catch (_) { groupIds = []; }
  let rows = [];
  if (groupIds.length) {
    const params = {};
    const marks = [];
    for (let i = 0; i < groupIds.length && i < 20; i++) {
      params["g" + i] = String(groupIds[i]);
      marks.push("{:g" + i + "}");
    }
    try {
      const found = arrayOf(new DynamicModel({ id: "", members: "", disbanded: false }));
      $app.db()
        .newQuery("SELECT id, members, disbanded FROM groups WHERE id IN (" + marks.join(",") + ") ORDER BY updated DESC")
        .bind(params)
        .all(found);
      rows = found.map((g) => ({ id: g.id, members: g.members, disbanded: g.disbanded }));
    } catch (err) {
      $app.logger().warn("partner-reset: пары не прочитались", "uid", user.id, "err", String(err));
    }
  }
  const pick = rule.pickPartner(user.id, rows);
  if (!pick) {
    $app.logger().warn("partner-reset: пары нет", "uid", user.id);
    return e.json(200, { via: "none" });
  }

  const histKey = "preset_hist_" + user.id;
  const may = rule.mayRequest(store.get(histKey) || [], now);
  if (!may.ok) {
    return e.json(429, {
      code: may.why,
      message: may.why === "gap"
        ? "Код уже у партнёра. Новый можно попросить через две минуты."
        : "Слишком много запросов за сутки. Попробуйте завтра или письмом.",
    });
  }
  store.set(histKey, may.history);

  // Прежний запрос этого человека гасится: действует только последний код.
  const old = store.get("preset_req_" + user.id);
  if (old && old.partner) store.remove("preset_for_" + old.partner);

  const code = $security.randomStringWithAlphabet(6, "0123456789");
  store.set("preset_req_" + user.id, { code: code, at: now, tries: 0, partner: pick.partner, groupId: pick.groupId });
  store.set("preset_for_" + pick.partner, user.id);

  const T = require(`${__hooks}/push_texts.js`);
  const own = String(user.getString("display_name") || user.getString("name") || "").trim();
  const she = user.getString("gender") === "female";
  push.sendTo(
    pick.partner,
    (lang) => T.t("reset_title", lang, { name: own || T.t("partner", lang) }),
    (lang) => T.t(she ? "reset_body_f" : "reset_body_m", lang, { name: own || T.t("partner", lang) }),
    "pair_reset",
    { force: true },
  );
  // Хозяину аккаунта — на его телефоны: попросить код на чужую почту может и
  // сам партнёр, и тогда код приходит ему же. Без этого уведомления хозяин о
  // смене своего пароля не узнавал вовсе (10.11.2026). Метка та же
  // `pair_reset`: приложение по ней спрашивает и `pending`, и `own`.
  let partnerName = "";
  try {
    const p = $app.findRecordById("users", pick.partner);
    partnerName = String(p.getString("display_name") || p.getString("name") || "").trim();
  } catch (_) {
    partnerName = "";
  }
  push.sendTo(
    user.id,
    (lang) => T.t("reset_own_title", lang),
    (lang) => T.t("reset_own_body", lang, { name: partnerName || T.t("partner", lang) }),
    "pair_reset",
    { force: true },
  );
  $app.logger().warn("partner-reset: код у партнёра", "uid", user.id, "partner", pick.partner, "group", pick.groupId);
  return e.json(200, { via: "partner", ttl: Math.round(rule.CODE_TTL_MS / 1000) });
});

/// Запрос на МОЙ аккаунт: приложение хозяина показывает лист «Ваш пароль
/// меняют» с кнопкой отмены. Самого кода здесь нет: он только у партнёра.
/// `stage`: `code` — код ещё не введён, `ticket` — введён, выдан пропуск на
/// новый пароль.
routerAdd("GET", "/api/auth/partner-reset/own", (e) => {
  const rule = require(`${__hooks}/partner_reset.js`);
  const store = $app.store();
  const me = e.auth.id;
  const now = Date.now();

  let found = null;
  const req = store.get("preset_req_" + me);
  if (req && req.code && now - req.at <= rule.CODE_TTL_MS && Number(req.tries || 0) < rule.MAX_TRIES) {
    found = { stage: "code", partner: req.partner, at: req.at, expiresAt: req.at + rule.CODE_TTL_MS };
  }
  if (!found) {
    const tix = store.get("preset_tix_" + me);
    if (tix && tix.ticket && now - tix.at <= rule.TICKET_TTL_MS && store.get("preset_ticket_" + tix.ticket)) {
      found = { stage: "ticket", partner: tix.partner, at: tix.at, expiresAt: tix.at + rule.TICKET_TTL_MS };
    }
  }
  if (!found) return e.json(200, { pending: null });

  let partnerName = "";
  let partnerGender = "";
  try {
    const p = $app.findRecordById("users", found.partner);
    partnerName = String(p.getString("display_name") || p.getString("name") || "");
    partnerGender = p.getString("gender");
  } catch (_) {
    partnerName = "";
  }
  return e.json(200, {
    pending: {
      stage: found.stage,
      partnerName: partnerName,
      partnerGender: partnerGender,
      at: found.at,
      expiresAt: found.expiresAt,
    },
  });
}, $apis.requireAuth("users"));

/// «Это не я»: хозяин аккаунта гасит и код, и уже выданный пропуск.
routerAdd("POST", "/api/auth/partner-reset/cancel", (e) => {
  const store = $app.store();
  const me = e.auth.id;
  let cancelled = false;

  const req = store.get("preset_req_" + me);
  if (req) {
    if (req.partner) store.remove("preset_for_" + req.partner);
    store.remove("preset_req_" + me);
    cancelled = true;
  }
  const tix = store.get("preset_tix_" + me);
  if (tix) {
    if (tix.ticket && store.get("preset_ticket_" + tix.ticket)) cancelled = true;
    if (tix.ticket) store.remove("preset_ticket_" + tix.ticket);
    store.remove("preset_tix_" + me);
  }
  if (cancelled) $app.logger().warn("partner-reset: хозяин отменил", "uid", me);
  return e.json(200, { ok: true, cancelled: cancelled });
}, $apis.requireAuth("users"));

/// Код для партнёра: приложение забирает его при открытии и по пушу.
routerAdd("GET", "/api/auth/partner-reset/pending", (e) => {
  const rule = require(`${__hooks}/partner_reset.js`);
  const store = $app.store();
  const me = e.auth.id;
  const uid = store.get("preset_for_" + me);
  if (!uid) return e.json(200, { pending: null });
  const req = store.get("preset_req_" + uid);
  const now = Date.now();
  if (!req || req.partner !== me || now - req.at > rule.CODE_TTL_MS || req.tries >= rule.MAX_TRIES) {
    store.remove("preset_for_" + me);
    return e.json(200, { pending: null });
  }
  let user;
  try { user = $app.findRecordById("users", uid); } catch (_) { return e.json(200, { pending: null }); }
  return e.json(200, {
    pending: {
      uid: uid,
      name: String(user.getString("display_name") || user.getString("name") || ""),
      gender: user.getString("gender"),
      code: req.code,
      at: req.at,
      expiresAt: req.at + rule.CODE_TTL_MS,
    },
  });
}, $apis.requireAuth("users"));

/// «Это не он»: код перестаёт работать, хозяину аккаунта — предупреждение.
routerAdd("POST", "/api/auth/partner-reset/deny", (e) => {
  const push = require(`${__hooks}/apns_push.js`);
  const store = $app.store();
  const me = e.auth.id;
  const uid = store.get("preset_for_" + me);
  if (!uid) return e.json(200, { ok: true });
  const req = store.get("preset_req_" + uid);
  store.remove("preset_for_" + me);
  if (req && req.partner === me) store.remove("preset_req_" + uid);

  const T = require(`${__hooks}/push_texts.js`);
  const own = String(e.auth.getString("display_name") || e.auth.getString("name") || "").trim();
  const she = e.auth.getString("gender") === "female";
  push.sendTo(
    uid,
    (lang) => T.t("security_title", lang),
    (lang) => T.t(she ? "security_body_f" : "security_body_m", lang, { name: own || T.t("partner", lang) }),
    "security",
    { force: true },
  );
  $app.logger().warn("partner-reset: партнёр отказал", "uid", uid, "partner", me);
  return e.json(200, { ok: true });
}, $apis.requireAuth("users"));

/// Код с нового телефона. Верный код меняется на пропуск для нового пароля.
routerAdd("POST", "/api/auth/partner-reset/verify", (e) => {
  const rule = require(`${__hooks}/partner_reset.js`);
  const store = $app.store();
  const now = Date.now();

  // Перебор по многим аккаунтам с одного адреса тоже держим.
  const ipKey = "preset_vip_" + e.realIP();
  const hit = store.get(ipKey);
  const win = hit && now - hit.at < 3600 * 1000 ? hit : { at: now, n: 0 };
  if (win.n >= 30) return e.json(429, { code: "ip", message: "Слишком много попыток. Попробуйте через час." });
  store.set(ipKey, { at: win.at, n: win.n + 1 });

  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const email = String(body.email || "").trim();
  const input = String(body.code || "");

  let user = null;
  try {
    user = $app.findAuthRecordByEmail("users", email);
  } catch (_) {
    user = null;
  }
  if (!user && email) {
    try {
      const rows = arrayOf(new DynamicModel({ id: "" }));
      $app.db()
        .newQuery("SELECT id FROM users WHERE lower(email) = lower({:e}) LIMIT 2")
        .bind({ e: email })
        .all(rows);
      if (rows.length === 1) user = $app.findRecordById("users", rows[0].id);
    } catch (_) {
      user = null;
    }
  }
  if (!user) return e.json(404, { code: "none", message: "Запроса нет. Попросите код ещё раз." });

  const key = "preset_req_" + user.id;
  const req = store.get(key);
  const res = rule.checkCode(req, input, now);
  if (res.verdict === "ok") {
    store.remove(key);
    store.remove("preset_for_" + req.partner);
    const ticket = $security.randomString(40);
    store.set("preset_ticket_" + ticket, { uid: user.id, at: now, partner: req.partner });
    // По этой записи хозяин находит и гасит пропуск (`own`, `cancel`).
    store.set("preset_tix_" + user.id, { ticket: ticket, at: now, partner: req.partner });
    let partnerName = "";
    let partnerGender = "";
    try {
      const p = $app.findRecordById("users", req.partner);
      partnerName = String(p.getString("display_name") || p.getString("name") || "");
      partnerGender = p.getString("gender");
    } catch (_) {
      partnerName = "";
    }
    $app.logger().warn("partner-reset: код верный", "uid", user.id, "partner", req.partner);
    return e.json(200, {
      ticket: ticket,
      name: String(user.getString("display_name") || user.getString("name") || ""),
      partnerName: partnerName,
      partnerGender: partnerGender,
    });
  }
  if (req) store.set(key, req);
  if (res.verdict === "wrong") return e.json(400, { code: "wrong", left: res.left, message: "Код не подходит." });
  if (res.verdict === "locked") {
    store.remove(key);
    if (req && req.partner) store.remove("preset_for_" + req.partner);
    $app.logger().warn("partner-reset: код заперт промахами", "uid", user.id);
    return e.json(429, { code: "locked", message: "Слишком много промахов. Попросите новый код." });
  }
  if (res.verdict === "expired") return e.json(410, { code: "expired", message: "Код истёк. Попросите новый." });
  return e.json(404, { code: "none", message: "Запроса нет. Попросите код ещё раз." });
});

/// Новый пароль по пропуску. Ответ — как у входа: токен и запись.
routerAdd("POST", "/api/auth/partner-reset/complete", (e) => {
  const rule = require(`${__hooks}/partner_reset.js`);
  const store = $app.store();
  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const ticket = String(body.ticket || "");
  const password = body.password;

  const pass = ticket ? store.get("preset_ticket_" + ticket) : null;
  if (!pass || Date.now() - pass.at > rule.TICKET_TTL_MS) {
    if (ticket) store.remove("preset_ticket_" + ticket);
    return e.json(410, { code: "expired", message: "Время вышло. Попросите код ещё раз." });
  }
  const problem = rule.passwordProblem(password);
  if (problem) return e.json(400, { code: problem, message: problem === "short" ? "Нужно не меньше 8 символов." : "Слишком длинный пароль." });

  // Свежая запись прямо перед сохранением: снимок, пролежавший в памяти, мог
  // бы вернуть в базу устаревшие поля (так терялся выданный Плюс 18.10.2026).
  const user = $app.findRecordById("users", pass.uid);
  user.setPassword(password);
  $app.save(user);
  store.remove("preset_ticket_" + ticket);
  try {
    $app.db()
      .newQuery("UPDATE users SET password_set = {:t} WHERE id = {:id}")
      .bind({ t: Date.now(), id: user.id })
      .execute();
  } catch (err) {
    $app.logger().warn("partner-reset: отметка пароля не записалась", "uid", user.id, "err", String(err));
  }
  store.remove("preset_tix_" + user.id);
  $app.logger().warn("partner-reset: пароль сменён", "uid", user.id);
  // Хозяину — на все его телефоны: прежние сессии сменой пароля сорваны, и без
  // этих слов он не поймёт, почему его выкинуло и чьим кодом это сделано.
  try {
    const push = require(`${__hooks}/apns_push.js`);
    const T = require(`${__hooks}/push_texts.js`);
    let partnerName = "";
    try {
      const p = $app.findRecordById("users", String(pass.partner || ""));
      partnerName = String(p.getString("display_name") || p.getString("name") || "").trim();
    } catch (_) {
      partnerName = "";
    }
    push.sendTo(
      user.id,
      (lang) => T.t("reset_done_title", lang),
      (lang) => T.t("reset_done_body", lang, { name: partnerName || T.t("partner", lang) }),
      "security",
      { force: true },
    );
  } catch (err) {
    $app.logger().warn("partner-reset: уведомление о смене не ушло", "uid", user.id, "err", String(err));
  }
  return $apis.recordAuthResponse(e, user, "password", null);
});
