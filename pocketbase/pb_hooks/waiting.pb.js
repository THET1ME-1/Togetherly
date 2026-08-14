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
/// ЗАПИСЬ ПАРЫ ЖИВЁТ В POSTGRES (15.08.2026). Все проверки состава и все
/// правки идут в сервис hotpath (127.0.0.1:8120) — он держит строку пары и
/// делает решение одним запросом под блокировкой этой строки. PocketBase здесь
/// не пишет ничего: раньше каждая такая операция открывала транзакцию на
/// единственном соединении записи и стояла в общей очереди со всем остальным.
/// Профили (имя, аватар) по-прежнему читаются из PocketBase — users остались там.
///
/// ВАЖНО (PB JSVM): обработчик исполняется изолированно и НЕ видит функций
/// уровня файла — все хелперы объявлены ВНУТРИ каждого обработчика.

// ── создать пару с пустым местом ─────────────────────────────────────────────
routerAdd("POST", "/api/waiting/create", (e) => {
  const uid = e.auth.id;
  const body = e.requestInfo().body || {};
  const name = String(body.name || "").trim().slice(0, 60);
  if (!name) return e.json(400, { success: false, message: "Впишите имя" });

  let me = { name: "", avatar: "" };
  try {
    const u = $app.findRecordById("users", uid);
    me = { name: u.getString("display_name") || "", avatar: u.getString("avatar_url") || "" };
  } catch (_) { /* профиль не прочитался — имя подставит клиент */ }

  try {
    const r = $http.send({
      url: "http://127.0.0.1:8120/internal/waiting-create",
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        uid: uid,
        placeholder_name: name,
        placeholder_avatar: String(body.avatar || "").trim(),
        return_date: String(body.returnDate || "").trim(),
        my_name: me.name,
        my_avatar: me.avatar,
      }),
      timeout: 15,
    });
    const out = (r && r.json) || null;
    if (!out || out.success !== true) {
      return e.json(r && r.statusCode === 400 ? 400 : 500,
        { success: false, message: (out && out.message) || "Не удалось создать пару" });
    }
    return e.json(200, out);
  } catch (err) {
    $app.logger().warn("waiting create: hotpath недоступен", "err", String(err));
    return e.json(500, { success: false, message: "Не удалось создать пару" });
  }
}, $apis.requireAuth());

// ── поправить заглушку (имя, фото, дата возвращения) ────────────────────────
routerAdd("POST", "/api/waiting/update", (e) => {
  const uid = e.auth.id;
  const body = e.requestInfo().body || {};
  const groupId = String(body.groupId || "");
  if (!groupId) return e.json(400, { success: false, message: "Не указана пара" });

  const hp = (path, method, payload) => {
    const r = $http.send({
      url: "http://127.0.0.1:8120" + path,
      method: method,
      headers: { "content-type": "application/json" },
      body: payload ? JSON.stringify(payload) : undefined,
      timeout: 10,
    });
    return { code: r.statusCode, body: (r && r.json) || null };
  };

  let пара;
  try {
    const got = hp("/internal/group-read?id=" + encodeURIComponent(groupId), "GET", null);
    пара = got.body && got.body.record;
  } catch (err) {
    $app.logger().warn("waiting update: hotpath недоступен", "err", String(err));
    return e.json(500, { success: false, message: "Не сохранилось" });
  }
  if (!пара) return e.json(404, { success: false, message: "Пара не найдена" });

  const members = Array.isArray(пара.members) ? пара.members : [];
  if (members.indexOf(uid) === -1) {
    return e.json(403, { success: false, message: "Это не ваша пара" });
  }
  if (!пара.waiting_mode) {
    return e.json(400, { success: false, message: "Место уже занято" });
  }

  const set = {};
  if (body.name !== undefined) {
    const n = String(body.name || "").trim().slice(0, 60);
    if (n) set.placeholder_name = n;
  }
  if (body.avatar !== undefined) set.placeholder_avatar = String(body.avatar || "");
  if (body.returnDate !== undefined) set.return_date = String(body.returnDate || "").trim();
  if (!Object.keys(set).length) return e.json(200, { success: true });

  try {
    const r = hp("/internal/group-write", "POST", { group_id: groupId, set: set });
    if (!r.body || r.body.ok !== true) {
      return e.json(500, { success: false, message: "Не сохранилось" });
    }
  } catch (err) {
    $app.logger().warn("waiting update: запись не прошла", "err", String(err));
    return e.json(500, { success: false, message: "Не сохранилось" });
  }
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

  const hp = (path, method, payload) => {
    const r = $http.send({
      url: "http://127.0.0.1:8120" + path,
      method: method,
      headers: { "content-type": "application/json" },
      body: payload ? JSON.stringify(payload) : undefined,
      timeout: 10,
    });
    return { code: r.statusCode, body: (r && r.json) || null };
  };

  let пара = null;
  let свои = [];
  try {
    const got = hp("/internal/group-read?claim_token=" + encodeURIComponent(code), "GET", null);
    пара = got.body && got.body.record;
    const мои = hp("/internal/groups-of?uid=" + encodeURIComponent(uid) + "&live=1", "GET", null);
    свои = (мои.body && мои.body.items) || [];
  } catch (err) {
    $app.logger().warn("waiting claim: hotpath недоступен", "err", String(err));
    return deny(500, "Не удалось отправить заявку", "hotpath недоступен");
  }
  if (!пара) return deny(404, "Код не найден", "нет такого claim_token");
  if (!пара.waiting_mode) return deny(400, "Место уже занято", "waiting_mode выключен");

  const members = Array.isArray(пара.members) ? пара.members : [];
  if (members.indexOf(uid) !== -1) {
    return e.json(200, { success: true, status: "member", pairId: пара.id });
  }
  for (let i = 0; i < свои.length; i++) {
    if (свои[i].id !== пара.id) {
      return deny(400, "У вас уже есть пара — выйдите из неё", "заявитель уже в паре");
    }
  }

  let myName = "";
  try { myName = $app.findRecordById("users", uid).getString("display_name") || ""; }
  catch (_) {}

  try {
    const r = hp("/internal/group-write", "POST", {
      group_id: пара.id,
      set: { claim_uid: uid, claim_name: myName, claim_at: Date.now() },
    });
    if (!r.body || r.body.ok !== true) {
      return deny(500, "Не удалось отправить заявку", "запись не прошла");
    }
  } catch (err) {
    return deny(500, "Не удалось отправить заявку", "запись упала: " + String(err));
  }

  const names = (пара.member_names && typeof пара.member_names === "object")
    ? пара.member_names : {};
  return e.json(200, {
    success: true,
    status: "pending",
    pairId: пара.id,
    ownerName: names[members[0]] || "",
  });
}, $apis.requireAuth());

// ── она подтверждает или отклоняет ──────────────────────────────────────────
routerAdd("POST", "/api/waiting/approve", (e) => {
  const uid = e.auth.id;
  const body = e.requestInfo().body || {};
  const groupId = String(body.groupId || "");
  const approve = body.approve !== false;
  if (!groupId) return e.json(400, { success: false, message: "Не указана пара" });

  const hp = (path, method, payload) => {
    const r = $http.send({
      url: "http://127.0.0.1:8120" + path,
      method: method,
      headers: { "content-type": "application/json" },
      body: payload ? JSON.stringify(payload) : undefined,
      timeout: 15,
    });
    return { code: r.statusCode, body: (r && r.json) || null };
  };

  let пара;
  try {
    const got = hp("/internal/group-read?id=" + encodeURIComponent(groupId), "GET", null);
    пара = got.body && got.body.record;
  } catch (err) {
    $app.logger().warn("waiting approve: hotpath недоступен", "err", String(err));
    return e.json(500, { success: false, message: "Не сохранилось" });
  }
  if (!пара) return e.json(404, { success: false, message: "Пара не найдена" });

  const members = Array.isArray(пара.members) ? пара.members : [];
  if (members.indexOf(uid) === -1) {
    return e.json(403, { success: false, message: "Это не ваша пара" });
  }
  const claimUid = String(пара.claim_uid || "");
  if (!claimUid) return e.json(400, { success: false, message: "Заявки нет" });

  if (!approve) {
    try {
      const r = hp("/internal/group-write", "POST", {
        group_id: groupId,
        set: { claim_uid: "", claim_name: "", claim_at: 0 },
      });
      if (!r.body || r.body.ok !== true) {
        return e.json(500, { success: false, message: "Не сохранилось" });
      }
    } catch (err) {
      return e.json(500, { success: false, message: "Не сохранилось" });
    }
    return e.json(200, { success: true, approved: false });
  }

  let имя = "";
  let аватар = "";
  try {
    const u = $app.findRecordById("users", claimUid);
    имя = u.getString("display_name") || String(пара.placeholder_name || "");
    аватар = u.getString("avatar_url") || "";
  } catch (_) { имя = String(пара.placeholder_name || ""); }

  try {
    const r = hp("/internal/pair-claim-approve", "POST", {
      group_id: groupId,
      claim_uid: claimUid,
      claim_name: имя,
      claim_avatar: аватар,
    });
    if (!r.body || r.body.ok !== true) {
      const why = (r.body && r.body.error) || "запись не прошла";
      return e.json(why === "full" ? 400 : 500,
        { success: false, message: why === "full" ? "Место уже занято" : "Не сохранилось" });
    }
  } catch (err) {
    $app.logger().warn("waiting approve: запись не прошла", "err", String(err));
    return e.json(500, { success: false, message: "Не сохранилось" });
  }
  return e.json(200, { success: true, approved: true, pairId: groupId });
}, $apis.requireAuth());

// ── сбросить код (расставание, код утёк) ────────────────────────────────────
routerAdd("POST", "/api/waiting/reset", (e) => {
  const uid = e.auth.id;
  const groupId = String((e.requestInfo().body || {}).groupId || "");
  if (!groupId) return e.json(400, { success: false, message: "Не указана пара" });

  try {
    const r = $http.send({
      url: "http://127.0.0.1:8120/internal/waiting-reset",
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ group_id: groupId, uid: uid }),
      timeout: 10,
    });
    const out = (r && r.json) || null;
    if (!out || out.success !== true) {
      return e.json(r.statusCode >= 400 && r.statusCode < 500 ? r.statusCode : 500,
        { success: false, message: (out && out.message) || "Не сохранилось" });
    }
    return e.json(200, out);
  } catch (err) {
    $app.logger().warn("waiting reset: hotpath недоступен", "err", String(err));
    return e.json(500, { success: false, message: "Не сохранилось" });
  }
}, $apis.requireAuth());

// ── статус заявки для ждущего ───────────────────────────────────────────────
// Пока хозяйка не нажала «это он», заявитель не член группы и правила её не
// отдают. Этот роут — единственное, что ему видно: приняли, отклонили, ждём.
routerAdd("GET", "/api/waiting/state", (e) => {
  const uid = e.auth.id;
  const code = String((e.requestInfo().query || {}).code || "").toUpperCase().trim();

  const hp = (path) => {
    const r = $http.send({
      url: "http://127.0.0.1:8120" + path,
      method: "GET",
      timeout: 10,
    });
    return (r && r.json) || null;
  };

  // Приняли — группа уже наша, ищем по членству (код к тому времени погашен).
  try {
    const мои = hp("/internal/groups-of?uid=" + encodeURIComponent(uid) + "&live=1");
    const items = (мои && мои.items) || [];
    if (items.length) {
      return e.json(200, { success: true, status: "approved", pairId: items[0].id });
    }
  } catch (err) {
    $app.logger().warn("waiting state: hotpath недоступен", "err", String(err));
  }

  if (!code) return e.json(200, { success: true, status: "none" });

  let пара = null;
  try {
    const got = hp("/internal/group-read?claim_token=" + encodeURIComponent(code));
    пара = got && got.record;
  } catch (_) { пара = null; }
  if (!пара) return e.json(200, { success: true, status: "gone" });

  const members = Array.isArray(пара.members) ? пара.members : [];
  if (members.indexOf(uid) !== -1) {
    return e.json(200, { success: true, status: "approved", pairId: пара.id });
  }
  if (String(пара.claim_uid || "") === uid) {
    return e.json(200, { success: true, status: "pending" });
  }
  // Заявку сняли (отклонили или заменили чужой) — человеку надо повторить.
  return e.json(200, { success: true, status: "rejected" });
}, $apis.requireAuth());
