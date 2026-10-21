/// gift_push.js — когда и чем сказать получателю, что ему пришёл подарок.
///
/// Отдельным модулем, потому что обработчики JSVM не видят функций уровня
/// файла: хук `gift_push.pb.js` подключает это через `require`, тест — через
/// node (`node pocketbase/pb_hooks/gift_push.test.js`).
///
/// До 21.10.2026 сервер о подарке не говорил вовсе: знал о нём только
/// открытый сокет приложения. Закрытое приложение молчало, а карточка подарка
/// ждала внизу главной (TOG-10: «отправила парню, а у него не появился»).

/// Подарок с доставкой не позже этого срока считается пришедшим сразу.
const GRACE_MS = 2 * 60 * 1000;

/// Шаг крона, который говорит об отложенных подарках (письмо, завтрак).
const CRON_STEP_MS = 5 * 60 * 1000;

/// Подарок от человека, который ждёт ответа получателя. Оставленный себе
/// из сундука лежит от `chest` и сразу открыт — о нём говорить незачем.
function fromPartner(g) {
  if (!g || g.state !== "sent") return false;
  const sender = String(g.sender || "");
  const recipient = String(g.recipient || "");
  return !!sender && !!recipient && sender !== "chest" && sender !== recipient;
}

/// Пуш в момент создания: доставка уже наступила.
function pushOnCreate(g, nowMs) {
  return fromPartner(g) && Number(g.deliverAt) <= Number(nowMs) + GRACE_MS;
}

/// Пуш кроном: доставка наступила в окне (from, to], а при создании ещё
/// была впереди. Пришедший сразу подарок уже сказал о себе при создании.
function dueInWindow(g, fromMs, toMs, createdMs) {
  if (!fromPartner(g)) return false;
  const at = Number(g.deliverAt);
  return at > Number(fromMs) && at <= Number(toMs) && at > Number(createdMs) + GRACE_MS;
}

/// Начало окна крона: прошлый проход, иначе один шаг назад. После долгого
/// простоя тоже шаг назад: пачка старых пушей разом будила бы зря.
function windowFrom(lastRunMs, nowMs) {
  const now = Number(nowMs);
  const last = Number(lastRunMs);
  if (!isFinite(last) || last <= 0 || last > now || now - last > 2 * CRON_STEP_MS) {
    return now - CRON_STEP_MS;
  }
  return last;
}

/// Заголовок — имя дарителя, текст — по его роду. Рамку отдают, а не дарят.
function message(name, gender, giftKey) {
  const who = String(name || "").trim() || "Партнёр";
  const female = gender === "female";
  const male = gender === "male";
  if (String(giftKey || "").startsWith("frame_")) {
    const verb = female ? "Отдала" : male ? "Отдал" : "Отдал(а)";
    return { title: who, body: verb + " тебе свою рамку для аватарки" };
  }
  const verb = female ? "Прислала" : male ? "Прислал" : "Прислал(а)";
  return { title: who, body: verb + " тебе подарок 🎁" };
}

/// Подарок из записи `gifts` в том виде, что понимают правила выше.
function fromRecord(rec) {
  return {
    state: rec.getString("state"),
    sender: rec.getString("sender_uid"),
    recipient: rec.getString("recipient_uid"),
    deliverAt: rec.getInt("deliver_at"),
  };
}

/// Шлёт пуш получателю подарка. Кто сейчас в приложении, тот увидит подарок
/// сразу: экран откроет его сам, а сокет покажет своё уведомление. На связи
/// ли человек, знает hotpath — присутствие живёт в Postgres.
function notify(rec) {
  const uid = rec.getString("recipient_uid");
  try {
    const res = $http.send({
      url: "http://127.0.0.1:8120/internal/online?uid=" + encodeURIComponent(uid),
      method: "GET",
      timeout: 3,
    });
    if (res && res.json && res.json.online) return;
  } catch (_) { /* не знаем — лучше прислать */ }
  let name = "", gender = "";
  try {
    const sender = $app.findRecordById("users", rec.getString("sender_uid"));
    name = sender.getString("display_name") || sender.getString("name");
    gender = sender.getString("gender");
  } catch (_) { /* имя не нашлось — будет «Партнёр» */ }
  const msg = message(name, gender, rec.getString("gift_key"));
  const push = require(`${__hooks}/apns_push.js`);
  push.sendTo(uid, msg.title, msg.body, "gift", {
    force: true,
    data: { group: rec.getString("group_id"), gift: rec.id },
  });
}

module.exports = {
  GRACE_MS, CRON_STEP_MS, fromPartner, pushOnCreate, dueInWindow, windowFrom, message, fromRecord, notify,
};
