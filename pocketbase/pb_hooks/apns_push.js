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
/// Мёртвый токен (Apple отвечает Unregistered/BadDeviceToken, Google —
/// UNREGISTERED) вычищаем из профиля сразу, иначе будем стучать в него вечно.
///
/// Каналов доставки два, и выбирает их не платформа, а наличие токена: iPhone
/// приносит `apns_token`, Android — `fcm_token`. У кого есть оба (сменил
/// телефон, а токен второго ещё жив) — получит в оба, дубль лучше тишины.
/// Имя файла историческое: сначала здесь был только APNs.

const APNS_RELAY = "http://127.0.0.1:8096/push";
const FCM_RELAY = "http://127.0.0.1:8100/push";
const ONLINE_WINDOW_MS = 25 * 1000; // один пропущенный удар присутствия

function membersOf(group) {
  try { return JSON.parse(group.getString("members") || "[]") || []; }
  catch (_) { return []; }
}

function isOnline(uid) {
  try {
    const p = $app.findFirstRecordByFilter(
      "user_presence", "user_uid = {:u}", { u: uid });
    // `seen_at` — ЧИСЛО миллисекунд (см. схему user_presence), а не дата.
    // Прежний разбор гнал его через `new Date("1755440000000")`, получал Invalid
    // Date и возвращал «не на связи» всегда: пуш уходил даже тому, кто прямо
    // сейчас в приложении, и дублировал локальное уведомление.
    const raw = p.get("seen_at");
    let ms = Number(raw);
    if (!isFinite(ms) || ms <= 0) {
      // Старые записи без seen_at: остаётся служебная дата обновления.
      const seen = p.getString("updated") || "";
      if (!seen) return false;
      ms = new Date(String(seen).replace(" ", "T")).getTime();
    }
    if (!ms || !isFinite(ms)) return false;
    return (Date.now() - ms) < ONLINE_WINDOW_MS;
  } catch (_) {
    return false; // записи нет — считаем, что не на связи
  }
}

function forgetToken(user, field) {
  try {
    user.set(field || "apns_token", "");
    $app.save(user);
  } catch (_) { /* попробуем в следующий раз */ }
}

/// Вид уведомления → поле выключателя в users. Пустое поле означает
/// «включено»: у старых аккаунтов его нет вовсе, и молчать им нельзя.
const NOTIF_FIELD = {
  chat: "notif_chat",
  mood: "notif_mood",
  memory: "notif_new_memory",
  miss: "notif_miss_you",
  // Комментарии — свой вид, а не «новое воспоминание». Пока они шли одной
  // строкой с лентой, выключенная лента забирала с собой и разговор под
  // снимком: «не понятно, когда друг их пишет» (просьба из бота 17.08.2026).
  comment: "notif_comments",
  draw: "notif_draw",
};

function sendTo(uid, title, body, thread) {
  let user;
  try { user = $app.findRecordById("users", uid); } catch (_) { return; }
  if (isOnline(uid)) return;

  // Человек выключил этот вид уведомлений в приложении. Переключатели
  // доезжали сюда с самого начала, но их никто не читал: пуши уходили всем
  // подряд, а «Скучаю» было выключено у 16 507 человек (жалоба 16.08.2026).
  const field = NOTIF_FIELD[thread];
  if (field) {
    const raw = user.get(field);
    if (raw === false || raw === 0) return;
  }

  const apnsToken = String(user.getString("apns_token") || "");
  if (apnsToken) {
    try {
      const res = $http.send({
        url: APNS_RELAY,
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          token: apnsToken,
          title: title,
          body: body,
          thread: thread,
          sandbox: !!user.get("apns_sandbox"),
          data: { kind: thread },
        }),
        timeout: 10,
      });
      const answer = res.json || {};
      if (answer.gone) forgetToken(user, "apns_token");
      if (!answer.ok) {
        $app.logger().warn("apns: не доставлено", "uid", uid,
          "reason", String(answer.reason || res.statusCode));
      }
    } catch (e) {
      $app.logger().warn("apns: релей не ответил", "err", String(e));
    }
  }

  const fcmToken = String(user.getString("fcm_token") || "");
  if (fcmToken) {
    try {
      const res = $http.send({
        url: FCM_RELAY,
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          token: fcmToken,
          title: title,
          body: body,
          // Одна строка на вид события: новое сообщение заменяет прежнее в
          // шторке, а не копится десятком одинаковых баннеров.
          tag: thread,
          data: { kind: thread },
        }),
        timeout: 10,
      });
      const answer = res.json || {};
      if (answer.gone) forgetToken(user, "fcm_token");
      if (!answer.ok) {
        $app.logger().warn("fcm: не доставлено", "uid", uid,
          "reason", String(answer.reason || res.statusCode));
      }
    } catch (e) {
      $app.logger().warn("fcm: релей не ответил", "err", String(e));
    }
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

/// Android столько ждать не должен: тихие data-пуши FCM не лимитирует, а с
/// 13.08.2026 виджеты там держатся именно на пуше — свой фоновый сервис,
/// обновлявший их сокетом мгновенно, при живых пушах больше не поднимается.
/// Пока окно было общим на обе системы, партнёр менял фото, а виджет на столе
/// оставался прежним до четверти часа.
///
/// Совсем без зазора пачка правок одной секунды (статус, настроение, музыка)
/// дала бы три пробуждения подряд. Зазор живёт в памяти процесса: заводить
/// поле в записи ради десяти секунд незачем, а перезапуск сервера в худшем
/// случае разбудит телефон лишний раз.
const MIN_FCM_WAKE_GAP_MS = 10 * 1000;

function wakeUp(uid, kind) {
  let user;
  try { user = $app.findRecordById("users", uid); } catch (_) { return; }
  const apnsToken = String(user.getString("apns_token") || "");
  const fcmToken = String(user.getString("fcm_token") || "");
  if (!apnsToken && !fcmToken) return;
  if (isOnline(uid)) return;

  const now = Date.now();
  const lastApns = Number(user.get("apns_bg_ms") || 0);
  const apnsAllowed = !(lastApns && now - lastApns < MIN_WAKE_GAP_MS);

  const fcmKey = "fcmWake:" + uid;
  const lastFcm = Number($app.store().get(fcmKey) || 0);
  const fcmAllowed = !(lastFcm && now - lastFcm < MIN_FCM_WAKE_GAP_MS);

  if (!apnsAllowed && !fcmAllowed) return;

  let wokeApns = false;

  if (apnsToken && apnsAllowed) {
    try {
      const res = $http.send({
        url: APNS_RELAY,
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          token: apnsToken,
          silent: true,
          sandbox: !!user.get("apns_sandbox"),
          data: { kind: kind || "widgets" },
        }),
        timeout: 10,
      });
      const answer = res.json || {};
      if (answer.gone) forgetToken(user, "apns_token");
      else if (answer.ok) wokeApns = true;
      else {
        $app.logger().warn("apns: тихий пуш не доставлен", "uid", uid,
          "reason", String(answer.reason || res.statusCode));
      }
    } catch (e) {
      $app.logger().warn("apns: релей не ответил на тихий пуш", "err", String(e));
    }
  }

  if (fcmToken && fcmAllowed) {
    // Отметка ставится ДО отправки: пачка правок приходит соседними
    // событиями, и второе не должно проскочить мимо зазора, пока ждём релей.
    try { $app.store().set(fcmKey, now); } catch (_) { /* не критично */ }
    try {
      const res = $http.send({
        url: FCM_RELAY,
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          token: fcmToken,
          silent: true,
          data: { kind: kind || "widgets" },
        }),
        timeout: 10,
      });
      const answer = res.json || {};
      if (answer.gone) forgetToken(user, "fcm_token");
      else if (!answer.ok) {
        $app.logger().warn("fcm: тихий пуш не доставлен", "uid", uid,
          "reason", String(answer.reason || res.statusCode));
      }
    } catch (e) {
      $app.logger().warn("fcm: релей не ответил на тихий пуш", "err", String(e));
    }
  }

  // Отметку в записи двигает ТОЛЬКО пробуждение Apple — окно принадлежит ей.
  // Пока она ставилась и после удачного FCM, пуш на Android закрывал айфону
  // следующие пятнадцать минут: у человека бывают оба устройства сразу.
  if (!wokeApns) return;
  try {
    user.set("apns_bg_ms", now);
    $app.save(user);
  } catch (_) { /* отметка не критична: в худшем случае разбудим раньше */ }
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
