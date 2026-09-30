/// <reference path="../pb_data/types.d.ts" />

/// Смена почты аккаунта кодом из письма (30.09.2026).
///
/// Своей смены почты в приложении не было: «у меня не та почта», «неправильно
/// указан адрес» (обращения 148, 179, 208) каждый раз правились руками через
/// суперюзера. Штатная смена PocketBase не годится: письмо английское, ссылка
/// ведёт в админку, а подтверждение просит пароль, которого у вошедших через
/// Google или Apple нет вовсе.
///
/// Поэтому свой путь, для вошедшего человека:
///   POST /api/account/email-change/request  { email, lang }
///        → на НОВЫЙ адрес уходит код из шести цифр;
///   POST /api/account/email-change/confirm  { email, code }
///        → код совпал — почта меняется и сразу считается подтверждённой.
///
/// Код живёт 15 минут в памяти процесса ($app.store): перезапуск PB его
/// теряет, и человек просто запросит новый. Попыток ввода пять, писем — не
/// чаще раза в минуту и не больше пяти в час: бесплатный Resend даёт сотню
/// писем в сутки на всё, включая сброс пароля.
///
/// Ответы с ошибкой несут `code`: invalid, same, taken, wait, limit, expired,
/// wrong, tries, mail. Приложение показывает по нему свою фразу.
///
/// Хелперы повторены в каждом обработчике: JSVM не показывает обработчику
/// функции уровня файла (см. CLAUDE.md, «Грабли JSVM»).

routerAdd("POST", "/api/account/email-change/request", (e) => {
  const fail = (status, code) => e.json(status, { code: code });
  const auth = e.auth;
  const body = e.requestInfo().body || {};
  const email = String(body.email || "").trim().toLowerCase();
  const lang = String(body.lang || "ru");

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) || email.length > 200) {
    return fail(400, "invalid");
  }
  if (email === String(auth.email() || "").toLowerCase()) {
    return fail(400, "same");
  }
  const rows = arrayOf(new DynamicModel({ id: "" }));
  $app.db()
    .newQuery("SELECT id FROM users WHERE lower(email) = {:e} LIMIT 1")
    .bind({ e: email })
    .all(rows);
  if (rows.length > 0) return fail(409, "taken");

  const key = "email-change:" + auth.id;
  const now = Date.now();
  let prev = null;
  try {
    const raw = $app.store().get(key);
    if (raw) prev = JSON.parse(raw);
  } catch (_) {}
  const sends = ((prev && prev.sends) || []).filter((t) => now - t < 3600000);
  if (sends.length && now - sends[sends.length - 1] < 60000) {
    return e.json(429, {
      code: "wait",
      retryIn: Math.ceil((60000 - (now - sends[sends.length - 1])) / 1000),
    });
  }
  if (sends.length >= 5) return fail(429, "limit");

  const code = $security.randomStringWithAlphabet(6, "0123456789");
  const ru = lang === "ru";
  const subject = ru
    ? "Код для смены почты в Togetherly"
    : "Your Togetherly email change code";
  const intro = ru
    ? "Вы меняете почту аккаунта Togetherly на этот адрес. Введите код в приложении:"
    : "You are changing your Togetherly account email to this address. Enter the code in the app:";
  const outro = ru
    ? "Код действует 15 минут. Если вы ничего не меняли, просто удалите это письмо."
    : "The code is valid for 15 minutes. If this wasn't you, just delete this email.";
  const html =
    '<div style="font-family:Arial,sans-serif;font-size:16px;color:#22191a;line-height:1.5">' +
    "<p>" + intro + "</p>" +
    '<p style="font-size:32px;font-weight:700;letter-spacing:6px;margin:16px 0">' + code + "</p>" +
    '<p style="color:#524344;font-size:14px">' + outro + "</p></div>";

  try {
    const meta = $app.settings().meta;
    const message = new MailerMessage({
      from: { address: meta.senderAddress, name: meta.senderName },
      to: [{ address: email }],
      subject: subject,
      html: html,
    });
    $app.newMailClient().send(message);
  } catch (err) {
    $app.logger().warn("email-change: письмо не ушло", "uid", auth.id, "err", String(err));
    return fail(502, "mail");
  }

  sends.push(now);
  $app.store().set(key, JSON.stringify({
    email: email,
    code: code,
    exp: now + 15 * 60000,
    tries: 0,
    sends: sends,
  }));
  $app.logger().info("email-change: код отправлен", "uid", auth.id);
  return e.json(200, { ok: true, retryIn: 60 });
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/account/email-change/confirm", (e) => {
  const fail = (status, code) => e.json(status, { code: code });
  const auth = e.auth;
  const body = e.requestInfo().body || {};
  const email = String(body.email || "").trim().toLowerCase();
  const code = String(body.code || "").replace(/\D/g, "");

  const key = "email-change:" + auth.id;
  let pending = null;
  try {
    const raw = $app.store().get(key);
    if (raw) pending = JSON.parse(raw);
  } catch (_) {}
  const now = Date.now();
  if (!pending || !pending.code || pending.email !== email || now > pending.exp) {
    return fail(400, "expired");
  }
  if (pending.tries >= 5) return fail(429, "tries");
  if (code !== pending.code) {
    pending.tries = (pending.tries || 0) + 1;
    $app.store().set(key, JSON.stringify(pending));
    return fail(400, pending.tries >= 5 ? "tries" : "wrong");
  }

  // Адрес мог занять кто-то другой, пока письмо шло.
  const rows = arrayOf(new DynamicModel({ id: "" }));
  $app.db()
    .newQuery("SELECT id FROM users WHERE lower(email) = {:e} AND id != {:id} LIMIT 1")
    .bind({ e: email, id: auth.id })
    .all(rows);
  if (rows.length > 0) return fail(409, "taken");

  const record = $app.findRecordById("users", auth.id);
  const old = record.email();
  record.setEmail(email);
  record.setVerified(true);
  $app.save(record);
  // Код одноразовый: письма в этот час всё равно считаются в лимит.
  $app.store().set(key, JSON.stringify({ sends: pending.sends || [] }));
  $app.logger().info("email-change: почта сменена", "uid", auth.id, "from", old, "to", email);
  // Смена почты обнуляет прежние токены входа (так PocketBase защищает
  // аккаунт), и без нового токена человека выкинуло бы из приложения.
  return e.json(200, { ok: true, email: email, token: record.newAuthToken() });
}, $apis.requireAuth("users"));
