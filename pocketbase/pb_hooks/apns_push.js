/// Рассылка пушей — общая часть для хуков (см. `push_apns.pb.js`).
///
/// Хендлеры в JSVM PocketBase исполняются изолированно: функции уровня файла им
/// не видны, и попытка позвать такую функцию даёт `ReferenceError` уже на живых
/// событиях (285 записей в журнале за час, прежде чем это вылезло). Поэтому
/// общий код лежит отдельным модулем и подключается внутри каждого хендлера
/// через `require(`${__hooks}/apns_push.js`)`.
///
/// Кому НЕ посылаем:
///   • автору события;
///   • тому, кто на связи прямо сейчас (`user_presence.seen_at` свежее двух
///     минут) — у него живой сокет, уведомление нарисует само приложение, а
///     двойной баннер раздражает сильнее, чем отсутствие пуша;
///   • тому, у кого нет `apns_token` (Android и те, кто не дал разрешение).
///
/// Мёртвый токен (Apple отвечает Unregistered/BadDeviceToken) вычищаем из
/// профиля сразу, иначе будем стучать в него вечно.

const APNS_RELAY = "http://127.0.0.1:8096/push";
const ONLINE_WINDOW_MS = 2 * 60 * 1000;

function membersOf(group) {
  try { return JSON.parse(group.getString("members") || "[]") || []; }
  catch (_) { return []; }
}

function isOnline(uid) {
  try {
    const p = $app.findFirstRecordByFilter(
      "user_presence", "user_uid = {:u}", { u: uid });
    const seen = p.getString("seen_at") || p.getString("updated") || "";
    if (!seen) return false;
    const ms = new Date(String(seen).replace(" ", "T")).getTime();
    if (!ms) return false;
    return (Date.now() - ms) < ONLINE_WINDOW_MS;
  } catch (_) {
    return false; // записи нет — считаем, что не на связи
  }
}

function forgetToken(user) {
  try {
    user.set("apns_token", "");
    $app.save(user);
  } catch (_) { /* попробуем в следующий раз */ }
}

function sendTo(uid, title, body, thread) {
  let user;
  try { user = $app.findRecordById("users", uid); } catch (_) { return; }
  const token = String(user.getString("apns_token") || "");
  if (!token) return;
  if (isOnline(uid)) return;
  try {
    const res = $http.send({
      url: APNS_RELAY,
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        token: token,
        title: title,
        body: body,
        thread: thread,
        sandbox: !!user.get("apns_sandbox"),
        data: { kind: thread },
      }),
      timeout: 10,
    });
    const answer = res.json || {};
    if (answer.gone) forgetToken(user);
    if (!answer.ok) {
      $app.logger().warn("apns: не доставлено", "uid", uid,
        "reason", String(answer.reason || res.statusCode));
    }
  } catch (e) {
    $app.logger().warn("apns: релей не ответил", "err", String(e));
  }
}

/// Всем участникам группы, кроме автора.
function notifyGroup(groupId, authorUid, title, body, thread) {
  if (!groupId) return;
  let group;
  try { group = $app.findRecordById("groups", groupId); } catch (_) { return; }
  if (group.get("disbanded")) return;
  const members = membersOf(group);
  for (let i = 0; i < members.length; i++) {
    const uid = String(members[i] || "");
    if (!uid || uid === authorUid) continue;
    sendTo(uid, title, body, thread);
  }
}

/// Тихий пуш «проснись и обнови виджеты».
///
/// На iOS у виджетов нет фонового обновления: пока приложение закрыто, фото и
/// статус партнёра на рабочем столе застывают до следующего запуска. Лечится
/// только `content-available` — Apple будит приложение на несколько секунд, и
/// оно перекладывает свежие данные в контейнер App Group.
///
/// Apple такие пуши ЛИМИТИРУЕТ (несколько штук в час на устройство) и молча
/// выбрасывает лишние, поэтому будим не чаще, чем раз в [MIN_WAKE_GAP_MS], и
/// только того, кто сейчас НЕ на связи: у живого приложения данные и так
/// свежие. Отметка времени лежит в `users.apns_bg_ms`.
const MIN_WAKE_GAP_MS = 15 * 60 * 1000;

function wakeUp(uid, kind) {
  let user;
  try { user = $app.findRecordById("users", uid); } catch (_) { return; }
  const token = String(user.getString("apns_token") || "");
  if (!token) return;
  if (isOnline(uid)) return;

  const now = Date.now();
  const last = Number(user.get("apns_bg_ms") || 0);
  if (last && now - last < MIN_WAKE_GAP_MS) return;

  try {
    const res = $http.send({
      url: APNS_RELAY,
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        token: token,
        silent: true,
        sandbox: !!user.get("apns_sandbox"),
        data: { kind: kind || "widgets" },
      }),
      timeout: 10,
    });
    const answer = res.json || {};
    if (answer.gone) { forgetToken(user); return; }
    if (!answer.ok) {
      $app.logger().warn("apns: тихий пуш не доставлен", "uid", uid,
        "reason", String(answer.reason || res.statusCode));
      return;
    }
    try {
      user.set("apns_bg_ms", now);
      $app.save(user);
    } catch (_) { /* отметка не критична: в худшем случае разбудим раньше */ }
  } catch (e) {
    $app.logger().warn("apns: релей не ответил на тихий пуш", "err", String(e));
  }
}

/// Разбудить всех участников группы, кроме автора изменения.
function wakeGroup(groupId, authorUid, kind) {
  if (!groupId) return;
  let group;
  try { group = $app.findRecordById("groups", groupId); } catch (_) { return; }
  if (group.get("disbanded")) return;
  const members = membersOf(group);
  for (let i = 0; i < members.length; i++) {
    const uid = String(members[i] || "");
    if (!uid || uid === authorUid) continue;
    wakeUp(uid, kind);
  }
}

module.exports = {
  notifyGroup: notifyGroup,
  sendTo: sendTo,
  isOnline: isOnline,
  wakeUp: wakeUp,
  wakeGroup: wakeGroup,
};
