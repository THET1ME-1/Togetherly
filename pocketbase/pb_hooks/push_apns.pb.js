/// Пуши на iPhone через APNs.
///
/// Уведомления у нас рисует сам телефон: приложение слушает realtime и зовёт
/// flutter_local_notifications. Пока процесс жив — работает, но iOS выгружает
/// его быстро, сокет умирает вместе с ним, и человек не узнаёт ни о сообщении,
/// ни о «скучаю». «Уведы с закрытым приложением не ворк» — главная жалоба после
/// выхода в App Store, и починить её можно только пушем от Apple.
///
/// Подписать запрос к APNs нужно JWT на ES256, чего JSVM не умеет, поэтому рядом
/// живёт релей (`pocketbase/apns/apns_relay.py`, systemd `apns-relay`, порт
/// 8096). Здесь остаётся решить, кому и что послать.
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

/// Общая рассылка. Объявлена так, чтобы каждый хук поднимал свою копию: в JSVM
/// функции уровня файла хендлерам не видны.
function togetherlyPushFactory() {
  const membersOf = (g) => {
    try { return JSON.parse(g.getString("members") || "[]") || []; }
    catch (_) { return []; }
  };

  const isOnline = (uid) => {
    try {
      const p = $app.findFirstRecordByFilter(
        "user_presence", "user_uid = {:u}", { u: uid });
      const seen = p.getString("seen_at") || p.getString("updated") || "";
      if (!seen) return false;
      const ms = new Date(seen.replace(" ", "T")).getTime();
      if (!ms) return false;
      return (Date.now() - ms) < ONLINE_WINDOW_MS;
    } catch (_) {
      return false; // записи нет — считаем, что не на связи
    }
  };

  const forget = (user) => {
    try {
      user.set("apns_token", "");
      $app.save(user);
    } catch (_) { /* не критично, попробуем в следующий раз */ }
  };

  const sendTo = (uid, title, body, thread) => {
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
      if (answer.gone) forget(user);
      if (!answer.ok) {
        $app.logger().warn("apns: не доставлено", "uid", uid,
          "reason", String(answer.reason || res.statusCode));
      }
    } catch (e) {
      $app.logger().warn("apns: релей не ответил", "err", String(e));
    }
  };

  /// Всем участникам группы, кроме автора.
  const notifyGroup = (groupId, authorUid, title, body, thread) => {
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
  };

  return { notifyGroup: notifyGroup, sendTo: sendTo };
}

/// Проверка доставки: `POST /api/apns/test {token, sandbox?, title?, body?}`.
///
/// Нужна, чтобы отличать «пуши не работают» от «телефон не отдал токен». Ответ
/// Apple приходит как есть: `BadDeviceToken` — токен не тот, `InvalidProviderToken`
/// — не тот ключ или Team ID, `ok` — пуш ушёл. Только для суперюзера: рассылать
/// произвольные баннеры кому попало нельзя.
routerAdd("POST", "/api/apns/test", (e) => {
  const body = e.requestInfo().body || {};
  const token = String(body.token || "").trim();
  if (!token) return e.json(400, { ok: false, reason: "NoDeviceToken" });
  try {
    const res = $http.send({
      url: "http://127.0.0.1:8096/push",
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        token: token,
        title: String(body.title || "Togetherly"),
        body: String(body.body || "Проверка доставки"),
        thread: "test",
        sandbox: !!body.sandbox,
      }),
      timeout: 15,
    });
    return e.json(200, { relay: res.json || {}, status: res.statusCode });
  } catch (err) {
    return e.json(502, { ok: false, reason: String(err) });
  }
}, $apis.requireSuperuserAuth());

/// Новое сообщение в чате пары.
onRecordAfterCreateSuccess((e) => {
  try {
    const push = togetherlyPushFactory();
    const rec = e.record;
    if (rec.get("deleted")) return;
    const name = String(rec.getString("user_name") || "Партнёр");
    const text = String(rec.getString("text") || "").trim();
    const voice = String(rec.getString("voice_url") || "");
    const body = text
      ? (text.length > 120 ? text.slice(0, 117) + "…" : text)
      : (voice ? "Голосовое сообщение" : "Сообщение");
    push.notifyGroup(
      String(rec.getString("group_id") || ""),
      String(rec.getString("user_uid") || ""),
      name, body, "chat");
  } catch (err) {
    $app.logger().warn("apns: чат", "err", String(err));
  }
  e.next();
}, "chat_messages");

/// «Скучаю»: счётчик растёт у того, кто нажал, — уведомить нужно второго.
onRecordAfterUpdateSuccess((e) => {
  try {
    const push = togetherlyPushFactory();
    const rec = e.record;
    push.notifyGroup(
      String(rec.getString("group_id") || ""),
      String(rec.getString("user_uid") || ""),
      "Скучает по тебе",
      String(rec.getString("last_vibe_text") || "").trim() || "Обними в ответ",
      "miss");
  } catch (err) {
    $app.logger().warn("apns: скучаю", "err", String(err));
  }
  e.next();
}, "miss_you");

/// Настроение дня.
onRecordAfterCreateSuccess((e) => {
  try {
    const push = togetherlyPushFactory();
    const rec = e.record;
    const label = String(rec.getString("label") || "").trim();
    push.notifyGroup(
      String(rec.getString("group_id") || ""),
      String(rec.getString("user_uid") || ""),
      "Настроение партнёра",
      label ? "Сегодня: " + label : "Партнёр отметил настроение",
      "mood");
  } catch (err) {
    $app.logger().warn("apns: настроение", "err", String(err));
  }
  e.next();
}, "mood_entries");

/// Новое воспоминание в ленте.
onRecordAfterCreateSuccess((e) => {
  try {
    const push = togetherlyPushFactory();
    const rec = e.record;
    if (rec.get("deleted")) return;
    const who = String(rec.getString("author_name") || "Партнёр");
    push.notifyGroup(
      String(rec.getString("group_id") || ""),
      String(rec.getString("author_uid") || ""),
      who, "Добавил воспоминание", "memory");
  } catch (err) {
    $app.logger().warn("apns: воспоминание", "err", String(err));
  }
  e.next();
}, "memories");
