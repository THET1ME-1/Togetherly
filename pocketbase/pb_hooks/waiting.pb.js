/// Пара с пустым местом («он в армии»).
///
/// ЗАЧЕМ: пара, где второго ещё нет физически — он в армии, на вахте, в
/// экспедиции. Раньше такой человек сидел без пары: настроение не сохранялось,
/// лента и чат ждали партнёра, а когда он возвращался, переносить историю было
/// неоткуда. Теперь пара заводится сразу и на одного: второе место занимает
/// заглушка (имя, фото, дата возвращения), а все записи с первого дня пишутся
/// в группу. Он ставит приложение, вводит код — и вся история уже его.
///
/// Роуты (все под `$apis.requireAuth()`):
///   POST /api/waiting/create   { name, avatar?, returnDate? } → создать пару с пустым местом
///   POST /api/waiting/update   { groupId, name?, avatar?, returnDate? } → поправить заглушку
///   POST /api/waiting/claim    { code }        → заявка на второе место
///   POST /api/waiting/approve  { groupId, approve } → она подтверждает или отклоняет
///   POST /api/waiting/reset    { groupId }     → сбросить код (расставание)
///   GET  /api/waiting/state?code=…             → статус заявки для ждущего
///
/// РЕШЕНИЯ, которые нельзя молча поменять:
///   • Код НЕ протухает. Ни года, ни двух: человек уходит служить, а срок
///     возвращения плавает. TTL здесь означал бы «пара развалилась по таймеру».
///   • Привязку подтверждает хозяйка пары. Код может засветиться в сторис, и
///     без подтверждения чужой человек попадёт в чужую переписку.
///   • Заявку принимаем из ЛЮБОГО аккаунта, не только свежесозданного: он мог
///     поставить приложение раньше и уже что-то нажать.
///   • Своей группы у заявителя быть не должно — иначе он утащит в новую пару
///     вторую живую связь.
///
/// ВАЖНО (PB JSVM): обработчик исполняется изолированно и НЕ видит функций
/// уровня файла — все хелперы объявлены ВНУТРИ каждого обработчика.

// ── создать пару с пустым местом ─────────────────────────────────────────────
routerAdd("POST", "/api/waiting/create", (e) => {
  const uid = e.auth.id;
  const body = e.requestInfo().body || {};
  const name = String(body.name || "").trim().slice(0, 60);
  const avatar = String(body.avatar || "").trim();
  const returnDate = String(body.returnDate || "").trim();

  const membersOf = (g) => {
    try { return JSON.parse(g.getString("members") || "[]") || []; }
    catch (_) { return []; }
  };
  const newToken = () => {
    const abc = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let out = "";
    for (let i = 0; i < 8; i++) {
      out += abc[Math.floor(Math.random() * abc.length)];
    }
    return out;
  };
  const freeToken = () => {
    for (let i = 0; i < 12; i++) {
      const t = newToken();
      try {
        const rows = $app.findRecordsByFilter("groups", "claim_token = {:t}", "", 1, 0, { t: t });
        if (!rows || rows.length === 0) return t;
      } catch (_) { return t; }
    }
    return "";
  };

  if (!name) return e.json(400, { success: false, message: "Впишите имя" });

  // Уже есть живая пара — второй такой быть не должно.
  try {
    const mine = $app.findRecordsByFilter(
      "groups", "members ~ {:u} && disbanded = false", "", 5, 0, { u: uid });
    for (let i = 0; i < mine.length; i++) {
      const ms = membersOf(mine[i]);
      if (ms.length > 1 || mine[i].getString("claim_token")) {
        return e.json(400, { success: false, message: "У вас уже есть пара" });
      }
    }
  } catch (_) { /* нет групп — как раз наш случай */ }

  const token = freeToken();
  if (!token) return e.json(500, { success: false, message: "Не удалось выдать код" });

  let me = { name: "", avatar: "" };
  try {
    const u = $app.findRecordById("users", uid);
    me = { name: u.getString("display_name") || "", avatar: u.getString("avatar_url") || "" };
  } catch (_) { /* профиль не прочитался — имя подставит клиент */ }

  const nowIso = new Date().toISOString();
  let created = null;
  try {
    $app.runInTransaction((txApp) => {
      const col = txApp.findCollectionByNameOrId("groups");
      const g = new Record(col);
      const names = {}; names[uid] = me.name;
      const avatars = {}; avatars[uid] = me.avatar;
      g.set("members", [uid]);
      g.set("member_names", names);
      g.set("member_avatars", avatars);
      g.set("max_members", 2);
      g.set("relationship_type", "couple");
      g.set("custom_relationship_types", []);
      g.set("memories_count", 0);
      g.set("drawings_count", 0);
      g.set("start_date", nowIso);
      g.set("created_at", nowIso);
      g.set("disbanded", false);
      g.set("waiting_mode", true);
      g.set("placeholder_name", name);
      if (avatar) g.set("placeholder_avatar", avatar);
      if (returnDate) g.set("return_date", returnDate);
      g.set("claim_token", token);
      txApp.save(g);
      created = g.id;
    });
  } catch (err) {
    return e.json(500, { success: false, message: "Не удалось создать пару" });
  }
  return e.json(200, { success: true, pairId: created, code: token });
}, $apis.requireAuth());

// ── поправить заглушку (имя, фото, дата возвращения) ────────────────────────
routerAdd("POST", "/api/waiting/update", (e) => {
  const uid = e.auth.id;
  const body = e.requestInfo().body || {};
  const groupId = String(body.groupId || "");
  if (!groupId) return e.json(400, { success: false, message: "Не указана пара" });

  let g;
  try { g = $app.findRecordById("groups", groupId); }
  catch (_) { return e.json(404, { success: false, message: "Пара не найдена" }); }

  let members = [];
  try { members = JSON.parse(g.getString("members") || "[]") || []; } catch (_) {}
  if (members.indexOf(uid) === -1) {
    return e.json(403, { success: false, message: "Это не ваша пара" });
  }
  if (!g.get("waiting_mode")) {
    return e.json(400, { success: false, message: "Место уже занято" });
  }

  if (body.name !== undefined) {
    const n = String(body.name || "").trim().slice(0, 60);
    if (n) g.set("placeholder_name", n);
  }
  if (body.avatar !== undefined) g.set("placeholder_avatar", String(body.avatar || ""));
  if (body.returnDate !== undefined) {
    const d = String(body.returnDate || "").trim();
    g.set("return_date", d || null);
  }
  try { $app.save(g); }
  catch (err) { return e.json(500, { success: false, message: "Не сохранилось" }); }
  return e.json(200, { success: true });
}, $apis.requireAuth());

// ── заявка на второе место ──────────────────────────────────────────────────
routerAdd("POST", "/api/waiting/claim", (e) => {
  const uid = e.auth.id;
  const code = String((e.requestInfo().body || {}).code || "").toUpperCase().trim();
  const deny = (status, message, why) => {
    try {
      $app.logger().warn("waiting claim: отказ", "why", why, "code", code, "uid", uid);
    } catch (_) {}
    return e.json(status, { success: false, message: message });
  };
  if (!code) return deny(400, "Код не указан", "пустой код");

  const membersOf = (g) => {
    try { return JSON.parse(g.getString("members") || "[]") || []; }
    catch (_) { return []; }
  };

  let g;
  try {
    const rows = $app.findRecordsByFilter("groups", "claim_token = {:t}", "", 1, 0, { t: code });
    g = rows && rows.length ? rows[0] : null;
  } catch (_) { g = null; }
  if (!g) return deny(404, "Код не найден", "нет такого claim_token");
  if (!g.get("waiting_mode")) return deny(400, "Место уже занято", "waiting_mode выключен");

  const members = membersOf(g);
  if (members.indexOf(uid) !== -1) {
    return e.json(200, { success: true, status: "member", pairId: g.id });
  }
  // Своя живая пара у заявителя — он не может быть в двух сразу.
  try {
    const mine = $app.findRecordsByFilter(
      "groups", "members ~ {:u} && disbanded = false", "", 5, 0, { u: uid });
    for (let i = 0; i < mine.length; i++) {
      if (mine[i].id !== g.id) {
        return deny(400, "У вас уже есть пара — выйдите из неё", "заявитель уже в паре");
      }
    }
  } catch (_) {}

  let myName = "";
  try { myName = $app.findRecordById("users", uid).getString("display_name") || ""; }
  catch (_) {}

  g.set("claim_uid", uid);
  g.set("claim_name", myName);
  g.set("claim_at", Date.now());
  try { $app.save(g); }
  catch (err) { return deny(500, "Не удалось отправить заявку", "save упал"); }

  return e.json(200, {
    success: true,
    status: "pending",
    pairId: g.id,
    ownerName: (function () {
      try {
        const names = JSON.parse(g.getString("member_names") || "{}") || {};
        return names[members[0]] || "";
      } catch (_) { return ""; }
    })(),
  });
}, $apis.requireAuth());

// ── она подтверждает или отклоняет ──────────────────────────────────────────
routerAdd("POST", "/api/waiting/approve", (e) => {
  const uid = e.auth.id;
  const body = e.requestInfo().body || {};
  const groupId = String(body.groupId || "");
  const approve = body.approve !== false;
  if (!groupId) return e.json(400, { success: false, message: "Не указана пара" });

  const membersOf = (g) => {
    try { return JSON.parse(g.getString("members") || "[]") || []; }
    catch (_) { return []; }
  };
  const mapOf = (g, field) => {
    try { return JSON.parse(g.getString(field) || "{}") || {}; }
    catch (_) { return {}; }
  };

  let result;
  try {
    $app.runInTransaction((txApp) => {
      const g = txApp.findRecordById("groups", groupId);
      const members = membersOf(g);
      if (members.indexOf(uid) === -1) {
        result = { code: 403, body: { success: false, message: "Это не ваша пара" } };
        return;
      }
      const claimUid = String(g.getString("claim_uid") || "");
      if (!claimUid) {
        result = { code: 400, body: { success: false, message: "Заявки нет" } };
        return;
      }
      if (!approve) {
        g.set("claim_uid", "");
        g.set("claim_name", "");
        g.set("claim_at", 0);
        txApp.save(g);
        result = { code: 200, body: { success: true, approved: false } };
        return;
      }
      if (members.indexOf(claimUid) === -1) members.push(claimUid);
      const names = mapOf(g, "member_names");
      const avatars = mapOf(g, "member_avatars");
      try {
        const u = txApp.findRecordById("users", claimUid);
        names[claimUid] = u.getString("display_name") || g.getString("placeholder_name");
        avatars[claimUid] = u.getString("avatar_url") || "";
      } catch (_) {
        names[claimUid] = g.getString("placeholder_name");
        avatars[claimUid] = "";
      }
      g.set("members", members);
      g.set("member_names", names);
      g.set("member_avatars", avatars);
      // Место занято: заглушка больше не нужна, код гасим — второй раз им
      // воспользоваться нельзя.
      g.set("waiting_mode", false);
      g.set("claim_token", "");
      g.set("claim_uid", "");
      g.set("claim_name", "");
      g.set("claim_at", 0);
      txApp.save(g);
      result = { code: 200, body: { success: true, approved: true, pairId: g.id } };
    });
  } catch (err) {
    return e.json(500, { success: false, message: "Не сохранилось" });
  }
  return e.json(result.code, result.body);
}, $apis.requireAuth());

// ── сбросить код (расставание, код утёк) ────────────────────────────────────
routerAdd("POST", "/api/waiting/reset", (e) => {
  const uid = e.auth.id;
  const groupId = String((e.requestInfo().body || {}).groupId || "");
  if (!groupId) return e.json(400, { success: false, message: "Не указана пара" });

  const newToken = () => {
    const abc = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let out = "";
    for (let i = 0; i < 8; i++) out += abc[Math.floor(Math.random() * abc.length)];
    return out;
  };

  let g;
  try { g = $app.findRecordById("groups", groupId); }
  catch (_) { return e.json(404, { success: false, message: "Пара не найдена" }); }

  let members = [];
  try { members = JSON.parse(g.getString("members") || "[]") || []; } catch (_) {}
  if (members.indexOf(uid) === -1) {
    return e.json(403, { success: false, message: "Это не ваша пара" });
  }

  // Второй уже пришёл — сброс кода его не выгоняет: это отдельное решение
  // (роспуск пары), и делается оно другой кнопкой.
  if (members.length > 1) {
    return e.json(400, { success: false, message: "Место уже занято" });
  }

  const token = newToken();
  g.set("claim_token", token);
  g.set("claim_uid", "");
  g.set("claim_name", "");
  g.set("claim_at", 0);
  g.set("waiting_mode", true);
  try { $app.save(g); }
  catch (err) { return e.json(500, { success: false, message: "Не сохранилось" }); }
  return e.json(200, { success: true, code: token });
}, $apis.requireAuth());

// ── статус заявки для ждущего ───────────────────────────────────────────────
// Пока хозяйка не нажала «это он», заявитель не член группы и правила её не
// отдают. Этот роут — единственное, что ему видно: приняли, отклонили, ждём.
routerAdd("GET", "/api/waiting/state", (e) => {
  const uid = e.auth.id;
  const code = String((e.requestInfo().query || {}).code || "").toUpperCase().trim();

  const membersOf = (g) => {
    try { return JSON.parse(g.getString("members") || "[]") || []; }
    catch (_) { return []; }
  };

  // Приняли — группа уже наша, ищем по членству (код к тому времени погашен).
  try {
    const mine = $app.findRecordsByFilter(
      "groups", "members ~ {:u} && disbanded = false", "-created_at", 1, 0, { u: uid });
    if (mine && mine.length) {
      return e.json(200, { success: true, status: "approved", pairId: mine[0].id });
    }
  } catch (_) {}

  if (!code) return e.json(200, { success: true, status: "none" });
  let g;
  try {
    const rows = $app.findRecordsByFilter("groups", "claim_token = {:t}", "", 1, 0, { t: code });
    g = rows && rows.length ? rows[0] : null;
  } catch (_) { g = null; }
  if (!g) return e.json(200, { success: true, status: "gone" });
  if (membersOf(g).indexOf(uid) !== -1) {
    return e.json(200, { success: true, status: "approved", pairId: g.id });
  }
  const claimUid = String(g.getString("claim_uid") || "");
  if (claimUid === uid) return e.json(200, { success: true, status: "pending" });
  // Заявку сняли (отклонили или заменили чужой) — человеку надо повторить.
  return e.json(200, { success: true, status: "rejected" });
}, $apis.requireAuth());
