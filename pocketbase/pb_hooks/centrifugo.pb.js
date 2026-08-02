/// Togetherly realtime через Centrifugo.
///
/// ЗАЧЕМ: встроенный realtime PocketBase (SSE) держал долгоживущие read-
/// транзакции SQLite → WAL не чекпойнтился, рос до сотен МБ, PB упирался в CPU.
/// Выносим fan-out в Centrifugo: PB лишь публикует дельты, веером занимается он.
///
/// Что делает хук:
///   1) На create/update/delete отслеживаемых коллекций POST'ит изменение в
///      Centrifugo HTTP API (внутренний порт, plain HTTP, только localhost).
///   2) Выдаёт JWT: /api/centrifugo/connection-token (аутентификация соединения)
///      и /api/centrifugo/subscription-token (доступ к приватному каналу с
///      проверкой членства).
///
/// Каналы:
///   pair:<groupId>  — всё групповое (чат, настроения, воспоминания, маскоты,
///                     холст, виджеты, co-watch-сессии, miss_you, typing, reads…)
///   user:<uid>      — присутствие (user_presence) И изменения групп пользователя
///                     (для watchMyGroups: обнаружение новой пары/выхода партнёра)
///   loc:<channel>   — live-локация (channel = "pair_<uidA>_<uidB>")
///
/// ENV (drop-in /etc/systemd/system/pocketbase.service.d/centrifugo.conf):
///   CENTRIFUGO_API        напр. http://127.0.0.1:9000/api
///   CENTRIFUGO_API_KEY    ключ HTTP API (X-API-Key)
///   CENTRIFUGO_TOKEN_HMAC HMAC-секрет подписи JWT (тот же, что в config.json)
///
/// !!! ГРАБЛИ PB JSVM (см. users_guard.pb.js / coins.pb.js / CUTOVER.md):
/// обработчик хука сериализуется и исполняется в ИЗОЛИРОВАННОМ пуле — он НЕ видит
/// функции/переменные уровня файла. Поэтому ВСЯ логика инлайн в каждом
/// обработчике; доступны только глобалы $app/$http/$os/$security/$apis и e.*.
/// Публикация — fire-and-forget в try/catch: сбой Centrifugo НИКОГДА не должен
/// ломать запись в БД; e.next() вызывается всегда.

// ── Публикация изменений записей ──────────────────────────────────────────────
// Каждый обработчик инлайнит идентичную логику: определить каналы по коллекции и
// опубликовать {event, collection, record} в Centrifugo. groups шлём И в pair:id,
// И в user:<member> (чтобы watchMyGroups видел появление/изменение пары).

onRecordAfterCreateSuccess((e) => {
  try {
    const rec = e.record;
    const col = rec.collection().name;
    const RT = { chat_messages:1, mood_entries:1, memories:1, memory_comments:1, mascots:1, miss_you:1, gifts:1, user_presence:1, live_sessions:1, live_session_presence:1, live_session_chat:1, live_location:1, canvas_strokes:1, canvas_meta:1, canvas_live:1, canvas_catalogue:1, widget_data:1, chat_typing:1, chat_reads:1, groups:1, watch_history:1, cycle_entries:1, wishes:1, wish_categories:1 };
    if (RT[col]) {
      const channels = [];
      if (col === "user_presence") { const u = rec.getString("user_uid"); if (u) channels.push("user:" + u); }
      else if (col === "live_location") { const c = rec.getString("channel"); if (c) channels.push("loc:" + c); }
      else if (col === "live_sessions") { channels.push("pair:" + rec.id); }
      else if (col === "live_session_presence" || col === "live_session_chat") { const p = rec.getString("pair_id"); if (p) channels.push("pair:" + p); }
      else if (col === "groups") {
        channels.push("pair:" + rec.id);
        // members — json-поле, и `rec.get()` в этой сборке JSVM отдаёт по нему НЕ
        // строку и НЕ массив: обе проверки ниже промахивались, каналы user:<uid>
        // не добавлялись, и создание пары не долетало приглашающему (пара
        // появлялась только после перезапуска приложения, когда список групп
        // тянется заново). Читаем как groups_membership.pb.js — getStringSlice,
        // с запасным разбором getString.
        let m = rec.getStringSlice("members") || [];
        if (!m.length) {
          try { const raw = rec.getString("members"); m = raw ? (JSON.parse(raw) || []) : []; } catch (_) { m = []; }
        }
        if (Array.isArray(m)) { for (let i = 0; i < m.length; i++) { if (m[i]) channels.push("user:" + String(m[i])); } }
      }
      else { const g = rec.getString("group_id"); if (g) channels.push("pair:" + g); }

      if (channels.length) {
        const api = $os.getenv("CENTRIFUGO_API"), key = $os.getenv("CENTRIFUGO_API_KEY");
        if (api && key) {
          const data = { event: "create", collection: col, record: rec };
          for (let i = 0; i < channels.length; i++) {
            $http.send({ method: "POST", url: api + "/publish",
              body: JSON.stringify({ channel: channels[i], data: data }),
              headers: { "Content-Type": "application/json", "X-API-Key": key }, timeout: 3 });
          }
        }
      }
    }
  } catch (err) { try { $app.logger().error("centrifugo publish(create): " + String(err)); } catch (_) {} }
  e.next();
});

onRecordAfterUpdateSuccess((e) => {
  try {
    const rec = e.record;
    const col = rec.collection().name;
    const RT = { chat_messages:1, mood_entries:1, memories:1, memory_comments:1, mascots:1, miss_you:1, gifts:1, user_presence:1, live_sessions:1, live_session_presence:1, live_session_chat:1, live_location:1, canvas_strokes:1, canvas_meta:1, canvas_live:1, canvas_catalogue:1, widget_data:1, chat_typing:1, chat_reads:1, groups:1, watch_history:1, cycle_entries:1, wishes:1, wish_categories:1 };
    if (RT[col]) {
      const channels = [];
      if (col === "user_presence") { const u = rec.getString("user_uid"); if (u) channels.push("user:" + u); }
      else if (col === "live_location") { const c = rec.getString("channel"); if (c) channels.push("loc:" + c); }
      else if (col === "live_sessions") { channels.push("pair:" + rec.id); }
      else if (col === "live_session_presence" || col === "live_session_chat") { const p = rec.getString("pair_id"); if (p) channels.push("pair:" + p); }
      else if (col === "groups") {
        channels.push("pair:" + rec.id);
        // members — json-поле, и `rec.get()` в этой сборке JSVM отдаёт по нему НЕ
        // строку и НЕ массив: обе проверки ниже промахивались, каналы user:<uid>
        // не добавлялись, и создание пары не долетало приглашающему (пара
        // появлялась только после перезапуска приложения, когда список групп
        // тянется заново). Читаем как groups_membership.pb.js — getStringSlice,
        // с запасным разбором getString.
        let m = rec.getStringSlice("members") || [];
        if (!m.length) {
          try { const raw = rec.getString("members"); m = raw ? (JSON.parse(raw) || []) : []; } catch (_) { m = []; }
        }
        if (Array.isArray(m)) { for (let i = 0; i < m.length; i++) { if (m[i]) channels.push("user:" + String(m[i])); } }
      }
      else { const g = rec.getString("group_id"); if (g) channels.push("pair:" + g); }

      if (channels.length) {
        const api = $os.getenv("CENTRIFUGO_API"), key = $os.getenv("CENTRIFUGO_API_KEY");
        if (api && key) {
          const data = { event: "update", collection: col, record: rec };
          for (let i = 0; i < channels.length; i++) {
            $http.send({ method: "POST", url: api + "/publish",
              body: JSON.stringify({ channel: channels[i], data: data }),
              headers: { "Content-Type": "application/json", "X-API-Key": key }, timeout: 3 });
          }
        }
      }
    }
  } catch (err) { try { $app.logger().error("centrifugo publish(update): " + String(err)); } catch (_) {} }
  e.next();
});

onRecordAfterDeleteSuccess((e) => {
  try {
    const rec = e.record;
    const col = rec.collection().name;
    const RT = { chat_messages:1, mood_entries:1, memories:1, memory_comments:1, mascots:1, miss_you:1, gifts:1, user_presence:1, live_sessions:1, live_session_presence:1, live_session_chat:1, live_location:1, canvas_strokes:1, canvas_meta:1, canvas_live:1, canvas_catalogue:1, widget_data:1, chat_typing:1, chat_reads:1, groups:1, watch_history:1, cycle_entries:1, wishes:1, wish_categories:1 };
    if (RT[col]) {
      const channels = [];
      if (col === "user_presence") { const u = rec.getString("user_uid"); if (u) channels.push("user:" + u); }
      else if (col === "live_location") { const c = rec.getString("channel"); if (c) channels.push("loc:" + c); }
      else if (col === "live_sessions") { channels.push("pair:" + rec.id); }
      else if (col === "live_session_presence" || col === "live_session_chat") { const p = rec.getString("pair_id"); if (p) channels.push("pair:" + p); }
      else if (col === "groups") {
        channels.push("pair:" + rec.id);
        // members — json-поле, и `rec.get()` в этой сборке JSVM отдаёт по нему НЕ
        // строку и НЕ массив: обе проверки ниже промахивались, каналы user:<uid>
        // не добавлялись, и создание пары не долетало приглашающему (пара
        // появлялась только после перезапуска приложения, когда список групп
        // тянется заново). Читаем как groups_membership.pb.js — getStringSlice,
        // с запасным разбором getString.
        let m = rec.getStringSlice("members") || [];
        if (!m.length) {
          try { const raw = rec.getString("members"); m = raw ? (JSON.parse(raw) || []) : []; } catch (_) { m = []; }
        }
        if (Array.isArray(m)) { for (let i = 0; i < m.length; i++) { if (m[i]) channels.push("user:" + String(m[i])); } }
      }
      else { const g = rec.getString("group_id"); if (g) channels.push("pair:" + g); }

      if (channels.length) {
        const api = $os.getenv("CENTRIFUGO_API"), key = $os.getenv("CENTRIFUGO_API_KEY");
        if (api && key) {
          const data = { event: "delete", collection: col, record: rec };
          for (let i = 0; i < channels.length; i++) {
            $http.send({ method: "POST", url: api + "/publish",
              body: JSON.stringify({ channel: channels[i], data: data }),
              headers: { "Content-Type": "application/json", "X-API-Key": key }, timeout: 3 });
          }
        }
      }
    }
  } catch (err) { try { $app.logger().error("centrifugo publish(delete): " + String(err)); } catch (_) {} }
  e.next();
});

// ── JWT-токены ────────────────────────────────────────────────────────────────

// Аутентификация соединения: sub = firebase uid (он же users.id).
routerAdd("POST", "/api/centrifugo/connection-token", (e) => {
  const secret = $os.getenv("CENTRIFUGO_TOKEN_HMAC");
  if (!secret) return e.json(500, { error: "not configured" });
  return e.json(200, { token: $security.createJWT({ sub: e.auth.id }, secret, 86400) });
}, $apis.requireAuth());

// Доступ к конкретному приватному каналу (проверка членства).
routerAdd("POST", "/api/centrifugo/subscription-token", (e) => {
  const uid = e.auth.id;
  const body = e.requestInfo().body || {};
  const channel = String(body.channel || "");
  if (!channel) return e.json(400, { error: "channel required" });

  let allowed = false;
  if (channel.indexOf("pair:") === 0) {
    const gid = channel.substring(5);
    try {
      const rows = $app.findRecordsByFilter("groups", "id = {:g} && members ~ {:u}", "", 1, 0, { g: gid, u: uid });
      allowed = !!(rows && rows.length > 0);
    } catch (_) {}
  } else if (channel.indexOf("user:") === 0) {
    const target = channel.substring(5);
    if (target === uid) { allowed = true; }
    else {
      try {
        const rows = $app.findRecordsByFilter("groups", "members ~ {:a} && members ~ {:b}", "", 1, 0, { a: uid, b: target });
        allowed = !!(rows && rows.length > 0);
      } catch (_) {}
    }
  } else if (channel.indexOf("loc:") === 0) {
    // loc:pair_<uidA>_<uidB> — разрешаем, если наш uid присутствует в имени канала
    allowed = channel.indexOf(uid) >= 0;
  } else if (channel.indexOf("watch:") === 0) {
    // Комната совместного просмотра. Её код — HMAC от group_id (см. watch.pb.js),
    // поэтому просто проверяем, что код совпал с одной из групп человека.
    const room = channel.substring(6);
    const secret = $os.getenv("CENTRIFUGO_TOKEN_HMAC");
    if (secret) {
      const abc = "abcdefghjkmnpqrstuvwxyz23456789";
      try {
        const rows = $app.findRecordsByFilter("groups", "members ~ {:u}", "", 20, 0, { u: uid });
        for (let i = 0; i < rows.length; i++) {
          const digest = $security.hs256(rows[i].id, secret);
          let code = "";
          for (let j = 0; j < 8; j++) code += abc[digest.charCodeAt(j) % abc.length];
          if (code === room) { allowed = true; break; }
        }
      } catch (_) {}
    }
  } else if (channel.indexOf("draw:") === 0) {
    // draw:<groupId> — эфемерные live-штрихи рисования (доступ члену группы)
    const gid = channel.substring(5);
    try {
      const rows = $app.findRecordsByFilter("groups", "id = {:g} && members ~ {:u}", "", 1, 0, { g: gid, u: uid });
      allowed = !!(rows && rows.length > 0);
    } catch (_) {}
  }
  if (!allowed) return e.json(403, { error: "forbidden" });

  const secret = $os.getenv("CENTRIFUGO_TOKEN_HMAC");
  if (!secret) return e.json(500, { error: "not configured" });
  return e.json(200, { token: $security.createJWT({ sub: uid, channel: channel }, secret, 86400) });
}, $apis.requireAuth());
